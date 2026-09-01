extends GdUnitTestSuite
## 惯性：抬手后地图继续滑行并衰减到停；有手指按下时必须立刻停。
## 决策者点名"当前没有惯性，体验不丝滑"——原实现 InputEventScreenDrag 直接
## _apply_world_delta，抬手即停。

const MapPoc := preload("res://scenes/map_poc/map_poc.gd")

func test_fling_moves_center_east_and_decays_to_stop() -> void:
	var n = auto_free(MapPoc.new())
	var lng0: float = n.center_lng
	n._fling_vel = Vector3(200.0, 0.0, 0.0) # 200 m/s 向东（世界系 +x = 东）
	var steps := 0
	while n._fling_vel.length() >= MapPoc.FLING_MIN_SPEED and steps < 2000:
		n._step_fling(1.0 / 60.0)
		steps += 1
	assert_bool(n.center_lng > lng0).is_true() # 确实向东走了
	assert_bool(steps > 10).is_true() # 不是一帧停死，有滑行手感
	assert_bool(steps < 600).is_true() # 也不会滑个没完（10 秒内停）

func test_touch_down_kills_fling_immediately() -> void:
	var n = auto_free(MapPoc.new())
	n._fling_vel = Vector3(200.0, 0.0, 0.0)
	n._touch_count = 1
	n._step_fling(1.0 / 60.0)
	assert_float(n._fling_vel.length()).is_equal(0.0)

func test_double_tap_window_and_radius() -> void:
	var n = auto_free(MapPoc.new())
	n._last_tap_ms = 1000
	n._last_tap_pos = Vector2(100, 100)
	assert_bool(n._is_double_tap(1200, Vector2(105, 103))).is_true() # 200ms 内、5px 内
	assert_bool(n._is_double_tap(1500, Vector2(100, 100))).is_false() # 超时
	assert_bool(n._is_double_tap(1200, Vector2(200, 200))).is_false() # 距离太远

func test_fling_respects_latitude_clamp() -> void:
	## 极高速向北甩不得把中心拖过 Web Mercator 边界（拖过极点会东西镜像）
	var n = auto_free(MapPoc.new())
	n._fling_vel = Vector3(0.0, 0.0, -5.0e6)
	n._step_fling(1.0)
	assert_bool(n.center_lat <= 85.051129).is_true()
