extends GdUnitTestSuite

func test_reset_restores_neutral_pan_zoom_and_clears_gesture_inertia() -> void:
	var pan := preload("res://modules/farm/scene_pan.gd").new()
	pan.offset = Vector3(1, 0, 1)
	pan._raw_offset = Vector3(5, 0, 5)
	pan._log_zoom = log(1.4)
	pan._raw_zoom = log(2.0)
	pan.velocity = Vector3.ONE
	pan.zoom_velocity = 1
	pan.pointers[0] = Vector2.ONE
	pan.reset()
	assert_vector(pan.offset).is_equal(Vector3.ZERO)
	assert_vector(pan._raw_offset).is_equal(Vector3.ZERO)
	assert_float(pan.zoom).is_equal(1.0)
	assert_float(pan._raw_zoom).is_equal(0.0)
	assert_bool(pan.active()).is_false()
	assert_bool(pan.moving()).is_false()

const ScenePan = preload("res://modules/farm/scene_pan.gd")

func test_android_uses_raw_pinch_below_platform_minimum_span() -> void:
	assert_bool(ProjectSettings.get_setting("input_devices/pointing/android/enable_pan_and_scale_gestures", false)).is_false()
	assert_bool(ProjectSettings.get_setting("input_devices/pointing/android/disable_scroll_deadzone", false)).is_true()
	var camera := _camera()
	var controller := ScenePan.new()
	controller.begin(4, Vector2(140, 340))
	controller.begin(9, Vector2(220, 340))
	controller.step(0.04, camera)
	controller.motion(4, Vector2(145, 340), camera)
	controller.motion(9, Vector2(215, 340), camera)
	assert_float(controller.zoom).is_equal_approx(0.875, 0.0001)
	controller.end(4, Vector2(145, 340))
	controller.end(9, Vector2(215, 340))
	controller.step(0.05, camera)
	assert_float(controller.zoom).is_less(0.875)
	_settle(controller, camera)
	assert_float(controller.zoom).is_greater_equal(controller.min_zoom - 0.0001)

func _camera() -> Camera3D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	add_child(auto_free(viewport))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 10.8
	viewport.add_child(camera)
	camera.position = Vector3(3, 13, 12)
	camera.look_at(Vector3.ZERO)
	return camera

func _settle(controller: RefCounted, camera: Camera3D, seconds := 2.0, fps := 60) -> void:
	for frame in int(seconds * fps): controller.step(1.0 / fps, camera)

func _swipe(controller: RefCounted, camera: Camera3D, distance: Vector2) -> Vector2:
	var start := Vector2(180, 340)
	controller.begin(0, start)
	for frame in 10:
		controller.step(1.0 / 60, camera)
		controller.motion(0, start + distance * float(frame + 1) / 10, camera)
	return start + distance

func test_release_continues_pan_then_new_touch_stops_it() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	var end := _swipe(controller, camera, Vector2(25, 0))
	controller.end(0, end)
	var before: Vector3 = controller.offset
	var speed: float = controller.velocity.length()
	controller.step(0.1, camera)
	assert_float(controller.offset.distance_to(before)).is_greater(0.01)
	assert_float(controller.velocity.length()).is_less(speed)
	controller.begin(1, end)
	before = controller.offset
	controller.step(0.3, camera)
	assert_vector(controller.offset).is_equal(before)
	assert_vector(controller.velocity).is_equal(Vector3.ZERO)

func test_overdrag_has_resistance_then_returns_inside_the_boundary() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	var end := _swipe(controller, camera, Vector2(180, 80))
	assert_float(controller.offset.length()).is_greater(controller.radius)
	assert_float(controller.offset.length()).is_less_equal(controller.radius + ScenePan.PAN_ELASTIC)
	controller.end(0, end)
	var released: Vector3 = controller.offset
	controller.step(1.0 / 120, camera)
	assert_float(controller.offset.distance_to(released)).is_less(0.1)
	_settle(controller, camera)
	assert_float(controller.offset.length()).is_less_equal(controller.radius + 0.0001)
	assert_bool(controller.moving()).is_false()

func test_holding_before_release_drops_stale_pan_velocity() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	var end := _swipe(controller, camera, Vector2(25, 0))
	controller.step(0.4, camera)
	controller.end(0, end)
	var before: Vector3 = controller.offset
	_settle(controller, camera)
	assert_vector(controller.offset).is_equal(before)

func test_pinch_is_elastic_and_remaining_finger_neither_pans_nor_taps() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	var taps := []
	controller.tapped.connect(func(point): taps.append(point))
	controller.begin(0, Vector2(140, 340))
	controller.begin(1, Vector2(220, 340))
	for frame in 12:
		controller.step(1.0 / 60, camera)
		controller.motion(0, Vector2(140 - frame * 5, 340), camera)
		controller.motion(1, Vector2(220 + frame * 5, 340), camera)
	assert_float(controller.zoom).is_greater(controller.max_zoom)
	assert_float(controller.zoom).is_less_equal(controller.max_zoom * exp(ScenePan.ZOOM_ELASTIC))
	controller.end(0, Vector2(85, 340))
	var before: Vector3 = controller.offset
	var zoom: float = controller.zoom
	controller.motion(1, Vector2(300, 380), camera)
	controller.step(0.05, camera)
	assert_vector(controller.offset).is_equal(before)
	assert_float(controller.zoom).is_equal(zoom)
	controller.end(1, Vector2(300, 380))
	_settle(controller, camera)
	assert_float(controller.zoom).is_less_equal(controller.max_zoom + 0.0001)
	assert_bool(controller.active()).is_false()
	assert_array(taps).is_empty()

