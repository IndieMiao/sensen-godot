extends P0Room
## A home-set outpost room (SGODOT-227) on the indoor shell (P0Room, SGODOT-226): the outpost's room kit (its
## `art` in p0_outposts.json, a Scene_design scene standing in until SGODOT-218) and anchors, its keeper and
## residents at their npc_ anchors, tap-triggered counters and seats (LOCK-07), and the outpost's realtime room:
## P0Online + OnlineCrowd show the other players, and the server picks Room 1, Room 2 … (indoor 12, Market
## Square 30). Counters and residents open the panel entries of SGODOT-224 / 225 when present; until then the
## tackle counter keeps the existing greeting.

const OnlineCrowd = preload("res://modules/net/online_crowd.gd")
const NPCS_PATH := "res://assets/p0/outpost_npcs.json"
## Drawn in the art but without a P0 use: no finger card, no tap (§17.2.1; SGODOT-227 5a63a8ec).
const DECOR := ["use_fish_board", "use_fee_board", "use_stamp_desk", "use_coffee_pot"]
## Tapping the counter is tapping the keeper (LOCK-15 / 16).
const COUNTERS := ["use_counter", "use_stall_1", "npc_keeper"]
## Furniture that seats: its seat_ anchors are seat_<group>_<n>.
const SEAT_GROUPS := {"use_tea_table_1": "seat_table1_", "use_tea_table_2": "seat_table2_", "use_bench": "seat_bench_"}
## sit_idle puts the hip joint 0.426 m above the rig root and the thighs rest about 0.086 m below the joint
## (measured on the base rig, SGODOT-227), so a seated root sits this far below the seat surface.
const SIT_ROOT_BELOW_SEAT := 0.34
## sit_up runs at this speed; the player is released once it is upright.
const STAND_SPEED := 2.0
const STAND_S := 0.55
## The root eases onto the seat within this time (art director: aligned within 0.3 s); clips cross-fade in.
const SIT_GLIDE_S := 0.3
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
	actor.ground_height = func(_p: Vector3) -> float:
		if not _glide.is_empty(): return _glide_point().y
		return seat_root_y(seat) if seat != "" else floor_y
	crowd = OnlineCrowd.new()
	crowd.show_health = false
	crowd.height_of = _crowd_height
	room.add_child(crowd)   # remote players arrive in room metres, like the anchors
	if use_runtime and not outpost.is_empty(): _go_online(P0Runtime.ensure().session)

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
	o.appearance = OnlineAppearance.payload(Avatar.load_outfit())
	attach_online(o)
	var door := anchor_data("spawn")
	var at := P0RoomAnchors.vec(door.get("position", [0, 0, 0]))
	online.start(str(outpost.id), Vector2(at.x, at.z))

## Wires a room connection to this room: the crowd, our position in room metres, joins and seat results.
func attach_online(o: P0Online) -> void:
	online = o
	o.crowd = crowd
	o.source = func(): return {"position": to_room(actor.position), "yaw": atan2(actor.facing().x, actor.facing().z),
		"action": "run" if actor.state == "move" else "idle"}
	add_child(o)
	o.joined.connect(_on_joined)
	o.result.connect(_on_result)

## Room 2 and later say so once; Room 1 and a reconnect to the same room say nothing (SGODOT-227 28c0580b).
func _on_joined(info: Dictionary) -> void:
	var n := int(info.get("room", 1))
	if n > 1 and not bool(info.get("rejoined", false)) and rt: rt.ui.toast("Room %d is full · you're in Room %d" % [n - 1, n])
	if seat != "": _stand_up()   # a new connection starts standing

## The space every P0 command carries (SGODOT-228 Rest "away from the farm"): outposts are "outpost".
func p0_space() -> String: return "outpost"

## Which outpost, for the server (蒙恬's map markers, SGODOT-232 U6): entering it marks its ◆ new goods as seen.
func p0_place() -> String: return str(outpost.get("id", ""))

