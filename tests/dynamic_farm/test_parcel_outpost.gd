extends SceneTree
## C-115: the dynamic farm's 3D space (parcel_outpost.tscn), farm-dev's Travel Post room run without the
## P0 runtime, with Jasmine (Market) and Scott (Carpenter). Headless, on the local stand-in for the parcel save: the
## cast and prompts, a tap walks to the keeper and opens her greeting, a sale and the coop blueprint go through the
## save, the door returns to the map (AppRouter pops the room), and no P0 runtime, session or online room starts.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const RouterFixture = preload("res://tests/dynamic_farm/app_router_fixture.gd")
const SCENE := "res://scenes/dynamic_farm/parcel_outpost.tscn"
const T0 := 1795392000000
const DIR := "user://test_parcel_outpost"
const PARCEL := "p-3512001"
var checks := 0
var failures := 0

## The router as the map uses it: the room is its top instance and pops itself.
class Router extends Node:
	var stack: Array = []
	var pops := 0
	func top_instance() -> Node: return stack.back() if not stack.is_empty() else null
	func pop_instance() -> void:
		pops += 1
		var top: Node = stack.pop_back()
		if top.get_parent(): top.get_parent().remove_child(top)
		top.queue_free()

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	_clean()
	var router := Router.new()
	var real_router := RouterFixture.install(root, router)
	var store := LocalStore.new(PARCEL, DIR)
	store.now_ms = func() -> int: return T0
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {},
		"bag": {"crop_carrot": 2}, "welcomed_at": T0}), 3)
	var room: Node3D = (load(SCENE) as PackedScene).instantiate()
	room.setup({"store": store, "parcel_id": PARCEL, "met_path": DIR.path_join("met.json")})
	router.stack.append(room)
	root.add_child(room)
	for i in 6: await process_frame
	_check(not room.use_runtime and room.rt == null, "the room runs without the P0 runtime")
	_check(room.place_name == "Washington Square Travel Post" and room.layout_path.ends_with("post_office/layout.json"),
		"farm-dev's Travel Post kit, named after the map's Washington Square pin (C-115#30)")
	_check(room.npcs.has("npc_keeper") and room.npcs.npc_keeper.name == "Jasmine" and room.npcs.has("npc_sam")
		and room.npcs.npc_sam.name == "Scott" and room.npcs.size() == 2, "Jasmine at the counter, Scott where Sam stands, nobody else")
	var taps := Array(room._tappable())
	taps.sort()
	_check(taps == ["exit", "npc_keeper", "npc_sam", "use_counter"], "only the keeper, her counter, Scott and the door take taps (%s)" % [taps])
	var hud: Node = room.get_node_or_null("RoomHud")
	_check(hud != null and hud.find_child("TopBar", true, false) != null, "the room has its own top bar")
	var tags: Array = hud.find_children("Tag_*", "", true, false)
	var names := tags.map(func(t): return t.text)
	names.sort()
	_check(names == ["Jasmine", "Scott"], "the two names ride over their heads (%s)" % [names])
	_check(hud.find_child("Icon_exit", true, false) != null or hud.find_child("Strip_exit", true, false) != null, "the door has its Map prompt")
	_check(room._marker("exit", {}).name == "Map", "the door leads to the Map")
	# A tap on Jasmine: the player walks to the counter and her greeting opens.
	var at: Vector2 = room.cam.unproject_position(room.anchor("npc_keeper").global_position + Vector3(0, 1.0, 0))
	_check(room.tap_scene(at), "a tap on Jasmine is taken")
	var deadline := Time.get_ticks_msec() + 20000
	while not is_instance_valid(room.town) and Time.get_ticks_msec() < deadline: await process_frame
	_check(is_instance_valid(room.town) and room.town.who == "market", "walking up to Jasmine opens her greeting")
	if is_instance_valid(room.town):
		deadline = Time.get_ticks_msec() + 10000
		while room.town.busy and Time.get_ticks_msec() < deadline: await process_frame
		_check(room.town.card.title == "Market · Jasmine" and room.town.keys.has("trade"), "her greeting has Trade")
		_check(not room.tap_scene(room.cam.unproject_position(room.anchor("npc_sam").global_position)), "taps wait while she talks")
		_check(tags.all(func(t): return not t.visible), "the prompts step aside under the greeting")
		var sold: Dictionary = await room.town.sell("crop_carrot", 1)
		_check(sold.get("ok", false) and store.read().farm.coins == 12 and store.read().farm.sales == 1, "a sale goes through the parcel save")
		room.is_back_navigation_locked()   # Back closes the greeting, not the room
		await process_frame
		_check(not is_instance_valid(room.town) and room.is_inside_tree() and room.farm.get("coins") == 12,
			"Back closes the greeting; the room keeps the save it saw")
	# Scott, after that sale: the coop blueprint.
	room.walk_to("npc_sam")
	deadline = Time.get_ticks_msec() + 20000
	while not is_instance_valid(room.town) and Time.get_ticks_msec() < deadline: await process_frame
	_check(is_instance_valid(room.town) and room.town.who == "carpenter", "walking up to Scott opens his greeting")
	if is_instance_valid(room.town):
		deadline = Time.get_ticks_msec() + 10000
		while room.town.busy and Time.get_ticks_msec() < deadline: await process_frame
		_check(room.town.keys.has("take"), "after a sale Scott offers the blueprint")
		await room.town.claim_blueprint()
		_check(store.read().farm.bag.get("blueprint_coop") == 1, "the coop blueprint is in the parcel's bag")
		room.town.close()
		await process_frame
	_check(_no_p0_runtime(), "no P0 runtime, session or online room was started")
	# The door: walking out pops the room.
	var left := [false]
	room.left.connect(func(): left[0] = true)
	room.walk_to("exit")
	deadline = Time.get_ticks_msec() + 20000
	while router.pops == 0 and Time.get_ticks_msec() < deadline: await process_frame
	_check(left[0] and router.pops == 1, "walking out through the door returns to the map")
	await process_frame
	RouterFixture.restore(root, router, real_router)
	_clean()
	print("PARCEL_OUTPOST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _no_p0_runtime() -> bool:
	for n in root.find_children("*", "", true, false):
		var script: Script = n.get_script()
		if script != null and script.resource_path in ["res://modules/p0/p0_runtime.gd", "res://modules/p0/p0_online.gd"]: return false
	return true

func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR): return
	for name in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR.path_join(name))
