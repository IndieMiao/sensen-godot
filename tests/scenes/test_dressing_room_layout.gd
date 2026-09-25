extends GdUnitTestSuite
## 布局回归：顶部操作、有效分类、两列选项、状态反馈、角色区旋转与安全区取景。
## 这些退化任一发生都会直接复现"点不到/看不到"的线上问题。

const SCENE := "res://scenes/dressing_room/dressing_room.tscn"

func _instantiate() -> Node:
	var scene := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	return scene

## 取景断言要的是"最坏情况的发型"，不是某个特定部件。以前三处都写死 hairhat101，
## 部件池一换（它因材质原因下架）就走 push_warning + return —— 而 push_warning
## 不计入 gdUnit 的 pass/fail，三条取景回归会一起静默失明，套件照样全绿。
## 改成实测：逐个戴上量包围盒高度，返回最高的那个 id。
##
## 刻意用**另起的一具 rig** 来量，不碰被测场景里那具：调用方普遍是先记下换装前的
## 相机基线再换装，若在同一具上逐顶试戴，基线就被搅了。
func _tallest_hair_id() -> String:
	var probe: AvatarRig = Avatar.create_rig()
	add_child(auto_free(probe))
	probe.apply_config(Avatar.slot_table.default_config())
	for i in 900:
		if not probe.is_busy():
			break
		await get_tree().process_frame
	var best := ""
	var best_h := -1.0
	for meta in Avatar.catalog.parts_for_slot(&"hairHat"):
		probe.equip(&"hairHat", meta.id)
		for i in 900:
			if not probe.is_busy():
				break
			await get_tree().process_frame
		var h := DressingCamera.merged_aabb(probe).size.y
		if h > best_h:
			best_h = h
			best = meta.id
	probe.queue_free()
	return best

func test_drawer_sits_at_bottom_with_expected_height() -> void:
	var s := _instantiate()
	var drawer := s.get_node("UI/SafeArea/VBox/Drawer") as PanelContainer
	assert_object(drawer).is_not_null()
	# Leave most of the viewport for the character; smaller screens retain scrolling.
	var viewport_height := s.get_viewport().get_visible_rect().size.y
	assert_float(drawer.custom_minimum_size.y).is_less_equal(viewport_height * 0.44)
	assert_float(drawer.custom_minimum_size.y).is_greater_equal(180.0)

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

