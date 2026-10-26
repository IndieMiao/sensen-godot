extends GdUnitTestSuite

func after_test() -> void:
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	await _frames()

func _state(purchased := true, props: Array = []) -> Dictionary:
	return {"clock": {"chapter_index": 5, "player_day_id": "2026-09-05"}, "wallet": 287,
		"growth_choice": {"purchase": "tool" if purchased else null}, "decorations": props.duplicate(true)}

func _panel(initial: Dictionary, responses: Array = []) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = initial.duplicate(true)
	session.version = 1
	var panel := DecorationPanel.new()
	panel.setup(session)
	panel.theme = GameUi.theme()
	panel.custom_minimum_size.x = 296
	add_child(auto_free(panel))
	return [panel, session, transport]

func _reply(state: Dictionary, version := 2) -> Dictionary:
	return {"status": 200, "json": {"version": version, "state": state}}

func _frames() -> void:
	for index in 3: await get_tree().process_frame

func test_six_defaults_fit_the_shared_zones_without_overlap_or_obstructing_the_path() -> void:
	var props := []
	for id in DecorationLayout.IDS:
		var q = DecorationLayout.first_position(str(id), props)
		assert_bool(q != null).is_true()
		props = DecorationLayout.with_position(props, str(id), q)
	assert_int(props.size()).is_equal(6)
	assert_bool(DecorationLayout.is_valid(props)).is_true()
	# 可放置性现在查地面属性：建筑那格永远放不了东西。
	var bp := FarmPlot.blueprint_for()
	assert_bool(DecorationLayout.cell_allowed(bp, {}, {}, "bench", bp.anchor("house"))).is_false()
	assert_bool(DecorationLayout.cell_allowed(bp, {}, {}, "bench", Vector2i(24, 3))).is_true()
	# 已开垦的地不能压道具。
	assert_bool(DecorationLayout.cell_allowed(bp, {"24,3": {"state": "tilled"}}, {}, "bench", Vector2i(24, 3))).is_false()
	var rendered := auto_free(DecorationLayout.build(props)) as Node3D
	assert_int(rendered.get_child_count()).is_equal(6)
	for child in rendered.get_children():
		var mesh := child as MeshInstance3D
		assert_object(mesh).is_not_null()
		assert_bool(mesh.mesh.get_aabb().size.x * mesh.scale.x <= 0.8).is_true()
		assert_int(mesh.mesh.get_surface_count()).is_equal(1)

func test_schema_rejects_duplicates_overlapping_footprints_and_unknown_fields() -> void:
	var one := DecorationLayout.entry("bench", Vector2i(24, 3))
	assert_bool(DecorationLayout.is_valid([one, one])).is_false()
	# bench 占 2×1（24,3 与 25,3）；crate 再放 25,3 就压上去了。
	assert_bool(DecorationLayout.is_valid([one, DecorationLayout.entry("crate", Vector2i(25, 3))])).is_false()
	var fraction := one.duplicate(true)
	fraction.cell = [24.5, 4]
	assert_bool(DecorationLayout.is_valid([fraction])).is_false()
	var unknown := one.duplicate(true)
	unknown.rotation = 1
	assert_bool(DecorationLayout.is_valid([unknown])).is_false()
	assert_bool(DecorationLayout.is_valid([DecorationLayout.entry("missing", Vector2i(24, 3))])).is_false()
	assert_bool(DecorationLayout.is_valid([])).is_true()

func test_pre_purchase_preview_can_place_adjust_undo_and_cancel_without_network_or_state_mutation() -> void:
	var pair := _panel(_state(false))
	var panel: DecorationPanel = pair[0]
	await _frames()
	assert_bool(panel.place_selected()).is_true()
	assert_bool(panel.dirty).is_true()
	# 起点是这件道具的默认格；移动一格再撤销要回到原位。
	var start: Array = panel.preview()[0].cell.duplicate()
	assert_bool(panel.adjust(Vector2i(0, 1))).is_true()
	assert_that(panel.preview()[0].cell).is_equal([int(start[0]), int(start[1]) + 1])
	panel.undo()
	assert_that(panel.preview()[0].cell).is_equal(start)
	assert_bool(await panel.save_layout()).is_false()
	assert_bool((panel.find_child("SaveDecorations", true, false) as Button).disabled).is_true()
	assert_int(pair[2].requests.size()).is_equal(0)
	assert_that(pair[1].state.decorations).is_equal([])
	panel.cancel_preview()
	assert_bool(panel.dirty).is_false()
	assert_that(panel.preview()).is_equal([])

