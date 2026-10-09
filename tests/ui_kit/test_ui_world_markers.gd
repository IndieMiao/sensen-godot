extends GdUnitTestSuite
## UiStatusBadge, UiEntryCard and the WorldAnchor pointer hook (SGODOT-221 / 231, LOCK-07 / 11 / 21).

const B := UiStatusBadge.State

func _host(c: Control) -> Control:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 640)
	add_child(auto_free(host))
	host.add_child(c)
	return c

func _settle() -> void:
	for i in 3: await get_tree().process_frame

# ---------------------------------------------------------------- world anchor

func _mouse(pos: Vector2, down: bool) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = pos
	m.pressed = down
	return m

func test_world_anchor_keeps_the_pointer_on_a_facility_at_the_screen_edge() -> void:
	var world := Node3D.new()
	add_child(auto_free(world))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 0, 10)
	cam.current = true
	var stove := Node3D.new()
	world.add_child(stove)
	var layer := WorldAnchor.new()
	_host(layer)
	layer.size = Vector2(360, 640)
	layer.camera = cam
	var card := UiEntryCard.new("Floor 2 · 2 Energy")
	layer.track(card, stove, {clamp = true})
	await _settle()
	# Near the right edge the card is clamped inside; its pointer still ends over the gate, as far right as the card
	# lets it (Pointer=Right: 21 px in, EntryCard's own clamp).
	stove.position = cam.project_position(Vector2(get_viewport().get_visible_rect().size.x - 8, 300), 10.0)
	layer.update_now()
	var stove_x := cam.unproject_position(stove.global_position).x
	assert_float(card.get_global_rect().end.x).is_less_equal(get_viewport().get_visible_rect().size.x)
	var right_most := card.global_position.x + card._card.size.x - 21.0 - UiTokens.SIZE_POINTER_W * 0.5
	assert_float(card.global_position.x + card.pointer_tip_x()).is_equal_approx(minf(stove_x, right_most), 1.0)

# ---------------------------------------------------------------- status badge

func test_badge_sizes_and_rings_follow_the_main() -> void:
	var w := _host(UiStatusBadge.new(B.READY)) as UiStatusBadge
	var n := _host(UiStatusBadge.new(B.REQUEST, UiStatusBadge.Size.NPC)) as UiStatusBadge
	await _settle()
	assert_vector(w._badge.size).is_equal(Vector2(UiTokens.SIZE_STATUS_BADGE_WORLD, UiTokens.SIZE_STATUS_BADGE_WORLD))
	assert_vector(n._badge.size).is_equal(Vector2(UiTokens.SIZE_STATUS_BADGE_NPC, UiTokens.SIZE_STATUS_BADGE_NPC))
	assert_vector(w._glyph.size).is_equal(Vector2(UiTokens.SIZE_STATUS_GLYPH_WORLD, UiTokens.SIZE_STATUS_GLYPH_WORLD))
	assert_vector(n._glyph.size).is_equal(Vector2(UiTokens.SIZE_STATUS_GLYPH_NPC, UiTokens.SIZE_STATUS_GLYPH_NPC))
	assert_float(w.ring_width()).is_equal(1.0)    # Ready: 1 px primary ring
	assert_float(n.ring_width()).is_equal(2.0)    # Request: 2 px amber ring

func test_every_state_has_its_colours_and_glyph() -> void:
	var pot := load("res://assets/p0/icons/pot.svg") if ResourceLoader.exists("res://assets/p0/icons/pot.svg") else load("res://assets/p0/icons/hoe.svg")
	for s in B.values():
		var b := _host(UiStatusBadge.new(s)) as UiStatusBadge
		b.icon = pot
		var box := b._badge.get_theme_stylebox(&"panel") as UiStyleBox
		assert_object(box.bg_color).is_equal(UiStatusBadge._FILL[s])
		assert_object(box.border_color).is_equal(UiStatusBadge._RING[s])
		assert_object(b._glyph.texture).is_not_null()
		if s == B.AVAILABLE: assert_object(b._glyph.texture).is_equal(pot)

