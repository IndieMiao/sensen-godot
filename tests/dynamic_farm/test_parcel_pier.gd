extends SceneTree
## C-232: the Aquatic Park pier (parcel_pier.tscn), headless on the local stand-in for the parcel save: the model's four
## contours (SEN-C-233's when it is in the build, else the stand-in pier), the first visit's Starter Rod, a tap on the
## water at two different points of the edge walks there and casts toward the tap (the owner on SEN-C-233#50: the
## whole edge fishes), the reel plays (auto_play) and the save takes the server-side result, the bait chip, Back to the map.
##   godot --headless --path . --script res://tests/dynamic_farm/test_parcel_pier.gd
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fishing = preload("res://modules/dynamic_farm/parcel_fishing.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const RouterFixture = preload("res://tests/dynamic_farm/app_router_fixture.gd")
const SCENE := "res://scenes/dynamic_farm/parcel_pier.tscn"
const T0 := 1795392000000
const DIR := "user://test_parcel_pier"
const PARCEL := "p-3512001"
var checks := 0
var failures := 0
var _start := 0

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

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for name in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR.path_join(name))

func _run() -> void:
	_clean()
	_start = Time.get_ticks_msec()
	var router := Router.new()
	var real_router := RouterFixture.install(root, router)
	var store := LocalStore.new(PARCEL, DIR)
	store.now_ms = func() -> int: return T0 + Time.get_ticks_msec() - _start
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"bait_worm": 2},
		"welcomed_at": T0 - 86400000, "coins": 40}), 3)
	var pier: Node3D = (load(SCENE) as PackedScene).instantiate()
	pier.setup({"store": store, "parcel_id": PARCEL})
	router.stack.append(pier)
	root.add_child(pier)
	pier.panel.auto_play = true
	var deadline := Time.get_ticks_msec() + 10000
	while (pier.farm.is_empty() or pier.busy) and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame
	var model := ResourceLoader.exists(pier.PIER_SCENE)
	print("pier model: ", pier.PIER_SCENE if model else "stand-in")
	_check(pier.walk_polygon.size() >= 3 and pier.stand_polygon.size() >= 3 and pier.fish_edge.size() >= 2 and pier.water_polygon.size() >= 3,
		"the pier's four contours read (walk_polygon, stand_polygon, fish_edge, water_polygon)")
	_check(pier.water_y < -0.5, "the water lies under the deck (%.2f)" % pier.water_y)
	_check(pier.bp.is_walkable(pier.bp.world_to_cell(pier.actor.position)), "the player starts on the deck at the entrance")
	# First visit: the Starter Rod, once.
	_check(int(pier.farm.bag.get("rod_starter", 0)) == 1 and Fishing.fishing_of(pier.farm.fishing).gifted_at != null, "the first visit gives a Starter Rod")
	_check(pier.toast.current_text() == "Received Starter Rod ×1", "… and says so")
	# Two taps on the water on two sides of the pier: two different edge points, both cast toward the tap.
	var spots := _two_spots(pier)
	_check(spots.size() == 2, "two water points with an edge point each")
	if spots.size() < 2:
		_finish(router, real_router)
		return
	var a: Dictionary = pier.cast_plan(spots[0])
	var b: Dictionary = pier.cast_plan(spots[1])
	_check(a.origin.distance_to(b.origin) > 1.0, "the two casts stand at different points of the edge (%.1f m apart)" % a.origin.distance_to(b.origin))
	for p: Dictionary in [a, b]:
		_check(pier.bp.is_walkable(pier.bp.world_to_cell(p.origin)) and Geometry2D.is_point_in_polygon(Vector2(p.target.x, p.target.z), pier.water_polygon)
			and Vector2(p.origin.x, p.origin.z).distance_to(Vector2(p.target.x, p.target.z)) <= pier.MAX_CAST_M + 0.01,
			"stands on the deck, lands on the water within reach")
	var deck: Vector3 = pier.walkable_point(pier.entrance)
	_check(pier.cast_plan(Vector3(deck.x, pier.water_y, deck.z)).is_empty(), "a point under the deck is not a cast")
	var energy_before := int(pier.farm.energy.value)
	for i in 2:
		var spot: Vector3 = spots[i]
		var screen: Vector2 = pier.cam.unproject_position(spot)
		_check(pier.tap_scene(screen), "tap %d on the water is taken" % (i + 1))
		deadline = Time.get_ticks_msec() + 30000
		while not pier.panel.visible and Time.get_ticks_msec() < deadline: await process_frame
		_check(pier.panel.visible and is_instance_valid(pier.view), "tap %d: walked to the edge and the panel opened" % (i + 1))
		var stood: Vector3 = pier.actor.position
		var want: Dictionary = a if i == 0 else b
		_check(Vector2(stood.x, stood.z).distance_to(Vector2(want.origin.x, want.origin.z)) <= pier.ARRIVE_M + pier.CELL_M,
			"tap %d: the player stands at its edge point" % (i + 1))
		deadline = Time.get_ticks_msec() + 45000
		while pier.panel.phase != "result" and Time.get_ticks_msec() < deadline: await process_frame
		var last = Fishing.fishing_of(pier.farm.fishing).last
		_check(pier.panel.phase == "result" and last is Dictionary and str(last.result) in ["landed", "escaped"],
			"tap %d: the reel played out and the save took its result (%s)" % [i + 1, str(last)])
		if last is Dictionary and str(last.result) == "landed":
			_check(int(pier.farm.bag.get(str(last.fish), 0)) >= 1 and pier.panel.last_result().outcome == "caught", "a landed fish is in the bag")
		_check(Fishing.fishing_of(pier.farm.fishing).cast == null, "no line left in the water")
		await pier.panel.close()
		await process_frame
		_check(not is_instance_valid(pier.view) and pier.actor.state != "locked", "closing the panel hands the player back")
	var f: Dictionary = ParcelFarm.rules().fishing
	_check(int(Fishing.fishing_of(pier.farm.fishing).casts) == 2, "two casts went to the save")
	_check(int(pier.farm.energy.value) <= energy_before - 2 * int(f.refund_fail) + 1, "each cast cost Energy")
	# The bait chip: none → Worm Bait → none.
	_check(pier.baits_in_bag() == ["bait_worm"] and pier._bait_key.visible and pier.selected_bait() == null, "the chip shows with a Worm in the bag, no bait picked")
	pier.cycle_bait()
	_check(pier.selected_bait() == "bait_worm" and pier._bait_count.text == "×2", "a tap picks the Worm Bait (×2)")
	pier.cycle_bait()
	_check(pier.selected_bait() == null, "another tap: no bait")
	# Back: to the map.
	pier.leave()
	for i in 3: await process_frame
	_check(router.pops == 1, "Back pops the pier")
	_finish(router, real_router)

## Two water points ~3 m out from fish_edge at a fifth and four fifths of its length, each on the side the water is.
func _two_spots(pier: Node3D) -> Array:
	var out := []
	var edge: PackedVector2Array = pier.fish_edge
	var total := 0.0
	for i in edge.size() - 1: total += edge[i].distance_to(edge[i + 1])
	for share in [0.2, 0.8]:
		var left: float = total * float(share)
		for i in edge.size() - 1:
			var seg := edge[i].distance_to(edge[i + 1])
			if left > seg:
				left -= seg
				continue
			var along: Vector2 = (edge[i + 1] - edge[i]).normalized()
			var at: Vector2 = edge[i] + along * left
			for side in [1.0, -1.0]:
				var w: Vector2 = at + Vector2(-along.y, along.x) * float(side) * 3.0
				if Geometry2D.is_point_in_polygon(w, pier.water_polygon) and not Geometry2D.is_point_in_polygon(w, pier.walk_polygon):
					out.append(Vector3(w.x, pier.water_y, w.y))
					break
			break
	return out

func _finish(router: Node, real_router: Node) -> void:
	RouterFixture.restore(root, router, real_router)
	print("PARCEL_PIER checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
