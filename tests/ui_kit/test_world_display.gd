extends GdUnitTestSuite
## SGODOT-222 world display components: NEED-TILE / NeedSource (LOCK-10), HUD (LOCK-06), Today panel,
## Energy card and panel (LOCK-09). Layout is covered by the gallery snapshots.

func _host(c: Control) -> Control:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	host.add_child(c)
	return c

func _settle() -> void:
	for i in 2: await get_tree().process_frame

func _labels(c: Node) -> Array:
	return c.find_children("*", "Label", true, false).filter(func(l): return (l as Label).is_visible_in_tree()).map(func(l): return (l as Label).text)

# ---------------------------------------------------------------- NEED-TILE

func test_need_tile_states() -> void:
	assert_int(auto_free(UiNeedTile.new("Timber", 16, 16)).state()).is_equal(UiNeedTile.State.MET)
	assert_int(auto_free(UiNeedTile.new("Coins", 5, 4)).state()).is_equal(UiNeedTile.State.MET)   # surplus stays met
	assert_int(auto_free(UiNeedTile.new("Timber", 10, 16)).state()).is_equal(UiNeedTile.State.SHORT)
	assert_int(auto_free(UiNeedTile.new("Meals", 100, 300, UiNeedTile.Size.S, null, true)).state()).is_equal(UiNeedTile.State.COUNT)

func test_need_tile_ring_rounds_down_to_ten_percent() -> void:
	var t := UiNeedTile.new("Timber", 15, 16)          # 93.75 % short → 90 %, never a full ring while short
	assert_float(t.progress()).is_equal_approx(0.9, 0.0001)
	t.have = 0
	assert_float(t.progress()).is_equal(0.0)
	t.counting = true
	t.have = 300
	t.need = 300
	assert_float(t.progress()).is_equal(1.0)
	t.counting = false
	t.have = 5
	t.need = 4
	assert_float(t.progress()).is_equal(1.0)              # met is always the full green ring
	t.free()

func test_need_tile_short_number_is_amber_and_need_is_secondary() -> void:
	var t: UiNeedTile = _host(UiNeedTile.new("Timber", 10, 16, UiNeedTile.Size.M))
	await _settle()
	var labels := t.find_children("*", "Label", true, false)
	assert_array(labels.map(func(l): return (l as Label).text)).is_equal(["Timber", "10", "/16"])
	assert_str((labels[1] as Label).get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_WARNING.to_html())
	assert_str((labels[2] as Label).get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_SECONDARY.to_html())
	t.have = 16
	assert_str((labels[1] as Label).get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_TEXT.to_html())

func test_need_tile_sizes_follow_the_three_tokens() -> void:
	var expect := {UiNeedTile.Size.L: UiTokens.SIZE_NEED_TILE_RING_L, UiNeedTile.Size.M: UiTokens.SIZE_NEED_TILE_RING_M,
		UiNeedTile.Size.S: UiTokens.SIZE_NEED_TILE_RING_S}
	for size in expect:
		var t: UiNeedTile = _host(UiNeedTile.new("Tea", 1, 3, size))
		await _settle()
		assert_float(t.ring_side()).is_equal(float(expect[size]))
		assert_bool(t.size.x >= UiTokens.SIZE_TOUCH and t.size.y >= UiTokens.SIZE_TOUCH).is_true()

func test_need_tiles_wrap_instead_of_a_fixed_grid() -> void:
	var g: HFlowContainer = auto_free(UiNeedTile.group([UiNeedTile.new("A", 1, 2), UiNeedTile.new("B", 1, 2)]))
	assert_object(g).is_instanceof(HFlowContainer)