func test_ground_placement_quantizes_to_plot_cells_and_rejects_clashes() -> void:
	var pair := _panel(_state())
	var panel: DecorationPanel = pair[0]
	await _frames()
	var lawn := Vector2i(24, 3)
	var world := func(cell: Vector2i) -> Vector3:
		return DecorationLayout.world_position({"cell": [cell.x, cell.y]})
	# 世界坐标落在哪一格，就放在哪一格——quantize 与 world_position 互逆。
	assert_bool(panel.place_at(world.call(lawn))).is_true()
	assert_that(panel.preview()[0].cell).is_equal([lawn.x, lawn.y])
	# bench 占 2×1，所以它右边那格已被自己占住，别的道具放不进去。
	panel.select_prop("crate")
	assert_bool(panel.place_at(world.call(lawn + Vector2i(1, 0)))).is_false()
	assert_bool(panel.place_at(world.call(lawn + Vector2i(0, 2)))).is_true()
	assert_bool(panel.pick_at(world.call(lawn))).is_true()
	assert_str(panel.selected_prop).is_equal("bench")
	assert_int(pair[2].requests.size()).is_equal(0)

func test_save_sends_the_full_layout_once_and_adopts_only_the_server_reply() -> void:
	var server_props := [DecorationLayout.entry("bench", Vector2i(24, 4))]
	var pair := _panel(_state(), [_reply(_state(true, server_props))])
	var panel: DecorationPanel = pair[0]
	await _frames()
	panel.place_selected()
	assert_bool(await panel.save_layout()).is_true()
	assert_str(pair[2].last_body().type).is_equal("save_decorations")
	var want: Array = DecorationLayout.data().props.bench.default_cell
	assert_that(DecorationLayout.canonical(pair[2].last_body().payload.props)).is_equal(
		[DecorationLayout.entry("bench", Vector2i(int(want[0]), int(want[1])))])
	assert_that(panel.preview()).is_equal(server_props)
	assert_that(pair[1].state.decorations).is_equal(server_props)
	assert_bool(panel.dirty).is_false()
	assert_int(pair[1].state.wallet).is_equal(287)
	assert_bool(await panel.save_layout()).is_false()
	assert_int(pair[2].requests.size()).is_equal(1)

func test_rejected_save_keeps_preview_and_saved_state_then_cancel_restores_the_saved_layout() -> void:
	var saved := [DecorationLayout.entry("bench", Vector2i(30, 12))]
	var pair := _panel(_state(true, saved), [{"status": 422, "json": {"code": "INVALID_DECORATION"}}])
	var panel: DecorationPanel = pair[0]
	await _frames()
	panel.adjust(Vector2i(0, 1))
	assert_bool(await panel.save_layout()).is_false()
	assert_bool(panel.dirty).is_true()
	assert_str(panel.message.text).contains("spot that cannot be used")
	assert_that(pair[1].state.decorations).is_equal(saved)
	panel.cancel_preview()
	assert_that(panel.preview()).is_equal(saved)
	assert_bool(panel.dirty).is_false()

func test_lost_reply_preserves_pending_preview_across_reentry_and_reconciles_without_resubmitting() -> void:
	var after := _state(true, [DecorationLayout.entry("bench", Vector2i(30, 12))])
	var pair := _panel(_state(), [{"error": "timeout"}, {"error": "timeout"}, _reply(after), _reply(after)])
	var panel: DecorationPanel = pair[0]
	await _frames()
	panel.place_selected()
	assert_bool(await panel.save_layout()).is_false()
	assert_bool(pair[1].has_meta(DecorationPanel.PENDING_META)).is_true()
	remove_child(panel)
	var reopened := DecorationPanel.new()
	reopened.setup(pair[1])
	add_child(auto_free(reopened))
	await _frames()
	assert_bool(reopened.dirty).is_true()
	assert_bool(await reopened.reconcile_save()).is_true()
	assert_bool(reopened.dirty).is_false()
	assert_that(reopened.preview()).is_equal(after.decorations)
	assert_bool(pair[1].has_meta(DecorationPanel.PENDING_META)).is_false()
	assert_that(pair[2].requests.map(func(request): return request.method)).is_equal(["POST", "POST", "POST", "GET"])
	assert_str(pair[2].requests[0].body.idempotency_key).is_equal(pair[2].requests[1].body.idempotency_key)
	assert_that(pair[2].requests[2].body).is_equal(pair[2].requests[0].body)

