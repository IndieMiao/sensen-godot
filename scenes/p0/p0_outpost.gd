extends P0Room
## A home-set outpost room (SGODOT-227) on the indoor shell (P0Room, SGODOT-226): the outpost's room kit (its
## `art` in p0_outposts.json, a Scene_design scene standing in until SGODOT-218) and anchors, its keeper and
## residents at their npc_ anchors, tap-triggered counters and seats (LOCK-07), and the outpost's realtime room:
## P0Online + OnlineCrowd show the other players, and the server picks Room 1, Room 2 … (indoor 12, Market
## Square 30). Counters and residents open the panel entries of SGODOT-224 / 225 when present; until then the
## tackle counter keeps the existing greeting.

const P0Locals := preload("res://modules/p0/p0_locals.gd")   # the keeper's local requests (q(272))
const OnlineCrowd = preload("res://modules/net/online_crowd.gd")
const P0VoiceRoom := preload("res://modules/p0/p0_voice_room.gd")
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
var voice_room: Node   # P0VoiceRoom: this room's voice (SGODOT-383; Market Square's too since q(286)), for the HUD's mic key and drawer
const NPCS_PATH := "res://assets/p0/outpost_npcs.json"
## Drawn in the art but without a P0 use: no finger card, no tap (§17.2.1; SGODOT-227 5a63a8ec).
## The Tackle Shop's board is the Bite Board since P1 (SGODOT-283), and the Travel Post's Stamp Desk and Fare Board are
## its read-only counters since q(165): facilities, not decor.
const DECOR := ["use_coffee_pot"]
## Tapping the counter is tapping the keeper (LOCK-15 / 16).
const COUNTERS := ["use_counter", "use_stall_1", "npc_keeper"]
## Furniture that seats: its seat_ anchors are seat_<group>_<n>.
const SEAT_GROUPS := {"use_tea_table_1": "seat_table1_", "use_tea_table_2": "seat_table2_", "use_tea_table_3": "seat_table3_",
	"use_bench": "seat_bench_"}   # the tea house's third table on its own kit (SGODOT-216)
## sit_idle puts the hip joint 0.426 m above the rig root and the thighs rest about 0.086 m below the joint
## (measured on the base rig, SGODOT-227), so a seated root sits this far below the seat surface.
const SIT_ROOT_BELOW_SEAT := 0.34
## sit_up runs at this speed; the player is released once it is upright.
const STAND_SPEED := 2.0
const STAND_S := 0.55
## Cells free on every side of where the player stands up (0.15 m each), by room kit: Grace Cathedral's pews end at the
## aisle with a gap between rows the front pew hides (不知火舞 on #850); elsewhere none — the tea house's stools stand
## up where they were walked to, as in 0.3.0.
const STAND_CLEAR := {"poi_church": 2}
## The root eases onto the seat within this time (art director: aligned within 0.3 s); clips cross-fade in. Further than
## SIT_GLIDE_S covers at SIT_SLIDE_MPS (along a pew from the aisle to its middle, q(304)) it takes as long as it needs.
const SIT_GLIDE_S := 0.3
const SIT_SLIDE_MPS := 2.5
## Kits whose lone seats are walked to by their layout `approach` (the aisle end of the pew) and slid onto along the pew,
## their icons kept on their anchors, never spread (q(304), the user on 0.3.5: one seat in each pew's middle).
const PEW_KITS := ["poi_church"]
## The two second seats q(304) took off the pews, still in the shared outpost table so an older client may sit there:
## its pew counts as taken while one does (no icon, no seat for us), and that player is drawn where it sat, at the
## height of the pew's own seat (不知火舞 on q(304): one to a pew while both builds are about).
const LEGACY_SEATS := {"seat_left_4": "seat_left_2", "seat_right_4": "seat_right_2"}
const CLIP_BLEND_S := 0.1

var outpost: Dictionary = {}
var role := ""
var keeper: Dictionary = {}
var online: P0Online
var crowd: Node3D
var npcs := {}           # npc anchor name → {id, name, root}
var seat := ""           # the seat we sit on ("" while standing)
var _sit_request := {}   # {seq, seat} waiting for the server
var _standing := {}      # {left, then} while sit_up plays
var _glide := {}         # {from, to, t, dur}: the root eases between the floor and the seat
var _dev_no_marks := false

func setup(args: Dictionary) -> void:
	outpost = P0Outposts.find(str(args.get("outpost_id", "")))
	role = str(outpost.get("role", ""))
	keeper = outpost.get("keeper", {})
	place_name = str(outpost.get("name", "Outpost"))
	anchors_path = str(outpost.get("anchors", ""))
	use_art(str(outpost.get("art", "")))   # the outpost's room kit; the anchors file is written for that kit
	backdrop = outpost.get("backdrop", {})   # screen colours sampled from the kit's signed render
	exit_to = "Map"   # the door's world prompt: i-door + Map (SGODOT-250)

func _room_ready() -> void:
	_spawn_npcs()
	_write_sign()
	actor.ground_height = func(_p: Vector3) -> float:
		if not _glide.is_empty(): return _glide_point().y
		return seat_root_y(seat) if seat != "" else floor_y
	crowd = OnlineCrowd.new()
	crowd.show_health = false
	crowd.height_of = _crowd_height
	room.add_child(crowd)   # remote players arrive in room metres, like the anchors
	# a server without the card room (no view.blackjack, 0.2.12 ahead of it) has no room for it either: offline there
	if use_runtime and not outpost.is_empty() and not (str(outpost.get("role", "")) == "casino"
			and not P0Runtime.ensure().session.view.has("blackjack")):
		landing.expect()   # q(311): the cover waits for the room's pick (the places need the opening's camera first)
		_go_online(P0Runtime.ensure().session)

func _exit_tree() -> void:
	if online: online.stop()
	super._exit_tree()

