extends GdUnitTestSuite
## RewardMoment 1179:82271 / QualityBadge 1178:82154 (SGODOT-226; the catch card and banners of SGODOT-233 use the
## same component): empty fields hide their parts, tones colour the event, LOCK-10 reasons, pills and long names.

func _card(fields: Dictionary) -> UiRewardMoment:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var r := UiRewardMoment.new()
	r.show_fields(fields)
	host.add_child(r)
	return r

func _settle() -> void:
	for i in 2: await get_tree().process_frame

func _texts(c: Control) -> Array:
	return c.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree()).map(func(l): return (l as Label).text)

func _buttons(c: Control) -> Array:
	return c.find_children("*", "UiCommandButton", true, false).filter(func(b): return b.is_visible_in_tree())

func test_a_dish_card_shows_every_part_it_is_given() -> void:
	var r := _card({event = "New recipe!", icon = load("res://assets/p0/icons/dish_herb_grilled_fish.svg"), item_name = "Herb Grilled Fish",
		rarity = 2, rarity_word = "Fine", quality = 1, strip = "First cooked · +20 Cooking XP · Cookbook 2/48",
		primary = "Eat · +45 Energy", secondary = "Keep", note = "Gift later from your bag"})
	await _settle()
	var t := _texts(r)
	for s in ["New recipe!", "Herb Grilled Fish", "Fine", "★ Good", "First cooked · +20\u00a0Cooking XP\nCookbook 2/48", "Gift later from your bag"]:
		assert_bool(t.has(s)).override_failure_message("missing %s in %s" % [s, t]).is_true()
	assert_array(_buttons(r).map(func(b): return b.text)).contains_exactly(["Eat · +45 Energy", "Keep"])
	assert_float(r.size.x).is_equal(UiRewardMoment.WIDTH)

func test_a_catch_card_without_actions_hides_buttons_note_and_strip() -> void:
	var r := _card({event = "Caught!", item_name = "Pond Crucian", rarity = 1, rarity_word = "Common"})
	await _settle()
	assert_array(_buttons(r)).is_empty()
	assert_array(_texts(r)).contains_exactly(["Caught!", "Pond Crucian", "Common"])   # Plain: no quality badge

func test_tones_colour_the_event_line() -> void:
	var colours := {UiRewardMoment.Tone.REWARD: UiTokens.COLOR_PRIMARY, UiRewardMoment.Tone.NEUTRAL: UiTokens.COLOR_SECONDARY,
		UiRewardMoment.Tone.MILESTONE: UiTokens.COLOR_TEXT}
	for tone in colours:
		var r := _card({tone = tone, event = "Mystery Dish", item_name = "Hmm… not a dish"})
		await _settle()
		var ev := r.find_children("*", "Label", true, false).filter(func(l): return l.text == "Mystery Dish")[0] as Label
		assert_that(ev.get_theme_color(&"font_color")).is_equal(colours[tone])

func test_an_unavailable_primary_shows_its_reason_and_emits_it() -> void:
	var r := _card({event = "Dish ready", item_name = "Herb Grilled Fish", primary = "Eat · +45 Energy", primary_reason = "Energy full", secondary = "Keep"})
	await _settle()
	var said := []
	r.unavailable_pressed.connect(func(reason): said.append(reason))
	r.primary_pressed.connect(func(): said.append("ate"))
	var eat: UiCommandButton = _buttons(r)[0]
	assert_str(eat.text).is_equal("Energy full")
	eat.pressed.emit()
	assert_array(said).contains_exactly(["Energy full"])

func test_pills_passed_again_are_kept_and_dropped_ones_freed() -> void:
	var r := _card({event = "Caught!", item_name = "Pond Crucian"})
	var a := PanelContainer.new()
	var b := PanelContainer.new()
	r.rewards = [a, b]
	r.rewards = [a]
	await _settle()
	assert_bool(is_instance_valid(a) and a.is_inside_tree()).is_true()
	assert_bool(is_instance_valid(b)).is_false()
	r.rewards = []
	await _settle()
	assert_bool(is_instance_valid(a)).is_false()

