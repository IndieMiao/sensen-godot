extends RefCounted
## q(295) ④: a landmark scene (LandmarkScenes: Alcatraz, Griffith) opened from the P0 map is a P0 world with no
## function — P0's HUD and place chip over it (the chip and Android Back go back to the map), the stick and a tap on the
## ground walk, a pinch zooms, and the scene's own Journey chrome (title, Overview, Follow, + / −) is not built. Nothing
## is sent: its space is "" (P0Runtime.space_of), which the server ignores, and where the player is stays as it was.
## Where the scene has a way out on the ground (Alcatraz's dock, layout `exit`) it wears the rooms' door prompt — i-door,
## and Map as its strip once near (SGODOT-250) — and walking onto it leaves, as a room's door does.
## The scene holds one of these from setup(args) and hands it its p0_* calls.
## SGODOT-462 / q(307) (the user, 11-10: 「恶魔岛无法多人,无法语音」, 「都是现成代码的复用」): the landmark is an online room of
## 8, `landmark:<id>`, as a pond is (SGODOT-383) — the others walk round it too, on its ground, and the room has voice (the
## HUD's mic key and people drawer read the scene's voice_room). Nothing else is sent: q(295) ④ stands.

const EXIT_ID := "landmark:exit"
## The door strip opens within this of the dock (a room's CARD_NEAR_M is for a room; the dock is out in the open).
const NEAR_M := 4.0
## Walking onto the dock leaves once the player has been this far from it (P0Room.EXIT_ARM_M / EXIT_RADIUS_M; wider
## here: Alcatraz lands the player 1.1 m from its dock).
const EXIT_ARM_M := 2.5
const EXIT_RADIUS_M := 0.8

var scene: Node3D
var chip := ""
var landmark := ""   # its id: the room is `landmark:<id>`
var rt: P0Runtime
var crowd: Node3D   # an OnlineCrowd: the others, in the scene's own metres
var online: P0Online
var voice_room: Node   # P0VoiceRoom, also the scene's (P0Runtime hands it the HUD)
var _heights := {}   # peer id → the ground last found under them (the next ask starts there: a stair's level)
var stick := Vector2.ZERO
var _armed := false
var _to_exit := false
var _leaving := false

## What the map hands AppRouter.open_instance: the chip (`San Francisco · Alcatraz Island`, also the loading cover's
## destination) and the landmark.
static func args_for(entry: Dictionary, city: String) -> Dictionary:
	var place := str(entry.get("name", ""))
	return {"p0_visit": true, "landmark": str(entry.get("id", "")), "chip": "%s · %s" % [city, place] if city != "" else place}

static func wanted(args: Dictionary) -> bool: return bool(args.get("p0_visit", false))

## Whether a landmark's Go is on in P0: the content table's landmark_scenes (one flag each, assets/p0/content/
## landmarks.json). Off, its card has no key and a request for it goes nowhere; the dev entry ignores it.
static func open(id: String) -> bool:
	return bool(P0Logic.content().get("landmark_scenes", {}).get(id, false))

var _dev := {}   # P0_SCENE's landmark:<id>:<point>:<zoom> (dev_point, dev_zoom)

func _init(s: Node3D, args: Dictionary) -> void:
	scene = s
	chip = str(args.get("chip", ""))
	landmark = str(args.get("landmark", ""))
	for k in ["dev_point", "dev_zoom"]:
		if args.has(k): _dev[k] = args[k]

## From the scene's _ready, once it stands: the world P0 drives.
func start() -> void:
	rt = P0Runtime.ensure()
	rt.attach(scene)
	rt.ui.set_place(chip)
	_armed = false
	# into the room from where the player stands once off the door: the room takes a jump after the join as none (a
	# teleport), so the others would see them where they landed (SGODOT-462)
	landing.expect()   # q(311): the cover waits for the room's pick (the places need the ground first)
	if exit_at() != Vector3.INF: _step_off_then_online.call_deferred()
	else: _go_online()
	if _dev.has("dev_point"): _stand_when_ready.call_deferred(str(_dev.dev_point))
	if _dev.has("dev_zoom"): scene.call("p0_zoom", float(_dev.dev_zoom))