# ---------------------------------------------------------------- realtime room
func _go_online(session: P0Session) -> void:
	# A room opened first (dev boot) creates the runtime this frame: its session reads the server URL and
	# player id in _ready, one frame later.
	if not session.is_node_ready(): await session.ready
	if not is_inside_tree(): return
	var o := P0Online.new()
	o.url = P0Online.ws_url(session.base_url)
	o.player_id = session.player_id
	o.access_key = session.access_key
	o.version = session.version
	o.features = session.features()
	o.appearance = OnlineAppearance.payload(Avatar.load_outfit())
	o.layout = str(outpost.get("art", ""))   # the kit drawn here: the market plaza has instances of its own (SGODOT-218)
	attach_online(o)
	voice_room = P0VoiceRoom.new()
	add_child(voice_room)
	voice_room.setup(session, o, role)
	o.joined.connect(func(_i): if voice_room.here and not voice_room.available: voice_room.fetch_status(), CONNECT_ONE_SHOT)
	var door := anchor_data("spawn")
	var at := P0RoomAnchors.vec(door.get("position", [0, 0, 0]))
	await get_tree().process_frame   # frame_all: the opening's camera; the art's bodies in the physics space
	if not is_inside_tree(): return
	var mine := places(at)
	landing.begin(o, mine, to_room(actor.position))
	online.start(str(outpost.id), Vector2(at.x, at.z), mine)

# ---------------------------------------------------------------- q(311): where a newcomer stands (SGODOT-470)
## The visit's landing on the room's pick (P0Landing; the arrival cover waits for it, P0Runtime).
var landing := P0Landing.new()
func p0_landing_pending() -> bool: return landing.pending()
## Off a seat by this much (the server's free radius: a person on it would be on this one).
const SEAT_CLEAR_M := 0.45
## Heights a person is looked at from the camera for furniture in the way: the legs, the middle, the head.
const SEEN_AT_M: Array[float] = [0.3, 0.9, 1.55]

## Where the player may stand on coming in, in room metres, the spawn anchor `at` first (P0SpawnRing, round where the
## player stands): reachable on the floor, out of the door's reach, off the seats, not behind a keeper or a resident,
## seen whole past the furniture (a ray from the camera to the legs, the middle and the head; the room's unseen walls
## and fences let through, _unseen), and on the opening's screen 8 px from the keys as drawn — the nearest within
## CARD_NEAR_M open (a facility's or the door's strip either way, a seat's icon near), the others' 28 px icons (q(311) ②;
## LOCK-34 v2; 不知火舞 on #988).
func places(at: Vector3, why := {}) -> Array[Vector2]:
	var view: Dictionary = P0Runtime.ensure().session.current() if use_runtime else {}
	var exit := anchor("exit")
	var seats: Array = []
	for n in _anchors.keys(): if str(n).begins_with("seat_") and anchor(n) != null: seats.append(anchor(n).global_position)
	var people: Array = npcs.values().map(func(e): return (e.root as Node3D).global_position)
	var keys: Array = []   # {n, at (the anchor, world), screen, kind, icon, name, fact}
	for n in _tappable():
		var m := _marker(n, view)
		if m.is_empty() or not str(m.get("kind", "")) in ["seat", "facility"]: continue
		var badge := anchor("badge_" + (P0RoomAnchors.object_of(n) if P0RoomAnchors.object_of(n) != "" else n))
		keys.append({n = n, at = anchor(n).global_position, kind = str(m.kind), icon = m.get("icon", null), name = str(m.get("name", "")),
			fact = str(m.get("fact", "")),
			screen = cam.unproject_position(badge.global_position if badge else anchor(n).global_position + _hit_lift(n) * 1.1)})
	var space := get_world_3d().direct_space_state
	var walls: Array = (layout.get("boundaries", []) as Array).map(func(b): return StringName(str(b.get("name", ""))))   # unseen
	var ok := func(p: Vector3) -> bool:
		var w := Vector3(p.x, floor_y, p.z)
		var c := bp.world_to_cell(w)
		if not bp.in_bounds(c) or not bp.is_walkable(c): return _no(why, p, "floor")
		if bp.world_to_cell(reachable(w)) != c: return _no(why, p, "walled in")   # walled in (a counter's inside): not from the door
		if exit and _flat(w, exit.global_position) <= EXIT_RADIUS_M: return _no(why, p, "door")
		for s in seats: if _flat(w, s) < SEAT_CLEAR_M: return _no(why, p, "seat")
		if P0RoomNav.hidden(w, people, _cam_dir): return _no(why, p, "behind someone")
		for h in SEEN_AT_M:
			var to := w + Vector3.UP * h
			var ray := PhysicsRayQueryParameters3D.create(to + _cam_dir * 30.0, to, ~CALIB_LAYER)
			for i in 8:   # through the room's unseen walls, stopped by what is drawn
				var hit := space.intersect_ray(ray)
				if hit.is_empty(): break
				if not _unseen(hit.collider as Node, hit.position, walls): return _no(why, p, "hidden by " + str((hit.collider as Node).get_parent().name))
				ray.exclude = ray.exclude + [hit.rid]
		if not P0SpawnRing.clear_of(cam, w, []): return _no(why, p, "off screen")
		# as drawn (不知火舞 on #988): the nearest key within CARD_NEAR_M is the open one — a facility's (the door's) strip
		# either way, a seat's icon near (1.1×); the others their 28 px icons
		var card := ""
		var best := CARD_NEAR_M
		for k in keys:
			var d := _flat(w, k.at)
			if d <= best:
				best = d
				card = k.n
		for k in keys:
			var r := P0SpawnRing.icon_rect(k.screen, k.n == card)
			if k.n == card and k.kind == "facility": r = P0SpawnRing.strip_rect(k.screen, k.icon, k.name, k.fact)
			if not P0SpawnRing.clear_of(cam, w, [r]): return _no(why, p, "key " + str(k.n))
		return true
	var axes := P0SpawnRing.axes(cam)
	var out: Array[Vector2] = [Vector2(at.x, at.z)]
	for p in P0SpawnRing.places(actor.position, axes[0], axes[1], ok).slice(1):
		var r := to_room(Vector3(p.x, floor_y, p.y))
		out.append(Vector2(r.x, r.z))
	return out

static func _flat(a: Vector3, b: Vector3) -> float: return Vector2(a.x - b.x, a.z - b.z).length()

