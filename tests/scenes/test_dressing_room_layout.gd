extends GdUnitTestSuite
## 布局回归：顶部操作、有效分类、部件格、状态反馈、角色区旋转与安全区取景。
## 这些退化任一发生都会直接复现"点不到/看不到"的线上问题。
## C-108: the v3 layout of C-85 page ② (owner-approved in Q-124): glass ‹ / Dressing tag / glass ↺ / Done; the sheet
## with its band, hanger, Ø44 slot chips, the slot's title and Ø72 cells four to a row.

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

func _in_viewport(height := 640) -> Array:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, height)
	viewport.handle_input_locally = true
	viewport.gui_disable_input = false
	add_child(auto_free(viewport))
	var s := (load(SCENE) as PackedScene).instantiate()
	viewport.add_child(s)
	s.safe_area.apply_margins(Rect2i(), Vector2i(360, height), Vector2(360, height))
	for frame in 4:
		await get_tree().process_frame
	return [viewport, s]

func _tap(viewport: SubViewport, at: Vector2, touch := false) -> void:
	for pressed in [true, false]:
		if touch:
			var t := InputEventScreenTouch.new()
			t.index = 0
			t.position = at
			t.pressed = pressed
			viewport.push_input(t, true)
		else:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			e.position = at
			e.global_position = at
			e.pressed = pressed
			viewport.push_input(e, true)
	await get_tree().process_frame

func test_sheet_sits_at_the_foot_with_the_designed_height() -> void:
	for height in [640, 800]:
		var r: Array = await _in_viewport(height)
		var s: Node = r[1]
		var drawer: Control = s.drawer
		assert_object(drawer).is_not_null()
		var rect := drawer.get_global_rect()
		# ②-A: 262 on a 640 screen (41 %), at most 300 on a tall one; full width to the screen's foot.
		assert_float(rect.size.y).is_equal_approx(clampf(height * 0.41, 240.0, 300.0), 0.5)
		assert_float(rect.end.y).is_equal_approx(float(height), 0.5)
		assert_float(rect.position.x).is_equal_approx(0.0, 0.5)
		assert_float(rect.size.x).is_equal_approx(360.0, 0.5)
		var band := drawer.get_node("Band") as Control
		assert_float(band.size.y).is_equal(52.0)
		var sb := band.get_theme_stylebox("panel") as StyleBoxFlat
		assert_bool(sb.bg_color.is_equal_approx(UiTokens.COLOR_SURFACE_HEADER)).is_true()
		var hero := drawer.get_node("Hero") as TextureRect
		assert_object(hero.texture).is_not_null()
		assert_float(hero.position.y).is_less(0.0)   # the hanger stands out over the sheet's top edge

