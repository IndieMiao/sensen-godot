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

## 打断惯性是"按下事件"的职责（_unhandled_input 的 pressed 分支清零），
## 不是 _step_fling 的。原先这条测试断言 _step_fling 在 _touch_count>0 时清零，
## 那恰好是 2026-09-01 真机上"完全没有惯性"的根因——见下面两条回归。
func test_touch_down_event_kills_fling() -> void:
	var n = auto_free(MapPoc.new())
	n._fling_vel = Vector3(200.0, 0.0, 0.0)
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = Vector2(100, 100)
	n._unhandled_input(press)
	assert_float(n._fling_vel.length()).is_equal(0.0)

## 回归（2026-09-01 真机）：手指按着的每一帧 _process 都会跑 _step_fling，
## 它当时把 _fling_vel 清零 → 一次 300ms 拖拽被清约 18 次 → 抬手那帧手指通常
## 已不动、没有新的 drag 事件补速度 → 惯性永远不触发。
## 所以按住期间必须"不推进但保住速度"。
func test_velocity_survives_frames_while_finger_is_down() -> void:
	var n = auto_free(MapPoc.new())
	var lng0: float = n.center_lng
	n._touch_count = 1
	n._fling_vel = Vector3(200.0, 0.0, 0.0)
	n._step_fling(1.0 / 60.0)
	assert_float(n._fling_vel.length()).is_equal_approx(200.0, 1e-6) # 速度没被清掉
	assert_float(n.center_lng).is_equal_approx(lng0, 1e-12) # 但按住期间不自己推进

func test_drag_frames_then_release_actually_flings() -> void:
	var n = auto_free(MapPoc.new())
	var lng0: float = n.center_lng
	n._touch_count = 1
	for i in 10: # 拖拽期间：每帧 drag 事件刷新速度，同帧 _process 也跑
		n._fling_vel = Vector3(200.0, 0.0, 0.0)
		n._step_fling(1.0 / 60.0)
	n._touch_count = 0 # 抬手，且该帧没有新的 drag 事件
	for i in 30:
		n._step_fling(1.0 / 60.0)
	assert_float(n.center_lng).is_greater(lng0) # 抬手后必须继续向东滑行

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

## —— 缩放轴惯性（2026-09-01 真机反馈：拖拽惯性有了，双指缩放松手即停）——

func test_zoom_fling_continues_and_decays_after_release() -> void:
	var n = auto_free(MapPoc.new())
	var z0: float = n.zoom
	n._touch_count = 0
	n._zoom_vel = 2.0 # zoom 单位/秒
	var steps := 0
	while absf(n._zoom_vel) >= MapPoc.ZOOM_FLING_MIN and steps < 2000:
		n._step_fling(1.0 / 60.0)
		steps += 1
	assert_float(n.zoom).is_greater(z0) # 松手后继续放大
	assert_bool(steps > 5).is_true() # 有滑行，不是一帧停死
	assert_bool(steps < 600).is_true() # 10 秒内停

func test_zoom_velocity_survives_frames_while_pinching() -> void:
	## 与平移轴同一个坑：按住期间 _step_fling 每帧都会跑到，不能清掉积累的速度
	var n = auto_free(MapPoc.new())
	n._touch_count = 2 # 双指
	n._zoom_vel = 2.0
	n._step_fling(1.0 / 60.0)
	assert_float(n._zoom_vel).is_equal_approx(2.0, 1e-6)

func test_touch_down_kills_zoom_fling() -> void:
	var n = auto_free(MapPoc.new())
	n._zoom_vel = 2.0
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = Vector2(100, 100)
	n._unhandled_input(press)
	assert_float(n._zoom_vel).is_equal(0.0)

func test_zoom_fling_respects_zoom_clamp() -> void:
	var n = auto_free(MapPoc.new())
	n.zoom = 19.5
	n._zoom_vel = 50.0 # 极速放大
	for i in 60:
		n._step_fling(1.0 / 60.0)
	assert_bool(n.zoom <= 20.0).is_true()

func test_pan_and_zoom_fling_are_independent() -> void:
	## 一个轴停了不该把另一个轴也掐掉
	var n = auto_free(MapPoc.new())
	n._touch_count = 0
	n._fling_vel = Vector3.ZERO # 平移已停
	n._zoom_vel = 2.0 # 缩放还在
	var z0: float = n.zoom
	n._step_fling(1.0 / 60.0)
	assert_float(n.zoom).is_greater(z0)

## —— 捏合不得泄漏 pan 惯性（2026-09-01 真机反馈）——
## 捏合抬手是一根一根抬的：第一根离开后 _touch_count 掉回 1，剩下那根往往还在动，
## 它的 drag 事件会通过 "_touch_count <= 1" 门禁把 pan 速度灌进 _fling_vel，
## 抬手就甩出一段用户没要的平移。

func _press(n, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.pressed = true
	e.position = pos
	n._unhandled_input(e)

func _release(n, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.pressed = false
	e.position = pos
	n._unhandled_input(e)

func _drag(n, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.position = pos
	e.relative = rel
	n._unhandled_input(e)

func test_second_finger_discards_pan_velocity_accumulated_by_first() -> void:
	var n = auto_free(MapPoc.new())
	_press(n, Vector2(100, 100))
	n._fling_vel = Vector3(200.0, 0.0, 0.0) # 第一指已攒出速度
	_press(n, Vector2(300, 100)) # 第二指落下 → 转为捏合
	assert_float(n._fling_vel.length()).is_equal(0.0)
	assert_bool(n._gesture_multi).is_true()

func test_lifting_one_finger_of_a_pinch_does_not_resume_pan_velocity() -> void:
	## 这是真机上"缩放时冒出一段平移惯性"的确切路径
	var n = auto_free(MapPoc.new())
	_press(n, Vector2(100, 100))
	_press(n, Vector2(300, 100)) # 双指
	_release(n, Vector2(300, 100)) # 抬起一根 → _touch_count 回到 1
	_drag(n, Vector2(160, 100), Vector2(60, 0)) # 剩下那根还在动
	assert_float(n._fling_vel.length()).is_equal(0.0) # 不得攒出 pan 速度

func test_gesture_multi_resets_after_all_fingers_lift() -> void:
	var n = auto_free(MapPoc.new())
	_press(n, Vector2(100, 100))
	_press(n, Vector2(300, 100))
	_release(n, Vector2(300, 100))
	_release(n, Vector2(100, 100)) # 全部离手
	assert_bool(n._gesture_multi).is_false()
	# 下一次单指拖拽必须恢复正常
	_press(n, Vector2(100, 100))
	assert_bool(n._gesture_multi).is_false()
