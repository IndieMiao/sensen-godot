extends GdUnitTestSuite
## 回归：地图手势必须能穿过壳（AppShell → SafeArea → 列 → Pages → 地图页 → 页面容器）落到
## map_poc 的 _unhandled_input。2026-09-08 真机上「地图完全拖不动」，就是这条链上有满屏容器
## 默认 mouse_filter = STOP 把触摸吃光了。这里搭真壳 + 真地图场景，直接往视口推事件。

var shell: AppShell

func before_test() -> void:
	shell = (load(AppRoutes.SHELL) as PackedScene).instantiate() as AppShell
	add_child(auto_free(shell))

func after_test() -> void:
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
	get_viewport().push_input(_touch(mid, true))
	assert_int(map._touch_count).is_equal(1) # 触摸确实落到了地图
	get_viewport().push_input(_drag(mid + Vector2(0, 120), Vector2(0, 120)))
	get_viewport().push_input(_touch(mid + Vector2(0, 120), false))
	await get_tree().process_frame
	var after := Vector2(map.center_lat, map.center_lng)
	assert_bool(before.is_equal_approx(after)).is_false() # 相机跟手了

func test_tab_bar_still_receives_taps() -> void:
	var map := _map()
	await get_tree().process_frame
	var button := shell.tab_button(AppRoutes.TAB_IM)
	var center := button.get_global_rect().get_center()
	get_viewport().push_input(_touch(center, true))
	get_viewport().push_input(_touch(center, false))
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
	get_viewport().push_input(_touch(mid, true))
	get_viewport().push_input(_drag(mid + Vector2(0, 120), Vector2(0, 120)))
	get_viewport().push_input(_touch(mid + Vector2(0, 120), false))
	await get_tree().process_frame
	assert_int(map._touch_count).is_equal(0)
	assert_bool(before.is_equal_approx(Vector2(map.center_lat, map.center_lng))).is_true()