func test_need_source_pops_above_the_tile_and_show_only_runs_the_guide() -> void:
	var host := Control.new()
	host.size = Vector2(360, 800)
	_host(host)
	var shown := []
	var anchor := Rect2(Vector2(140, 400), Vector2(78, 86))
	var layer := UiNeedSource.popup(host, anchor, "Radish Seeds · Homestead Stall", func(): shown.append(true))
	await _settle()
	var pill: UiNeedSource = layer.get_child(0)
	assert_float(pill.get_global_rect().end.y).is_less_equal(anchor.position.y)
	assert_bool(pill.get_global_rect().position.x >= UiTokens.SPACE_PAGE).is_true()
	var show_btn: UiCommandButton = pill.find_children("*", "UiCommandButton", true, false)[0]
	assert_bool(show_btn.visible).is_true()
	show_btn.pressed.emit()
	await _settle()
	assert_array(shown).is_equal([true])
	assert_bool(is_instance_valid(layer)).is_false()

func test_need_source_without_a_target_hides_show() -> void:
	var host := Control.new()
	host.size = Vector2(360, 800)
	_host(host)
	var layer := UiNeedSource.popup(host, Rect2(100, 300, 60, 60), "Pond Crucian · Ponds on the map")
	await _settle()
	var show_btn: UiCommandButton = layer.find_children("*", "UiCommandButton", true, false)[0]
	assert_bool(show_btn.visible).is_false()
	var box: UiStyleBox = (layer.get_child(0) as UiNeedSource).get_theme_stylebox(&"panel")
	assert_that(box.shadow_color).is_equal(UiTokens.COLOR_SHADOW_MENU)   # floats over the world like the main
	assert_float(box.shadow_offset.y).is_equal(float(UiTokens.SIZE_SHADOW_MENU_OFFSET_Y))

# ---------------------------------------------------------------- HUD

func test_energy_colour_is_never_by_percentage() -> void:
	# LOCK-06 (user 2026-10-07): green normally, amber only when short of the next action, red at 0.
	var E := UiHud.Energy
	assert_int(UiHud.energy_state_for(30, 200, 2)).is_equal(E.NORMAL)     # 15 % but enough: still green
	assert_int(UiHud.energy_state_for(1, 200, 2)).is_equal(E.LOW)
	assert_int(UiHud.energy_state_for(150, 200, 0)).is_equal(E.NORMAL)
	assert_int(UiHud.energy_state_for(0, 200, 0)).is_equal(E.EMPTY)
	assert_int(UiHud.energy_state_for(200, 200, 5)).is_equal(E.FULL)
	assert_int(UiHud.energy_state_for(214, 200, 5)).is_equal(E.BONUS)

func test_hud_energy_number_colour_follows_the_state() -> void:
	var hud: UiHud = _host(UiHud.new())
	hud.apply({energy = 1, energy_max = 200, next_cost = 2})
	var value: Label = hud.find_children("*", "Label", true, false).filter(func(l): return (l as Label).text == "1/200")[0]
	assert_str(value.get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_WARNING.to_html())
	hud.apply({energy = 0})
	assert_str(value.get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_DANGER.to_html())
	hud.apply({energy = 120})
	assert_str(value.get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_TEXT.to_html())