func test_zoom_out_rebounds_and_native_android_events_do_not_double_scale() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	controller.begin(0, Vector2(80, 340))
	controller.begin(1, Vector2(280, 340))
	controller.step(0.04, camera)
	controller.motion(0, Vector2(160, 340), camera)
	controller.motion(1, Vector2(200, 340), camera)
	var zoom: float = controller.zoom
	assert_float(zoom).is_less(controller.min_zoom)
	var native := InputEventMagnifyGesture.new()
	native.factor = 0.5
	assert_bool(controller.handle(native, camera, true)).is_true()
	assert_float(controller.zoom).is_equal(zoom)
	controller.end(0, Vector2(160, 340))
	controller.end(1, Vector2(200, 340))
	controller.handle(native, camera, true)
	assert_float(controller.zoom).is_equal(zoom)
	_settle(controller, camera)
	assert_float(controller.zoom).is_greater_equal(controller.min_zoom - 0.0001)
	assert_bool(controller.moving()).is_false()

func test_pinch_zoom_keeps_focal_point_and_coasts_after_release() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	var focus := Vector2(160, 340)
	var world: Vector3 = controller._ground(camera, focus)
	controller.begin(0, focus - Vector2(50, 0))
	controller.begin(1, focus + Vector2(50, 0))
	controller.step(0.04, camera)
	controller.motion(0, focus - Vector2(55, 0), camera)
	controller.motion(1, focus + Vector2(55, 0), camera)
	assert_float(camera.unproject_position(world).distance_to(focus)).is_less(0.01)
	controller.end(0, focus - Vector2(55, 0))
	controller.end(1, focus + Vector2(55, 0))
	var zoom: float = controller.zoom
	controller.step(0.05, camera)
	assert_float(controller.zoom).is_greater(zoom)

func test_inertia_and_spring_are_consistent_across_refresh_rates() -> void:
	var outcomes := []
	for fps in [30, 60, 120]:
		var camera := _camera()
		var controller := ScenePan.new()
		controller.offset = Vector3(1.4, 0, 0)
		controller.velocity = Vector3(3, 0, 1)
		controller.zoom_velocity = 1.8
		controller._zoom_focus = Vector2(180, 320)
		_settle(controller, camera, 0.5, fps)
		outcomes.append(Vector4(controller.offset.x, controller.offset.z, controller.zoom, controller.zoom_velocity))
	for outcome in outcomes:
		assert_float(outcome.distance_to(outcomes[0])).is_less(0.002)

func test_cancel_clears_all_pointers_and_inertia_without_changing_a_valid_view() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	_swipe(controller, camera, Vector2(25, 0))
	var before: Vector3 = controller.offset
	controller.cancel()
	_settle(controller, camera)
	assert_vector(controller.offset).is_equal(before)
	assert_bool(controller.active()).is_false()
	assert_bool(controller.moving()).is_false()

func test_android_native_pinch_scales_once_and_keeps_zoom_inertia() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	controller.native_touch_gestures = true
	controller.begin(0, Vector2(140, 340))
	controller.begin(1, Vector2(220, 340))
	controller.step(0.04, camera)
	controller.motion(0, Vector2(130, 340), camera)
	controller.motion(1, Vector2(230, 340), camera)
	assert_float(controller.zoom).is_equal(1.0)
	var event := InputEventMagnifyGesture.new()
	event.position = Vector2(180, 340)
	event.factor = 1.2
	assert_bool(controller.handle(event, camera)).is_true()
	assert_float(controller.zoom).is_equal_approx(1.2, 0.0001)
	controller.end(0, Vector2(130, 340))
	controller.end(1, Vector2(230, 340))
	controller.step(0.05, camera)
	assert_float(controller.zoom).is_greater(1.2)

func test_free_pan_has_no_radius_spring_and_cancel_keeps_the_view() -> void:
	var camera := _camera()
	var controller := ScenePan.new()
	controller.free_pan = true
	var end := _swipe(controller, camera, Vector2(240, 120))
	assert_float(controller.offset.length()).is_greater(controller.radius + ScenePan.PAN_ELASTIC)
	controller.end(0, end)
	_settle(controller, camera)
	assert_float(controller.offset.length()).is_greater(controller.radius + ScenePan.PAN_ELASTIC)
	var settled: Vector3 = controller.offset
	controller.cancel()
	assert_vector(controller.offset).is_equal(settled)
	assert_bool(controller.moving()).is_false()
