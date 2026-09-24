extends GdUnitTestSuite

const SCENE := "res://scenes/landmark/griffith_observatory.tscn"
var _original_scene: Node
var _map_root: Node

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	FarmChoice.save("la_c", 2)
	FarmRegions.save_choice("los_angeles")
	_original_scene = get_tree().current_scene

func after_test() -> void:
	while AppRouter._navigation_pending: await get_tree().process_frame
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	get_tree().current_scene = _original_scene
	if is_instance_valid(_map_root):
		_map_root.queue_free()
		_map_root = null
	FarmChoice.clear()
	FarmRegions.clear_choice()
	UiState.clear()
	await get_tree().process_frame

func _scene() -> GriffithObservatory:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	viewport.own_world_3d = true
	add_child(auto_free(viewport))
	var scene := (load(SCENE) as PackedScene).instantiate() as GriffithObservatory
	viewport.add_child(scene)
	for frame in 120:
		await get_tree().physics_frame
		if scene.navigation_ready(): break
	scene.set_process(false)
	scene._update_camera()
	return scene

func _touch(scene: GriffithObservatory, point: Vector2, pressed: bool, index := 0, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	if pressed: scene._unhandled_input(event)
	else: scene._input(event)

func _drag(scene: GriffithObservatory, point: Vector2, index := 0) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point
	event.index = index
	scene._input(event)

func _swipe(scene: GriffithObservatory) -> Vector2:
	var start := Vector2(160, 380)
	_touch(scene, start, true)
	for i in 10:
		scene._process(1.0 / 60.0)
		_drag(scene, start + Vector2(8, 3) * (i + 1))
	var end := start + Vector2(80, 30)
	_touch(scene, end, false)
	return end

func test_entry_is_only_available_for_authored_griffith_in_los_angeles() -> void:
	var entry: Dictionary = CityMapData.landmarks("los_angeles")[1]
	assert_str(LandmarkScenes.path_for("los_angeles", entry)).is_equal(SCENE)
	assert_str(LandmarkScenes.path_for("shanghai", entry)).is_empty()
	entry.kind = "poi"
	assert_str(LandmarkScenes.path_for("los_angeles", entry)).is_empty()
	for other in CityMapData.landmarks("los_angeles"):
		if str(other.id) != "griffith_observatory":
			assert_str(LandmarkScenes.path_for("los_angeles", other)).is_empty()

func test_card_enters_once_and_back_restores_map_pose_selection_and_camera() -> void:
	_map_root = (load(AppRouter.MAP) as PackedScene).instantiate()
	get_tree().root.add_child(_map_root)
	get_tree().current_scene = _map_root
	await get_tree().process_frame
	var map := _map_root
	var entry: Dictionary = CityMapData.landmarks("los_angeles")[1]
	map.center_lat = entry.lat
	map.center_lng = entry.lng
	map.zoom = 14.7
	map._update_cameras()
	map.city_map.select(entry)
	assert_bool(map.city_map.info_action.visible).is_true()
	assert_str(map.city_map.info_action.text).is_equal(L10n.text("Enter scene"))
	var before := [map.center_lat, map.center_lng, map.zoom, map.bearing]
	var choice := FileAccess.get_file_as_string(FarmChoice.PATH)
	map.city_map.info_action.pressed.emit()
	map.city_map.info_action.pressed.emit()
	while AppRouter._navigation_pending: await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	var scene := AppRouter.top_instance() as GriffithObservatory
	assert_object(scene).is_not_null()
	assert_bool(map.visible).is_false()
	assert_that(map.world_env.environment).is_null()
	assert_object(get_viewport().get_camera_3d()).is_same(scene._camera)
	assert_bool(get_viewport().transparent_bg).is_false()
	AppRouter.handle_back()
	await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(0)
	assert_bool(map.visible).is_true()
	assert_object(get_viewport().get_camera_3d()).is_same(map.cam)
	assert_bool(get_viewport().transparent_bg).is_true()
	assert_array([map.center_lat, map.center_lng, map.zoom, map.bearing]).contains_exactly(before)
	assert_str(map.city_map.selected.id).is_equal("griffith_observatory")
	assert_str(FileAccess.get_file_as_string(FarmChoice.PATH)).is_equal(choice)
	map.city_map.select(CityMapData.landmarks("los_angeles")[0])
	assert_bool(map.city_map.info_action.visible).is_false()
	map.city_map._on_info_action()
	assert_int(AppRouter.instance_depth()).is_equal(0)

func test_scene_uses_farm_free_pan_without_farming_and_keeps_own_navigation() -> void:
	var scene := await _scene()
	assert_bool(scene.camera_pan.free_pan).is_true()
	assert_bool(scene.camera_pan.hold_enabled).is_false()
	assert_float(scene.camera_pan.min_zoom).is_equal(0.8)
	assert_float(scene.camera_pan.max_zoom).is_equal(1.4)
	assert_bool(scene._nav_map == scene.get_world_3d().navigation_map).is_false()
	assert_bool(Net.booted_once).is_false()
	assert_bool(Net.session.has_unconfirmed_command()).is_false()

func test_drag_coasts_decays_and_new_touch_stops_without_walking() -> void:
	var scene := await _scene()
	var player := scene._player.position
	var end := _swipe(scene)
	var camera := scene._camera.position
	var speed: float = scene.camera_pan.velocity.length()
	assert_float(speed).is_greater(0.1)
	scene._process(0.1)
	assert_float(scene._camera.position.distance_to(camera)).is_greater(0.01)
	assert_float(scene.camera_pan.velocity.length()).is_less(speed)
	assert_vector(scene._player.position).is_equal(player)
	assert_bool(scene._path.is_empty()).is_true()
	_touch(scene, end, true)
	camera = scene._camera.position
	scene._process(0.2)
	assert_vector(scene._camera.position).is_equal(camera)
	assert_vector(scene.camera_pan.velocity).is_equal(Vector3.ZERO)
	_touch(scene, end, false, 0, true)
	assert_bool(scene._path.is_empty()).is_true()

func test_short_tap_walks_and_does_not_follow_player() -> void:
	var scene := await _scene()
	var camera := scene._camera.position
	var target := NavigationServer3D.map_get_closest_point(scene._nav_map, Vector3(-3, 0, 3))
	var point := scene._camera.unproject_position(target)
	_touch(scene, point, true)
	_touch(scene, point + Vector2(2, 1), false)
	for i in 600: scene._process(1.0 / 60.0)
	assert_float(scene._player.position.distance_to(target)).is_less(0.2)
	assert_vector(scene._camera.position).is_equal(camera)
	assert_bool(Net.session.has_unconfirmed_command()).is_false()

func test_pinch_has_zoom_inertia_and_remaining_finger_never_walks() -> void:
	var scene := await _scene()
	_touch(scene, Vector2(150, 360), true, 4)
	_touch(scene, Vector2(230, 360), true, 9)
	scene._process(0.04)
	_drag(scene, Vector2(145, 360), 4)
	_drag(scene, Vector2(235, 360), 9)
	var zoom: float = scene.camera_pan.zoom
	assert_float(zoom).is_greater(1.0)
	_touch(scene, Vector2(235, 360), false, 9)
	var camera := scene._camera.position
	_drag(scene, Vector2(180, 410), 4)
	assert_vector(scene._camera.position).is_equal(camera)
	_touch(scene, Vector2(180, 410), false, 4)
	scene._process(0.05)
	assert_float(scene.camera_pan.zoom).is_greater(zoom)
	assert_bool(scene._path.is_empty()).is_true()
	for i in 240: scene._process(1.0 / 60.0)
	assert_float(scene.camera_pan.zoom).is_less_equal(1.4001)
	assert_float(scene.camera_pan.zoom).is_greater_equal(0.7999)

func test_background_and_suspend_cancel_gestures_and_reclaim_camera() -> void:
	var scene := await _scene()
	_swipe(scene)
	_touch(scene, Vector2(180, 400), true)
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(scene.camera_pan.active()).is_false()
	assert_bool(scene.camera_pan.moving()).is_false()
	scene.suspend()
	assert_bool(scene.visible).is_false()
	assert_bool(scene._hud.visible).is_false()
	assert_that(scene._environment.environment).is_null()
	scene.resume()
	assert_bool(scene.visible).is_true()
	assert_bool(scene._hud.visible).is_true()
	assert_object(scene.get_viewport().get_camera_3d()).is_same(scene._camera)
	assert_bool(scene.get_viewport().transparent_bg).is_false()

func test_all_terraces_remain_reachable_without_touching_farm_state() -> void:
	var scene := await _scene()
	var original_state := Net.session.state.duplicate(true)
	for target in [Vector3(-3, 0, 3), Vector3(-0.4, 0.5, -1.8), Vector3(-9.1, 0.5, -3), Vector3(10.2, 0.5, 0.1)]:
		var goal := NavigationServer3D.map_get_closest_point(scene._nav_map, target)
		scene.walk_to(goal)
		assert_int(scene._path.size()).is_greater(1)
		for i in 1800:
			scene._step_walk(1.0 / 60.0)
			if scene._path_i >= scene._path.size(): break
		assert_float(scene._player.position.distance_to(goal)).is_less(0.15)
		assert_float(scene._player.position.distance_to(NavigationServer3D.map_get_closest_point(scene._nav_map, scene._player.position))).is_less(0.1)
	assert_that(Net.session.state).is_equal(original_state)
