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
	var card := UiEntryCard.new("New run · 2 Energy", "Current run will end · Runs today 1/2")
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

func test_entry_card_matches_the_main() -> void:
	var c := _host(UiEntryCard.new("New run · 2 Energy", "Current run will end · Runs today 1/2")) as UiEntryCard
	await _settle()
	assert_float(c._card.size.y).is_between(50.0, 58.0)     # main 54 high: 8 + 13 × 1.35 + 2 + 11 + 9
	assert_float(c._card.size.x).is_between(200.0, 240.0)    # hugs the copy, 220 in the main
	assert_bool(c._caption.visible).is_true()
	assert_object(c._action.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_PRIMARY)
	assert_float(c.pointer_tip_x()).is_equal_approx(c._card.size.x * 0.5, 0.5)
	assert_float(c.get_combined_minimum_size().y).is_equal(c._card.size.y + UiTokens.SIZE_POINTER_H)

func test_unavailable_entry_card_writes_the_reason_and_drops_the_caption() -> void:
	var c := _host(UiEntryCard.new("New run · Clear Floor 2 first", "Current run will end", UiEntryCard.State.UNAVAILABLE)) as UiEntryCard
	await _settle()
	assert_bool(c._caption.visible).is_false()
	assert_object(c._action.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
	c.state = UiEntryCard.State.AVAILABLE
	c.amber = true
	assert_object(c._action.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_WARNING)
	assert_bool(c._caption.visible).is_true()   # short of Energy keeps the consequence (不知火舞 on #45)

func test_entry_card_pointer_right_sits_21_px_in() -> void:
	var c := _host(UiEntryCard.new("New run · 2 Energy", "Current run will end · Runs today 1/2")) as UiEntryCard
	await _settle()
	var w := c._card.size.x
	c.point_at(w + 80.0)
	assert_float(c.pointer_tip_x()).is_equal(w - 21.0 - 7.0)   # Pointer=Right: box 21 px in from the right
	c.point_at(-80.0)
	assert_float(c.pointer_tip_x()).is_equal(21.0 + 7.0)

func test_entry_card_is_one_button_that_ignores_drags() -> void:
	var c := _host(UiEntryCard.new("New run · 2 Energy")) as UiEntryCard
	var hits := [0]
	c.pressed.connect(func(): hits[0] += 1)
	c._on_input(_mouse(Vector2(30, 12), true))
	c._on_input(_mouse(Vector2(32, 14), false))
	assert_int(hits[0]).is_equal(1)
	c._on_input(_mouse(Vector2(30, 12), true))
	c._on_input(_mouse(Vector2(30 + GestureArbiter.TAP_SLOP + 1, 12), false))
	assert_int(hits[0]).is_equal(1)

func test_passive_entry_card_lets_the_scene_take_the_press() -> void:
	var c := _host(UiEntryCard.new("New run · 2 Energy")) as UiEntryCard
	c.passive = true
	assert_int(c._card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	await _settle()
	assert_float(c.hit_rect().size.y).is_greater_equal(float(UiTokens.SIZE_TOUCH))

func test_entry_card_setters_skip_unchanged_values() -> void:
	var c := _host(UiEntryCard.new("New run · 2 Energy", "Current run will end")) as UiEntryCard
	await _settle()
	c._action.remove_theme_color_override(&"font_color")   # a restyle would put it back
	c.action = "New run · 2 Energy"
	c.state = UiEntryCard.State.AVAILABLE
	assert_bool(c._action.has_theme_color_override(&"font_color")).is_false()
	c.state = UiEntryCard.State.UNAVAILABLE
	assert_object(c._action.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