func test_caption_pill_hangs_under_the_badge() -> void:
	var b := _host(UiStatusBadge.new(B.COUNTDOWN)) as UiStatusBadge
	b.caption = "1h 12m"
	await _settle()
	assert_bool(b._pill.visible).is_true()
	assert_float(b._pill.position.y).is_equal(float(UiTokens.SIZE_STATUS_BADGE_WORLD) + 2.0)
	assert_float(b._pill.size.y).is_equal(float(UiTokens.SIZE_CAPTION_PILL_H))
	assert_float(b._badge.position.x + b._badge.size.x * 0.5).is_equal_approx(b.size.x * 0.5, 0.5)
	b.caption = ""
	await _settle()
	assert_bool(b._pill.visible).is_false()
	assert_vector(b.get_combined_minimum_size()).is_equal(Vector2(28, 28))

## SGODOT-266 (不知火舞 9ce583a8): the mouth's card — title row with the fact in secondary, the map card's Go as the main
## button across the card, New run as a secondary text button 44 high and its note right under it.
func test_entry_card_reads_title_main_then_second() -> void:
	var c := _host(UiEntryCard.new("Continue run · Free")) as UiEntryCard
	c.title = "The mine"
	c.title_fact = "Runs today 1/2"
	c.second = "New run · 2 Energy"
	c.note = "Current run will end"
	await _settle()
	assert_bool(c._title_row.visible).is_true()
	assert_object(c._title.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_TEXT)
	assert_object(c._title_fact.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
	assert_str(c.main_text()).is_equal("Continue run · Free")
	assert_str(str(c._main.theme_type_variation)).is_equal(str(UiTokens.BUTTON_CMD_PRIMARY))
	assert_float(c._main.size.x).is_equal_approx(c._card.size.x - 24.0, 0.5)   # across the card, 12 in from each side
	assert_float(c._main.size.y).is_equal(float(UiTokens.SIZE_COMMAND))
	assert_float(c.second_rect().size.y).is_greater_equal(float(UiTokens.SIZE_TOUCH))
	assert_bool(c.note_shown()).is_true()
	assert_float(c._note.get_global_rect().position.y).is_less(c.second_rect().end.y)   # inside the second's 44
	assert_float(c._card.size.x).is_greater_equal(UiEntryCard.MIN_WIDTH)
	assert_float(c.pointer_tip_x()).is_equal_approx(c._card.size.x * 0.5, 0.5)
	assert_float(c.get_combined_minimum_size().y).is_equal(c._card.size.y + UiTokens.SIZE_POINTER_H)

## A ladder's card: no title, one button (the destination is on it).
func test_a_ladder_card_is_one_button_without_a_title() -> void:
	var c := _host(UiEntryCard.new("Floor 2 · 2 Energy")) as UiEntryCard
	await _settle()
	assert_bool(c._title_row.visible).is_false()
	assert_bool(c.second_shown()).is_false()
	assert_float(c._card.size.y).is_equal_approx(float(UiTokens.SIZE_COMMAND) + 24.0, 0.5)

## LOCK-10: grey is CmdBlocked with the reason and still takes the tap; amber (short of Energy) keeps the whole line.
func test_unavailable_and_amber_main() -> void:
	var c := _host(UiEntryCard.new("Floor 2 · Clear Floor 1 first", UiEntryCard.State.UNAVAILABLE)) as UiEntryCard
	await _settle()
	assert_str(str(c._main.theme_type_variation)).is_equal(str(UiTokens.BUTTON_CMD_BLOCKED))
	assert_str(c.main_text()).is_equal("Floor 2 · Clear Floor 1 first")
	assert_bool(c.is_amber()).is_false()
	var hits := [0]
	c.pressed.connect(func(): hits[0] += 1)
	assert_str(c.tap_at(c.main_rect().get_center())).is_equal("main")
	assert_int(hits[0]).is_equal(1)   # the owner toasts why
	c.state = UiEntryCard.State.AVAILABLE
	c.action = "Floor 2 · Need 2 Energy"
	c.amber = true
	await _settle()
	assert_bool(c.is_amber()).is_true()
	assert_str(c.main_text()).is_equal("Floor 2 · Need 2 Energy")
	var box := c._main.get_theme_stylebox(&"normal")
	assert_object(box.get(&"bg_color")).is_equal(UiTokens.COLOR_AMBER)
	assert_object(c._main.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_TEXT)
	c.amber = false
	assert_bool(c.is_amber()).is_false()

## The second: secondary ink, amber short of Energy, grey with its reason and then no note.
func test_second_states_and_note() -> void:
	var c := _host(UiEntryCard.new("Continue run · Free")) as UiEntryCard
	c.second = "New run · 2 Energy"
	c.note = "Current run will end"
	await _settle()
	assert_object(c._second.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
	c.second_amber = true
	assert_object(c._second.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_WARNING)
	assert_bool(c.note_shown()).is_true()   # short of Energy keeps the consequence (不知火舞 on #45)
	c.second = "New run · Clear Floor 2 first"
	c.second_state = UiEntryCard.State.UNAVAILABLE
	assert_object(c._second.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_DISABLED_INK)
	assert_bool(c.note_shown()).is_false()

func test_entry_card_pointer_right_sits_21_px_in() -> void:
	var c := _host(UiEntryCard.new("Floor 2 · 2 Energy")) as UiEntryCard
	await _settle()
	var w := c._card.size.x
	c.point_at(w + 80.0)
	assert_float(c.pointer_tip_x()).is_equal(w - 21.0 - 7.0)   # Pointer=Right: box 21 px in from the right
	c.point_at(-80.0)
	assert_float(c.pointer_tip_x()).is_equal(21.0 + 7.0)

## A real tap on a part (down and up on it within the slop) is that part's; a drag or a tap between them is nothing.
func test_entry_card_taps_its_parts_and_ignores_drags() -> void:
	var c := _host(UiEntryCard.new("Continue run · Free")) as UiEntryCard
	c.second = "New run · 2 Energy"
	await _settle()
	var hits := {"main": 0, "second": 0}
	c.pressed.connect(func(): hits.main += 1)
	c.second_pressed.connect(func(): hits.second += 1)
	var main := c.main_rect().get_center() - c._card.global_position
	var second := c.second_rect().get_center() - c._card.global_position
	c._on_input(_mouse(main, true))
	c._on_input(_mouse(main + Vector2(2, 2), false))
	assert_int(hits.main).is_equal(1)
	c._on_input(_mouse(second, true))
	c._on_input(_mouse(second, false))
	assert_int(hits.second).is_equal(1)
	c._on_input(_mouse(main, true))
	c._on_input(_mouse(main + Vector2(GestureArbiter.TAP_SLOP + 1, 0), false))
	assert_int(hits.main).is_equal(1)
	assert_str(c.tap_at(Vector2(-50, -50))).is_equal("")
	assert_str(c.tap_at(c._card.global_position + Vector2(4, 4))).is_equal("card")   # its padding: nothing
	assert_int(hits.main + hits.second).is_equal(2)

func test_passive_entry_card_lets_the_scene_take_the_press() -> void:
	var c := _host(UiEntryCard.new("Floor 2 · 2 Energy")) as UiEntryCard
	c.passive = true
	assert_int(c._card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(c._main.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	await _settle()
	assert_float(c.hit_rect().size.y).is_greater_equal(float(UiTokens.SIZE_TOUCH))

func test_entry_card_setters_skip_unchanged_values() -> void:
	var c := _host(UiEntryCard.new("Floor 2 · 2 Energy")) as UiEntryCard
	await _settle()
	c._second.remove_theme_color_override(&"font_color")   # a restyle would put it back
	c.action = "Floor 2 · 2 Energy"
	c.state = UiEntryCard.State.AVAILABLE
	assert_bool(c._second.has_theme_color_override(&"font_color")).is_false()
	c.state = UiEntryCard.State.UNAVAILABLE
	assert_str(str(c._main.theme_type_variation)).is_equal(str(UiTokens.BUTTON_CMD_BLOCKED))