func test_offline_preview_never_sends_a_save_and_removal_can_be_undone() -> void:
	var saved := [DecorationLayout.entry("bench", Vector2i(30, 12))]
	var pair := _panel(_state(true, saved))
	var panel: DecorationPanel = pair[0]
	pair[1].offline = true
	await _frames()
	panel.remove_selected()
	assert_that(panel.preview()).is_equal([])
	assert_bool(await panel.save_layout()).is_false()
	panel.undo()
	assert_that(panel.preview()).is_equal(saved)
	assert_int(pair[2].requests.size()).is_equal(0)
	assert_bool(panel.mouse_filter == Control.MOUSE_FILTER_PASS).is_true()

func test_saved_json_numbers_normalize_without_creating_unsaved_changes() -> void:
	# JSON 解析出来的数字是 float；规范化必须把它们收成 int，否则每次进面板都"脏"。
	var props: Array = JSON.parse_string('[{"prop_id":"bench","cell":[30.0,12.0]}]')
	var pair := _panel(_state(true, props))
	var panel: DecorationPanel = pair[0]
	await _frames()
	assert_bool(panel.dirty).is_false()
	assert_that(panel.preview()).is_equal([DecorationLayout.entry("bench", Vector2i(30, 12))])
	# 放到自己已经占着的那一格：什么都不该变。
	assert_bool(panel.place_at(DecorationLayout.world_position({"cell": [30, 12]}))).is_false()
	assert_bool(panel.dirty).is_false()

func _inventory_state(props: Array = []) -> Dictionary:
	var initial := _state(true, props)
	initial.journey = {"version": 1, "facts": ["planter_crafted"], "unlocks": ["decorations"]}
	initial.bag = {"version": 2, "sequence": 0, "capacity": 24, "slots": [
		{"id": "bag_1", "item_id": "planter", "quantity": 2, "quality": "normal"}],
		"overflow": [{"id": "bag_2", "item_id": "crate", "quantity": 1, "quality": "normal"}], "equipped": {}}
	return initial

func test_canonical_courtyard_uses_owned_and_overflow_pieces_without_free_palette() -> void:
	var pair := _panel(_inventory_state())
	var panel: DecorationPanel = pair[0]
	await _frames()
	assert_that(panel._allowed_props()).is_equal(["planter", "crate"])
	panel.select_prop("bench")
	assert_bool(panel.place_selected()).is_false()
	assert_bool(panel.place_at(Vector3(-2, 0, 1.5))).is_false()
	panel.select_prop("planter")
	assert_bool(panel.place_selected()).is_true()
	assert_str(panel._picker_label("planter")).contains("x1")
	assert_int(pair[1].state.bag.slots[0].quantity).is_equal(2)
	assert_int(pair[2].requests.size()).is_equal(0)

func test_saved_piece_can_move_remove_and_replace_without_a_second_bag_copy() -> void:
	var initial := _inventory_state([DecorationLayout.entry("bench", Vector2i(30, 12))])
	initial.bag.slots = []
	initial.bag.overflow = []
	var pair := _panel(initial)
	var panel: DecorationPanel = pair[0]
	await _frames()
	assert_that(panel._allowed_props()).is_equal(["bench"])
	panel.select_prop("bench")
	assert_bool(panel.adjust(Vector2i(0, 1))).is_true()
	panel.remove_selected()
	assert_str(panel._picker_label("bench")).contains("x1")
	assert_bool(panel.place_selected()).is_true()
	assert_int(panel.preview().size()).is_equal(1)
	assert_that(pair[1].state.bag.slots).is_empty()

