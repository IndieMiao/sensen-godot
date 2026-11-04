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

## The callers set the theme on the popup's layer after it is made (HOME-1, the workbench): Show is first measured in the
## fallback font (77 wide) and must come back to the main's 65 once the theme is on (SGODOT-394: Fishing's line fits).
func test_need_source_show_keeps_its_size_when_the_theme_comes_after() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(360, 800)
	add_child(host)
	var layer := UiNeedSource.popup(host, Rect2(140, 400, 78, 86), "Fishing Lv5 · Catch fish to level up", func(): pass)
	layer.theme = UiKit.theme()
	await _settle()
	var pill: UiNeedSource = layer.get_child(0)
	var show_btn: UiShowPill = pill.find_children("*", "UiShowPill", true, false)[0]
	assert_float(show_btn.size.x).is_equal_approx(65.0, 1.0)
	assert_str((pill.find_children("*", "Label", true, false)[0] as Label).text).is_equal("Fishing Lv5 · Catch fish to level up")   # one line

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
	var show_btn: UiShowPill = pill.find_children("*", "UiShowPill", true, false)[0]
	assert_bool(show_btn.visible).is_true()
	assert_float(show_btn.size.y).is_equal(31.0)   # NeedSource main: Show 65 × 31, card 45 high
	assert_float(show_btn.size.x).is_equal_approx(65.0, 2.0)
	assert_float(pill.size.y).override_failure_message("card %s show %s" % [pill.size, show_btn.size]).is_equal_approx(45.0, 1.5)   # 6 + 31 + 6 + the 1 px border (Figma rounds 31.2)
	assert_bool(show_btn._has_point(Vector2(32, -6))).is_true()   # touch area reaches 44 around the pill
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
	var show_btn: UiShowPill = layer.find_children("*", "UiShowPill", true, false)[0]
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

func test_skill_ring_halves_fill_from_twelve_with_4_degree_gaps_and_5_percent_steps() -> void:
	var a := UiHud.skill_arcs(0.6, 0.4)   # the HUD main's sample: Farming -86 → 17.2, Fishing -94 → -162.8
	assert_vector(a.farming).is_equal_approx(Vector2(-86.0, 17.2), Vector2(0.01, 0.01))
	assert_vector(a.fishing).is_equal_approx(Vector2(-94.0, -162.8), Vector2(0.01, 0.01))
	assert_float(UiHud.skill_arcs(0.64, 0.0).farming.y).is_equal_approx(17.2, 0.01)   # floored to 60 %
	var full := UiHud.skill_arcs(1.0, 1.0)   # top level: both halves full, 4° short of 6 o'clock
	assert_float(full.farming.y).is_equal_approx(86.0, 0.01)
	assert_float(full.fishing.y).is_equal_approx(-266.0, 0.01)

