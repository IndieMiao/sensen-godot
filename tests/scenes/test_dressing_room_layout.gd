extends GdUnitTestSuite
## 布局回归：抽屉高度、网格列数、标签可横滚、角色区触摸穿透、抽屉不顶宽出安全区。
## 这些退化任一发生都会直接复现"点不到/看不到"的线上问题。

const SCENE := "res://scenes/dressing_room/dressing_room.tscn"

func _instantiate() -> Node:
	var scene := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	return scene

func test_drawer_sits_at_bottom_with_expected_height() -> void:
	var s := _instantiate()
	var drawer := s.get_node("UI/SafeArea/VBox/Drawer") as PanelContainer
	assert_object(drawer).is_not_null()
	assert_float(drawer.custom_minimum_size.y).is_equal(312.0)

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

func test_drawer_does_not_overflow_safe_area_on_four_part_slot() -> void:
	## 回归 Critical 缺陷：PartsGrid 4 列 + 3 间距的最小宽度（312）曾经比 Drawer
	## 的可用内宽更大，PartsScroll 横向不可滚动导致 Drawer 被顶宽出安全区，
	## 右侧安全边距被完全挤没——正是这个任务要修的原始"点不到"bug。
	## 用真实 manifest 里恰好有 4 个部件的槽位（hairHat/cloth）触发最坏情况。
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过")
		return
	var s := _instantiate()
	var target_slot: StringName = &""
	for slot_def in Avatar.slot_table.slots:
		if Avatar.catalog.parts_for_slot(slot_def.slot_name).size() >= 4:
			target_slot = slot_def.slot_name
			break
	if target_slot == &"":
		push_warning("没有部件数 >= 4 的槽位可测，跳过")
		return
	var safe_area := s.get_node("UI/SafeArea") as MarginContainer
	var viewport_size: Vector2 = s.get_viewport().get_visible_rect().size
	# 真机在无缺口机型上系统上报整屏，SafeAreaMargin 退回对称的 min_margin=16。
	# 这台跑测机器的宿主屏幕（非本项目窗口）也有摄像头缺口，headless 下
	# DisplayServer.get_display_safe_area() 会把宿主屏幕的不对称缺口数据带进来，
	# 导致结果随跑测机器漂移。用 Task 3 设计的注入式入口强制成"无缺口"这一
	# 最坏可用宽度场景（对称 16/16），与 review 里 328≥312 的推导前提对齐。
	safe_area.apply_margins(Rect2i(), DisplayServer.window_get_size(), viewport_size)
	var parts_panel := s.get_node("UI/SafeArea/VBox/Drawer/VBox")
	parts_panel._show_slot(target_slot)
	# GridContainer/Container 的尺寸重算是延迟到 sort_children 通知的，等两帧让它落地
	await s.get_tree().process_frame
	await s.get_tree().process_frame
	var drawer := s.get_node("UI/SafeArea/VBox/Drawer") as PanelContainer
	var margin_l: float = safe_area.get_theme_constant(&"margin_left")
	var margin_r: float = safe_area.get_theme_constant(&"margin_right")
	var content_w := viewport_size.x - margin_l - margin_r
	assert_float(drawer.size.x).is_less_equal(content_w)