func _step_off_then_online() -> void:
	await _step_off_the_door()
	_go_online()

# ---------------------------------------------------------------- the landmark's online room (SGODOT-462, as a pond's)
const OnlineCrowd := preload("res://modules/net/online_crowd.gd")
const P0VoiceRoom := preload("res://modules/p0/p0_voice_room.gd")

## The landmark's room on the server: `landmark:<landmark id>`.
func room_id() -> String: return "landmark:" + landmark

func _go_online() -> void:
	var session := rt.session
	if session == null or landmark == "": return
	if not session.is_node_ready(): await session.ready   # a landmark booted first (dev) makes the runtime this frame
	if _leaving or not scene.is_inside_tree(): return
	var c := OnlineCrowd.new()
	c.show_health = false
	c.height_of = _height_of
	crowd = c
	scene.add_child(crowd)   # the scene's metres, as the server's room keeps them
	var o := P0Online.new()
	o.url = P0Online.ws_url(session.base_url)
	o.player_id = session.player_id
	o.access_key = session.access_key
	o.version = session.version
	o.features = session.features()
	o.appearance = OnlineAppearance.payload(Avatar.load_outfit())
	o.crowd = crowd
	o.source = func(): return {"position": scene.call("player_position"), "yaw": _yaw(), "action": "run" if _moving() else "idle"}
	scene.add_child(o)
	online = o
	o.joined.connect(_on_joined)
	voice_room = P0VoiceRoom.new()
	scene.add_child(voice_room)
	voice_room.setup(session, o, "landmark")
	scene.set("voice_room", voice_room)
	o.joined.connect(func(_i): if voice_room.age == "unknown" and not voice_room.available: voice_room.fetch_status(), CONNECT_ONE_SHOT)
	# the places need the ground — the player's own zone's too, which joins the navigation a sync or two after it reads
	# ready (gs66 11-11: a quicker load went out with the spawn alone, every ring place "off the ground"): up to NAV_WAIT_MS
	var t0 := Time.get_ticks_msec()
	while not _on_own_ground() and Time.get_ticks_msec() - t0 < NAV_WAIT_MS and scene.is_inside_tree():
		await scene.get_tree().physics_frame
	if _leaving or not scene.is_inside_tree(): return
	var at: Vector3 = scene.call("player_position")
	var why := {}
	var mine := places(at, why)
	if mine.size() < 3 and not why.is_empty():   # few: why, for the log
		var counts := {}
		for r in why.values():
			var k := str(r).get_slice(" hidden by", 0)
			counts[k] = int(counts.get(k, 0)) + 1
		print("P0 q311 %s: left out %s" % [room_id(), counts])
	o.start(room_id(), Vector2(at.x, at.z), mine)
	landing.begin(o, mine, at)   # after start: its room's name, and the socket opens a frame or more later

## Whether the navigation is in under the player (their zone's region joined, not just the map ready).
func _on_own_ground() -> bool:
	if not bool(scene.call("navigation_ready")): return false
	var nav: RID = scene.call("nav_map")
	return nav.is_valid() and _on_nav(nav, scene.call("player_position")) != Vector3.INF

## How long the places wait for the ground before going out with the spawn alone (P0Landing.EXPECT_MS covers it).
const NAV_WAIT_MS := 3000
## q(311) (SGODOT-470): the visit's landing — the server's pick from `places`, waited for under the arrival cover.
var landing := P0Landing.new()