## A collider the camera sees through: one of the layout's `boundaries`, or hit outside the drawn meshes of the piece it
## belongs to (周瑜 on #988: the tackle shop's and the post's room_shell is a floor with an unseen fence 1.5 m high on its
## two camera sides, and their layouts list no boundaries).
var _piece_boxes := {}   # collider instance id → its piece's drawn box (world), AABB() for none
func _unseen(collider: Node, at: Vector3, walls: Array) -> bool:
	if collider.name in walls: return true
	var id := collider.get_instance_id()
	if not _piece_boxes.has(id):
		var box := AABB()
		var piece := collider.get_parent()
		if piece != null and piece != self:
			for m in piece.find_children("*", "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				if not mi.is_visible_in_tree() or mi.mesh == null: continue
				var b := mi.global_transform * mi.get_aabb()
				box = b if box.size == Vector3.ZERO else box.merge(b)
		_piece_boxes[id] = box
	var drawn: AABB = _piece_boxes[id]
	# no drawn mesh of its own (the card room's FrontTerracottaMonstera, drawn in the tavern's plant batch; 周瑜 on #988):
	# seen, as it stands in the way
	return drawn.size != Vector3.ZERO and not drawn.grow(0.05).has_point(at)

## A place left out, and why (tests, the review's table): false.
static func _no(why: Dictionary, p: Vector3, reason: String) -> bool:
	why[Vector2(snappedf(p.x, 0.01), snappedf(p.z, 0.01))] = reason
	return false

## 不知火舞 on #895 (SGODOT-218): the market plaza opens framed on its own, as the pond does — the player's feet at this row
## of the 800 px frame, so the stalls, Mei's counter and the row houses' ground floor show above under the HUD (its 16 m
## square left the lower third bare when centred). Across, as the room's opening shot has it. Other rooms: no entry.
const OPENING_FEET_Y := {"market_plaza": 600.0}

func opening_focus(right: Vector3, up: Vector3, forward: Vector3) -> Vector3:
	var base := super.opening_focus(right, up, forward)
	var feet_y := float(OPENING_FEET_Y.get(str(outpost.get("art", "")), -1.0))
	if feet_y < 0.0: return base
	var view := _view()
	var m := cam.size / maxf(view.x, 1.0)   # metres per px
	var q := Vector2(base.dot(right), base.dot(up))
	q.y = actor.position.dot(up) - (view.y * 0.5 - feet_y / 800.0 * view.y) * m   # the screen's centre that far above the feet
	return _on_floor(right, up, forward, q)

## The market plaza's row houses and far city by city (SGODOT-218, layout.json facade_variants): San Francisco's
## pastel Victorians in San Francisco (Mission Market Square), the plain set in every other city's square.
func _art_options(kit: Node) -> void:
	if "city_variant" in kit: kit.set("city_variant", city_variant(outpost))

static func city_variant(o: Dictionary) -> String:
	return "san_francisco" if str(o.get("cluster", "")) == P0Clusters.cluster_of_region("san_francisco") else "generic"

## Wires a room connection to this room: the crowd, our position in room metres, joins and seat results.
func attach_online(o: P0Online) -> void:
	online = o
	o.crowd = crowd
	o.source = func(): return {"position": to_room(actor.position), "yaw": atan2(actor.facing().x, actor.facing().z),
		"action": "run" if actor.state == "move" else "idle"}
	add_child(o)
	o.joined.connect(_on_joined)
	o.result.connect(_on_result)
	o.failed.connect(_on_online_failed)

## The room refused the join (SGODOT-280, 蒙恬 #243): a generated outpost of a city without a pass (PASS_REQUIRED),
## whose pass ran out before the player came in (TRIP_EXPIRED), or with a pass while the player is not in that city
## (TRAVEL_REQUIRED, q(256) ④; 后裔 #568). Back to the map, where the city's travel card opens (q(108)), as the entry
## read's refusal does.
func _on_online_failed(code: String) -> void:
	if not code in ["PASS_REQUIRED", "TRIP_EXPIRED", "TRAVEL_REQUIRED"] or rt == null: return
	var cluster := str(outpost.get("cluster", ""))
	rt.after_leave = "travel:" + cluster if cluster != "" else ""
	rt.leave_room()

## Layer 2 and later say so once; Layer 1 and a reconnect to the same layer say nothing (P0Online.layer_notice).
func _on_joined(info: Dictionary) -> void:
	var to := landing.target(info, to_room(actor.position))   # the visit's first: onto the room's pick (q(311) ④)
	if to != Vector3.INF:
		var w := room.position + Vector3(to.x, 0, to.z)
		w.y = floor_y
		if bp.is_walkable(bp.world_to_cell(w)):
			var facing := actor.facing()
			actor.teleport(w)
			actor.face(w + facing)
			frame_all()
	var said := P0Online.layer_notice(info)
	if said != "" and rt: rt.ui.toast(said, 0.0, true)   # Layer 1 is full / you're in Layer 2 (不知火舞 on #646)
	if seat != "": _stand_up()   # a new connection starts standing

## The space every P0 command carries (SGODOT-228 Rest "away from the farm"): outposts are "outpost".
func p0_space() -> String: return "outpost"

## Which outpost, for the server (蒙恬's map markers, SGODOT-232 U6): entering it marks its ◆ new goods as seen.
func p0_place() -> String: return str(outpost.get("id", ""))

## Today's Show for a request handed in here (`outpost:<this id>`, q(204) ⑨: Ivo's in his Mine Hut): the camera goes to
## the resident whose request is taken, else the room's first resident; other targets as any room's.
func p0_has_spot(where: String) -> bool:
	return resident_spot(where) != "" or super.p0_has_spot(where)

func p0_show_spot(where: String) -> void:
	var n := resident_spot(where)
	if n == "":
		super.p0_show_spot(where)
		return
	var m := anchor(n)
	_focus = Vector3(m.global_position.x, floor_y, m.global_position.z)
	_follow.hold()

## The npc_ anchor Today's `outpost:<this id>` points at: the resident here with a taken request, else the first one.
func resident_spot(where: String) -> String:
	if where != "outpost:" + p0_place(): return ""
	var view: Dictionary = rt.session.view if rt != null and rt.session != null else {}
	var first := ""
	for n in npcs:
		if n == "npc_keeper" or anchor(n) == null: continue
		if first == "": first = n
		var rv = view.get("residents", {}).get(str(npcs[n].id), {})
		if rv is Dictionary and str(rv.get("request_state", "")) == "accepted": return n
	return first

## Other players stand on the floor, or on their seat (room metres; the crowd lives in the room node).
func _crowd_height(id: int) -> float:
	var s := online.seat_of(id) if online else ""
	return (seat_root_y(s) if s != "" and _seat_anchor(s) else floor_y) - room.position.y

func to_room(world: Vector3) -> Vector3:
	return world - room.position

func _room_frame(_view: Dictionary, dt: float) -> void:
	_counter_shot()
	if not _glide.is_empty():
		_glide.t = float(_glide.t) + dt
		var p := _glide_point()
		actor.mover.position = Vector3(p.x, actor.mover.position.y, p.z)   # x / z here, y through ground_height
		actor.position = Vector3(p.x, actor.position.y, p.z)
		if float(_glide.t) >= float(_glide.dur) and _standing.is_empty(): _glide = {}
	if not _standing.is_empty():
		_standing.left = float(_standing.left) - dt
		if float(_standing.left) <= 0.0: _finish_stand()
	if crowd: crowd.step(dt, to_room(actor.position))

# ---------------------------------------------------------------- keeper and residents
# ---------------------------------------------------------------- the name sign (SGODOT-216; 不知火舞 216 5759f002)
## The kit's sign_name board, written at run time: the place's own word, as its map pin's label has it (P0Map.short_name,
## q(137) ①: `Oak`, `Union Square` — about 45 px wide on a phone, the whole name would not read; 不知火舞 216 ce290834),
## Nunito ExtraBold in walnut ink (#4A3424; #FFF6E5 when the anchor says `ink: light`), no outline, shadow or glow, flat
## on the board 2 mm in front of it, one-sided. Read up close, not from the opening view.
const SIGN_INK := Color("4A3424")
const SIGN_INK_LIGHT := Color("FFF6E5")
const SIGN_CAP := 0.55        # cap height, of the board's writable height
const SIGN_CAP_MIN := 0.35    # the smallest it shrinks to
const SIGN_SIDE := 0.06       # clear at each side, of its width
const SIGN_FONT_PX := 96      # the glyphs' raster; pixel_size scales them to metres
const CAP_OF_EM := 0.7        # Nunito's cap height, of its font size
const SIGN_FRONT_M := 0.002
const P0MapScript := preload("res://scenes/p0/p0_map.gd")   # its pins' short names

func _write_sign() -> void:
	var m := anchor("sign_name")
	var given = anchor_data("sign_name").get("size", [])
	var size := Vector2(float(given[0]), float(given[1])) if given is Array and given.size() >= 2 else Vector2.ZERO
	if m == null or size.x <= 0.0 or size.y <= 0.0 or place_name == "": return
	var font: Font = UiKit.theme().get_font(&"font", UiTokens.STYLE_BODY_XB14)
	var fit := sign_fit(place_name, font, size)
	var label := Label3D.new()
	label.name = "SignText"
	label.text = str(fit.text)
	label.font = font
	label.font_size = SIGN_FONT_PX
	label.pixel_size = float(fit.cap) / (SIGN_FONT_PX * CAP_OF_EM)
	label.modulate = SIGN_INK_LIGHT if str(anchor_data("sign_name").get("ink", "")) == "light" else SIGN_INK
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.rotation.y = PI                          # its text faces its +Z; the anchor faces its −Z (yaw_dir)
	label.position = Vector3(0, 0, -SIGN_FRONT_M)  # on the board, just in front
	m.add_child(label)

## The sign's words and cap height (metres) for a board `size` (writable width × height): the place's own word in one
## line at SIGN_CAP of the height, shrunk to fit the width less SIGN_SIDE a side, down to SIGN_CAP_MIN; then in two lines
## at the space nearest the middle at the smallest size, or smaller where the two lines would not fit the board (周瑜 on
## #692: two lines at 35 % stood 136 % of its height) — never cut.
static func sign_fit(name: String, font: Font, size: Vector2) -> Dictionary:
	var room_w := size.x * (1.0 - 2.0 * SIGN_SIDE)
	var place := P0MapScript.short_name(name)
	var em_w := font.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_FONT_PX).x / (SIGN_FONT_PX * CAP_OF_EM)   # width per metre of cap
	var cap := minf(size.y * SIGN_CAP, room_w / maxf(em_w, 0.0001))
	if cap >= size.y * SIGN_CAP_MIN - 0.00001: return {"text": place, "cap": cap}
	var best := -1
	for i in place.length():
		if place[i] == " " and (best < 0 or absf(i - place.length() / 2.0) < absf(best - place.length() / 2.0)): best = i
	var text := place if best < 0 else place.substr(0, best) + "\n" + place.substr(best + 1)
	var lines := text.split("\n")
	var widest := 0.0
	for l in lines: widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_FONT_PX).x)
	var per_cap := 1.0 / (SIGN_FONT_PX * CAP_OF_EM)   # metres per glyph px at a cap height of 1 m
	var tall := lines.size() * font.get_height(SIGN_FONT_PX) * per_cap   # the lines' height per metre of cap
	return {"text": text, "cap": minf(size.y * SIGN_CAP_MIN, minf(size.y / maxf(tall, 0.0001), room_w / maxf(widest * per_cap, 0.0001)))}

