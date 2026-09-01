extends GdUnitTestSuite
## 惯性：抬手后地图继续滑行并衰减到停；有手指按下时必须立刻停。
## 决策者点名"当前没有惯性，体验不丝滑"——原实现 InputEventScreenDrag 直接
## _apply_world_delta，抬手即停。

const MapPoc := preload("res://scenes/map_poc/map_poc.gd")
const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"

## 双击缩放的两条 Tween 用例需要节点真的在场景树里（create_tween() 的前提）。
## 早先试过 add_child(auto_free(MapPoc.new()))：裸脚本实例没有 $Sun/$HUD/...
## 这些子节点，_ready() 里直接崩溃。改成子类覆写 _ready() 为空能避免崩溃，
## 但 @onready 变量的隐式初始化不受 _ready() 覆写影响，仍会为每个缺失的子节点
## 打一条 "Node not found" ERROR，把测试输出弄脏。实例化真正的 .tscn 没有这个
## 问题（子节点都在），耗时也在个位数十毫秒，两全。
func _instantiate_map_poc() -> Node:
	var scene := (load(MAP_POC_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	return scene

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

func test_step_fling_clamps_delta_like_drag() -> void:
	## 拖拽路径对每次 delta 用 limit_length(_cam_distance()) 限幅，注释写明原因：
	## 一次拖拽不限幅能把地图甩出上百公里。fling 路径此前没有对称限幅——帧率
	## 抖动或极端速度下，单帧就能把地图甩出几千公里，是同一个洞、不对称的补丁。
	var n = auto_free(MapPoc.new())
	var lat0: float = n.center_lat
	# 限幅发生在 center_lat 变化之前，取同一时刻的值比较——事后再算 _cam_distance()
	# 会因为 center_lat 已经挪动、cos(lat) 略微变了而产生虚假的几十厘米级偏差。
	var d0: float = n._cam_distance()
	n._fling_vel = Vector3(0.0, 0.0, -5.0e6) # 极端速度：不限幅一步就能甩出几千公里
	n._step_fling(1.0)
	var moved_m: float = (n.center_lat - lat0) * MapGeoMath.M_PER_DEG_LAT
	assert_float(moved_m).is_less_equal(d0 + 0.01)

func test_second_finger_press_does_not_trigger_double_tap() -> void:
	## 捏合起手：第二根手指的落点往往在时间和距离上都离第一指很近，若不比照
	## 拖拽路径加 _touch_count 门禁，会被误判成双击，在用户捏合手势中途
	## 叠加一次意外缩放。
	var n = auto_free(SpyMapPoc.new())
	n._touch_count = 1 # 已有一指按下
	n._last_tap_ms = Time.get_ticks_msec()
	n._last_tap_pos = Vector2(100, 100)
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = Vector2(102, 101) # 时间、距离都落在双击判定窗口内
	n._unhandled_input(ev)
	assert_int(n.zoom_tween_calls).is_equal(0)
	assert_bool(n._last_tap_pos == Vector2(100, 100)).is_true() # 第二指不覆盖单指落点记录

func test_double_tap_zoom_tweens_not_instant() -> void:
	## 瞬变实现会让 zoom 在调用后立刻等于目标值——这正是决策者点名"不丝滑"的
	## 另一半，此前测试从未调用过 _tween_zoom，对这条毫无保护。
	var n = _instantiate_map_poc()
	var z0: float = n.zoom
	n._tween_zoom(z0 + 1.0)
	assert_object(n._zoom_tween).is_not_null()
	assert_bool(n._zoom_tween.is_running()).is_true()
	assert_float(n.zoom).is_equal(z0) # 调用后还没推进，证明是过渡而非瞬变

func test_double_tap_zoom_tween_replaces_previous() -> void:
	## 双击的双击：第二次 _tween_zoom 必须杀掉第一个 tween，不留两条并行变焦。
	var n = _instantiate_map_poc()
	n._tween_zoom(n.zoom + 1.0)
	var first_tween: Tween = n._zoom_tween
	n._tween_zoom(n.zoom + 1.0)
	assert_bool(first_tween.is_running()).is_false()
	assert_object(n._zoom_tween).is_not_same(first_tween)
	assert_bool(n._zoom_tween.is_running()).is_true()

## 测试替身：把 _tween_zoom 换成计数器，用来验证"是否试图缩放"而不需要节点在
## 场景树里（create_tween() 的前提是节点在树中，但这条只关心门禁，不关心 Tween 本身）。
class SpyMapPoc extends MapPoc:
	var zoom_tween_calls := 0
	func _tween_zoom(_target: float) -> void:
		zoom_tween_calls += 1