## Where the player may stand on coming in, the spawn `at` first (P0SpawnRing): on the ground (the navigation, which keeps
## the props' clearance, 474), outside the way out's reach, and on the opening's screen whole and 8 px from the door key
## as drawn — its Map strip within NEAR_M of the dock, its icon further (q(311) ②; P0SpawnRing.strip_rect). Just `at` while the navigation is not in.
func places(at: Vector3, why := {}) -> Array[Vector2]:
	var nav: RID = scene.call("nav_map")
	var cam := scene.get_viewport().get_camera_3d() if scene.is_inside_tree() else null
	if cam == null or not nav.is_valid() or not bool(scene.call("navigation_ready")):
		print("P0 q311 %s: the ground is not in yet, the spawn alone" % room_id())
		return [Vector2(at.x, at.z)]
	if scene.has_method("_update_camera"): scene.call("_update_camera")   # the opening's framing, on the player now
	var axes := P0SpawnRing.axes(cam)
	var exit := exit_at()
	var boxes: Array = scene.call("occluders") if scene.has_method("occluders") else []
	var toward := cam.global_basis.z   # from the ground to the camera (orthographic: one direction for every point)
	var ok := func(p: Vector3) -> bool:
		var g := _on_nav(nav, p)
		if g == Vector3.INF: return _no(why, p, "off the ground")
		var keys := []
		if exit != Vector3.INF:
			if _flat(g, exit) <= EXIT_RADIUS_M: return _no(why, p, "the way out")
			if not cam.is_position_behind(exit):
				var c := cam.unproject_position(exit + Vector3.UP * 0.6)
				# as drawn (不知火舞 on #988): the Map strip within NEAR_M (either way), its icon further
				keys.append(P0SpawnRing.strip_rect(c, P0Logic.icon("door"), "Map") if _flat(g, exit) <= NEAR_M else P0SpawnRing.icon_rect(c))
		# seen whole: the legs, the middle and the head, each with nothing in the way from the camera (as an outpost's)
		for h in SEEN_AT:
			var to: Vector3 = g + Vector3.UP * float(h[0])
			for b in boxes:
				if _crosses(b[0], b[1], to + toward * 40.0, to): return _no(why, p, "%s hidden by %s" % [h[1], b[2]])
		if not P0SpawnRing.clear_of(cam, g, []): return _no(why, p, "off screen")
		return P0SpawnRing.clear_of(cam, g, keys) or _no(why, p, "the Map key")
	return P0SpawnRing.places(at, axes[0], axes[1], ok)

## The heights a person is looked at for things in the way (P0Outpost.SEEN_AT_M), and what each is called in `why`.
const SEEN_AT := [[0.3, "legs"], [0.9, "middle"], [1.55, "head"]]

## Whether the segment `a` → `b` (world) passes through `box`, a mesh's box in the space `xf` puts in the world.
static func _crosses(xf: Transform3D, box: AABB, a: Vector3, b: Vector3) -> bool:
	var inv := xf.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var d := lb - la
	var t0 := 0.0
	var t1 := 1.0
	for i in 3:
		var lo := box.position[i]
		var hi := box.end[i]
		if absf(d[i]) < 0.000001:
			if la[i] < lo or la[i] > hi: return false
			continue
		var u := (lo - la[i]) / d[i]
		var v := (hi - la[i]) / d[i]
		t0 = maxf(t0, minf(u, v))
		t1 = minf(t1, maxf(u, v))
		if t0 > t1: return false
	return t0 < 1.0 - 0.0001   # not just touching it at the person's own point

## A place left out, and why (tests, the review's table): false.
static func _no(why: Dictionary, p: Vector3, reason: String) -> bool:
	why[Vector2(snappedf(p.x, 0.01), snappedf(p.z, 0.01))] = reason
	return false

## The world's ask (P0Runtime._landing_pending): the arrival cover waits while this is true.
func landing_pending() -> bool: return landing.pending()

## Layer 2 and later say so once, as an outpost's and a pond's do (P0Online.layer_notice). The visit's first `joined`
## first stands the player where the room put them (q(311) ④), before the first position goes out.
func _on_joined(info: Dictionary) -> void:
	var to := landing.target(info, scene.call("player_position"))
	if to != Vector3.INF:
		var nav: RID = scene.call("nav_map")
		var g := _on_nav(nav, to) if nav.is_valid() else Vector3.INF
		scene.call("dev_stand", g if g != Vector3.INF else to)
	var said := P0Online.layer_notice(info)
	if said != "" and rt: rt.ui.toast(said, 0.0, true)

## The way the player faces (their -Z, as the stick and a walk turn them), as the room's yaw: a rig turned by it faces there.
func _yaw() -> float:
	var p = scene.get("_player")
	if not (p is Node3D): return 0.0
	var f := -(p as Node3D).global_basis.z
	return atan2(f.x, f.z)

func _moving() -> bool: return bool(scene.call("walking")) or bool(scene.get("stick_moving"))