## q(107) / SGODOT-271: Today is an icon with no words, its red dot on or off; the place chip reads the actual place.
func test_hud_rows_read_the_today_dot_and_the_actual_place() -> void:
	var hud: UiHud = _host(UiHud.new())
	hud.apply({today_dot = false, place = {city = "San Francisco", space = "Farmhouse"}})
	await _settle()
	var texts := _labels(hud)
	assert_array(texts).contains(["San Francisco · ", "Farmhouse"])
	assert_array(texts.filter(func(t): return str(t).begins_with("Today"))).is_empty()
	assert_bool(hud.today_dot_shown()).is_false()
	# The place chip is 300 wide with the icon (SGODOT-271): a space long enough to be cut there.
	const LONG := "Sumida Riverside Ferry Pier Fishing Steps"
	hud.apply({today_dot = true, place = {city = "Tokyo", space = LONG, kind = UiHud.PlaceKind.FOREIGN, day_pass = "23h"}})
	await _settle()
	assert_bool(hud.today_dot_shown()).is_true()
	assert_array(_labels(hud)).contains(["Tokyo · ", " · Day Pass 23h"])
	assert_str(UiHud.place_text(hud.data.place)).is_equal("Tokyo · %s · Day Pass 23h" % LONG)
	# LOCK-06 v1.9: Helping wins over the pass; an expired pass leaves no third segment
	assert_str(UiHud.place_text({city = "Tokyo", space = "Mia's Farm", day_pass = "3h", helping = true})).is_equal("Tokyo · Mia's Farm · Helping")
	assert_str(UiHud.place_text({city = "Tokyo", space = "Sumida Pond", day_pass = ""})).is_equal("Tokyo · Sumida Pond")
	# the space is truncated first and always shows its "…" (Godot alone only adds it once 6 letters fit)
	var space: Label = hud._place_space
	assert_str(space.text).ends_with("…")
	assert_bool(LONG.begins_with(space.text.trim_suffix("…"))).is_true()
	assert_int(space.text.length()).is_greater(1)
	var fs := space.get_theme_font_size(&"font_size")
	assert_float(space.get_theme_font(&"font").get_string_size(space.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x).is_less_equal(space.size.x)
	assert_float(hud._place_suffix.get_global_rect().end.x).is_less_equal(hud.place_chip_rect().end.x)
	hud.apply({place = {city = "San Francisco", space = "Farmhouse", kind = UiHud.PlaceKind.HOME, day_pass = ""}})
	await _settle()
	assert_str(space.text).is_equal("Farmhouse")   # room again: the whole space comes back
	assert_str(UiHud.place_text({city = "San Francisco", space = "Homestead"})).is_equal("San Francisco · Homestead")

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
	# SGODOT-271 (不知火舞 76ebeaad): the Today icon is a 32 x 24 pill where the chip began, its hit area 44 x 44; the
	# place chip takes the rest, 340 − 32 − 8 = 300; the 8 px dot stands 2 past the pill's right and top edges.
	var today := hud.today_chip_rect()
	assert_vector(today.size).is_equal(Vector2(UiTokens.SIZE_TODAY_ICON_W, UiTokens.SIZE_HUD_ROW2_H))
	assert_float(today.position.x).is_equal_approx(UiTokens.SIZE_HUD_X + 2.0, 0.5)
	assert_vector(hud._today_chip.size).is_equal(Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_TOUCH))
	var place := hud.place_chip_rect()
	assert_float(place.position.x - today.end.x).is_equal_approx(float(UiTokens.SPACE_HUD_ROW_GAP), 0.5)
	assert_float(place.size.x).is_equal_approx(300.0, 0.5)
	assert_float(place.position.y).is_equal_approx(today.position.y, 0.5)
	hud.apply({today_dot = true})
	var dot := hud._today_dot.get_global_rect()
	assert_vector(dot.size).is_equal(Vector2(8, 8))
	assert_float(dot.end.x - today.end.x).is_equal_approx(2.0, 0.01)
	assert_float(today.position.y - dot.position.y).is_equal_approx(2.0, 0.01)

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
	var pills := p.find_children("*", "UiShowPill", true, false)
	assert_int(pills.size()).is_equal(2)                  # a done row shows its tick, not Show
	assert_float((pills[0] as UiShowPill).size.y).is_equal(28.0)   # TodayRow main: Show 55 × 28
	assert_float((pills[0] as UiShowPill).size.x).is_equal_approx(55.0, 2.5)
	var picked := []
	p.show_pressed.connect(func(i): picked.append(i))
	(pills[1] as UiShowPill).pressed.emit()
	assert_array(picked).is_equal([1])
	assert_float(p.size.x).is_equal(float(UiTokens.SIZE_TODAY_PANEL_W))