func test_a_long_name_is_cut_instead_of_widening_the_card() -> void:
	var r := _card({event = "Dish ready", icon = load("res://assets/p0/icons/dish_herb_grilled_fish.svg"),
		item_name = "Extraordinarily Slow-Braised Riverside Grass Carp", rarity = 3, rarity_word = "Rare"})
	await _settle()
	assert_float(r.size.x).is_equal(UiRewardMoment.WIDTH)
	var short := _card({event = "Caught!", item_name = "Bass"})
	await _settle()
	var name := short.find_children("*", "Label", true, false).filter(func(l): return l.text == "Bass")[0] as Label
	assert_float(name.size.x).is_less(UiRewardMoment.NAME_MAX_W)   # short names keep their own width (centred)

func test_the_quality_badge_hides_for_plain() -> void:
	var host := Control.new()
	host.theme = UiKit.theme()
	add_child(auto_free(host))
	var g := UiQualityBadge.new(0)
	host.add_child(g)
	assert_bool(g.visible).is_false()
	g.quality = 2
	assert_bool(g.visible).is_true()
	assert_str((g.get_child(0) as Label).text).is_equal("★★ Perfect")

func test_a_freely_placed_card_shrinks_to_its_content() -> void:
	# The kitchen's way: the card goes into a full-screen holder before it is in the tree, themed on itself.
	var host := Control.new()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	var r := UiRewardMoment.new()
	r.theme = UiKit.theme()
	r.show_fields({event = "Dish ready", item_name = "Herb Grilled Fish", rarity = 2, rarity_word = "Fine",
		strip = "First cooked · +20 Cooking XP · Cookbook 2/48", primary = "Eat · +45 Energy", secondary = "Keep", note = "Gift later from your bag"})
	wrap.add_child(r)
	host.add_child(wrap)
	for i in 4: await get_tree().process_frame
	print("RM_SIZE ", r.size, " min ", r.get_combined_minimum_size())
	assert_float(r.size.y).is_equal_approx(r.get_combined_minimum_size().y, 0.5)
	assert_float(r.size.y).is_less(400.0)

func test_a_fact_line_without_rarity_shows_under_the_name_without_a_dot() -> void:
	# The No dish card (int6 C14): "Ingredients back" on the name line, "9 left today" on its own line, whole.
	var r := _card({tone = UiRewardMoment.Tone.NEUTRAL, event = "No dish this time", item_name = "Ingredients back",
		rarity_word = "9 left today", primary = "OK"})
	await _settle()
	assert_array(_texts(r)).contains(["Ingredients back", "9 left today"])
	assert_bool(r._dot.visible).is_false()
	var rarity: Label = r.find_children("*", "Label", true, false).filter(func(l): return (l as Label).text == "9 left today")[0]
	assert_float(rarity.size.x).is_greater_equal(rarity.get_minimum_size().x)   # not cut

## The one-time strip breaks between its rewards, never inside one (不知火舞 on 289 73b6029e: `+10` / `XP` split across
## lines): whole rewards a line, no line ending in « ·», a number held to its unit; the strip property keeps its text.
func test_the_strip_breaks_between_its_rewards() -> void:
	var r := _card({event = "In your trap!", item_name = "River Perch", rarity = 2, rarity_word = "Fine",
		strip = "First catch! +30 XP · New city! +10 XP", strip_icon = P0Logic.icon("star")})
	await _settle()
	var shown: String = (r.get("_strip_text") as Label).text
	assert_str(shown).is_equal("First catch! +30 XP\nNew city! +10 XP")
	assert_str(r.strip).is_equal("First catch! +30 XP · New city! +10 XP")
	var short := _card({event = "Caught!", item_name = "Pond Crucian", strip = "First catch! +15 XP", strip_icon = P0Logic.icon("star")})
	await _settle()
	assert_str((short.get("_strip_text") as Label).text).is_equal("First catch! +15 XP")
	var font := (r.get("_strip_text") as Label).get_theme_font(&"font")
	for w in [60.0, 140.0, 400.0]:
		var lines := UiRewardMoment.strip_lines("First cooked · +20 Cooking XP · Cookbook 2/48", font, 12, w).split("\n")
		for l in lines: assert_bool(l.ends_with("·") or l.begins_with("·")).is_false()
		assert_str(" · ".join(lines)).is_equal("First cooked · +20 Cooking XP · Cookbook 2/48")
	assert_str(UiRewardMoment.strip_lines("a · b", null, 12, 100.0)).is_equal("a · b")
