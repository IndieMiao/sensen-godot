extends GdUnitTestSuite
## q(295): Alcatraz and Griffith Observatory opened from the P0 map are P0 worlds that only walk (P0LandmarkVisit) —
## P0's HUD over them, no Journey chrome, the stick and taps walk, nothing sent; Alcatraz's taps reach the island
## through its invisible boundary walls.

const P0LandmarkVisit := preload("res://modules/p0/p0_landmark_visit.gd")
const ALCATRAZ := "res://scenes/landmark/alcatraz_island.tscn"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())

func after() -> void:
	P0Runtime.free_instance_for_tests()

func test_only_the_two_landmarks_have_a_scene() -> void:
	var lm := func(id: String): return {"kind": "landmark", "id": id}
	assert_str(LandmarkScenes.path_for("san_francisco", lm.call("alcatraz_island"))).is_equal(LandmarkScenes.ALCATRAZ)
	assert_str(LandmarkScenes.path_for("los_angeles", lm.call("griffith_observatory"))).is_equal(LandmarkScenes.GRIFFITH)
	assert_str(LandmarkScenes.path_for("san_francisco", lm.call("golden_gate_bridge"))).is_empty()
	assert_str(LandmarkScenes.path_for("los_angeles", lm.call("alcatraz_island"))).is_empty()   # its own city only
	assert_str(LandmarkScenes.path_for("san_francisco", {"kind": "poi", "id": "alcatraz_island"})).is_empty()
	assert_str(LandmarkScenes.region_of("alcatraz_island")).is_equal("san_francisco")
	assert_str(LandmarkScenes.region_of("hollywood_sign")).is_empty()
	assert_bool(LandmarkScenes.is_scene(LandmarkScenes.ALCATRAZ)).is_true()
	assert_int(AppRouter.back_action_for_scene(LandmarkScenes.ALCATRAZ)).is_equal(AppRouter.BACK_TO_MAP)

func test_args_name_the_place_for_the_chip_and_the_cover() -> void:
	var args := P0LandmarkVisit.args_for({"kind": "landmark", "id": "alcatraz_island", "name": "Alcatraz Island"}, "San Francisco")
	assert_bool(P0LandmarkVisit.wanted(args)).is_true()
	assert_str(str(args.chip)).is_equal("San Francisco · Alcatraz Island")
	assert_str(P0LoadingLayer.destination(LandmarkScenes.GRIFFITH, args)).is_equal("San Francisco · Alcatraz Island")
	assert_bool(P0LandmarkVisit.wanted({})).is_false()

## A world that is no space keeps where the player is: the chip on the map still goes back to the pond left.
func test_a_visit_keeps_the_way_back() -> void:
	var rt := P0Runtime.ensure()
	rt.return_to = "pond:pond_san_francisco_03"
	var scene := await _alcatraz()
	assert_object(rt.world).is_same(scene)
	assert_str(rt.session.space).is_equal("")
	assert_str(rt.ui.surface).is_equal("visit")
	assert_str(rt.return_to).is_equal("pond:pond_san_francisco_03")
	assert_object(scene.get_node_or_null("HUD")).is_null()   # no title, Map box, Follow or + / −

## The camera looks over the south boundary wall: a tap on the hillside (the review point mid_hill) walks up there,
## not to the dock's south edge (the tap stopped on SouthBoundary before).
func test_a_tap_goes_through_the_boundary_walls() -> void:
	var scene := await _alcatraz()
	var hill: Vector3 = scene.dev_point("mid_hill")
	scene.walk_to_screen(scene._camera.unproject_position(hill))
	assert_bool(scene.walking()).is_true()
	var end: Vector3 = scene._path[-1]
	assert_float(Vector2(end.x - hill.x, end.z - hill.z).length()).is_less(1.5)
	assert_float(end.y).is_greater(4.0)

## The stick walks the player along the ground the camera faces (up the screen: away from the camera).
func test_the_stick_walks() -> void:
	var scene := await _alcatraz()
	var from: Vector3 = scene.player_position()
	for i in 30: scene.step_stick(Vector2(0, -1), 1.0 / 30.0)
	assert_float(scene.player_position().z).is_less(from.z - 0.5)
	assert_bool(scene._running).is_true()
	scene.step_stick(Vector2.ZERO, 1.0 / 30.0)
	assert_bool(scene._running).is_false()

## 不知火舞 on #870: landed 1.1 m from the dock, its Map strip touched the player — the visit starts 2.2 m from it.
func test_the_player_starts_clear_of_the_door() -> void:
	var scene := await _alcatraz()
	var p: Vector3 = scene.player_position()
	var exit: Vector3 = scene.exit_position()
	assert_float(Vector2(p.x - exit.x, p.z - exit.z).length()).is_greater(2.1)

## 用户 0.3.2 (424 da2e9368): walking by the stick the player slid — with no tap path _step_walk set idle each frame and
## step_stick run again, and play_motion starts a clip over. Held, the run stays on through the scene's own frames.
func test_the_stick_walk_keeps_running() -> void:
	var scene := await _alcatraz()
	for i in 10:
		scene.step_stick(Vector2(0, -1), 1.0 / 30.0)
		scene._step_walk(1.0 / 30.0)
		assert_bool(scene._running).override_failure_message("frame %d" % i).is_true()
	scene.step_stick(Vector2.ZERO, 1.0 / 30.0)
	scene._step_walk(1.0 / 30.0)
	assert_bool(scene._running).is_false()   # let go: idle

## 用户 0.3.2 (424 da2e9368): zoomed out past their view width the flowerbeds, planters, bins, lamps and signs were hidden
## while their collision stayed — invisible walls. What stands in the way is drawn at every width; flowers and grass
## still go.
func test_what_blocks_the_way_stays_drawn_when_zoomed_out() -> void:
	var scene := await _alcatraz()
	var hidden_by_width: Array = scene._detail_batches.map(func(n): return str(n.name))
	for blocker in ["AlcFlowerbedBatch", "AlcPlanterBatch", "AlcBinBatch", "AlcLampBatch", "AlcSignBatch"]:
		assert_array(hidden_by_width).not_contains([blocker])
	assert_array(hidden_by_width).contains(["AlcGrassTuftBatch"])
	scene.camera_pan.reset(1.0 / 3.0)   # the widest view
	scene._update_camera()
	for n in scene.batch_nodes:
		if str(n.name) == "AlcFlowerbedBatch": assert_bool((n as Node3D).visible).is_true()

func _alcatraz() -> Node3D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	viewport.own_world_3d = true
	add_child(auto_free(viewport))
	var scene := (load(ALCATRAZ) as PackedScene).instantiate() as Node3D
	scene.call("setup", P0LandmarkVisit.args_for({"id": "alcatraz_island", "name": "Alcatraz Island"}, "San Francisco"))
	viewport.add_child(scene)
	for frame in 120:
		await get_tree().physics_frame
		if scene.navigation_ready(): break
	for frame in 10: await get_tree().physics_frame   # the zones' navigation meshes join a sync or two after the first
	scene.set_process(false)
	scene._update_camera()
	return scene