func test_hud_rows_read_today_and_the_actual_place() -> void:
	var hud: UiHud = _host(UiHud.new())
	hud.apply({today = "", place = {city = "Shanghai", space = "Farmhouse"}})
	await _settle()
	var texts := _labels(hud)
	assert_array(texts).contains(["Today · All caught up", "Shanghai · ", "Farmhouse"])
	hud.apply({today = "Radishes ready in 1h 12m", place = {city = "Tokyo", space = "Arrived", kind = UiHud.PlaceKind.FOREIGN, day_pass = "23h"}})
	await _settle()
	assert_array(_labels(hud)).contains(["Today · Radishes ready in 1h 12m", "Tokyo · ", " · Day Pass 23h"])
	assert_str(UiHud.place_text(hud.data.place)).is_equal("Tokyo · Arrived · Day Pass 23h")
	# the space is truncated first and always shows its "…" (Godot alone only adds it once 6 letters fit)
	var space: Label = hud._place_space
	assert_str(space.text).ends_with("…")
	assert_bool("Arrived".begins_with(space.text.trim_suffix("…"))).is_true()
	assert_int(space.text.length()).is_greater(1)
	var fs := space.get_theme_font_size(&"font_size")
	assert_float(space.get_theme_font(&"font").get_string_size(space.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x).is_less_equal(space.size.x)
	assert_float(hud._place_suffix.get_global_rect().end.x).is_less_equal(hud.place_chip_rect().end.x)
	hud.apply({place = {city = "Shanghai", space = "Farmhouse", kind = UiHud.PlaceKind.HOME, day_pass = ""}})
	await _settle()
	assert_str(space.text).is_equal("Farmhouse")   # room again: the whole space comes back
	assert_str(UiHud.place_text({city = "Shanghai", space = "Homestead"})).is_equal("Shanghai · Homestead")

func test_hud_badge_buff_and_balances() -> void:
	var hud: UiHud = _host(UiHud.new())
	hud.apply({unread = 0, buff = {}})
	await _settle()
	assert_bool(hud._badge.visible).is_false()
	assert_bool(hud._buff.visible).is_false()
	hud.apply({unread = 3, buff = {remaining = "2h 59m"}})
	assert_bool(hud._badge.visible).is_true()
	assert_str(hud._badge_count.text).is_equal("3")
	assert_bool(hud._buff.visible).is_true()
	hud.apply({unread = 140})
	assert_str(hud._badge_count.text).is_equal("99+")
	hud.show_balances = false
	assert_float(hud._balances.modulate.a).is_equal(0.0)
	assert_int(hud._inbox.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_hud_chips_emit_and_keep_44_hit_areas() -> void:
	var hud: UiHud = _host(UiHud.new())
	await _settle()
	var seen := []
	for sig in [&"avatar_pressed", &"energy_pressed", &"inbox_pressed", &"today_pressed", &"place_pressed"]:
		hud.connect(sig, func(): seen.append(String(sig)))
	var chips := hud.find_children("*", "BaseButton", true, false)
	assert_int(chips.size()).is_equal(5)
	for c in chips:
		var size: Vector2 = (c as Control).size
		assert_bool(size.x >= UiTokens.SIZE_TOUCH and size.y >= UiTokens.SIZE_TOUCH).override_failure_message("%s" % size).is_true()
		(c as BaseButton).pressed.emit()
	assert_array(seen).contains_exactly_in_any_order(["avatar_pressed", "energy_pressed", "inbox_pressed", "today_pressed", "place_pressed"])

func test_hud_sits_at_the_main_position_and_exposes_chip_rects() -> void:
	var hud: UiHud = _host(UiHud.new())
	hud.safe_top = 24
	await _settle()
	var energy := hud.energy_chip_rect()
	assert_vector(energy.size).is_equal(Vector2(UiTokens.SIZE_ENERGY_CHIP_W, UiTokens.SIZE_ENERGY_CHIP_H))
	assert_float(hud._energy_chip.size.y).is_equal(float(UiTokens.SIZE_TOUCH))   # content fits the 42 box
	assert_float(energy.position.y).is_equal_approx(UiTokens.SIZE_HUD_TOP + 24 + 2, 0.5)
	assert_float(hud.today_chip_rect().size.y).is_equal(float(UiTokens.SIZE_HUD_ROW2_H))
	assert_float(hud.today_chip_rect().size.x).is_equal(float(UiTokens.SIZE_TODAY_CHIP_W))

# ---------------------------------------------------------------- Today panel

func test_today_panel_has_at_most_three_rows_and_show_only_where_given() -> void:
	var rows := [
		{line = "Radishes ready in 1h 12m", action = "Show"},
		{line = "Sow your first plot", tail = "needs 2 Energy · +1 in 2:41", action = "Show", state = "short"},
		{line = "Pond Catch · 2 Pond Crucian", state = "done", action = "Show"},
		{line = "Fourth line"},
	]
	var p: UiTodayPanel = _host(UiTodayPanel.new(rows))
	await _settle()
	assert_int(p.row_count()).is_equal(UiTodayPanel.MAX_ROWS)
	assert_array(_labels(p)).not_contains(["Fourth line"])
	assert_array(_labels(p)).contains(["needs 2 Energy · +1 in 2:41"])
	var pills := p.find_children("*", "UiCommandButton", true, false)
	assert_int(pills.size()).is_equal(2)                  # a done row shows its tick, not Show
	var picked := []
	p.show_pressed.connect(func(i): picked.append(i))
	(pills[1] as UiCommandButton).pressed.emit()
	assert_array(picked).is_equal([1])
	assert_float(p.size.x).is_equal(float(UiTokens.SIZE_TODAY_PANEL_W))

# ---------------------------------------------------------------- Energy card / panel

func _facts(home := true) -> Dictionary:
	return {have = 1, max = 200, regen = "+1 in 2:41", zero = false, fact = "Sow 1 plot needs 2 Energy · you have 1",
		wait = "Wait · Full in 13h 20m", tiles = [
			{label = "Eat", fact = "3 dishes in bag", guide = "Open bag", go = "bag", on = true},
			{label = "Cook", fact = "At home" if not home else "4 fish in creel", guide = "Show kitchen", go = "stove", on = home},
			{label = "Tea", fact = "Tea House opens later", guide = "", go = "", on = false},
			{label = "Rest", fact = "At home" if not home else "Available", guide = "Show home", go = "home", on = home},
		]}

func test_energy_card_has_one_button_free_to_do_now() -> void:
	# LOCK-09: the only button is the primary pill; no ×, no Back, no Details.
	var card: UiEnergyCard = _host(UiEnergyCard.card(_facts()))
	await _settle()
	var buttons := card.find_children("*", "Button", true, false)
	assert_int(buttons.size()).is_equal(1)
	var free_now := buttons[0] as UiCommandButton
	assert_str(free_now.text).is_equal("Free to do now")
	assert_str(String(free_now.theme_type_variation)).is_equal(String(UiTokens.BUTTON_CMD_PRIMARY))
	var closed := []
	card.free_pressed.connect(func(): closed.append(true))
	free_now.pressed.emit()
	assert_array(closed).is_equal([true])
	assert_int(card.find_children("*", "UiEnergyTile", true, false).size()).is_equal(4)

func test_energy_tiles_only_guide_and_grey_out_with_the_reason() -> void:
	var card: UiEnergyCard = _host(UiEnergyCard.card(_facts(false)))
	await _settle()
	var gone := []
	card.tile_pressed.connect(func(go): gone.append(go))
	for t in card.find_children("*", "UiEnergyTile", true, false): (t as UiEnergyTile).pressed.emit()
	assert_array(gone).is_equal(["bag"])                  # Cook / Rest are At home away from home, Tea later
	var texts := _labels(card)
	assert_int(texts.count("At home")).is_equal(2)
	assert_array(texts).not_contains(["Show kitchen ›", "Show home ›"])
	assert_array(texts).contains(["Open bag ›"])

func test_energy_card_headline_colour_short_vs_zero() -> void:
	var short: UiEnergyCard = _host(UiEnergyCard.card(_facts()))
	var zero_facts := _facts()
	zero_facts.zero = true
	zero_facts.have = 0
	var zero: UiEnergyCard = _host(UiEnergyCard.card(zero_facts))
	await _settle()
	var value := func(c: Node) -> Label: return c.find_child("Value", true, false)
	assert_str((value.call(short) as Label).get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_WARNING.to_html())
	assert_str((value.call(zero) as Label).get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_DANGER.to_html())

func test_energy_panel_shows_use_as_count_tiles_and_the_blessing() -> void:
	var p: UiEnergyCard = _host(UiEnergyCard.panel({max = 200, uses = [{name = "Meals", have = 100, need = 300}, {name = "Rest", have = 0, need = 1}],
		blessing = {title = "Newcomer Blessing · 5 days left", detail = "Energy returns 1.5× faster · Meals 300 a day"}}))
	await _settle()
	var tiles := p.find_children("*", "UiNeedTile", true, false)
	assert_int(tiles.size()).is_equal(2)
	for t in tiles: assert_int((t as UiNeedTile).state()).is_equal(UiNeedTile.State.COUNT)
	assert_array(_labels(p)).contains(["Max 200", "Newcomer Blessing · 5 days left"])
	assert_int(p.find_children("*", "Button", true, false).size()).is_equal(0)
	assert_float(p.size.x).is_equal(float(UiTokens.SIZE_ENERGY_PANEL_W))