## The ground under another player (the room sends x / z only; the island has steps and levels): the navigation's, asked
## from where they last stood (at first the player's height).
func _height_of(id: int) -> float:
	var a = crowd.get("actors").get(id, null) if crowd else null
	if not (a is Dictionary): return 0.0
	var p: Vector3 = a.position
	var nav: RID = scene.call("nav_map")
	if not nav.is_valid() or not bool(scene.call("navigation_ready")): return p.y
	var guess := float(_heights.get(id, (scene.call("player_position") as Vector3).y))
	var y := _ground(nav, Vector3(p.x, guess, p.z)).y
	_heights[id] = y
	return y

## Landed by the way out (Alcatraz's spawn is 1.1 m from its dock), the Map strip would touch the player (不知火舞 on
## #870: ≥ 8 px between them, as in the cathedral): the player starts START_FROM_EXIT_M from it, on the same side.
const START_FROM_EXIT_M := 2.2

func _step_off_the_door() -> void:
	for i in 30:
		if not scene.is_inside_tree(): return
		if bool(scene.call("navigation_ready")): break
		await scene.get_tree().physics_frame
	var at: Vector3 = scene.call("player_position")
	var exit := exit_at()
	var away := Vector3(at.x - exit.x, 0, at.z - exit.z)
	if away.length() >= START_FROM_EXIT_M or away.length() < 0.01: return
	scene.call("dev_stand", exit + away.normalized() * START_FROM_EXIT_M + Vector3.UP * (at.y - exit.y))

## The navigation is ready a physics frame or two after the scene stands: the dev point waits for it.
func _stand_when_ready(point: String) -> void:
	var at: Vector3 = scene.call("dev_point", point)
	if at == Vector3.INF: return
	for i in 30:
		if not scene.is_inside_tree(): return
		if bool(scene.call("navigation_ready")): break
		await scene.get_tree().physics_frame
	scene.call("dev_stand", at)

func resume() -> void:
	if rt == null: return
	rt.attach(scene)
	rt.ui.set_place(chip)

func exit_at() -> Vector3:
	return scene.call("exit_position")

func frame(dt: float) -> void:
	# popped (the chip, Back) before the map below takes the world back: nothing of it is left to drive
	if _leaving or rt == null or not scene.is_inside_tree(): return
	scene.call("step_stick", stick, dt)   # let go: the run stops (unless a tap's walk goes on)
	if crowd: crowd.call("step", dt, scene.call("player_position"))   # the others, between their frames
	var exit := exit_at()
	if exit == Vector3.INF: return
	var d := _flat(scene.call("player_position"), exit)
	if d > EXIT_ARM_M: _armed = true
	elif _armed and d <= EXIT_RADIUS_M:
		leave()
		return
	if _to_exit and not bool(scene.call("walking")): _to_exit = false
	var cam := scene.get_viewport().get_camera_3d()
	var on := cam != null and not cam.is_position_behind(exit)
	var at := cam.unproject_position(exit + Vector3.UP * 0.6) if on else Vector2.ZERO
	var door := P0Logic.icon("door")
	if on and d <= NEAR_M: rt.ui.name_bar(EXIT_ID, door, "Map", "", at, true)
	else: rt.ui.world_icon(EXIT_ID, door, at, on)

func tap(screen: Vector2) -> void:
	if rt and rt.ui.has_modal(): return
	if rt and str(rt.ui.tapped_card) == EXIT_ID and exit_at() != Vector3.INF:
		_to_exit = true
		_armed = true   # going there on purpose: arriving leaves
		scene.call("walk_to", exit_at())
		return
	scene.call("walk_to_screen", screen)

func leave() -> void:
	if _leaving: return
	_leaving = true
	clear()
	if rt: rt.leave_world()

## The door prompt goes with the scene (a world's prompts are the HUD's); so does the room.
func clear() -> void:
	if online: online.stop()
	if rt == null: return
	rt.ui.name_bar(EXIT_ID, null, "", "", Vector2.ZERO, false)
	rt.ui.world_icon(EXIT_ID, null, Vector2.ZERO, false)