func _spawn_npcs() -> void:
	var data := P0RoomAnchors.read_json(NPCS_PATH).get("npcs", {}) as Dictionary
	var cast := {"npc_keeper": str(keeper.get("name", "")).to_lower()}
	# A generated city's keeper (SGODOT-280) is not in outpost_npcs.json: they wear their look preset (world.keeper_looks,
	# role × climate × 3) under their name plate. The hand-written keepers (Finn, Ama, Sigrid, Mei) keep their own.
	if not data.has(cast.npc_keeper) and keeper.has("look"):
		var looks: Dictionary = P0Logic.content().get("world", {}).get("keeper_looks", {})
		if looks.has(str(keeper.look)):
			data = data.duplicate()
			data[cast.npc_keeper] = {"name": str(keeper.get("name", "")), "scale": 1.0, "slots": looks[str(keeper.look)]}
	for id in outpost.get("residents", []):
		var def: Dictionary = data.get(str(id), {})
		if def.has("anchor"): cast[str(def.anchor)] = str(id)
	for n in cast:
		var spot := anchor(n)
		var def: Dictionary = data.get(cast[n], {})
		if spot == null or def.is_empty(): continue
		var root := Node3D.new()
		root.name = "Npc_" + str(cast[n])
		spot.add_child(root)
		root.scale = Vector3.ONE * float(def.get("scale", 1.0))
		var rig := Avatar.create_rig()
		rig.assembler = AvatarAssemblerMerged.new()
		rig.rotation.y = PI   # the rig faces +Z; the anchor's yaw is where the NPC faces
		# The room's orthographic camera stands 22–30 m off: past RigActivity's 16 m every keeper and resident slept on
		# their first frame (用户 on 0.3.4's market: 「市场的两个角色没有 idle 动画」). As the farm's residents (resident_cast).
		for child in rig.get_children():
			if child is RigActivity:
				child.reduced_distance = 50
				child.sleep_distance = 80
		root.add_child(rig)
		rig.config_applied.connect(func(_c): rig.play_motion("idle"))
		rig.apply_config(OnlineAppearance.config({"version": 1, "slots": def.get("slots", {})}, true))   # NPC-only parts (SGODOT-229) too
		# The name rides over the head as the UI's NpcNameTag (SGODOT-250, LOCK-16 v2), not a Label3D: see _marker.
		npcs[n] = {"id": str(cast[n]), "name": str(def.get("name", "")), "root": root}

