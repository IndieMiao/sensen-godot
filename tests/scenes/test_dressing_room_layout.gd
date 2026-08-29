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
	# 回归：Spacer 自己是 IGNORE 不够——它的祖先 SafeArea/VBox 只要有一个是默认
	# STOP，就会在事件传到 Spacer 之前把整个全屏容器的触摸事件吞掉，导致换装
	# 房间完全无法拖拽转身。变异测试证实了这条真实回归向量，且现有 96 个用例
	# 对此全部失明。
	var safe_area := s.get_node("UI/SafeArea") as Control
	var vbox := s.get_node("UI/SafeArea/VBox") as Control
	assert_object(safe_area).is_not_null()
	assert_object(vbox).is_not_null()
	assert_int(safe_area.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(vbox.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_parts_grid_has_four_columns() -> void:
	var s := _instantiate()
	var grid := s.get_node("UI/SafeArea/VBox/Drawer/VBox/PartsScroll/PartsGrid") as GridContainer
	assert_object(grid).is_not_null()
	assert_int(grid.columns).is_equal(4)

func test_slot_tabs_are_horizontally_scrollable() -> void:
	var s := _instantiate()
	var scroll := s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll") as ScrollContainer
	assert_object(scroll).is_not_null()
	# 标签必须能横滑，否则槽位多时最后几个（如 glass）溢出屏幕点不到
	assert_bool(scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED).is_true()
	assert_int(scroll.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_object(s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll/SlotTabs")).is_not_null()

func test_list_buttons_pass_touch_for_scroll() -> void:
	## 回归（2026-08-29 真机）：ScrollContainer 触摸滚动依赖按压事件冒泡到容器
	## （引擎在按压时开始拖拽跟踪，越过死区后 propagate NOTIFICATION_SCROLL_BEGIN
	## 取消子按钮按压——base_button.cpp 对该通知有专门处理）。列表内按钮若是默认
	## STOP，事件在按钮处截断，手指落在按钮上便只能拖滚动条。必须 PASS。
	var s := _instantiate()
	var tabs := s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll/SlotTabs")
	assert_int(tabs.get_child_count()).is_greater(0)
	for b in tabs.get_children():
		assert_int((b as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	var grid := s.get_node("UI/SafeArea/VBox/Drawer/VBox/PartsScroll/PartsGrid")
	assert_int(grid.get_child_count()).is_greater(0)
	for b in grid.get_children():
		assert_int((b as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)

func test_action_buttons_share_width() -> void:
	var s := _instantiate()
	for name in ["SaveButton", "ResetButton", "SceneButton"]:
		var b := s.get_node("UI/SafeArea/VBox/Drawer/VBox/Buttons/" + name) as Button
		assert_object(b).is_not_null()
		assert_int(b.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)

func test_equip_taller_part_triggers_camera_reframe() -> void:
	## 回归 Critical：equip()/unequip()（parts_panel 点缩略图走的正是这条路，见
	## parts_panel.gd 的 `rig.equip(current_slot, meta.id)`）只发 slot_applied，
	## 不发 config_applied（avatar_rig.gd:124-126，config_applied 只在
	## _initial_loading 为真的首次装配那次发出）。dressing_room.gd 若只连
	## config_applied，进场取景一次之后换任何部件相机都不会重新取景——戴上更高的
	## 帽子会直接切头顶，直接违反"能看到角色全身"的验收项。
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过")
		return
	var s := _instantiate()
	var rig: AvatarRig = s.rig
	var applied := []
	rig.config_applied.connect(func(c): applied.append(c))
	for i in 600:
		if applied.size() > 0:
			break
		await get_tree().process_frame
	assert_int(applied.size()).is_equal(1)
	# _reframe() 内部自身 await 一帧才真正取景，这里多等几帧让进场取景落定，
	# 拿到换装前的基线相机距离。
	for i in range(5):
		await get_tree().process_frame
	var cam: DressingCamera = s.cam
	var before_z := cam.position.z
	var target := ""
	for meta in Avatar.catalog.parts_for_slot(&"hairHat"):
		if meta.id == "hairhat101":  # manifest 里 hairHat 槽最高的部件（收敛后 size.y≈2.0m）
			target = meta.id
			break
	if target == "":
		push_warning("hairhat101 不在 manifest 里，跳过")
		return
	var slots_applied := []
	rig.slot_applied.connect(func(slot, part_id): slots_applied.append([slot, part_id]))
	rig.equip(&"hairHat", target)
	for i in 600:
		if slots_applied.size() > 0:
			break
		await get_tree().process_frame
	assert_int(slots_applied.size()).is_greater(0)
	for i in range(5):
		await get_tree().process_frame
	assert_float(cam.position.z).is_greater(before_z)

func _assert_body_within_usable_area(cam: DressingCamera, rig: AvatarRig, drawer: PanelContainer, safe_area: MarginContainer) -> void:
	var box := DressingCamera.merged_aabb(rig)
	assert_float(box.size.y).is_greater(0.0)
	var cx := box.position.x + box.size.x * 0.5
	var cz := box.position.z + box.size.z * 0.5
	var top_screen := cam.unproject_position(Vector3(cx, box.position.y + box.size.y, cz))
	var bottom_screen := cam.unproject_position(Vector3(cx, box.position.y, cz))
	var top_bound: float = safe_area.get_theme_constant(&"margin_top")
	var bottom_bound: float = drawer.global_position.y
	assert_float(top_screen.y).is_greater_equal(top_bound)
	assert_float(top_screen.y).is_less_equal(bottom_bound)
	assert_float(bottom_screen.y).is_greater_equal(top_bound)
	assert_float(bottom_screen.y).is_less_equal(bottom_bound)

func test_character_full_body_stays_within_usable_area() -> void:
	## 现有相机测试断言的全是代理量（z 变大、v_offset 为负、fov==35），没有一条
	## 断言用户真正关心的不变量：头顶和脚底是否真的落在屏幕可用区（安全区上边界
	## ~ 抽屉顶边）内。这条直接把角色包围盒顶/底中心投影到屏幕坐标做断言，能同时
	## 抓住已修的多个取景缺陷和任何未来的回归。换上 manifest 里最高的部件
	## hairhat101 再断言一次（终审实测：头顶余量 24.5、脚底 24.4，均为正）。
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过")
		return
	var s := _instantiate()
	var rig: AvatarRig = s.rig
	var applied := []
	rig.config_applied.connect(func(c): applied.append(c))
	for i in 600:
		if applied.size() > 0:
			break
		await get_tree().process_frame
	assert_int(applied.size()).is_equal(1)
	for i in range(5):
		await get_tree().process_frame
	var cam: DressingCamera = s.cam
	var drawer := s.get_node("UI/SafeArea/VBox/Drawer") as PanelContainer
	var safe_area := s.get_node("UI/SafeArea") as MarginContainer
	_assert_body_within_usable_area(cam, rig, drawer, safe_area)

	var target := ""
	for meta in Avatar.catalog.parts_for_slot(&"hairHat"):
		if meta.id == "hairhat101":  # manifest 里 hairHat 槽最高的部件
			target = meta.id
			break
	if target == "":
		push_warning("hairhat101 不在 manifest 里，跳过换装后的第二段断言")
		return
	var slots_applied := []
	rig.slot_applied.connect(func(slot, part_id): slots_applied.append([slot, part_id]))
	rig.equip(&"hairHat", target)
	for i in 600:
		if slots_applied.size() > 0:
			break
		await get_tree().process_frame
	assert_int(slots_applied.size()).is_greater(0)
	for i in range(5):
		await get_tree().process_frame
	_assert_body_within_usable_area(cam, rig, drawer, safe_area)

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

func test_conversion_artifacts_present_otherwise_regressions_silently_skip() -> void:
	# 本套件多条关键回归（换装相机重取景、Drawer 顶宽出安全区等）在转换产物缺失
	# 时会 push_warning 后 return 跳过，而 push_warning 不进 gdUnit4 的 pass/fail
	# 汇总——产物一旦丢失，套件依然报"全部通过"，但最重要的几条回归实际一条
	# 都没跑。这条用例把"产物是否存在"变成一处显式失败，防止误报绿色。
	assert_bool(FileAccess.file_exists("res://assets/avatar/parts_manifest.json")).is_true()