## The stick moves `player` along the ground as `cam` faces, at `speed` scaled by how far it is pushed, kept on the
## navigation `nav`; a push off it slides along its edge (slide_on, 不知火舞's stick-slide spec v1), the player facing
## the way it goes — stopped, the way it pushes. How far it went over how far the stick asked (1 free, sin θ along an
## edge, 0 stopped); −1 when the push is too small to count.
static func stick_step(player: Node3D, nav: RID, cam: Camera3D, speed: float, v: Vector2, dt: float) -> float:
	var right := cam.global_basis.x
	right.y = 0
	var ahead := -cam.global_basis.z
	ahead.y = 0
	var dir := right.normalized() * v.x - ahead.normalized() * v.y
	if dir.length() > 1.0: dir = dir.normalized()
	if dir.length() < 0.05: return -1.0
	var want := dir * speed * dt
	var from := player.position
	var to := slide_on(nav, from, want)
	var went := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var ratio := went.length() / want.length()
	if ratio < PlayerMover.STUCK_RATIO:   # stopped where it stands (no snapping back and forth in a corner)
		player.look_at(from + dir, Vector3.UP)
		return 0.0
	player.position = to
	player.look_at(to + went.normalized(), Vector3.UP)
	return minf(ratio, 1.0)

## Where a step `want` from `p` ends on the navigation `nav` (the slide spec, as PlayerMover's on the grid): on it
## as asked; else along the edge it runs off — at sin θ, θ the push's angle off the edge's normal, once more along a
## second edge in a corner unless that turns it back or leaves under STUCK_RATIO; square-on (θ < SLIDE_MIN_DEG) not
## at all, but for the edge's end within YIELD_M to one side, stepped round at sin SLIDE_MIN_DEG. `p` when it stops.
static func slide_on(nav: RID, p: Vector3, want: Vector3) -> Vector3:
	var to := _slide(nav, p, want)
	# A stair's ground can sit a little past the step (周瑜 on #893: 4.3 % on Alcatraz's new steps): no further than the
	# stick asked, on the ground again.
	for i in 2:
		var went := Vector2(to.x - p.x, to.z - p.z).length()
		if went <= want.length() * 1.001: return to
		var flat := Vector3(to.x - p.x, 0.0, to.z - p.z)
		var back := _on_nav(nav, p + flat * (want.length() / went))
		if back == Vector3.INF:   # cut back off the navigation (an opening's corner): the farthest of it on it, short of that
			var lo := 0.0
			var hi := want.length() / went
			for k in 6:
				var mid := (lo + hi) * 0.5
				if _on_nav(nav, p + flat * mid) != Vector3.INF: lo = mid
				else: hi = mid
			return _on_nav(nav, p + flat * lo) if lo > 0.0 else p
		to = back
	return to

static func _slide(nav: RID, p: Vector3, want: Vector3) -> Vector3:
	var on := _on_nav(nav, p + want)
	if on != Vector3.INF: return on
	var n := _crossed(nav, p, want)
	var length := want.length()
	var d := want / length
	if n == Vector3.ZERO or d.dot(n) >= 0.0: return p
	if -d.dot(n) > cos(deg_to_rad(PlayerMover.SLIDE_MIN_DEG)):
		var across := n.cross(Vector3.UP).normalized()
		var k := PlayerMover.YIELD_STEP_M
		while k <= PlayerMover.YIELD_M + 0.0001:
			for side in [1.0, -1.0]:
				var off: Vector3 = p + across * side * k
				if _on_nav(nav, off) != Vector3.INF and _on_nav(nav, off + d * maxf(length, YIELD_LOOK_M)) != Vector3.INF:
					on = _on_nav(nav, p + across * side * length * sin(deg_to_rad(PlayerMover.SLIDE_MIN_DEG)))
					return on if on != Vector3.INF else p
			k += PlayerMover.YIELD_STEP_M
		return p
	var t := want - n * want.dot(n)
	on = _on_nav(nav, p + t)
	if on != Vector3.INF: return on
	var n2 := _crossed(nav, p, t)
	var t2 := t - n2 * t.dot(n2)
	if n2 == Vector3.ZERO or t2.dot(t) <= 0.0 or t2.length() < length * PlayerMover.STUCK_RATIO: return p
	on = _on_nav(nav, p + t2)
	return on if on != Vector3.INF else p