# ---------------------------------------------------------------- taps
func _tappable() -> PackedStringArray:
	var out := PackedStringArray()
	for n in super._tappable():
		if DECOR.has(n): continue
		if P0RoomAnchors.prefix_of(n) == "npc" and not npcs.has(n): continue
		out.append(n)
	out.append_array(_lone_seats())
	return out

## The outpost's seats (its `seats`, the server's) no use_ anchor stands for — Grace Cathedral's eight pew seats
## (SGODOT-423; 黄忠: an i-seat over each): each its own prompt, a tap walks to that seat. A kit's other seat_ points
## (the tavern's bar stools under the card room, seats []) stay scenery.
func _lone_seats() -> PackedStringArray:
	var grouped := []
	for g in SEAT_GROUPS: if anchor(g) != null: grouped.append(str(SEAT_GROUPS[g]))
	var out := PackedStringArray()
	for n in outpost.get("seats", []):
		if anchor(str(n)) != null and not grouped.any(func(prefix): return str(n).begins_with(prefix)): out.append(str(n))
	return out

func _pews() -> bool: return PEW_KITS.has(str(outpost.get("art", "")))

## A pew's seat: from the aisle end of its pew (the layout's `approach`, in the anchors' own space), slid along it to
## the middle (_sit_down). Found once a seat: card_pick asks for every prompt's near point every frame, and a floor
## search for each of the eight seats each frame held Grace Cathedral at 22 fps on a phone (0.3.5, the user's vivo;
## about 9 ms a frame on an M4). The room and its pews do not move.
var _pew_points := {}
func _walk_point(n: String, target: Node3D) -> Vector3:
	if _pew_points.has(n): return _pew_points[n]
	var appr = anchor_data(n).get("approach", null)
	if _pews() and appr is Array and (appr as Array).size() == 3 and _lone_seats().has(n):
		var at := (target.get_parent() as Node3D).to_global(Vector3(float(appr[0]), float(appr[1]), float(appr[2])))
		var floor_at := reachable(at)   # the floor the door reaches (a layout moved: never slide on from afar, 周瑜)
		_pew_points[n] = floor_at if floor_at != Vector3.INF else super(n, target)
		return _pew_points[n]
	return super(n, target)

func _may_overlap(n: String) -> bool: return _pews() and _lone_seats().has(n)

## A pew's seat is near from where it is sat down from, its aisle end (its middle is between two rows).
func _near_point(n: String) -> Vector3:
	if _pews() and _lone_seats().has(n) and anchor(n): return _walk_point(n, anchor(n))
	return super(n)

## Standing, and done getting up: the seat prompts come back once the player is out of the pew (不知火舞 on #925: as
## they go the moment one sits, not while one still slides out past them).
func _on_feet() -> bool: return seat == "" and _standing.is_empty()

## A seat's anchor, or for an older client's seat q(304) took off, its pew's own.
func _seat_anchor(s: String) -> Marker3D:
	var m := anchor(s)
	return m if m != null or not LEGACY_SEATS.has(s) else anchor(str(LEGACY_SEATS[s]))

func p0_tap(screen: Vector2) -> void:
	if rt and rt.ui.has_modal(): return
	var n := tap_target(screen)   # a world prompt's tap goes to its own anchor, wherever its badge_ point puts it
	if n == "": return
	if not _standing.is_empty(): return
	var go := func():
		if SEAT_GROUPS.has(n): _go_sit(str(SEAT_GROUPS[n]))
		elif _lone_seats().has(n): _go_sit(n)   # a lone seat: that one, if free
		else: walk_to(n)
	if seat != "": _stand_up(go)
	else: go.call()

func _on_facility(n: String) -> void:
	if COUNTERS.has(n):
		_open_keeper()
	elif n.begins_with("seat_"): _claim(n)
	elif npcs.has(n):
		_open_resident(str(npcs[n].id), str(npcs[n].name))
	# Boards and shelves are facilities, not keepers: they open the market counter directly (LOCK-16 / 07).
	elif n == "use_market_board": _open_entry("open_counter", ["market", counter_opts("board")], "Market Board")
	elif n == "use_specialty_shelf":   # only where this city sells its postcard (SGODOT-296); else a prop
		if rt and P0CounterDrawer.has_specialty(rt.session.view): _open_entry("open_counter", ["market", counter_opts("specialty")], "City Specialty")
	elif n == "use_fish_board": _open_entry("open_bite_board", [outpost], "Bite Board")   # SGODOT-283 e61cda10 ③
	# q(165): the Stamp Desk opens the Passport (PASS-1, as from the profile; Back returns here), the Fare Board Trip fares
	elif n == "use_stamp_desk": _open_entry("open_passport", [], "Stamp Desk")
	elif n == "use_fee_board": _open_entry("open_fare_board", [], "Fare Board")
	# SGODOT-351: the card room's table opens the table page straight away (a facility, LOCK-07 v2; no greeting first)
	elif n == "use_blackjack_table": _open_entry("_play_blackjack", [keeper_ctx()], "Blackjack table")

