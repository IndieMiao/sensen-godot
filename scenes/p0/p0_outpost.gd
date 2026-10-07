extends P0Room
## A home-set outpost room (SGODOT-227) on the indoor shell (P0Room, SGODOT-226): the outpost's placeholder art
## and anchors, its keeper and residents at their npc_ anchors, tap-triggered counters and seats (LOCK-07), and
## the outpost's realtime room: P0Online + OnlineCrowd show the other players, and the server picks Room 1,
## Room 2 … (indoor 12, Market Square 30). Counters and residents open the panel entries of SGODOT-224 / 225
## when present; until then the tackle counter keeps the existing greeting.

const OnlineCrowd = preload("res://modules/net/online_crowd.gd")
const NPCS_PATH := "res://assets/p0/outpost_npcs.json"
## Drawn in the art but without a P0 use: no finger card, no tap (§17.2.1; SGODOT-227 5a63a8ec).
const DECOR := ["use_fish_board", "use_fee_board", "use_stamp_desk", "use_coffee_pot"]
## Tapping the counter is tapping the keeper (LOCK-15 / 16).
const COUNTERS := ["use_counter", "use_stall_1", "npc_keeper"]
## Furniture that seats: its seat_ anchors are seat_<group>_<n>.
const SEAT_GROUPS := {"use_tea_table_1": "seat_table1_", "use_bench": "seat_bench_"}

var outpost: Dictionary = {}
var role := ""
var keeper: Dictionary = {}
var online: P0Online
var crowd: Node3D
var npcs := {}           # npc anchor name → {id, name, root}
var seat := ""           # the seat we sit on ("" while standing)
var _sit_request := {}   # {seq, seat} waiting for the server

func setup(args: Dictionary) -> void:
	outpost = P0Outposts.find(str(args.get("outpost_id", "")))
	role = str(outpost.get("role", ""))
	keeper = outpost.get("keeper", {})
	place_name = str(outpost.get("name", "Outpost"))
	anchors_path = str(outpost.get("anchors", ""))
	if role == "market": exit_text = "Exit · Back to map"

func _room_ready() -> void:
	_spawn_npcs()
	crowd = OnlineCrowd.new()
	crowd.show_health = false
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

func to_room(world: Vector3) -> Vector3:
	return world - room.position

func _room_frame(_view: Dictionary, dt: float) -> void:
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
		rig.apply_config(OnlineAppearance.config({"version": 1, "slots": def.get("slots", {})}))
		var tag := Label3D.new()   # every NPC carries a name tag (art director, SGODOT-227)
		tag.text = str(def.get("name", ""))
		tag.font = GameUi.theme().default_font
		tag.font_size = 28
		tag.pixel_size = 0.006
		tag.position.y = 2.0
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(tag)
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
	var n := pick(screen)
	if n == "": return
	if seat != "": _stand_up()
	if SEAT_GROUPS.has(n): _go_sit(str(SEAT_GROUPS[n]))
	else: walk_to(n)

func _on_facility(n: String) -> void:
	if COUNTERS.has(n): _open_keeper()
	elif n.begins_with("seat_"): _claim(n)
	elif npcs.has(n): _open_resident(str(npcs[n].id), str(npcs[n].name))
	# Boards and shelves are facilities, not keepers: they open the market counter directly (LOCK-16 / 07).
	elif n == "use_market_board": _open_entry("open_counter", ["market", {"section": "board"}], "Market Board")
	elif n == "use_specialty_shelf": _open_entry("open_counter", ["market", {"section": "specialty"}], "City Specialty")

## LOCK-16: keepers greet first, Trade opens the counter (SGODOT-224's open_keeper_greeting(role)).
func _open_keeper() -> void:
	if rt == null: return
	if rt.ui.has_method("open_keeper_greeting"): rt.ui.call("open_keeper_greeting", role, {})
	elif role == "tackle": rt.ui.open_kai_greeting()   # the existing tackle greeting until 224 lands
	else: rt.ui.toast("%s · %s" % [str(keeper.get("role", "")), str(keeper.get("name", ""))])

## LOCK-18: residents open the dialogue bar (SGODOT-225).
func _open_resident(id: String, resident_name: String) -> void:
	_open_entry("open_resident", [id], resident_name)

func _open_entry(method: String, args: Array, fallback: String) -> void:
	if rt == null: return
	if rt.ui.has_method(method): rt.ui.callv(method, args)
	else: rt.ui.toast(fallback)

func _marker(n: String, view: Dictionary) -> Dictionary:
	if npcs.has(n): return {text = "%s · Tap to talk" % str(npcs[n].name)}
	if SEAT_GROUPS.has(n): return {text = "Sit"} if seat == "" and not _free_seats(str(SEAT_GROUPS[n])).is_empty() else {}
	if n == "use_market_board": return {text = "Market Board"}
	if n == "use_specialty_shelf": return {text = "City Specialty"}
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
	actor.teleport(Vector3(m.global_position.x, floor_y, m.global_position.z))
	actor.face(actor.position + yaw_dir(float(anchor_data(n).get("yaw_degrees", 0))))
	actor.lock(true)   # sit clips pending (sit_down / sit_idle / sit_up): idle on the seat until they land

func _stand_up() -> void:
	var m := anchor(seat)
	seat = ""
	_sit_request = {}
	actor.lock(false)
	if m:
		var p := P0RoomNav.nearest_walkable(bp, m.global_position)
		if p != Vector3.INF: actor.teleport(Vector3(p.x, floor_y, p.z))
	if online and online.epoch > 0: online.stand()

## The joystick stands a sitting player up before it moves them.
func _on_joystick(v: Vector2) -> void:
	if seat != "" and v != Vector2.ZERO: _stand_up()

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"sit": _go_sit(step[1] if step.size() > 1 else "seat_table1_")
		"stand": _stand_up()
		_: return super.p0_dev(step)
	return true

func p0_until(n: String) -> bool:
	match n:
		"online": return online != null and online.epoch > 0
		"seated": return seat != ""
	return super.p0_until(n)