const NAV_ON_M := 0.005    # off the navigation by more than this (flat) is off it
const YIELD_LOOK_M := 0.3  # past an edge's end, this much ahead clear
## The navigation's ground under `q`: its nearest point, asked again at that height until it is under `q` (a slope or a
## stair is not off it; each ask closes most of the way on a slope).
static func _ground(nav: RID, q: Vector3) -> Vector3:
	var c := NavigationServer3D.map_get_closest_point(nav, q)
	for i in 3:
		if _flat(c, q) < 0.001: break
		c = NavigationServer3D.map_get_closest_point(nav, Vector3(q.x, c.y, q.z))
	return c

## `q` on the navigation (its ground), INF off it.
static func _on_nav(nav: RID, q: Vector3) -> Vector3:
	var g := _ground(nav, q)
	return g if _flat(g, q) < NAV_ON_M else Vector3.INF

## The normal of the edge a step `want` from `p` runs off the navigation by (flat, unit, inward): asked just past where
## it leaves — past a corner the step's end can be nearer another edge than the one it crossed.
static func _crossed(nav: RID, p: Vector3, want: Vector3) -> Vector3:
	var lo := 0.0
	var hi := 1.0
	for i in 6:
		var mid := (lo + hi) * 0.5
		if _on_nav(nav, p + want * mid) != Vector3.INF: lo = mid
		else: hi = mid
	return _into_nav(nav, p + want * hi + want.normalized() * 0.002)

## The way back onto the navigation from `q` off it (flat, unit): its edge's normal.
static func _into_nav(nav: RID, q: Vector3) -> Vector3:
	var g := _ground(nav, q)
	var v := Vector3(g.x - q.x, 0.0, g.z - q.z)
	return v.normalized() if v.length() > 1e-6 else Vector3.ZERO

## The scene rig's clips' speed: a stick's run at `ratio` of the walk's along an edge, not under SLIDE_RUN_MIN; 1 else.
static func run_speed(rig: Node, ratio: float) -> void:
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer if rig != null else null
	var scale := 1.0 if ratio >= 1.0 else maxf(PlayerMover.SLIDE_RUN_MIN, ratio)
	if ap != null and ap.speed_scale != scale: ap.speed_scale = scale

## Shot steps (P0Runtime._dev_shot hands its unknown ones to the world): lmtap:x:y a tap at that viewport point;
## lmzoom:f a pinch by f; lmgoto:<point> the player stood at one of the scene's review points (dev_point), lmwalk:<point>
## walked there; lmexit walked to the way out.
func dev(step: Array) -> bool:
	match str(step[0]):
		"lmtap": tap(Vector2(float(step[1]), float(step[2])))
		"lmzoom": scene.call("p0_zoom", float(step[1]))
		"lmgoto":
			var at: Vector3 = scene.call("dev_point", str(step[1]))
			if at == Vector3.INF: return false
			scene.call("dev_stand", at)
		"lmwalk":
			var at: Vector3 = scene.call("dev_point", str(step[1]))
			if at == Vector3.INF: return false
			scene.call("walk_to", at)
		"lmwhere":   # where the player is on screen (shots: circle them), and in the scene
			var cam := scene.get_viewport().get_camera_3d()
			var p: Vector3 = scene.call("player_position")
			print("P0_LM_WHERE screen=", cam.unproject_position(p + Vector3.UP * 0.8), " at=", p, " vp=", scene.get_viewport().get_visible_rect().size)
		"lmcrowd":   # the others in the room (SGODOT-462): each one's id, where the room has them, the ground found, on screen
			var cam := scene.get_viewport().get_camera_3d()
			if online: print("P0_LM_ROOM ", room_id(), " layer=", online.room, " self=", online.self_id, " members=", online.members.keys())
			for id in (crowd.get("actors") if crowd else {}):
				var p: Vector3 = crowd.actors[id].position
				var y := _height_of(int(id))
				print("P0_LM_CROWD id=", id, " at=", p, " ground=", y, " screen=", cam.unproject_position(Vector3(p.x, y + 0.8, p.z)))
		"lmexit":
			_to_exit = true
			_armed = true
			scene.call("walk_to", exit_at())
		_: return false
	return true

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