func test_full_bag_return_rejection_keeps_saved_piece_and_pending_preview() -> void:
	var initial := _inventory_state([DecorationLayout.entry("bench", Vector2i(30, 12))])
	var pair := _panel(initial, [{"status": 422, "json": {"code": "BAG_FULL"}}])
	var panel: DecorationPanel = pair[0]
	await _frames()
	panel.select_prop("bench")
	panel.remove_selected()
	assert_bool(await panel.save_layout()).is_false()
	assert_bool(panel.dirty).is_true()
	assert_int(pair[1].state.decorations.size()).is_equal(1)
	assert_that(panel.preview()).is_empty()
	panel.cancel_preview()
	assert_int(panel.preview().size()).is_equal(1)

func test_courtyard_inventory_picker_translates_name_before_appending_quantity() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var pair := _panel(_inventory_state())
	var panel: DecorationPanel = pair[0]
	await _frames()
	assert_str(panel._picker_label("crate")).is_equal(ItemCatalog.name_of("crate") + " x1")
	assert_str(panel._picker_label("crate")).not_contains("crate")
	TranslationServer.set_locale(previous)

func _scene(state: Dictionary, responses: Array = []) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = state.duplicate(true)
	session.version = 1
	var scene := AppRouter.push_instance(AppRouter.PLACE, {"place_id": "courtyard", "session": session})
	return [scene, session, transport]

func test_courtyard_tab_draws_saved_and_preview_meshes_and_requires_discard_confirmation() -> void:
	var pair := _scene(_state())
	var scene: Node = pair[0]
	await _frames()
	assert_bool(scene.canvas.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE).is_true()
	scene.select_tab("decorations")
	await _frames()
	var panel := scene.active_panel as DecorationPanel
	panel.place_selected()
	await _frames()
	assert_object(scene._decorations.get_node_or_null("bench")).is_not_null()
	assert_object(scene._decorations.get_node_or_null("SelectedDecoration")).is_not_null()
	scene.select_tab("people")
	await _frames()
	assert_str(scene.selected_tab).is_equal("decorations")
	assert_bool(panel.place_at(Vector3(1.5, 0, 2.5))).is_false()
	(panel.find_child("KeepEditingDecorations", true, false) as Button).pressed.emit()
	await _frames()
	assert_bool(panel.dirty).is_true()
	scene.select_tab("people")
	await _frames()
	(panel.find_child("DiscardDecorationChanges", true, false) as Button).pressed.emit()
	await _frames()
	assert_str(scene.selected_tab).is_equal("people")
	assert_int(scene._decorations.get_child_count()).is_equal(0)
	assert_that(pair[1].state.decorations).is_equal([])
	assert_int(pair[2].requests.size()).is_equal(0)

func test_courtyard_save_and_continue_uses_server_layout_and_back_can_keep_editing() -> void:
	var props := [DecorationLayout.entry("bench", Vector2i(30, 12))]
	var pair := _scene(_state(), [_reply(_state(true, props))])
	var scene: Node = pair[0]
	await _frames()
	scene.select_tab("decorations")
	await _frames()
	var panel := scene.active_panel as DecorationPanel
	panel.place_selected()
	scene._exit.pressed.emit()
	await _frames()
	assert_bool(AppRouter.top_instance() == scene).is_true()
	assert_object(panel.find_child("DiscardDecorationChanges", true, false)).is_not_null()
	assert_bool(scene.is_back_navigation_locked()).is_true()
	await _frames()
	assert_object(panel.find_child("DecorationPicker", true, false)).is_not_null()
	scene.select_tab("people")
	await _frames()
	(panel.find_child("SaveAndLeaveDecorations", true, false) as Button).pressed.emit()
	await _frames()
	assert_str(scene.selected_tab).is_equal("people")
	assert_object(scene._decorations.get_node_or_null("bench")).is_not_null()
	assert_object(scene._decorations.get_node_or_null("SelectedDecoration")).is_null()
	assert_that(pair[1].state.decorations).is_equal(props)
	assert_int(pair[2].requests.size()).is_equal(1)