func test_spacer_passes_touches_through_for_rotation() -> void:
	var s := _instantiate()
	var spacer := s.get_node("UI/SafeArea/VBox/Spacer") as Control
	assert_object(spacer).is_not_null()
	# IGNORE 才能让 _unhandled_input 收到拖拽事件转动角色
	assert_int(spacer.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(spacer.size_flags_vertical).is_equal(Control.SIZE_EXPAND_FILL)
	# 回归：Spacer 自己是 IGNORE 不够——它的祖先 SafeArea/VBox 只要有一个是默认
	# STOP，就会在事件传到 Spacer 之前把整个全屏容器的触摸事件吞掉，导致换装
	# 房间完全无法拖拽转身。
	for path in ["UI/SafeArea", "UI/SafeArea/VBox", "UI/Root", "UI/Root/Toasts"]:
		assert_int((s.get_node(path) as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_top_bar_is_glass_back_tag_reset_and_done() -> void:
	var r: Array = await _in_viewport()
	var s: Node = r[1]
	var top := s.get_node("UI/SafeArea/VBox/TopBar") as Control
	assert_int(top.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var back := top.get_node("BackButton") as Button
	var title := top.get_node("Title") as UiTagPill
	var restore := top.get_node("RestoreButton") as Button
	var done := top.get_node("DoneButton") as Button
	assert_object(top.get_child(0)).is_same(back)
	assert_object(top.get_child(1)).is_same(title)
	assert_object(top.get_child(top.get_child_count() - 2)).is_same(restore)
	assert_object(top.get_child(top.get_child_count() - 1)).is_same(done)
	assert_bool(back is UiGlassButton and (back as UiGlassButton).glyph == UiGlassButton.Glyph.BACK).is_true()
	assert_bool(restore is UiGlassButton and restore.icon != null).is_true()
	assert_str(title.text).is_equal("Dressing")
	assert_str(back.tooltip_text).is_equal("Back")
	assert_str(restore.tooltip_text).is_equal("Reset")
	assert_str(str(done.theme_type_variation)).is_equal(str(UiTokens.BUTTON_CMD_PRIMARY))
	for b in [back, restore]:
		assert_bool((b as Control).get_global_rect().size.is_equal_approx(Vector2(44, 44))).is_true()
	assert_float(done.get_global_rect().size.y).is_equal_approx(44.0, 0.5)
	assert_float(done.get_global_rect().size.x).is_greater_equal(88.0)
	# 12 from the sides (the glass ‹ draws its 36 disc 4 inside its 44), 8 under the safe top.
	assert_float(back.get_global_rect().position.x).is_equal_approx(8.0, 0.5)
	assert_float(back.get_global_rect().position.y).is_equal_approx(8.0, 0.5)
	assert_float(360.0 - done.get_global_rect().end.x).is_equal_approx(12.0, 0.5)

func test_redundant_selection_status_row_is_gone() -> void:
	var s := _instantiate()
	assert_object(s.drawer.find_child("SelectionStatus", true, false)).is_null()
	assert_object(s.drawer.find_child("FooterRow", true, false)).is_null()
	assert_bool(FileAccess.get_file_as_string(
		"res://scenes/dressing_room/parts_panel.gd").contains("status_label")).is_false()

func test_parts_are_round_cells_four_to_a_row() -> void:
	var r: Array = await _in_viewport()
	var s: Node = r[1]
	var grid: GridContainer = s.parts_panel.grid
	assert_int(grid.columns).is_equal(4)
	assert_int(grid.get_child_count()).is_greater(4)
	var cells := grid.get_children()
	var first := (cells[0] as Control).get_global_rect()
	var second := (cells[1] as Control).get_global_rect()
	assert_float(first.size.x).is_equal(72.0)
	assert_float(first.position.x).is_equal_approx(18.0, 0.5)
	assert_float(second.position.x - first.end.x).is_equal_approx(12.0, 0.5)
	var fifth := (cells[4] as Control).get_global_rect()
	assert_float(fifth.position.y - first.position.y).is_equal_approx(first.size.y + 14.0, 0.5)
	# the grid starts 34 under the band
	assert_float(first.position.y - s.drawer.get_global_rect().position.y).is_equal_approx(52.0 + 34.0, 0.5)
	var title: Label = s.parts_panel.title
	assert_str(title.text).is_equal("Hair")
	assert_float(title.position.x).is_equal(20.0)

func test_slot_tabs_are_five_chips_on_the_band() -> void:
	var r: Array = await _in_viewport()
	var s: Node = r[1]
	var tabs: Control = s.parts_panel.tabs
	var names: Array[String] = []
	for chip in tabs.get_children():
		names.append((chip as Button).tooltip_text)
		var rect := (chip as Control).get_global_rect()
		assert_bool(rect.size.is_equal_approx(Vector2(44, 44))).is_true()
		assert_float(rect.position.x).is_greater_equal(96.0 - 0.5)
		assert_float(rect.end.x).is_less_equal(360.0 - 12.0 + 0.5)
		assert_float(rect.get_center().y - s.drawer.get_global_rect().position.y).is_equal_approx(26.0, 0.5)
	assert_array(names).contains_exactly(["Hair", "Outfits", "Shoes", "Bags", "Glasses"])
	assert_bool(names.has("body")).is_false()
	var chips := tabs.get_children()
	assert_bool(chips[0].selected).is_true()
	assert_float(chips[0].icon_rect().material.get_shader_parameter(&"amount")).is_equal(0.0)
	assert_float(chips[1].icon_rect().material.get_shader_parameter(&"amount")).is_equal(1.0)

func test_list_cells_pass_touch_for_scroll() -> void:
	## 回归（2026-08-29 真机）：ScrollContainer 触摸滚动依赖按压事件冒泡到容器。
	## 列表内按钮若是默认 STOP，事件在按钮处截断，手指落在按钮上便只能拖滚动条。必须 PASS。
	var s := _instantiate()
	var grid: Control = s.parts_panel.grid
	assert_int(grid.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	assert_int(grid.get_child_count()).is_greater(0)
	for b in grid.get_children():
		assert_int((b as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)

func test_choices_are_human_readable_and_one_is_worn() -> void:
	var s := _instantiate()
	var grid: Control = s.parts_panel.grid
	var worn := 0
	for child in grid.get_children():
		var cell := child as Button
		assert_float(cell.get_combined_minimum_size().y).is_greater_equal(72.0)
		assert_bool(cell.name_label.text.contains("hairhat")).is_false()
		assert_bool(cell.tooltip_text.contains("hairhat")).is_false()
		if cell.worn:
			worn += 1
			assert_bool(cell.name_label.get_theme_color(&"font_color").is_equal_approx(Color("3F5A12"))).is_true()
	assert_int(worn).is_equal(1)

func test_choice_cell_receives_pointer_and_touch_inside_scroll_container() -> void:
	## 属性检查不足以证明真机能点中：用布局后的真实 rect 中心走 Viewport GUI
	## 派发，覆盖 ScrollContainer、PASS 冒泡、Button.pressed 和 rig.equip 全链路。
	var r: Array = await _in_viewport()
	var viewport: SubViewport = r[0]
	var s: Node = r[1]
	var panel = s.parts_panel
	panel._show_slot(&"hairHat")
	for i in 30:
		await get_tree().process_frame
	var before: String = s.rig.desired_part(&"hairHat")
	var target_cell: Button = null
	var original_cell: Button = null
	for child in panel.grid.get_children():
		var candidate := child as Button
		if String(candidate.get_meta(&"part_id")) == before:
			original_cell = candidate
		elif target_cell == null:
			target_cell = candidate
	assert_object(target_cell).is_not_null()
	assert_object(original_cell).is_not_null()
	if target_cell == null or original_cell == null:
		return
	var target := String(target_cell.get_meta(&"part_id"))
	var hits: Array[bool] = []
	target_cell.pressed.connect(func(): hits.append(true))
	await _tap(viewport, target_cell.get_global_rect().get_center())
	assert_int(hits.size()).is_equal(1)
	assert_bool(s.rig.desired_part(&"hairHat") == target).is_true()
	assert_bool(target_cell.worn).is_true()
	var touch_hits: Array[bool] = []
	original_cell.pressed.connect(func(): touch_hits.append(true))
	await _tap(viewport, original_cell.get_global_rect().get_center(), true)
	assert_int(touch_hits.size()).is_equal(1)
	assert_bool(s.rig.desired_part(&"hairHat") == before).is_true()
	assert_bool(original_cell.worn and not target_cell.worn).is_true()

func test_top_bar_actions_are_really_tappable_not_just_present() -> void:
	## TopBar 与 Spacer 都是 IGNORE（否则空白会吞掉转身拖拽）；用真实 rect 中心走 Viewport GUI 派发，真按一次。
	var r: Array = await _in_viewport()
	var viewport: SubViewport = r[0]
	var s: Node = r[1]
	for path in ["BackButton", "RestoreButton", "DoneButton"]:
		var button := s.get_node("UI/SafeArea/VBox/TopBar/" + path) as Button
		assert_object(button).is_not_null()
		button.disabled = false
		var hits: Array[bool] = []
		button.pressed.connect(func(): hits.append(true))
		# Back would leave (or ask) — count the press only.
		for c in button.pressed.get_connections():
			if c.callable.get_object() == s: button.pressed.disconnect(c.callable)
		await _tap(viewport, button.get_global_rect().get_center(), true)
		assert_int(hits.size()).is_equal(1)

func test_single_primary_action_replaces_demo_buttons() -> void:
	var s := _instantiate()
	for legacy in ["SaveButton", "ResetButton", "SceneButton", "MapButton", "Buttons"]:
		assert_object(s.drawer.find_child(legacy, true, false)).is_null()
	assert_object(s.get_node_or_null("UI/SafeArea/VBox/Drawer")).is_null()

func test_loading_state_disables_completion_and_shows_three_dots() -> void:
	var s := _instantiate()
	## 忙碌反馈只剩 Done 一处：禁用并显示三点，宽度不变（②-B）。
	var done := s.get_node("UI/SafeArea/VBox/TopBar/DoneButton") as Button
	assert_bool(s.rig.is_busy()).is_true()
	assert_bool(done.disabled).is_true()
	assert_str(done.text).is_equal("• • •")
	assert_float(done.custom_minimum_size.x).is_equal(88.0)

func test_background_is_separate_from_camera_and_cells_fit_both_phone_heights() -> void:
	for height in [640, 800]:
		var r: Array = await _in_viewport(height)
		var s: Node = r[1]
		s.safe_area.apply_margins(Rect2i(16, 44, 328, height - 72), Vector2i(360, height), Vector2(360, height))
		for frame in 8:
			await get_tree().process_frame
		var environment := s.get_node("WorldEnvironment").environment as Environment
		assert_int(environment.background_mode).is_equal(Environment.BG_CANVAS)
		assert_int(environment.background_canvas_max_layer).is_equal(-1)
		var background := s.get_node("RoomBackground/Scenery") as TextureRect
		assert_object(background.texture).is_not_null()
		var before := background.get_global_rect()
		s.cam.position.z += 1.0
		assert_bool(background.get_global_rect() == before).is_true()
		assert_float(before.size.y).is_equal_approx(float(height), 1.0)
		var panel = s.parts_panel
		for slot in panel.visible_slot_names():
			panel._show_slot(slot)
			await get_tree().process_frame
			await get_tree().process_frame
			for child in panel.grid.get_children():
				var cell := child as Control
				# the cells stay within the sheet's width: none runs off the right
				assert_float(cell.get_global_rect().end.x).is_less_equal(360.0 - 18.0 + 0.5)
		# the safe area's sides keep the top bar in; the sheet is full width and its foot clears the gesture bar
		assert_float(s.drawer.get_global_rect().size.y).is_equal_approx(clampf(height * 0.41, 240.0, 300.0) + 28.0, 0.5)

func test_equip_taller_part_keeps_the_character_the_same_size() -> void:
	## 产品口径（2026-09-02 改）：换装**不能**改变角色在画面中的比例。
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
	_assert_body_within_usable_area(s)

func _assert_body_within_usable_area(s: Node) -> void:
	var cam: DressingCamera = s.cam
	var rig: AvatarRig = s.rig
	var box := DressingCamera.merged_aabb(rig)
	assert_float(box.size.y).is_greater(0.0)
	var cx := box.position.x + box.size.x * 0.5
	var cz := box.position.z + box.size.z * 0.5
	var top_screen := cam.unproject_position(Vector3(cx, box.position.y + box.size.y, cz))
	var bottom_screen := cam.unproject_position(Vector3(cx, box.position.y, cz))
	var top_bar := s.get_node("UI/SafeArea/VBox/TopBar") as Control
	var top_bound: float = top_bar.global_position.y + top_bar.size.y
	var bottom_bound: float = (s.drawer as Control).global_position.y
	assert_float(top_screen.y).is_greater_equal(top_bound)
	assert_float(top_screen.y).is_less_equal(bottom_bound)
	assert_float(bottom_screen.y).is_greater_equal(top_bound)
	assert_float(bottom_screen.y).is_less_equal(bottom_bound)

func test_character_full_body_stays_within_usable_area() -> void:
	## 头顶和脚底真的落在屏幕可用区（顶栏下沿 ~ 底板顶边）内；换上最高的发型再断言一次。
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
	_assert_body_within_usable_area(s)
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
	_assert_body_within_usable_area(s)

func test_head_zoom_keeps_the_tallest_hair_on_screen() -> void:
	## 推近头部 + 最高发型：头顶投影仍在视口内（可以溢进透明顶栏那条带子，不能出画）。
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
	cam.focus_region = DressingCamera.Region.HEAD
	cam.reframe(rig, s.get_viewport().get_visible_rect().size)
	await get_tree().process_frame
	var box := DressingCamera.merged_aabb(rig)
	var cx := box.position.x + box.size.x * 0.5
	var cz := box.position.z + box.size.z * 0.5
	var top_screen := cam.unproject_position(Vector3(cx, box.position.y + box.size.y, cz))
	assert_float(top_screen.y).is_greater_equal(0.0)


func test_sheet_does_not_overflow_the_screen_on_any_slot() -> void:
	## 回归：部件格的最小宽度曾把底板顶宽出安全区。四列 Ø72 + 三个 12 间距 + 两侧 18 = 360，恰好一屏。
	var r: Array = await _in_viewport()
	var s: Node = r[1]
	for slot in s.parts_panel.visible_slot_names():
		s.parts_panel._show_slot(slot)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_float(s.drawer.get_global_rect().size.x).is_less_equal(360.0)
		assert_float(s.parts_panel.grid.get_global_rect().end.x).is_less_equal(360.0 - 18.0 + 0.5)

func test_conversion_artifacts_present_otherwise_regressions_silently_skip() -> void:
	# 本套件多条关键回归（换装相机重取景、Drawer 顶宽出安全区等）在转换产物缺失
	# 时会 push_warning 后 return 跳过，而 push_warning 不进 gdUnit4 的 pass/fail
	# 汇总——产物一旦丢失，套件依然报"全部通过"，但最重要的几条回归实际一条
	# 都没跑。这条用例把"产物是否存在"变成一处显式失败，防止误报绿色。
	assert_bool(FileAccess.file_exists("res://assets/avatar/parts_manifest.json")).is_true()


func test_no_voice_profile_entry_here() -> void:
	## The Voice Profile entry moved to the P0 profile (SGODOT-349, 不知火舞 2ca37b44): none on the dressing room.
	var s := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(s))
	for i in 2:
		await get_tree().process_frame
	assert_object(s.find_child("VoiceProfileButton", true, false)).is_null()
	assert_object(s.find_child("VoiceMatchLink", true, false)).is_null()


func test_voice_match_url_carries_embed_theme_mode_and_english() -> void:
	var url := VoiceMatchLink.url_for("solo")
	assert_str(url).starts_with("https://match.sensenapp.com/?")
	assert_str(url).contains("embed=1").contains("theme=gensen").contains("mode=solo").contains("lang=en")
	# 游戏是中文界面时 H5 也固定英文
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	assert_str(VoiceMatchLink.url_for("pair")).contains("mode=pair").contains("lang=en")
	TranslationServer.set_locale(previous)