func test_top_bar_has_title_and_grouped_actions_without_blocking_rotation() -> void:
	var s := _instantiate()
	var top := s.get_node("UI/SafeArea/VBox/TopBar") as Control
	var back := s.get_node("UI/SafeArea/VBox/TopBar/BackButton") as Button
	var done := s.get_node("UI/SafeArea/VBox/TopBar/DoneButton") as Button
	assert_bool(top is PanelContainer).is_false()
	assert_int(top.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((top.get_node("Spacer") as Control).mouse_filter).is_equal(
		Control.MOUSE_FILTER_IGNORE)
	# 返回是纯图标圆钮：没有 icon 就成了一个没有任何标识的空白圆
	assert_object(back.icon).is_not_null()
	assert_str(str(back.theme_type_variation)).is_equal("SecondaryButton")
	assert_str(back.tooltip_text).is_equal("Back")
	assert_float(back.get_combined_minimum_size().x).is_greater_equal(48.0)
	assert_float(back.get_combined_minimum_size().y).is_greater_equal(48.0)
	# Done 必须排在最后（右上角），且不再位于抽屉里
	assert_object(top.get_child(top.get_child_count() - 1)).is_same(done)
	assert_float(done.get_combined_minimum_size().y).is_greater_equal(48.0)
	assert_object(s.get_node_or_null("UI/SafeArea/VBox/Drawer/VBox/DoneButton")).is_null()
	var title := top.get_node("Title") as Label
	assert_str(title.text).is_equal("Dressing")
	assert_int(title.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var restore := top.get_node("RestoreButton") as Button
	assert_str(str(back.theme_type_variation)).is_equal(str(restore.theme_type_variation))
	assert_object(top.get_child(0)).is_same(back)
	assert_object(top.get_child(1)).is_same(title)
	assert_object(top.get_child(top.get_child_count() - 2)).is_same(restore)


func test_redundant_selection_status_row_is_gone() -> void:
	## "Selected: X" 说的三件事各自都已有更直接的表达：选中项有薄荷描边、角色身上
	## 已经穿着、忙碌态 Done 会显示 "Trying on..."。整行（48 单位）删掉还给部件列表。
	## Reset 一并回到顶栏，做成与返回同款的图标圆钮——它作用于整套装扮，不属于某个分类。
	var s := _instantiate()
	var restore := s.get_node("UI/SafeArea/VBox/TopBar/RestoreButton") as Button
	assert_object(restore.icon).is_not_null()
	assert_str(restore.tooltip_text).is_equal("Reset")
	assert_float(restore.get_combined_minimum_size().x).is_greater_equal(48.0)
	assert_float(restore.get_combined_minimum_size().y).is_greater_equal(48.0)
	assert_object(s.get_node_or_null("UI/SafeArea/VBox/Drawer/VBox/FooterRow")).is_null()
	var editor := s.get_node("UI/SafeArea/VBox/Drawer/VBox")
	assert_object(editor.find_child("SelectionStatus", true, false)).is_null()
	assert_bool(FileAccess.get_file_as_string(
		"res://scenes/dressing_room/parts_panel.gd").contains("status_label")).is_false()

func test_parts_grid_has_three_responsive_columns() -> void:
	## 上了缩略图后从 2 列改 3 列：3×2 正好装下部件最多的槽位，任何分类都不用滚动。
	var s := _instantiate()
	var grid := s.get_node("UI/SafeArea/VBox/Drawer/VBox/PartsScroll/PartsGrid") as GridContainer
	assert_object(grid).is_not_null()
	assert_int(grid.columns).is_equal(3)
	assert_int(grid.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)


func test_thumbnail_cell_height_matches_the_drawer_budget() -> void:
	## THUMB_CELL_HEIGHT 是量出来的（Button 的最小尺寸参考纹理原始尺寸，
	## icon_max_width 只管绘制宽度）。一旦改了 RENDER_SIZE / 字号 / icon_max_width，
	## 真实格子高度就会偏离这个常量，抽屉高度也得跟着重算——这条把偏离拦下来。
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过")
		return
	var s := _instantiate()
	var panel = s.get_node("UI/SafeArea/VBox/Drawer/VBox")
	var grid := s.get_node("UI/SafeArea/VBox/Drawer/VBox/PartsScroll/PartsGrid") as GridContainer
	var measured := 0.0
	for i in 900:
		await get_tree().process_frame
		for child in grid.get_children():
			var button := child as Button
			if button.icon != null and not String(button.get_meta(&"part_id")).is_empty():
				measured = button.get_combined_minimum_size().y
				break
		if measured > 0.0:
			break
	assert_float(measured).is_greater(0.0)
	assert_float(measured).is_equal_approx(panel.COMPACT_CELL_HEIGHT if panel._compact else panel.THUMB_CELL_HEIGHT, 0.5)
	# A standard viewport fits two rows; shorter viewports retain the scrolling list.
	var drawer := s.get_node("UI/SafeArea/VBox/Drawer") as PanelContainer
	var needed := 24.0 + 48.0 + 8.0 + measured * 2.0 + 8.0
	var viewport_height := s.get_viewport().get_visible_rect().size.y
	if viewport_height * 0.44 >= needed:
		assert_float(drawer.custom_minimum_size.y).is_greater_equal(needed)
	else:
		assert_int((grid.get_parent() as ScrollContainer).vertical_scroll_mode).is_not_equal(ScrollContainer.SCROLL_MODE_DISABLED)

func test_slot_tabs_are_horizontally_scrollable() -> void:
	var s := _instantiate()
	var scroll := s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll") as ScrollContainer
	assert_object(scroll).is_not_null()
	# 标签必须能横滑，否则槽位多时最后几个（如 glass）溢出屏幕点不到
	assert_bool(scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED).is_true()
	assert_int(scroll.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_object(s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll/SlotTabs")).is_not_null()

func test_only_slots_with_real_choices_are_visible_and_named_in_english() -> void:
	var s := _instantiate()
	var tabs := s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll/SlotTabs")
	var labels: Array[String] = []
	for child in tabs.get_children():
		labels.append((child as Button).text)
	assert_array(labels).contains_exactly(["Hair", "Outfits", "Shoes", "Bags", "Glasses"])
	assert_bool(labels.has("body")).is_false()
	assert_bool(labels.has("eyes")).is_false()
	# 360dp 设计宽度扣除抽屉左右 16dp 后仍应完整显示五个英文分类。
	assert_float((tabs as Control).get_combined_minimum_size().x).is_less_equal(328.0)

func test_list_buttons_pass_touch_for_scroll() -> void:
	## 回归（2026-08-29 真机）：ScrollContainer 触摸滚动依赖按压事件冒泡到容器
	## （引擎在按压时开始拖拽跟踪，越过死区后 propagate NOTIFICATION_SCROLL_BEGIN
	## 取消子按钮按压——base_button.cpp 对该通知有专门处理）。列表内按钮若是默认
	## STOP，事件在按钮处截断，手指落在按钮上便只能拖滚动条。必须 PASS。
	var s := _instantiate()
	var tabs := s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll/SlotTabs")
	assert_int((tabs as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	assert_int(tabs.get_child_count()).is_greater(0)
	for b in tabs.get_children():
		assert_int((b as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	var grid := s.get_node("UI/SafeArea/VBox/Drawer/VBox/PartsScroll/PartsGrid")
	assert_int((grid as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	assert_int(grid.get_child_count()).is_greater(0)
	for b in grid.get_children():
		assert_int((b as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)

func test_choices_are_human_readable_and_have_selected_state() -> void:
	var s := _instantiate()
	var grid := s.get_node("UI/SafeArea/VBox/Drawer/VBox/PartsScroll/PartsGrid")
	var selected := 0
	for child in grid.get_children():
		var button := child as Button
		assert_float(button.get_combined_minimum_size().y).is_greater_equal(48.0)
		assert_bool(button.text.contains("hairhat")).is_false()
		assert_bool(button.tooltip_text.contains("hairhat")).is_false()
		if button.theme_type_variation == &"ThumbChoiceSelectedButton":
			selected += 1
	assert_int(selected).is_equal(1)

func test_choice_button_receives_pointer_and_touch_inside_scroll_container() -> void:
	## 属性检查不足以证明真机能点中：用布局后的真实 rect 中心走 Viewport GUI
	## 派发，覆盖 ScrollContainer、PASS 冒泡、Button.pressed 和 rig.equip 全链路。
	## headless 根窗口不做 GUI hit-test，因此挂到启用本地输入的 SubViewport。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	viewport.handle_input_locally = true
	viewport.gui_disable_input = false
	add_child(auto_free(viewport))
	var s := (load(SCENE) as PackedScene).instantiate()
	viewport.add_child(s)
	var panel = s.get_node("UI/SafeArea/VBox/Drawer/VBox")
	panel._show_slot(&"hairHat")
	await get_tree().process_frame
	await get_tree().process_frame
	var before: String = s.rig.desired_part(&"hairHat")
	var target_button: Button = null
	var original_button: Button = null
	for child in panel.grid.get_children():
		var candidate := child as Button
		if String(candidate.get_meta(&"part_id")) == before:
			original_button = candidate
		elif target_button == null:
			target_button = candidate
	assert_object(target_button).is_not_null()
	assert_object(original_button).is_not_null()
	if target_button == null or original_button == null:
		return
	var target := String(target_button.get_meta(&"part_id"))
	var hits: Array[bool] = []
	target_button.pressed.connect(func(): hits.append(true))
	var center := target_button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = center
		event.global_position = center
		event.pressed = pressed
		viewport.push_input(event, true)
	await get_tree().process_frame
	assert_int(hits.size()).is_equal(1)
	assert_bool(s.rig.desired_part(&"hairHat") == target).is_true()
	assert_bool(target_button.theme_type_variation == &"ThumbChoiceSelectedButton").is_true()

	var touch_hits: Array[bool] = []
	original_button.pressed.connect(func(): touch_hits.append(true))
	var touch_center := original_button.get_global_rect().get_center()
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = touch_center
		touch.pressed = pressed
		viewport.push_input(touch, true)
	await get_tree().process_frame
	assert_int(touch_hits.size()).is_equal(1)
	assert_bool(s.rig.desired_part(&"hairHat") == before).is_true()
	assert_bool(original_button.theme_type_variation == &"ThumbChoiceSelectedButton").is_true()

func test_top_bar_actions_are_really_tappable_not_just_present() -> void:
	## 顶栏改成浮在 3D 场景上的透明 HBox 后，TopBar 与 Spacer 都是 MOUSE_FILTER_IGNORE
	## （否则整条 48 单位高的空白会吞掉转身拖拽）。属性断言证明不了按钮还收得到点击：
	## 父容器 IGNORE 时子控件仍参与命中测试是引擎行为，一旦哪次改动把按钮自己也设成
	## IGNORE/或被 Spacer 盖住，右上角的 Done 就会变成"看得见点不到"——正是 §2.4 那类
	## 静默回归。这里用布局后的真实 rect 中心走 Viewport GUI 派发，真按一次。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	viewport.handle_input_locally = true
	viewport.gui_disable_input = false
	add_child(auto_free(viewport))
	var s := (load(SCENE) as PackedScene).instantiate()
	viewport.add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame

	for path in ["BackButton", "RestoreButton", "DoneButton"]:
		var button := s.get_node("UI/SafeArea/VBox/TopBar/" + path) as Button
		assert_object(button).is_not_null()
		# 提交中会禁用按钮，这里只验证命中链路，先确保可按
		button.disabled = false
		var hits: Array[bool] = []
		button.pressed.connect(func(): hits.append(true))
		var center := button.get_global_rect().get_center()
		for pressed in [true, false]:
			var touch := InputEventScreenTouch.new()
			touch.index = 0
			touch.position = center
			touch.pressed = pressed
			viewport.push_input(touch, true)
		await get_tree().process_frame
		assert_int(hits.size()).is_equal(1)


func test_single_primary_action_replaces_demo_buttons() -> void:
	var s := _instantiate()
	var editor := s.get_node("UI/SafeArea/VBox/Drawer/VBox")
	var done := s.get_node("UI/SafeArea/VBox/TopBar/DoneButton") as Button
	assert_object(done).is_not_null()
	assert_str(done.theme_type_variation).is_equal("AccentButton")
	assert_float(done.get_combined_minimum_size().y).is_greater_equal(48.0)
	assert_object(editor.get_node_or_null("Buttons")).is_null()
	for legacy in ["SaveButton", "ResetButton", "SceneButton", "MapButton"]:
		assert_object(editor.find_child(legacy, true, false)).is_null()

func test_loading_state_disables_completion_and_is_visible() -> void:
	var s := _instantiate()
	## 删掉 "Selected/Trying on" 那行文案后，忙碌反馈只剩 Done 一处，
	## 它必须同时禁用并说明在忙——否则用户会觉得点了没反应。
	var done := s.get_node("UI/SafeArea/VBox/TopBar/DoneButton") as Button
	assert_bool(s.rig.is_busy()).is_true()
	assert_bool(done.disabled).is_true()
	assert_str(done.text).is_equal("Loading")
	assert_bool(done.clip_text).is_true()


func test_background_is_separate_from_camera_and_grid_fits_both_phone_heights() -> void:
	for height in [640, 800]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(360, height)
		add_child(auto_free(viewport))
		var s := (load(SCENE) as PackedScene).instantiate()
		viewport.add_child(s)
		s.safe_area.apply_margins(Rect2i(16, 44, 328, height - 72),
			Vector2i(360, height), Vector2(360, height))
		for frame in 8:
			await get_tree().process_frame
		var environment := s.get_node("WorldEnvironment").environment as Environment
		assert_int(environment.background_mode).is_equal(Environment.BG_CANVAS)
		assert_int(environment.background_canvas_max_layer).is_equal(-1)
		var background := s.get_node("RoomBackground/Scenery") as TextureRect
		assert_object(background.texture).is_not_null()
		var before := background.get_global_rect()
		s.cam.position.z += 1.0
		assert_object(background.get_parent()).is_same(s.get_node("RoomBackground"))
		assert_bool(background.get_global_rect() == before).is_true()
		assert_float(before.size.y).is_equal_approx(float(height), 1.0)
		var panel = s.parts_panel
		var scroll := panel.get_node("PartsScroll") as ScrollContainer
		for slot in panel.visible_slot_names():
			panel._show_slot(slot)
			await get_tree().process_frame
			await get_tree().process_frame
			assert_float(panel.grid.get_global_rect().end.y).is_less_equal(scroll.get_global_rect().end.y + 1.0)
			for child in panel.grid.get_children():
				var choice := child as Button
				assert_bool(choice.expand_icon).is_true()
				var text_width := choice.get_theme_font("font").get_string_size(choice.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, choice.get_theme_font_size("font_size")).x
				var content_padding := choice.get_theme_stylebox("normal").get_minimum_size().x
				assert_float(text_width).override_failure_message("Clipped label: " + choice.text).is_less_equal(choice.size.x - content_padding)
		var tabs := panel.tabs as Control
		assert_float(tabs.get_global_rect().end.x).is_less_equal(s.drawer.get_global_rect().end.x - 12.0)

func test_equip_taller_part_keeps_the_character_the_same_size() -> void:
	## 产品口径（2026-09-02 改）：换装**不能**改变角色在画面中的比例。
	## 旧行为相反——按 merged_aabb 取景，戴上 hairhat101（1.971m vs 默认 1.721m）
	## 相机就后退 14%，屏幕上角色肉眼可见地一缩。现在取景对着固定的
	## DressingCamera.reference_box()，REF_HEIGHT 已含最高发型的余量，
	## 因此换装既不改大小也不会切头顶。
	## 这条走的是真实链路：parts_panel 点选项 → rig.equip() → slot_applied。
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
	var before_v := cam.v_offset
	var target := await _tallest_hair_id()
	assert_str(target).is_not_empty()
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
	assert_float(cam.position.z).is_equal_approx(before_z, 0.0001)
	assert_float(cam.v_offset).is_equal_approx(before_v, 0.0001)
	# 比例不变的同时头顶不能被切：换上最高发型后全身仍在可用区内
	var drawer := s.get_node("UI/SafeArea/VBox/Drawer") as PanelContainer
	var safe_area := s.get_node("UI/SafeArea") as MarginContainer
	_assert_body_within_usable_area(cam, rig, drawer, safe_area)

func _assert_body_within_usable_area(cam: DressingCamera, rig: AvatarRig, drawer: PanelContainer, safe_area: MarginContainer) -> void:
	var box := DressingCamera.merged_aabb(rig)
	assert_float(box.size.y).is_greater(0.0)
	var cx := box.position.x + box.size.x * 0.5
	var cz := box.position.z + box.size.z * 0.5
	var top_screen := cam.unproject_position(Vector3(cx, box.position.y + box.size.y, cz))
	var bottom_screen := cam.unproject_position(Vector3(cx, box.position.y, cz))
	var top_bar := safe_area.get_node("VBox/TopBar") as Control
	var top_bound: float = top_bar.global_position.y + top_bar.size.y
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

	var target := await _tallest_hair_id()
	assert_str(target).is_not_empty()
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

func test_head_zoom_keeps_the_tallest_hair_on_screen() -> void:
	## HEAD 取景盒按常见发型定（上界 1.85），最高的 hairhat101（1.971m）会向上
	## 溢出到顶栏那条透明带子里。溢出到"顶栏底下"没问题，溢出到"画面外"就是切头。
	## 这条把最坏组合——推近头部 + 最高发型——的头顶投影出来，断言仍在视口内。
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
	var target := await _tallest_hair_id()
	assert_str(target).is_not_empty()
	var slots_applied := []
	rig.slot_applied.connect(func(slot, part_id): slots_applied.append([slot, part_id]))
	rig.equip(&"hairHat", target)
	for i in 600:
		if slots_applied.size() > 0:
			break
		await get_tree().process_frame
	assert_int(slots_applied.size()).is_greater(0)
	var cam: DressingCamera = s.cam
	# 直接落位，跳过补间，免得断言撞在动画中途
	cam.focus_region = DressingCamera.Region.HEAD
	cam.reframe(rig, s.get_viewport().get_visible_rect().size)
	await get_tree().process_frame
	var box := DressingCamera.merged_aabb(rig)
	var cx := box.position.x + box.size.x * 0.5
	var cz := box.position.z + box.size.z * 0.5
	var top_screen := cam.unproject_position(Vector3(cx, box.position.y + box.size.y, cz))
	var header := s.get_node("UI/HeaderPaper") as Control
	assert_float(top_screen.y).is_greater_equal(header.size.y)


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


func test_voice_profile_entry_floats_right_above_drawer_and_is_tappable() -> void:
	## 声音画像入口：右对齐安全区、贴在抽屉上方，不能压到抽屉或顶栏，且真能点到。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	viewport.handle_input_locally = true
	viewport.gui_disable_input = false
	add_child(auto_free(viewport))
	var s := (load(SCENE) as PackedScene).instantiate()
	viewport.add_child(s)
	for i in 4:
		await get_tree().process_frame
	var button := s.get_node("UI/VoiceProfileButton") as Button
	assert_object(button).is_not_null()
	assert_str(button.text).is_equal("Voice Profile")
	var rect := button.get_global_rect()
	var drawer := (s.get_node("UI/SafeArea/VBox/Drawer") as Control).get_global_rect()
	var top_bar := (s.get_node("UI/SafeArea/VBox/TopBar") as Control).get_global_rect()
	assert_float(rect.end.y).is_less_equal(drawer.position.y)
	assert_float(rect.position.y).is_greater(top_bar.end.y)
	assert_float(rect.end.x).is_less_equal(360.0)
	assert_float(rect.position.x).is_greater(180.0)
	assert_float(rect.size.y).is_greater_equal(44.0)
	# 桌面没有原生插件会走 OS.shell_open；这里只验证命中链路，不真的触发打开。
	button.pressed.disconnect(s._on_voice_profile)
	var hits: Array[bool] = []
	button.pressed.connect(func(): hits.append(true))
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = rect.get_center()
		touch.pressed = pressed
		viewport.push_input(touch, true)
	await get_tree().process_frame
	assert_int(hits.size()).is_equal(1)


func test_voice_match_url_carries_embed_theme_mode_and_english() -> void:
	var url := VoiceMatchLink.url_for("solo")
	assert_str(url).starts_with("https://match.sensenapp.com/?")
	assert_str(url).contains("embed=1").contains("theme=gensen").contains("mode=solo").contains("lang=en")
	# 游戏是中文界面时 H5 也固定英文
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	assert_str(VoiceMatchLink.url_for("pair")).contains("mode=pair").contains("lang=en")
	TranslationServer.set_locale(previous)