func test_world_taps_pick_or_place_pieces_but_panel_taps_and_drags_do_not_edit() -> void:
	var props := [DecorationLayout.entry("bench", Vector2i(30, 12))]
	var pair := _scene(_state(true, props))
	var scene: Node = pair[0]
	await _frames()
	scene.select_tab("decorations")
	await _frames()
	var panel := scene.active_panel as DecorationPanel
	panel.select_prop("crate")
	# 用被测代码自己的坐标函数定位，而不是另算一套。
	var at := func(cell: Vector2i) -> Vector2:
		return scene.cam.unproject_position(DecorationLayout.world_position({"cell": [cell.x, cell.y]}))
	# 点已放的 bench：选中它，而不是在它上面再放一件。
	assert_bool(scene.decoration_tap(at.call(Vector2i(30, 12)))).is_true()
	assert_str(panel.selected_prop).is_equal("bench")
	panel.select_prop("crate")
	assert_bool(scene.decoration_tap(at.call(Vector2i(30, 15)))).is_true()
	assert_int(panel.preview().size()).is_equal(2)
	var before := panel.preview()
	assert_bool(scene.decoration_tap(scene.body.get_global_rect().get_center())).is_false()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = scene.cam.unproject_position(Vector3(-3, 0, 2.5))
	scene._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(25, 0)
	scene._unhandled_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	scene._unhandled_input(release)
	assert_that(panel.preview()).is_equal(before)
	assert_int(pair[2].requests.size()).is_equal(0)

func _touch(position: Vector2, pressed: bool, index := 0, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	get_viewport().push_input(event, true)

func test_touch_input_places_once_and_ignores_canceled_and_dragged_gestures() -> void:
	var pair := _scene(_state())
	var scene: Node = pair[0]
	await _frames()
	scene.select_tab("decorations")
	await _frames()
	var panel := scene.active_panel as DecorationPanel
	var position: Vector2 = scene.cam.unproject_position(Vector3(-2, 0, 1.5))
	_touch(position, true)
	assert_that(panel.preview()).is_equal([])
	_touch(position, false)
	assert_int(panel.preview().size()).is_equal(1)
	assert_int(panel._history.size()).is_equal(1)
	var before := panel.preview()
	position = scene.cam.unproject_position(Vector3(-3, 0, 2.5))
	_touch(position, true)
	_touch(position, false, 0, true)
	assert_that(panel.preview()).is_equal(before)
	_touch(position, true)
	var drag := InputEventScreenDrag.new()
	drag.position = position + Vector2(25, 0)
	drag.relative = Vector2(25, 0)
	get_viewport().push_input(drag, true)
	_touch(position, false)
	assert_that(panel.preview()).is_equal(before)
	_touch(position, true)
	_touch(scene.body.get_global_rect().get_center(), false)
	assert_int(scene._pointer_id).is_equal(-2)
	_touch(position, true)
	_touch(position, false)
	assert_that(panel.preview()).is_not_equal(before)
	assert_int(pair[2].requests.size()).is_equal(0)

func test_swiping_from_decoration_text_scrolls_the_panel_without_editing_the_world() -> void:
	var pair := _scene(_state())
	var scene: Node = pair[0]
	await _frames()
	scene.select_tab("decorations")
	await _frames()
	_swipe_up(scene.scroll.get_global_rect().position + Vector2(12, 16))
	assert_int(scene.scroll.scroll_vertical).is_greater(0)
	assert_that(scene.active_panel.preview()).is_equal([])

func test_swiping_from_decoration_button_scrolls_without_placing_a_piece() -> void:
	var pair := _scene(_state())
	var scene: Node = pair[0]
	await _frames()
	scene.select_tab("decorations")
	await _frames()
	var button := scene.active_panel.find_child("PlaceDecoration", true, false) as Button
	scene.scroll.ensure_control_visible(button)
	await _frames()
	var before: int = scene.scroll.scroll_vertical
	_swipe_up(button.get_global_rect().get_center())
	assert_int(scene.scroll.scroll_vertical).is_greater(before)
	assert_that(scene.active_panel.preview()).is_equal([])

func _swipe_up(position: Vector2) -> void:
	var previous_emulation := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	get_viewport().push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(0, -60)
	motion.relative = Vector2(0, -60)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	get_viewport().push_input(release, true)
	Input.emulate_touch_from_mouse = previous_emulation
