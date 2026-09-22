extends GdUnitTestSuite
## Street mode keeps north/pitch fixed and permits zoom 15-18 with elastic limits.

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"
const REGION := {"id": "t", "name": "T", "street_zoom": 16.0, "pitch": 45.0, "center": [31.2, 121.4]}

func _map() -> Node:
	var scene := (load(MAP_POC_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	scene.enter_street_mode(REGION)
	return scene

func test_zoom_is_available_with_elastic_limits_and_fixed_pitch() -> void:
	var m := _map()
	m._set_zoom(18.0)
	assert_float(m.zoom).is_equal(18.0)
	var mag := InputEventMagnifyGesture.new()
	mag.factor = 2.0
	m._unhandled_input(mag)
	assert_float(m.zoom).is_equal(18.0)
	assert_float(m._zoom_elastic).is_greater(0.0)
	m._set_zoom(10.0)
	assert_float(m.zoom).is_equal(15.0)
	assert_float(m._zoom_elastic).is_less(0.0)
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 100)
	m._unhandled_input(pan)
	assert_float(m.pitch).is_equal(45.0)
	assert_float(m.bearing).is_equal(0.0)

func test_zoom_buttons_reach_limits_from_a_fractional_pinch_level() -> void:
	var m := _map()
	m._set_zoom(17.6)
	m._tween_zoom(m.zoom + 1)
	await get_tree().create_timer(0.35).timeout
	assert_float(m.zoom).is_equal(18.0)
	m._set_zoom(15.4)
	m._tween_zoom(m.zoom - 1)
	await get_tree().create_timer(0.35).timeout
	assert_float(m.zoom).is_equal(15.0)
	m._tween_zoom(14)
	assert_float(m._zoom_elastic).is_less(0)
	await get_tree().create_timer(0.65).timeout
	assert_float(m._zoom_elastic).is_equal_approx(0, 0.001)

func test_double_tap_starts_a_zoom_tween_while_browsing() -> void:
	var m := _map()
	# New farms use taps to move their chosen location; double-tap zoom belongs to browsing.
	m._placement_mode = false
	await get_tree().create_timer(0.01).timeout
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
	assert_object(m._zoom_tween).is_not_null()

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

## D3（2026-09-04 真机实测，vivo V2509A）：受限模式顶栏卡死在「Loading map...」。
## _update_load_bar() 用自由漫游的 INITIAL_ROLE_COUNT（1 自己 + 12 近处路人 +
## 10 洛杉矶夹具 = 23）当门禁；但受限模式下 _spawn_home_cohort() 不排近处路人
## （for i in (0 if street_mode else PAWNS_NEAR_COUNT)）、_spawn_la_fixture()
## 在 _ready() 里被 `if not street_mode` 整个跳过——ready 顶多到 1（玩家自己），
## 23 永远够不着，进度条永远不消失，顶部状态文案也永远卡在 "Loading map..."。
func test_load_bar_hides_after_the_single_player_pawn_is_ready_in_street_mode() -> void:
	var m := _map()
	assert_bool(m.street_mode).is_true()
	m._spawn_queue.clear()
	m._pawns.clear()
	var holder := Node3D.new()
	m.rigs.add_child(holder)
	m._pawns.append({"ready": true, "cohort": "self", "node": holder})
	m._map_is_ready = true
	m._header_locked = false
	m._load_bar_started_ms = Time.get_ticks_msec() - m.LOAD_BAR_MIN_VISIBLE_MS
	m._update_load_bar()
	assert_bool(m.load_bar.visible).is_false()
	assert_str(m._location_status_text()).is_not_equal("Loading map...")

## D4（收窄后的范围，2026-09-04）：受限模式下按设计不生成近处路人，人数
## 结构性恒为 0——"0 people" 是误导性的空信息，改成显示已选城市名字
## （region.name，来自 FarmRegions），比一个恒为零的数字更有意义。
## 自由漫游路径（street_mode == false）保持人数文案不变，见 test_map_ui.gd。
func test_nearby_label_shows_city_name_instead_of_zero_people_in_street_mode() -> void:
	var m := _map()
	m._header_locked = false
	m._refresh_header()
	assert_str(m.nearby_count.text).is_equal("T") # REGION.name
	assert_bool(m.nearby_count.text.contains("people")).is_false()