## LOCK-16: keepers greet first, Trade opens the counter (SGODOT-224's open_keeper_greeting(role, ctx)).
func _open_keeper() -> void:
	if rt == null: return
	rt.ui.open_keeper_greeting(role, keeper_ctx())

## What P0Logic.keeper_lines takes from the outpost data (names and places are data, not UI copy): the keeper's
## name, the place ("Keeps the stall · Mission Market Square") and, for the tackle shop, the pond it names.
func keeper_ctx() -> Dictionary:
	var ctx := {"keeper": str(keeper.get("name", "")), "place": place_name, "outpost": str(outpost.get("id", ""))}   # outpost: its local requests (q(272))
	if keeper.has("look"): ctx["look"] = str(keeper.look)   # a generated keeper's portrait is drawn from it (SGODOT-300)
	if outpost.has("nearest"): ctx["nearest"] = (outpost.nearest as Dictionary).duplicate()
	return ctx

## open_counter opts for a facility that opens the counter without the greeting: the section, and the keeper ctx
## so the keeper bar has its name and place even when the player never greeted the keeper (224 keeps it per role).
func counter_opts(section: String) -> Dictionary:
	return {"section": section, "ctx": keeper_ctx()}

## LOCK-18: residents open the dialogue bar (SGODOT-225); open_resident() is false when the view has no such
## resident, and then only their name shows.
func _open_resident(id: String, resident_name: String) -> void:
	if rt == null: return
	if not (rt.ui.has_method("open_resident") and rt.ui.call("open_resident", id)): rt.ui.toast(resident_name)

## The resident within reach: a finger card's distance (CARD_NEAR_M), the nearest of several; "" when none.
## The bag's dish card offers `Gift to <Name>` for them (SGODOT-225, 不知火舞 / 李白 on 225).
func p0_near_resident() -> String:
	var best := ""
	var best_d := CARD_NEAR_M
	var residents: Dictionary = P0Logic.content().get("residents", {})
	for n in npcs:
		if not residents.has(str(npcs[n].id)): continue   # the keeper stands here too, but takes no gifts
		var a := anchor(n)
		if a == null: continue
		var d := _flat_distance(actor.position, a.global_position)
		if d < best_d:
			best_d = d
			best = str(npcs[n].id)
	return best

func _open_entry(method: String, args: Array, fallback: String) -> void:
	if rt == null: return
	if rt.ui.has_method(method): rt.ui.callv(method, args)
	else: rt.ui.toast(fallback)

## Counter push-in (room camera unification; 不知火舞 via 奕星, UI rule on 227): while a counter drawer is open (its
## board sheets too) the camera eases onto the keeper, the name tag over their head down to the counter top, centred in
## the band from the HUD's second row + 8 to the drawer's top - 8. A band under COUNTER_BAND_MIN px, or one that span
## does not fit at the push-in width, holds no shot: the camera stays and the KeeperBar's portrait and name stand for
## the keeper (LOCK-16). So the tea house, post office and market push in; the tackle shop's counter + bag (its top at
## y 104) does not. The HUD stays (two-row HUD, 197). The shot follows the drawer's height (the market settles shorter).
const COUNTER_BAND_MIN := 120.0
const COUNTER_BAND_PAD := 8.0
const COUNTER_SHOT_M := 4.2        # orthographic width of the push-in (fixed)
const COUNTER_TAG_PX := 28.0       # the keeper's name tag, highlighted, over NAME_OVER_HEAD
var _counter_top := -1.0           # the drawer top (UI px) the shot is framed for; -1 none

func _counter_shot() -> void:
	var drawer: P0CounterDrawer = rt.ui.counter_drawer() if rt else null
	var top := rt.ui.root.size.y - drawer.height if drawer != null else -1.0
	if is_equal_approx(top, _counter_top): return
	_counter_top = top
	var shot := counter_shot(top) if top >= 0.0 else {}
	if shot.is_empty():
		if str(_shot.get("anchor", "")) == "cam_counter": release_focus()
		return
	focus("cam_counter", shot)

## The push-in for a counter drawer whose top is at `top` (UI px): focus() options, with the cam_counter mark placed
## at the middle of the keeper's span (name tag top to counter top); {} when there is no room for it (see above).
func counter_shot(top: float) -> Dictionary:
	var counter: Marker3D = null
	for n in COUNTERS:
		if n != "npc_keeper" and anchor(n): counter = anchor(n)
	if counter == null or not npcs.has("npc_keeper"): return {}
	var view := _view()
	var band_top := _safe_top() + HUD_BOTTOM + COUNTER_BAND_PAD
	var band_h := top - COUNTER_BAND_PAD - band_top
	if band_h < COUNTER_BAND_MIN: return {}
	var forward := -_cam_dir
	var up := (Vector3.UP - forward * forward.dot(Vector3.UP)).normalized()
	var m_per_px := COUNTER_SHOT_M / maxf(view.x, 1.0)
	var head := (npcs.npc_keeper.root as Node3D).to_global(NAME_OVER_HEAD) + up * COUNTER_TAG_PX * m_per_px
	if (head - counter.global_position).dot(up) / m_per_px > band_h: return {}
	if not _anchors.has("cam_counter"):
		var mark := Marker3D.new()
		mark.name = "cam_counter"
		room.add_child(mark)
		_anchors["cam_counter"] = mark
	(_anchors.cam_counter as Marker3D).global_position = (head + counter.global_position) * 0.5
	return {band = Rect2(0.0, band_top / maxf(view.y, 1.0), 1.0, band_h / maxf(view.y, 1.0)), size = COUNTER_SHOT_M,
		release_on_move = false}

## Where an NPC's name sits, in the NPC's own space (above the head; the rig's root carries the NPC's scale).
const NAME_OVER_HEAD := Vector3(0, 2.0, 0)

