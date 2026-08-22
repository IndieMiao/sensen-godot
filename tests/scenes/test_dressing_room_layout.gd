extends GdUnitTestSuite
## 布局回归：抽屉高度、网格列数、标签可横滚、角色区触摸穿透。
## 这四条任一退化都会直接复现"点不到/看不到"的线上问题。

const SCENE := "res://scenes/dressing_room/dressing_room.tscn"

func _instantiate() -> Node:
	var scene := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	return scene

func test_drawer_sits_at_bottom_with_expected_height() -> void:
	var s := _instantiate()
	var drawer := s.get_node("UI/SafeArea/VBox/Drawer") as PanelContainer
	assert_object(drawer).is_not_null()
	assert_float(drawer.custom_minimum_size.y).is_equal(296.0)

func test_spacer_passes_touches_through_for_rotation() -> void:
	var s := _instantiate()
	var spacer := s.get_node("UI/SafeArea/VBox/Spacer") as Control
	assert_object(spacer).is_not_null()
	# IGNORE 才能让 _unhandled_input 收到拖拽事件转动角色
	assert_int(spacer.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(spacer.size_flags_vertical).is_equal(Control.SIZE_EXPAND_FILL)

func test_parts_grid_has_four_columns() -> void:
	var s := _instantiate()
	var grid := s.get_node("UI/SafeArea/VBox/Drawer/VBox/PartsScroll/PartsGrid") as GridContainer
	assert_object(grid).is_not_null()
	assert_int(grid.columns).is_equal(4)

func test_slot_tabs_are_horizontally_scrollable() -> void:
	var s := _instantiate()
	var scroll := s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll") as ScrollContainer
	assert_object(scroll).is_not_null()
	# 标签必须能横滑，否则槽位多时最后几个（如 glasses）溢出屏幕点不到
	assert_bool(scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED).is_true()
	assert_int(scroll.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_object(s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll/SlotTabs")).is_not_null()

func test_action_buttons_share_width() -> void:
	var s := _instantiate()
	for name in ["SaveButton", "ResetButton", "SceneButton"]:
		var b := s.get_node("UI/SafeArea/VBox/Drawer/VBox/Buttons/" + name) as Button
		assert_object(b).is_not_null()
		assert_int(b.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
