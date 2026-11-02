extends GdUnitTestSuite
## Real viewport input: a drag must scroll without firing the starting button.

var _emulate_touch := false

func before_test() -> void:
	_emulate_touch = Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true

func after_test() -> void:
	Input.emulate_touch_from_mouse = _emulate_touch

func _settle() -> void:
	for frame in 5: await get_tree().process_frame

func _scroll(horizontal := false) -> TouchScrollContainer:
	var scroll := TouchScrollContainer.new()
	scroll.position = Vector2(20, 100)
	scroll.size = Vector2(280, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if horizontal else ScrollContainer.SCROLL_MODE_AUTO
	add_child(auto_free(scroll))
	return scroll

func _rows(scroll: ScrollContainer, horizontal := false) -> BoxContainer:
	var rows: BoxContainer = HBoxContainer.new() if horizontal else VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for i in 12:
		var wrapper := PanelContainer.new()
		rows.add_child(wrapper)
		var button := Button.new()
		button.text = "Item %d" % i
		button.custom_minimum_size = Vector2(120, 60)
		wrapper.add_child(button)
	return rows

func _mouse(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	get_viewport().push_input(event, true)

func _motion(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)

func _drag(button: Control, delta: Vector2) -> void:
	var start := button.get_global_rect().get_center()
	_mouse(start, true)
	for step in 8:
		_motion(start + delta * float(step + 1) / 8, delta / 8)
		await get_tree().process_frame
	_mouse(start + delta, false)

func test_vertical_drag_through_dynamic_card_wrapper_cancels_click() -> void:
	var scroll := _scroll()
	var rows := _rows(scroll)
	await _settle()
	var button: Button = rows.get_child(1).get_child(0)
	var clicks := [0]
	button.pressed.connect(func(): clicks[0] += 1)
	await _drag(button, Vector2(0, -90))
	assert_int(scroll.scroll_vertical).is_greater(30)
	assert_int(clicks[0]).is_zero()

func test_horizontal_drag_and_disabled_button_both_scroll() -> void:
	var scroll := _scroll(true)
	var rows := _rows(scroll, true)
	await _settle()
	var button: Button = rows.get_child(1).get_child(0)
	button.disabled = true
	await _drag(button, Vector2(-100, 0))
	assert_int(scroll.scroll_horizontal).is_greater(30)

func test_short_tap_with_jitter_still_activates_once() -> void:
	var scroll := _scroll()
	var rows := _rows(scroll)
	await _settle()
	var button: Button = rows.get_child(1).get_child(0)
	var clicks := [0]
	button.pressed.connect(func(): clicks[0] += 1)
	await _drag(button, Vector2(0, -3))
	assert_int(scroll.scroll_vertical).is_zero()
	assert_int(clicks[0]).is_equal(1)

func test_check_button_does_not_toggle_during_scroll() -> void:
	var scroll := _scroll()
	var rows := _rows(scroll)
	var toggle := CheckButton.new()
	toggle.text = "Allow visits"
	toggle.custom_minimum_size.y = 60
	rows.add_child(toggle)
	rows.move_child(toggle, 1)
	await _settle()
	var changes := [0]
	toggle.toggled.connect(func(_value): changes[0] += 1)
	await _drag(toggle, Vector2(0, -80))
	assert_int(scroll.scroll_vertical).is_greater(20)
	assert_int(changes[0]).is_zero()
	assert_bool(toggle.button_pressed).is_false()

func test_option_button_waits_for_release_and_drag_does_not_open_popup() -> void:
	var scroll := _scroll()
	var rows := _rows(scroll)
	var option := OptionButton.new()
	option.add_item("Member A")
	option.add_item("Member B")
	option.custom_minimum_size.y = 60
	rows.add_child(option)
	rows.move_child(option, 1)
	await _settle()
	_mouse(option.get_global_rect().get_center(), true)
	assert_bool(option.get_popup().visible).is_false()
	_mouse(option.get_global_rect().get_center(), false)
	assert_bool(option.get_popup().visible).is_true()
	option.get_popup().hide()
	await _drag(option, Vector2(0, -80))
	assert_int(scroll.scroll_vertical).is_greater(20)
	assert_bool(option.get_popup().visible).is_false()

func test_nested_horizontal_strip_passes_vertical_drag_to_sheet() -> void:
	var outer := _scroll()
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(column)
	var inner := TouchScrollContainer.new()
	inner.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inner.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.custom_minimum_size.y = 65
	column.add_child(inner)
	var rows := _rows(inner, true)
	var filler := Control.new()
	filler.custom_minimum_size.y = 600
	column.add_child(filler)
	await _settle()
	await _drag(rows.get_child(1).get_child(0), Vector2(0, -80))
	assert_int(outer.scroll_vertical).is_greater(20)
	assert_int(inner.scroll_horizontal).is_zero()

func test_nearby_farmer_cards_scroll_without_changing_selection() -> void:
	var stage := Control.new()
	stage.size = Vector2(360, 640)
	add_child(auto_free(stage))
	var panel := NearbyPanel.new()
	stage.add_child(panel)
	var entries := []
	for i in 9: entries.append({"farm_id": "f%d" % i, "avatar_ref": "seed:test%d" % i, "nursery_stage": "cleared"})
	panel.set_entries(entries, entries.size())
	await _settle()
	await _drag(panel.cards()[1], Vector2(-110, 0))
	assert_int(panel._scroll.scroll_horizontal).is_greater(30)
	assert_str(panel.focused_id).is_empty()

func test_party_actions_scroll_without_sending_commands() -> void:
	var transport := FakeTransport.new([])
	var online := OnlineSpace.new()
	online.session = FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	online.session.player_id = "self"
	online.kind = "farm"
	online.directory = {"travel_version": 1, "party": {"code": "SCROLL", "leader": "self", "members": ["self", "other"]}, "roster": []}
	online.panel = PanelContainer.new()
	online.panel.position = Vector2(20, 100)
	online.panel.size = Vector2(320, 300)
	add_child(auto_free(online))
	online.set_process(false)
	add_child(auto_free(online.panel))
	online._draw_party()
	await _settle()
	var scroll := online.panel.find_child("PartyScroll", true, false) as ScrollContainer
	var buttons := online.panel.find_children("*", "BaseButton", true, false)
	var target: BaseButton
	for button in buttons:
		if button.text == L10n.text("Disband party"): target = button
	scroll.ensure_control_visible(target)
	await _settle()
	var before := scroll.scroll_vertical
	await _drag(target, Vector2(0, -90))
	assert_int(scroll.scroll_vertical).is_greater(before)
	assert_int(transport.requests.size()).is_zero()

func test_drag_at_list_end_still_cancels_button_press() -> void:
	var scroll := _scroll()
	var rows := _rows(scroll)
	await _settle()
	scroll.scroll_vertical = 100000
	await _settle()
	var button: Button = rows.get_child(11).get_child(0)
	var clicks := [0]
	button.pressed.connect(func(): clicks[0] += 1)
	var before := scroll.scroll_vertical
	await _drag(button, Vector2(0, -70))
	assert_int(scroll.scroll_vertical).is_equal(before)
	assert_int(clicks[0]).is_zero()

func test_nested_horizontal_drag_does_not_scroll_outer_sheet() -> void:
	var outer := _scroll()
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(column)
	var inner := TouchScrollContainer.new()
	inner.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inner.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.custom_minimum_size.y = 65
	column.add_child(inner)
	var rows := _rows(inner, true)
	var filler := Control.new()
	filler.custom_minimum_size.y = 600
	column.add_child(filler)
	await _settle()
	await _drag(rows.get_child(1).get_child(0), Vector2(-90, 0))
	assert_int(inner.scroll_horizontal).is_greater(20)
	assert_int(outer.scroll_vertical).is_zero()

func _party() -> OnlineSpace:
	var directory := {"protocol": 1, "travel_version": 1, "party": {"code": "COPY-QA", "leader": "self", "members": ["self", "other"]}, "roster": []}
	var transport := FakeTransport.new([{ "status": 200, "json": directory }])
	var online := OnlineSpace.new()
	online.session = FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	online.session.player_id = "self"
	online.kind = "farm"
	add_child(auto_free(online))
	online.set_process(false)
	var available := Net.online_available
	await online._open_party()
	Net.online_available = available
	await _settle()
	return online

func test_party_close_stays_at_top_right_after_scrolling_and_refresh() -> void:
	var online := await _party()
	var close := online.panel.find_child("CloseParty", true, false) as Button
	var top_right := close.get_global_rect()
	var scroll := online.panel.find_child("PartyScroll", true, false) as ScrollContainer
	scroll.scroll_vertical = 200
	await _settle()
	assert_that(close.get_global_rect()).is_equal(top_right)
	# the panel's own padding (GameUi.panel_style), not a figure: it changed with the 09-23 restyle (c1d0d261)
	var pad := online.panel.get_theme_stylebox("panel").content_margin_right
	assert_float(top_right.end.x).is_equal_approx(online.panel.get_global_rect().end.x - pad, 1)
	var offset := scroll.scroll_vertical
	online._draw_party()
	await _settle()
	scroll = online.panel.find_child("PartyScroll", true, false) as ScrollContainer
	assert_int(scroll.scroll_vertical).is_equal(offset)
	close = online.panel.find_child("CloseParty", true, false) as Button
	assert_that(close.get_global_rect()).is_equal(top_right)
	_mouse(top_right.get_center(), true)
	_mouse(top_right.get_center(), false)
	assert_object(online.panel).is_null()

func test_party_backdrop_dismisses_on_release_without_clicking_underlying_world() -> void:
	var world := Button.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(auto_free(world))
	var clicks := [0]
	world.pressed.connect(func(): clicks[0] += 1)
	var online := await _party()
	_mouse(Vector2(5, 80), true)
	assert_object(online.panel).is_not_null()
	_mouse(Vector2(5, 80), false)
	await _settle()
	assert_object(online.panel).is_null()
	assert_object(online._modal_shield).is_null()
	assert_int(clicks[0]).is_zero()

func test_invite_copy_shows_localized_timed_toast_but_drag_does_not_copy() -> void:
	var online := await _party()
	var copy := online.panel.find_child("CopyInviteCode", true, false) as Button
	var previous_clipboard := DisplayServer.clipboard_get()
	DisplayServer.clipboard_set("before-copy")
	await _drag(copy, Vector2(0, -85))
	assert_str(DisplayServer.clipboard_get()).is_equal("before-copy")
	assert_object(online._copy_toast).is_null()
	var scroll := online.panel.find_child("PartyScroll", true, false) as ScrollContainer
	scroll.scroll_vertical = 0
	await _settle()
	var point := copy.get_global_rect().get_center()
	_mouse(point, true)
	_mouse(point, false)
	assert_str(DisplayServer.clipboard_get()).is_equal("COPY-QA")
	DisplayServer.clipboard_set(previous_clipboard)
	assert_bool(online._copy_toast.visible).is_true()
	assert_str((online._copy_toast.get_child(0) as Label).text).is_equal(L10n.text("Invite code copied"))
	assert_int(online._copy_toast.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	await _settle()
	assert_float(online._copy_toast.size.y).is_less_equal(60)
	assert_float(online._copy_toast.get_global_rect().end.y).is_less(online.panel.position.y)
	await get_tree().create_timer(2.1).timeout
	assert_bool(online._copy_toast.visible).is_false()