## Other players stand on the floor, or on their seat (room metres; the crowd lives in the room node).
func _crowd_height(id: int) -> float:
	var s := online.seat_of(id) if online else ""
	return (seat_root_y(s) if s != "" and anchor(s) else floor_y) - room.position.y

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
func _spawn_npcs() -> void:
	var data := P0RoomAnchors.read_json(NPCS_PATH).get("npcs", {}) as Dictionary
	var cast := {"npc_keeper": str(keeper.get("name", "")).to_lower()}
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
	return out

func p0_tap(screen: Vector2) -> void:
	if rt and rt.ui.has_modal(): return
	var n := tap_target(screen)   # a world prompt's tap goes to its own anchor, wherever its badge_ point puts it
	if n == "": return
	if not _standing.is_empty(): return
	var go := func():
		if SEAT_GROUPS.has(n): _go_sit(str(SEAT_GROUPS[n]))
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
	elif n == "use_specialty_shelf": _open_entry("open_counter", ["market", counter_opts("specialty")], "City Specialty")

## LOCK-16: keepers greet first, Trade opens the counter (SGODOT-224's open_keeper_greeting(role, ctx)).
func _open_keeper() -> void:
	if rt == null: return
	rt.ui.open_keeper_greeting(role, keeper_ctx())

## What P0Logic.keeper_lines takes from the outpost data (names and places are data, not UI copy): the keeper's
## name, the place ("Keeps the stall · Xuhui Market Square") and, for the tackle shop, the pond it names.
func keeper_ctx() -> Dictionary:
	var ctx := {"keeper": str(keeper.get("name", "")), "place": place_name}
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
	var drawer: Control = null
	if rt and rt.ui.modal_kind in P0Ui._COUNTER_FLOW and is_instance_valid(rt.ui._counter): drawer = rt.ui._counter
	var top := rt.ui.root.size.y - float(drawer.get("height")) if drawer != null else -1.0
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
func _marker(n: String, view: Dictionary) -> Dictionary:
	if _dev_no_marks: return {}
	# World prompts (SGODOT-250, LOCK-07 / 16 / 30 v2, q(62)): names only, no "Tap to …"; the room opens one at a time.
	if npcs.has(n):
		# Talking while their greeting card or dialogue bar is up, however it opened (不知火舞 on #57: that NPC's name
		# stays lit over those two; P0Ui decides what shows under which modal). The keeper is this room's only keeper.
		var who := rt.ui.speaker() if rt != null else ""
		var talking := who != "" and who == ("keeper" if n == "npc_keeper" else str(npcs[n].id))
		return {kind = "npc", name = str(npcs[n].name), head = (npcs[n].root as Node3D).to_global(NAME_OVER_HEAD), talking = talking}
	if SEAT_GROUPS.has(n):
		return {kind = "seat", icon = P0Logic.icon("seat")} if seat == "" and not _free_seats(str(SEAT_GROUPS[n])).is_empty() else {}
	if n == "use_market_board":
		var open := int(view.get("keepers", {}).get("market", {}).get("board_open", 0))
		return {kind = "facility", icon = P0Logic.icon("board"), name = "Market Board", badge = "request" if open > 0 else ""}
	if n == "use_specialty_shelf": return {kind = "facility", icon = P0Logic.icon("postcard"), name = "City Specialty"}
	return super._marker(n, view)

# ---------------------------------------------------------------- seats (茶桌 / 长椅, LOCK-30: the card says Sit)
func _free_seats(prefix: String) -> Array[Marker3D]:
	var taken := {}
	if online:
		for id in online.members:
			if int(id) != online.self_id and str(online.members[id].get("seat", "")) != "": taken[str(online.members[id].seat)] = true
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
	_glide_to(Vector3(m.global_position.x, seat_root_y(n), m.global_position.z), SIT_GLIDE_S)
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
	var m := anchor(seat_name)
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
	var floor_at := P0RoomNav.nearest_walkable(bp, at)
	if floor_at == Vector3.INF: floor_at = actor.position
	var ap := actor.rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var dur := STAND_S if ap and ap.has_animation("sit_up") else 0.0
	if dur > 0.0: ap.play("sit_up", CLIP_BLEND_S, STAND_SPEED)
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
		_: return super.p0_dev(step)
	return true

func p0_until(n: String) -> bool:
	match n:
		"online": return online != null and online.epoch > 0
		"seated": return seat != ""
	return super.p0_until(n)
