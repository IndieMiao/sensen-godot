extends GdUnitTestSuite

const Art = preload("res://scenes/p0/p0_sprinkler_art.gd")

class FarmStub extends Node3D:
	var bp := P0Garden.blueprint()
	var grid := BlueprintGrid.new(bp)

func after_test() -> void:
	P0Runtime._instance = null
	for path in ["user://test_244_bar.json", "user://test_244_tips.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _art() -> Node3D:
	var art := auto_free(P0FarmFacilities._sprinkler_art()) as Node3D
	add_child(art)
	return art

func test_whole_model_preserves_meshes_pivot_socket_material_and_idle_pose() -> void:
	var art := _art()
	var meshes := art.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_equal(2)
	assert_array(meshes.map(func(n): return str(n.name))).contains_exactly_in_any_order(["base", "head"])
	for mesh in meshes:
		assert_object(mesh.material_override).is_same(P0FarmFacilities.FarmArt.material())
		assert_int(mesh.mesh.get_surface_count()).is_equal(1)
	assert_vector(art.scale).is_equal(Vector3.ONE)
	assert_vector(art.head.position).is_equal_approx(Vector3(0, 0.42, 0), Vector3.ONE * 0.00001)
	assert_vector(art.spray_origin.position).is_equal_approx(P0FarmFacilities.HEAD, Vector3.ONE * 0.00001)
	assert_float(P0FarmFacilities.TAP_PX).is_equal(40.0)
	assert_bool(art.is_processing()).is_false()
	assert_object(art._drops).is_null()
	var start: Transform3D = art.head.transform
	art._process(10.0)
	assert_that(art.head.transform).is_equal(start)

func test_trigger_rotates_only_head_for_two_and_a_half_seconds_and_stops() -> void:
	var art := _art()
	var base := art.find_child("base", true, false) as Node3D
	var base_at := base.global_transform
	var pivot: Vector3 = art.head.global_position
	art.play()
	art.set_process(false)   # drive frame time deterministically
	assert_bool(art._drops.emitting).is_true()
	assert_vector(art._drops.global_position).is_equal_approx(art.spray_origin.global_position, Vector3.ONE * 0.00001)
	art._process(0.625)
	assert_float(art.head.rotation.y).is_equal_approx(PI / 2.0, 0.0001)
	assert_that(base.global_transform).is_equal(base_at)
	assert_vector(art.head.global_position).is_equal(pivot)
	art._process(10.0)   # a slow frame cannot extend the animation
	assert_float(art.remaining).is_equal(0.0)
	assert_bool(art.is_processing()).is_false()
	assert_bool(art._drops.emitting).is_false()
	var stopped: Transform3D = art.head.transform
	art._process(1.0)
	assert_that(art.head.transform).is_equal(stopped)

func test_retrigger_reuses_effect_without_duplicate_nodes_or_an_endless_loop() -> void:
	var art := _art()
	art.play()
	art.set_process(false)
	art._process(1.0)
	var drops: Node = art._drops
	var count := art.get_child_count()
	art.play()
	art.set_process(false)
	assert_object(art._drops).is_same(drops)
	assert_int(art.get_child_count()).is_equal(count)
	assert_float(art.remaining).is_equal(2.5)
	art._process(2.5)
	assert_bool(art._drops.emitting).is_false()

func _view() -> Dictionary:
	return {plots = [{id = 1.0, state = "tilled", crop = null}, {id = 2.0, state = "sown", crop = "crop_radish"},
		{id = 3.0, state = "growing", crop = "crop_radish"}, {id = 9.0, state = "sown", crop = "crop_radish"}],
		facilities = [{id = 5.0, kind = "sprinkler", plot = 7.0, covers = [1.0, 2.0, 3.0]},
			{id = 6.0, kind = "greenhouse", plot = 12.0, covers = [9.0]}]}

func test_authoritative_sow_and_placement_water_once_per_covering_sprinkler() -> void:
	var before := _view()
	var after := before.duplicate(true)
	after.plots[0].merge({state = "growing", crop = "crop_radish"}, true)
	after.plots[1].state = "growing"
	assert_array(P0FarmFacilities.watered_sprinklers(before, after)).is_equal([5])
	assert_array(P0FarmFacilities.watered_sprinklers(after, after.duplicate(true))).is_empty()
	before.facilities = []   # placing a new sprinkler on already-sown plots
	assert_array(P0FarmFacilities.watered_sprinklers(before, after)).is_equal([5])

func test_initial_load_refresh_fertilize_trees_and_other_sources_never_start_rotation() -> void:
	var before := _view()
	var after := before.duplicate(true)
	after.plots[3].state = "growing"   # greenhouse-only cover
	after.plots[2].ready_in = 1234   # a timer refresh or fertilizer
	assert_array(P0FarmFacilities.watered_sprinklers(before, after)).is_empty()
	after.plots[0].merge({state = "growing", crop = "crop_apple", tree = true}, true)
	assert_array(P0FarmFacilities.watered_sprinklers(before, after)).is_empty()
	assert_array(P0FarmFacilities.watered_sprinklers({}, after)).is_empty()
	before.facilities = []
	after.facilities = []
	after.plots[1].state = "growing"   # manual watering away from sprinklers
	assert_array(P0FarmFacilities.watered_sprinklers(before, after)).is_empty()

func test_state_subscription_and_open_card_trigger_the_real_model_without_snapshot_replays() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = "user://test_244_bar.json"
	rt.ui.tips_path = "user://test_244_tips.json"
	rt.session.transport = func(_m, _p, _b, _c): pass
	P0Runtime._instance = rt
	add_child(rt)
	rt.set_process(false)
	rt.session.set_process(false)
	var farm: FarmStub = auto_free(FarmStub.new())
	add_child(farm)
	rt.world = farm
	var before := _view()
	before.facilities.resize(1)
	rt.session.view = before
	var facilities := P0FarmFacilities.new().setup(farm)
	farm.add_child(facilities)
	facilities._sync_art(before.facilities)
	var art = facilities._art[5]
	assert_float(art.remaining).is_equal(0.0)
	var after := before.duplicate(true)
	after.plots[1].state = "growing"
	rt.session.view = after
	rt.session.state_changed.emit(after, [])
	assert_float(art.remaining).is_equal(2.5)
	art.set_process(false)
	art._process(2.5)
	rt.session.state_changed.emit(after, [])
	assert_float(art.remaining).is_equal(0.0)
	facilities.open_card(after.facilities[0])
	assert_float(art.remaining).is_equal(2.5)
	assert_int(facilities._highlight).is_equal(5)
	rt.ui.close_modal()
	art.set_process(false)
	art._process(2.5)
	rt.world = null
	facilities._water_view = before
	rt.session.state_changed.emit(after, [])
	assert_float(art.remaining).is_equal(0.0)   # no animation while another scene is active
	rt.world = farm
	facilities._water_view = before
	facilities._water_player = "another-account"
	rt.session.state_changed.emit(after, [])
	assert_float(art.remaining).is_equal(0.0)
	facilities.free()
	assert_bool(rt.session.state_changed.get_connections().any(func(c): return str(c.callable.get_method()) == "_water_changed")).is_false()
