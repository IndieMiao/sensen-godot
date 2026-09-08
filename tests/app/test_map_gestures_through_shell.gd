extends GdUnitTestSuite
## 回归：地图手势必须能穿过壳（AppShell → SafeArea → 列 → Pages → 地图页 → 页面容器）落到
## map_poc 的 _unhandled_input。2026-09-08 真机上「地图完全拖不动」，就是这条链上有满屏容器
## 默认 mouse_filter = STOP 把触摸吃光了。这里搭真壳 + 真地图场景，直接往视口推事件。

var shell: AppShell

func before_test() -> void:
	# 壳启动会读上次保存的 Tab（与 App 共用 user://）：不复位的话可能开在消息页，
	# 地图页 process_mode 是 DISABLED，输入根本不到地图，测试随上次运行状态飘。
	UiState.clear()
	shell = (load(AppRoutes.SHELL) as PackedScene).instantiate() as AppShell
	add_child(auto_free(shell))
	shell.show_tab(AppRoutes.TAB_MAP)

func after_test() -> void:
	UiState.clear()
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _map() -> Node:
	var page := shell.page(AppRoutes.TAB_MAP)
	page.ensure_map()
	return page.map_scene

func _touch(pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = pressed
	return e

func _drag(pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = rel
	return e

func test_drag_reaches_the_map_and_moves_the_camera() -> void:
	var map := _map()
	await get_tree().process_frame
	var before := Vector2(map.center_lat, map.center_lng)
	var mid := get_viewport().get_visible_rect().size * 0.5
	_push(_touch(mid, true))
	assert_int(map._touch_count).is_equal(1) # 触摸确实落到了地图
	_push(_drag(mid + Vector2(0, 120), Vector2(0, 120)))
	_push(_touch(mid + Vector2(0, 120), false))
	await get_tree().process_frame
	var after := Vector2(map.center_lat, map.center_lng)
	assert_bool(before.is_equal_approx(after)).is_false() # 相机跟手了

func test_tab_bar_still_receives_taps() -> void:
	var map := _map()
	await get_tree().process_frame
	var button := shell.tab_button(AppRoutes.TAB_IM)
	var center := button.get_global_rect().get_center()
	_push(_touch(center, true))
	_push(_touch(center, false))
	await get_tree().process_frame
	# 底栏按钮吃掉了这次触摸：地图不该把它当手势。
	assert_int(map._touch_count).is_equal(0)

## 反证：把壳的 SafeArea 改回默认（吃触摸），手势立刻到不了地图——证明上面两条用例真的守着这件事。
func test_a_full_screen_container_that_eats_touches_breaks_the_map() -> void:
	var map := _map()
	await get_tree().process_frame
	(shell.get_node("SafeArea") as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	var mid := get_viewport().get_visible_rect().size * 0.5
	var before := Vector2(map.center_lat, map.center_lng)
	_push(_touch(mid, true))
	_push(_drag(mid + Vector2(0, 120), Vector2(0, 120)))
	_push(_touch(mid + Vector2(0, 120), false))
	await get_tree().process_frame
	assert_int(map._touch_count).is_equal(0)
	assert_bool(before.is_equal_approx(Vector2(map.center_lat, map.center_lng))).is_true()

## 双指捏合：iOS 上 Godot 不合成 InputEventMagnifyGesture，必须从两个触点自己算（2026-09-08 真机没有缩放）。
func test_pinch_with_two_fingers_zooms() -> void:
	var map := _map()
	await get_tree().process_frame
	var mid := get_viewport().get_visible_rect().size * 0.5
	var before: float = map.zoom
	_push(_touch_at(0, mid - Vector2(40, 0), true))
	_push(_touch_at(1, mid + Vector2(40, 0), true))
	assert_int(map._touch_count).is_equal(2)
	# 两指各向外滑 40 px：间距 80 → 160，正好一级放大。
	_push(_drag_at(0, mid - Vector2(80, 0), Vector2(-40, 0)))
	_push(_drag_at(1, mid + Vector2(80, 0), Vector2(40, 0)))
	await get_tree().process_frame
	assert_float(map.zoom).is_greater(before)
	assert_float(map.zoom).is_equal_approx(before + 1.0, 0.05)
	# 收拢回去应该缩小。
	var zoomed: float = map.zoom
	_push(_drag_at(0, mid - Vector2(40, 0), Vector2(40, 0)))
	_push(_drag_at(1, mid + Vector2(40, 0), Vector2(-40, 0)))
	await get_tree().process_frame
	assert_float(map.zoom).is_less(zoomed)
	_push(_touch_at(0, mid, false))
	_push(_touch_at(1, mid, false))
	assert_int(map._touch_count).is_equal(0)
	assert_bool(map._touch_pos.is_empty()).is_true()

## 单指拖拽不该顺带缩放。
func test_single_finger_drag_does_not_zoom() -> void:
	var map := _map()
	await get_tree().process_frame
	var before: float = map.zoom
	var mid := get_viewport().get_visible_rect().size * 0.5
	_push(_touch_at(0, mid, true))
	_push(_drag_at(0, mid + Vector2(0, 120), Vector2(0, 120)))
	_push(_touch_at(0, mid + Vector2(0, 120), false))
	await get_tree().process_frame
	assert_float(map.zoom).is_equal(before)

func _touch_at(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	return e

func _drag_at(index: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	return e

## 捏合绕两指中点：同一屏幕点在缩放前后对应同一个地面点（真地图的手感）。
## 直接验 _zoom_at 的不变量——把两指事件拆成一步步推的模拟里，中点在两次事件之间必然偏移，
## 那是模拟的假象；真机上两指每帧只挪几像素，锚点跟着中点走正是想要的行为。
func test_zoom_at_keeps_the_ground_point_under_that_screen_point() -> void:
	var map := _map()
	await get_tree().process_frame
	var size := get_viewport().get_visible_rect().size
	var spot := Vector2(size.x * 0.3, size.y * 0.35) # 故意偏离屏幕中心
	var before = map._ground_point(spot)
	assert_object(before).is_not_null()
	map._zoom_at(spot, 1.0)
	await get_tree().process_frame
	var after = map._ground_point(spot)
	assert_object(after).is_not_null()
	assert_float(((before as Vector3) - (after as Vector3)).length()).is_less(1.0) # 米
	assert_float(map.zoom).is_equal_approx(17.0, 0.001)
	# 缩小同样成立。
	var b2 = map._ground_point(spot)
	map._zoom_at(spot, -1.5)
	await get_tree().process_frame
	assert_float(((b2 as Vector3) - (map._ground_point(spot) as Vector3)).length()).is_less(1.0)

## 捏合的锚点就是两指中点；双击的锚点是指尖。
func test_pinch_anchor_is_the_finger_midpoint() -> void:
	var map := _map()
	await get_tree().process_frame
	var mid := get_viewport().get_visible_rect().size * 0.5
	_push(_touch_at(0, mid - Vector2(40, 10), true))
	_push(_touch_at(1, mid + Vector2(40, 10), true))
	assert_vector(map._pinch_center()).is_equal(mid)
	_push(_touch_at(0, mid, false))
	_push(_touch_at(1, mid, false))
	# 不足两指时退化为屏幕中心，不该崩。
	assert_vector(map._pinch_center()).is_equal(get_viewport().get_visible_rect().size * 0.5)

## push_input 默认把事件当「窗口坐标」再按拉伸比例换算成视口坐标（本项目基准 360×640、窗口 720×1280，
## 位置会被折半）。手势位置相关的断言必须传局部坐标，否则点在哪都不对。
func _push(e: InputEvent) -> void:
	get_viewport().push_input(e, true)

