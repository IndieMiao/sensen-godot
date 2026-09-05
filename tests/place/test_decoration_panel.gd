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
	assert_bool(DecorationLayout.offset_allowed(Vector2i(0, 4))).is_false()
	assert_bool(DecorationLayout.offset_allowed(Vector2i(6, 3))).is_false()
	assert_bool(DecorationLayout.offset_allowed(Vector2i(4, 2))).is_false()
	var rendered := auto_free(DecorationLayout.build(props)) as Node3D
	assert_int(rendered.get_child_count()).is_equal(6)
	for child in rendered.get_children():
		var mesh := child as MeshInstance3D
		assert_object(mesh).is_not_null()
		assert_bool(mesh.mesh.get_aabb().size.x * mesh.scale.x <= 0.8).is_true()
		assert_int(mesh.mesh.get_surface_count()).is_equal(1)

func test_schema_rejects_duplicates_overlap_fractional_offsets_and_unknown_fields() -> void:
	var one := DecorationLayout.entry("bench", Vector2i(-4, 3))
	assert_bool(DecorationLayout.is_valid([one, one])).is_false()
	assert_bool(DecorationLayout.is_valid([one, DecorationLayout.entry("crate", Vector2i(-4, 4))])).is_false()
	var fraction := one.duplicate(true)
	fraction.offset_q = [-3.5, 4]
	assert_bool(DecorationLayout.is_valid([fraction])).is_false()
	var unknown := one.duplicate(true)
	unknown.rotation = 1
	assert_bool(DecorationLayout.is_valid([unknown])).is_false()
	assert_bool(DecorationLayout.is_valid([DecorationLayout.entry("missing", Vector2i(-4, 3))])).is_false()
	assert_bool(DecorationLayout.is_valid([])).is_true()

func test_pre_purchase_preview_can_place_adjust_undo_and_cancel_without_network_or_state_mutation() -> void:
	var pair := _panel(_state(false))
	var panel: DecorationPanel = pair[0]
	await _frames()
	assert_bool(panel.place_selected()).is_true()
	assert_bool(panel.dirty).is_true()
	assert_bool(panel.adjust(Vector2i(0, 1))).is_true()
	assert_that(panel.preview()[0].offset_q).is_equal([-4, 4])
	panel.undo()
	assert_that(panel.preview()[0].offset_q).is_equal([-4, 3])
	assert_bool(await panel.save_layout()).is_false()
	assert_bool((panel.find_child("SaveDecorations", true, false) as Button).disabled).is_true()
	assert_int(pair[2].requests.size()).is_equal(0)
	assert_that(pair[1].state.decorations).is_equal([])
	panel.cancel_preview()
	assert_bool(panel.dirty).is_false()
	assert_that(panel.preview()).is_equal([])

func test_ground_placement_quantizes_but_rejects_path_and_clashing_pieces() -> void:
	var pair := _panel(_state())
	var panel: DecorationPanel = pair[0]
	await _frames()
	assert_bool(panel.place_at(Vector3(-2.1, 0, 1.6))).is_true()
	assert_that(panel.preview()[0].offset_q).is_equal([-4, 3])
	assert_bool(panel.place_at(Vector3(0, 0, 2))).is_false()
	panel.select_prop("crate")
	assert_bool(panel.place_at(Vector3(-2, 0, 1.5))).is_false()
	assert_bool(panel.place_at(Vector3(1.5, 0, 2.5))).is_true()
	assert_bool(panel.pick_at(Vector3(-2, 0, 1.5))).is_true()
	assert_str(panel.selected_prop).is_equal("bench")
	assert_int(pair[2].requests.size()).is_equal(0)

func test_save_sends_the_full_layout_once_and_adopts_only_the_server_reply() -> void:
	var server_props := [DecorationLayout.entry("bench", Vector2i(-4, 4))]
	var pair := _panel(_state(), [_reply(_state(true, server_props))])
	var panel: DecorationPanel = pair[0]
	await _frames()
	panel.place_selected()
	assert_bool(await panel.save_layout()).is_true()
	assert_str(pair[2].last_body().type).is_equal("save_decorations")
	assert_that(DecorationLayout.canonical(pair[2].last_body().payload.props)).is_equal([DecorationLayout.entry("bench", Vector2i(-4, 3))])
	assert_that(panel.preview()).is_equal(server_props)
	assert_that(pair[1].state.decorations).is_equal(server_props)
	assert_bool(panel.dirty).is_false()
	assert_int(pair[1].state.wallet).is_equal(287)
	assert_bool(await panel.save_layout()).is_false()
	assert_int(pair[2].requests.size()).is_equal(1)

func test_rejected_save_keeps_preview_and_saved_state_then_cancel_restores_the_saved_layout() -> void:
	var saved := [DecorationLayout.entry("bench", Vector2i(-4, 3))]
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
	var after := _state(true, [DecorationLayout.entry("bench", Vector2i(-4, 3))])
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
	var saved := [DecorationLayout.entry("bench", Vector2i(-4, 3))]
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
	assert_bool(panel.mouse_filter == Control.MOUSE_FILTER_STOP).is_true()

func test_saved_json_numbers_normalize_without_creating_unsaved_changes() -> void:
	var props: Array = JSON.parse_string('[{"anchor_id":"courtyard","prop_id":"bench","offset_q":[-4,3]}]')
	var pair := _panel(_state(true, props))
	var panel: DecorationPanel = pair[0]
	await _frames()
	assert_bool(panel.dirty).is_false()
	assert_that(panel.preview()).is_equal([DecorationLayout.entry("bench", Vector2i(-4, 3))])
	assert_bool(panel.place_at(Vector3(-2, 0, 1.5))).is_false()
	assert_bool(panel.dirty).is_false()

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
	var props := [DecorationLayout.entry("bench", Vector2i(-4, 3))]
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
	var props := [DecorationLayout.entry("bench", Vector2i(-4, 3))]
	var pair := _scene(_state(true, props))
	var scene: Node = pair[0]
	await _frames()
	scene.select_tab("decorations")
	await _frames()
	var panel := scene.active_panel as DecorationPanel
	panel.select_prop("crate")
	assert_bool(scene.decoration_tap(scene.cam.unproject_position(Vector3(-2, 0, 1.5)))).is_true()
	assert_str(panel.selected_prop).is_equal("bench")
	panel.select_prop("crate")
	assert_bool(scene.decoration_tap(scene.cam.unproject_position(Vector3(1.5, 0, 2.5)))).is_true()
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