## A row too long for its line breaks at a " · " (不知火舞 on #201, UiKit.break_at_dot): `Catch 2 Pond Crucian` / `Fern Pond`
## beside Show on map, not `Catch 2 Pond Crucian ·` / `Fern Pond`; one that fits is left alone.
func test_today_rows_break_their_two_lines_at_a_dot() -> void:
	var rows := [
		{line = "Catch 2 Pond Crucian · Fern Pond", action = "Show on map"},
		{line = "Pip's First Fish · Common fish 0/1"},
		{line = "Pond Catch · 2/2", action = "Show"},
	]
	var p: UiTodayPanel = _host(UiTodayPanel.new(rows))
	await _settle()
	var texts := _labels(p)
	assert_array(texts).contains(["Catch 2 Pond Crucian\nFern Pond", "Pond Catch · 2/2"])
	var pip: Label = p.find_children("*", "Label", true, false).filter(func(l): return (l as Label).text.begins_with("Pip"))[0]
	var fs := pip.get_theme_font_size(&"font_size")
	var whole := pip.get_theme_font(&"font").get_string_size("Pip's First Fish · Common fish 0/1", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# beside no pill it breaks only if the whole line is wider than the label
	assert_str(pip.text).is_equal("Pip's First Fish\nCommon fish 0/1" if whole > pip.size.x else "Pip's First Fish · Common fish 0/1")

func test_break_at_dot_keeps_the_first_line_inside_the_width() -> void:
	var font := UiKit.font(&"bold")
	var w := font.get_string_size("Pond Catch · Pond Crucian", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	assert_str(UiKit.break_at_dot("Pond Catch · Pond Crucian · 1/2", font, 14, w)).is_equal("Pond Catch · Pond Crucian\n1/2")
	assert_str(UiKit.break_at_dot("Pond Catch · Pond Crucian · 1/2", font, 14, w - 1.0)).is_equal("Pond Catch\nPond Crucian · 1/2")
	assert_str(UiKit.break_at_dot("Short", font, 14, 10.0)).is_equal("Short")          # no dot: the label wraps by words
	assert_str(UiKit.break_at_dot("A · B", font, 14, 1000.0)).is_equal("A · B")        # fits

# ---------------------------------------------------------------- Energy card / panel

func _facts(home := true) -> Dictionary:
	return {have = 1, max = 200, regen = "+1 in 2:41", zero = false, fact = "Sow 1 plot needs 2 Energy · you have 1",
		wait = "Wait · Full in 13h 20m", tiles = [
			{label = "Eat", fact = "3 dishes in bag", guide = "Open bag", go = "bag", on = true},
			{label = "Cook", fact = "At home" if not home else "4 fish in creel", guide = "Show kitchen", go = "stove", on = home},
			{label = "Tea", fact = "0/3 today · 40 coins", guide = "Show on map", go = "outpost:tea", on = true},
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
	assert_array(gone).is_equal(["bag", "outpost:tea"])   # Cook / Rest are At home away from home; Tea is on the map
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

## TUT-3-03B (1410:104474): next to Show on map a long sentence wraps to two lines and the row grows; only a third
## line would be cut; the row grows when the text needs it. A short row keeps the 40 px main height.
func test_today_row_wraps_to_two_lines_beside_a_wide_pill() -> void:
	var p: UiTodayPanel = _host(UiTodayPanel.new([
		{line = "Catch 2 Pond Crucian · Reed Pond", action = "Show on map"},
		{line = "Cook it: Grilled Crucian", action = "Show"},
	]))
	await _settle()
	var lines := p.find_children("*", "Label", true, false).filter(func(l): return (l as Label).text.begins_with("Catch") or (l as Label).text.begins_with("Cook it"))
	var long: Label = lines[0]
	var short: Label = lines[1]
	assert_int(long.get_line_count()).is_equal(2)
	assert_int(long.get_visible_line_count()).is_equal(2)
	assert_int(short.get_line_count()).is_equal(1)
	assert_float((short.get_parent().get_parent() as Control).size.y).is_equal(float(UiTokens.SIZE_TODAY_ROW_H))
	# both lines fit: the row is at least as tall as the two-line text (two BodyXB14 lines fit the 40 px row)
	assert_float((long.get_parent().get_parent() as Control).size.y).is_greater_equal(long.size.y)
	assert_float(long.size.y).is_greater(short.size.y)