## The opening shot shows the keeper whole, the name tag over their head included, and the counter (不知火舞 on 227,
## int12-pre: Ama stood off the tea house's opening shot). The tag counts at its highlighted height and a long name's
## half width either side, so `Ama` / `Sigrid` stay whole on screen. A room with no keeper (the Mine Hut, q(204)) opens
## on its resident the same way: the player and Ivo with his name tag, which keeps the shaft and the steps in view too
## (不知火舞 / 上官婉儿 on 308: the opening shot on the player alone cut the shaft and put Ivo on the edge). The other
## residents come in as opening_extras (不知火舞 on #465, 214 36bbf7b6: Finn at the back wall pulled the tackle shop's
## shot right and cut Old Kai in half at the left edge).
const OPENING_TAG_HALF_PX := 40.0
func opening_subjects() -> Array:
	var host := "npc_keeper" if npcs.has("npc_keeper") else ""
	if host == "":
		for n in npcs: if host == "": host = n   # no keeper: the room's first resident
	if host == "":   # nobody at all (Grace Cathedral, SGODOT-423): the room's middle, where its kit's camera looks
		var mid := anchor("cam_default")
		return [[mid.global_position]] if mid else []
	var keeper := _npc_points(host)
	var counter := []
	for n in COUNTERS:
		if n != "npc_keeper" and anchor(n): counter.append(anchor(n).global_position)
	return [keeper, counter] if not counter.is_empty() else [keeper]

## The room's other residents, each with their name tag whole, when they fit too (不知火舞 on #465).
func opening_extras() -> Array:
	var host := "npc_keeper" if npcs.has("npc_keeper") else ""
	var out := []
	for n in npcs:
		if host == "": host = n   # no keeper: the first resident is the host (opening_subjects)
		elif n != host: out.append_array(_npc_points(n))
	return out

## An NPC as the opening shot counts them: the feet and the name tag's two top corners.
func _npc_points(n: String) -> Array:
	var forward := -_cam_dir
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var m := cam.size / maxf(_view().x, 1.0)
	var root := npcs[n].root as Node3D
	var tag := root.to_global(NAME_OVER_HEAD) + up * COUNTER_TAG_PX * m
	return [root.global_position, tag - right * OPENING_TAG_HALF_PX * m, tag + right * OPENING_TAG_HALF_PX * m]
func _marker(n: String, view: Dictionary) -> Dictionary:
	if _dev_no_marks: return {}
	# World prompts (SGODOT-250, LOCK-07 / 16 / 30 v2, q(62)): names only, no "Tap to …"; the room opens one at a time.
	if npcs.has(n):
		# Talking while their greeting card or dialogue bar is up, however it opened (不知火舞 on #57: that NPC's name
		# stays lit over those two; P0Ui decides what shows under which modal). The keeper is this room's only keeper.
		var who := rt.ui.speaker() if rt != null else ""
		var talking := who != "" and who == ("keeper" if n == "npc_keeper" else str(npcs[n].id))
		# the keeper's own mark: a local request of theirs (q(272), 不知火舞 091a3ae9: ✓ first, then !)
		var mark := P0Locals.badge(view, str(outpost.get("id", ""))) if n == "npc_keeper" else ""
		return {kind = "npc", name = str(npcs[n].name), head = (npcs[n].root as Node3D).to_global(NAME_OVER_HEAD), talking = talking,
			badge = mark if mark != "" else P0Guide.resident_badge(view, str(npcs[n].id), str(outpost.get("id", "")))}
	if SEAT_GROUPS.has(n):
		return {kind = "seat", icon = P0Logic.icon("seat")} if _on_feet() and not _free_seats(str(SEAT_GROUPS[n])).is_empty() else {}
	if n.begins_with("seat_") and _lone_seats().has(n):   # a lone seat: its i-seat while it is free and the player stands
		return {kind = "seat", icon = P0Logic.icon("seat")} if _on_feet() and not _free_seats(n).is_empty() else {}
	if n == "use_market_board":
		var open := int(view.get("keepers", {}).get("market", {}).get("board_open", 0))
		return {kind = "facility", icon = P0Logic.icon("board"), name = "Market Board", badge = P0Guide.target_badge(view, "button", n, "request" if open > 0 else "")}
	if n == "use_specialty_shelf":
		return {kind = "facility", icon = P0Logic.icon("postcard"), name = "City Specialty"} if P0CounterDrawer.has_specialty(view) else {}
	if n == "use_fish_board": return {kind = "facility", icon = P0Logic.icon("board"), name = "Bite Board"}
	if n == "use_stamp_desk": return {kind = "facility", icon = P0Logic.icon("stamp"), name = "Stamp Desk"}   # q(62) / q(165)
	if n == "use_fee_board": return {kind = "facility", icon = P0Logic.icon("board"), name = "Fare Board"}   # q(165)
	if n == "use_blackjack_table": return {kind = "facility", icon = P0Outposts.cards_icon(), name = "Blackjack table"}   # q(238)
	return super._marker(n, view)

# ---------------------------------------------------------------- seats (茶桌 / 长椅, LOCK-30: the card says Sit)
func _free_seats(prefix: String) -> Array[Marker3D]:
	var taken := {}
	if online:
		for id in online.members:
			var s := str(online.members[id].get("seat", ""))
			if int(id) == online.self_id or s == "": continue
			taken[s] = true
			if LEGACY_SEATS.has(s): taken[str(LEGACY_SEATS[s])] = true   # an older client on the pew's second seat (q(304))
	var out: Array[Marker3D] = []
	for m in anchors(prefix):
		if not taken.has(str(m.name)): out.append(m)
	return out

## Walk to the nearest free seat of this furniture, then claim it.
func _go_sit(prefix: String) -> void:
	var free := _free_seats(prefix)
	if free.is_empty():
		if rt: rt.ui.toast("No free seat")
		return
	free.sort_custom(func(a, b): return _flat_distance(a.global_position, actor.position) < _flat_distance(b.global_position, actor.position))
	walk_to(str(free[0].name))

## The server holds one player per seat; without a connection the seat is ours.
func _claim(n: String) -> void:
	if online == null or online.epoch == 0:
		_sit_down(n)
		return
	var at := to_room(anchor(n).global_position)
	_sit_request = {"seq": online.sit(n, Vector2(at.x, at.z)), "seat": n}

func _on_result(seq: int, ok: bool, code: String) -> void:
	if _sit_request.is_empty() or int(_sit_request.seq) != seq: return
	var n := str(_sit_request.seat)
	_sit_request = {}
	if ok: _sit_down(n)
	elif code == "SEAT_TAKEN" and rt: rt.ui.toast("Someone's sitting there")

