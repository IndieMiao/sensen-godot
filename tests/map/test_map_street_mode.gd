extends GdUnitTestSuite
## PRD §3.1：街区级固定浏览范围——固定 zoom/pitch/north-up，禁缩放旋转，只能在边界内平移。

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"
const REGION := {"id": "t", "name": "T", "street_zoom": 16.0, "pitch": 45.0, "center": [31.2, 121.4]}

func _map() -> Node:
	var scene := (load(MAP_POC_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	scene.enter_street_mode(REGION)
	return scene

func test_zoom_and_pitch_locked() -> void:
	var m := _map()
	m._set_zoom(18.0)
	assert_float(m.zoom).is_equal(16.0)
	var mag := InputEventMagnifyGesture.new()
	mag.factor = 2.0
	m._unhandled_input(mag)
	assert_float(m.zoom).is_equal(16.0)
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 100)
	m._unhandled_input(pan)
	assert_float(m.pitch).is_equal(45.0)
	assert_float(m.bearing).is_equal(0.0)

func test_double_tap_does_not_zoom() -> void:
	var m := _map()
	for k in 2:
		var down := InputEventScreenTouch.new()
		down.pressed = true
		down.position = Vector2(100, 100)
		m._unhandled_input(down)
		var up := InputEventScreenTouch.new()
		up.pressed = false
		up.position = Vector2(100, 100)
		m._unhandled_input(up)
	assert_float(m.zoom).is_equal(16.0)
	assert_object(m._zoom_tween).is_null()

func test_pan_clamped_to_bounds() -> void:
	var m := _map()
	m.set_pan_bounds(31.2, 121.4, 300.0)
	m._apply_world_delta(Vector3(5000.0, 0.0, 0.0))
	assert_float(m.center_lng).is_less_equal(m.pan_bounds.position.y + m.pan_bounds.size.y + 1e-9)
	m._apply_world_delta(Vector3(0.0, 0.0, 5000.0)) # 向南
	assert_float(m.center_lat).is_greater_equal(m.pan_bounds.position.x - 1e-9)

func test_fly_to_and_home_from_region() -> void:
	var m := _map()
	assert_float(m.home_lat).is_equal(31.2)
	assert_bool(m.street_mode).is_true()
	m.fly_to(31.3, 121.5)
	assert_float(m.center_lat).is_equal(31.3)
	assert_float(m.center_lng).is_equal(121.5)

func test_suspend_resume() -> void:
	var m := _map()
	m.suspend()
	assert_int(m.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_bool(m.visible).is_false()
	assert_bool(m.get_node("HUD").visible).is_false()
	m.resume()
	assert_int(m.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_bool(m.visible).is_true()
	assert_bool(m._camera_dirty).is_true()
