extends GdUnitTestSuite
## User int11 (SGODOT-231, 不知火舞): ① the mine's exits — the elevator's Ground, the exit ladder, the 04:00 kick-out —
## go back to the farm under the mine, not to the map; ② a tap on the mouth never enters (LOCK-21): it walks up to the
## mouth, pulses the main key there, or opens MINE-P0-8 with today's runs used up.

const P0Mine := preload("res://scenes/p0/p0_mine.gd")
const PROBE := "res://tests/fixtures/scenes/stack_probe.tscn"

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame

## The mine sits on the farm (the farm itself on the map, or the farm as the first session's root): leaving it pops that
## one layer. leave_world, the place chip's way to the map, took every exit to the map.
func test_leaving_the_mine_pops_only_the_mine() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.swap_root = func(): pass   # never the real scene change in a test
	var farm := AppRouter.push_instance(PROBE)
	var mine_layer := AppRouter.push_instance(PROBE)
	rt.world = mine_layer
	var mine = auto_free(P0Mine.new())   # not in the tree: only its exit
	mine.rt = rt
	mine.actor = auto_free(P0Actor.new())
	mine._leave()
	await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_bool(AppRouter.top_instance() == farm).is_true()
	assert_bool(is_instance_valid(mine_layer)).is_false()
	assert_bool(P0Runtime.room_leaves_for_map(1, true)).is_false()   # the mine on the farm root: also just one layer

func test_runs_spent_only_without_a_run_and_with_none_left() -> void:
	assert_bool(P0MaterialLogic.mine_runs_spent({"mine": {"runs": {"used": 2, "limit": 2}}})).is_true()
	assert_bool(P0MaterialLogic.mine_runs_spent({"mine": {"runs": {"used": 1, "limit": 2}}})).is_false()
	assert_bool(P0MaterialLogic.mine_runs_spent({"mine": {"run": {"floor": 2}, "runs": {"used": 2, "limit": 2}}})).is_false()

## Where a tap from afar walks to: walkable cells by the mouth, inside the reach that turns the key into Enter mine,
## nearest the player first.
func test_the_walk_ends_by_the_mouth_within_its_reach() -> void:
	var bp := P0Garden.blueprint()
	var grid := BlueprintGrid.new(bp)
	var mouth := bp.cell_to_world(bp.anchor("mine")) + Vector3(-0.3, 0, 0.3)
	var spawn := bp.cell_to_world(bp.anchor("spawn"))
	var stands := P0FarmMaterials.mouth_stands(grid, mouth, spawn)
	assert_bool(stands.is_empty()).is_false()
	var last := -1.0
	for p in stands:
		assert_bool(grid.astar.is_point_solid(bp.world_to_cell(p))).is_false()
		assert_float(P0FarmMaterials.flat(p, mouth)).is_less(P0FarmMaterials.MOUTH_REACH)
		assert_float(P0FarmMaterials.flat(p, spawn)).is_greater_equal(last)
		last = P0FarmMaterials.flat(p, spawn)
	assert_bool(grid.point_path(spawn, stands[0]).is_empty()).is_false()   # reachable from where a session starts

## A tap anywhere on the mouth's model counts, not only near its foot: its meshes' bounds on screen.
func test_the_whole_model_takes_the_tap() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 800)
	add_child(auto_free(vp))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.72
	vp.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 8, 8), Vector3.ZERO)
	var art: Node3D = preload("res://modules/mining/mine_art.gd").entrance()
	vp.add_child(art)
	var box := P0FarmMaterials.screen_box(cam, art)
	assert_bool(box.has_area()).is_true()
	assert_bool(box.has_point(cam.unproject_position(Vector3(0, 1.6, 0)))).is_true()   # high on the arch
	assert_bool(box.has_point(cam.unproject_position(Vector3(0, 0.1, 0)))).is_true()   # at its foot
	assert_bool(box.has_point(cam.unproject_position(Vector3(6, 0, 0)))).is_false()    # well beside it

## At the mouth the key pulses once: a 3 px ring from full out to +12 px, still full at 0.3 s (不知火舞 on #156 / #160).
func test_the_key_pulse_is_the_thicker_ring() -> void:
	var store := "user://test_p0_mine_exit.json"
	var ui := P0Ui.new()
	ui.quick_store = store
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view({"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000}, "bag": {"capacity": 25, "free": 25,
		"slots": []}, "plots": [], "coins": 40, "skills": {}, "rest": {"used": 0, "limit": 1, "resets_in": 1},
		"inbox": {"parcels": [], "letters": []}})
	ui.set_mode("farm")
	ui.set_surface("farm")
	await await_idle_frame()
	var pulse := ui.pulse_key()
	assert_object(pulse).is_not_null()
	assert_int(ui.key_pulses).is_equal(1)
	assert_float(pulse.stroke).is_equal(3.0)
	assert_float(pulse.start_alpha).is_equal(1.0)
	assert_float(pulse.grow_px).is_equal(12.0)
	pulse.progress = 0.75   # 0.3 s: still full (不知火舞 on #160)
	assert_float(pulse.ring_alpha()).is_equal(1.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store))