func _sit_down(n: String) -> void:
	var m := anchor(n)
	if m == null: return
	seat = n
	_standing = {}
	actor.lock(true)
	var to := Vector3(m.global_position.x, seat_root_y(n), m.global_position.z)
	var along := _pews() and _lone_seats().has(n)   # along a pew it takes as long as the slide; elsewhere 0.3 s as ever
	_glide_to(to, maxf(SIT_GLIDE_S, _flat_distance(actor.position, to) / SIT_SLIDE_MPS) if along else SIT_GLIDE_S)
	actor.face(actor.position + yaw_dir(float(anchor_data(n).get("yaw_degrees", 0))))
	_play_seated(actor.rig, true)

## sit_down then the sit_idle loop (in place: the hips stay over the seat anchor); cross-faded in.
static func _play_seated(rig: AvatarRig, from_standing: bool) -> void:
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation("sit_idle"): return
	if from_standing and ap.has_animation("sit_down"):
		ap.play("sit_down", CLIP_BLEND_S)
		ap.queue("sit_idle")
	else: ap.play("sit_idle", CLIP_BLEND_S)

## Ease the rig root (world position) to `to` over `dur` seconds; P0Actor follows ground_height for y.
func _glide_to(to: Vector3, dur: float) -> void:
	_glide = {from = actor.position, to = to, t = 0.0, dur = maxf(dur, 0.01)}

func _glide_point() -> Vector3:
	var k := ease(clampf(float(_glide.t) / float(_glide.dur), 0.0, 1.0), -2.0)
	return (_glide.from as Vector3).lerp(_glide.to, k)

## Rig root height (world) for a player on this seat: the seat anchor is the seat surface.
func seat_root_y(seat_name: String) -> float:
	var m := _seat_anchor(seat_name)
	return m.global_position.y - SIT_ROOT_BELOW_SEAT if m else floor_y

## Stand up: sit_up (sped up) while the root eases down to the floor beside the seat, then the player is
## released and `then` runs (walk to the door on Back, the tapped facility; the joystick moves on its own).
func _stand_up(then := Callable()) -> void:
	if seat == "":
		if then.is_valid(): then.call()
		return
	var m := anchor(seat)
	var at := m.global_position if m else actor.position
	seat = ""
	_sit_request = {}
	if online and online.epoch > 0: online.stand()
	# up beside the seat as before, but never into a gap the door's floor does not reach (Grace Cathedral, 李元芳 on
	# 0.3.1: stuck between the left rows) and in the open (STAND_CLEAR cells free all round: not wedged at a pew's end
	# with the front one hiding them). Not onto the kit's approach: the tea house's third table has its approach behind
	# Hana, and up there the player was hidden (不知火舞 on #850).
	# and not behind anyone in the room: up behind Hana at the tea house's third table the player was hidden (不知火舞)
	# a pew's seat (q(304)): up at the aisle end it was slid in from, along the pew — its middle is between two rows
	var pew := m != null and _pews() and _lone_seats().has(str(m.name))
	if pew: at = _walk_point(str(m.name), m)
	var floor_at := reachable(at, int(STAND_CLEAR.get(str(outpost.get("art", "")), 0)), npcs.values().map(func(x): return (x.root as Node3D).global_position))
	if floor_at == Vector3.INF: floor_at = actor.position
	var ap := actor.rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var dur := STAND_S if ap and ap.has_animation("sit_up") else 0.0
	if dur > 0.0: ap.play("sit_up", CLIP_BLEND_S, STAND_SPEED)
	if pew and dur > 0.0: dur = maxf(dur, _flat_distance(actor.position, floor_at) / SIT_SLIDE_MPS)
	_glide_to(Vector3(floor_at.x, floor_y, floor_at.z), dur)
	_standing = {left = dur, then = then}
	if dur <= 0.0: _finish_stand()

func _finish_stand() -> void:
	var s := _standing
	_standing = {}
	if not _glide.is_empty():
		actor.teleport(_glide.to)
		_glide = {}
	actor.lock(false)
	if (s.then as Callable).is_valid(): (s.then as Callable).call()

## Back while seated stands up first: the seat is inside the chair's collider, so the walk to the door
## would find no path from it. Back while already standing up (joystick, a tap) turns that into the walk out
## (哪吒's review of #14). The room has handled Back either way.
func is_back_navigation_locked() -> bool:
	if (seat != "" or not _standing.is_empty()) and not (rt and rt.ui.has_modal()):
		var out := func(): walk_to("exit")
		if seat != "": _stand_up(out)
		else: _standing.then = out
		return true
	return super.is_back_navigation_locked()

## The joystick stands a sitting player up before it moves them (movement resumes once standing).
func _on_joystick(v: Vector2) -> void:
	if seat != "" and v != Vector2.ZERO: _stand_up()

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"sit": _go_sit(step[1] if step.size() > 1 else "seat_table1_")
		"stand": _stand_up()
		"nomarks": _dev_no_marks = true   # acceptance shots: finger cards off, name tags stay
		"keeper": _open_keeper()   # a tap on the keeper: their greeting, with this outpost's local requests (q(272) shots)
		"biteboard": if rt: rt.ui.open_bite_board(outpost)   # the Bite Board as after tapping the board (SGODOT-283 shots)
		"fareboard": if rt: rt.ui.open_fare_board()   # Trip fares as after tapping the Fare Board (q(165) shots)
		"bitepond": if rt: rt.ui.open_board_pond(outpost, step[1])   # bitepond:<pond id> — a row's pond card
		"bitescroll":   # bitescroll — the open board scrolled to its end
			if rt and rt.ui.bite_board(): (rt.ui.bite_board().find_child("Scroll", true, false) as ScrollContainer).scroll_vertical = 100000
		"zoom":   # zoom:0.8 — a pinch to that zoom about the screen's centre (acceptance shots)
			_zoom_at = _view() * 0.5
			_set_zoom(float(step[1]) if step.size() > 1 else 1.0)
		_: return super.p0_dev(step)
	return true

func p0_until(n: String) -> bool:
	match n:
		"online": return online != null and online.epoch > 0
		"seated": return seat != ""
	return super.p0_until(n)
