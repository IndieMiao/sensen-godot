extends GdUnitTestSuite
## The Cookbook detail card (Compact/Kitchen/Recipe, SGODOT-226) lays out by what it says: the might-have line
## (int6 C41) and a grey button too long for the corner (int6 C3, 不知火舞 on 226: text never shrinks or wraps; the
## button takes a full row of its own under the facts).

const KL := preload("res://tests/p0/test_p0_kitchen_logic.gd")

func _drawer() -> P0KitchenDrawer:
	var v: Dictionary = auto_free(KL.new())._s5_view()
	var pages: Array = v.cooking.cookbook
	pages[1].merge({"families": ["W"], "maybe": true}, true)
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var d := P0KitchenDrawer.new(v)
	host.add_child(d)
	return d

func _settle() -> void:
	for i in 3: await get_tree().process_frame

func _card(d: P0KitchenDrawer) -> Rect2: return (d.get("_recipe") as Control).get_global_rect()

func test_a_grey_button_keeps_to_the_card_and_takes_a_row_when_too_long() -> void:
	var d := _drawer()
	d.view.names["crop_lettuce"] = "Moonlit Butterhead Lettuce"   # a gap too long for the corner
	d.refresh()
	await _settle()
	var b: UiCommandButton = d.get("_recipe_button")
	var effect: Label = d.get("_recipe_effect")
	d.select_page("dish_grilled_crucian")   # Cook: the corner, 90 wide, right edge at 328
	await _settle()
	var short_h := _card(d).size.y
	assert_float(b.size.x).is_equal(90.0)
	assert_float(b.position.x + b.size.x).is_equal(328.0)
	# Cooking Lv4 · 3rd slot (C3 cut it to "Cooking Lv4 · 3r"): right-aligned, as wide as its text, clear of the facts.
	d.select_page("dish_fisher_stew")
	await _settle()
	assert_str(b.text).is_equal("Cooking Lv4 · 3rd slot")
	assert_float(b.size.x).is_greater_equal(b.get_combined_minimum_size().x)
	assert_float(b.position.x + b.size.x).is_equal(328.0)
	assert_bool(_card(d).encloses(b.get_global_rect())).override_failure_message("%s in %s" % [b.get_global_rect(), _card(d)]).is_true()
	assert_float(b.position.x).is_greater(57.4 + P0KitchenDrawer._text_width(d.get("_recipe_state")))
	assert_float(_card(d).size.y).is_equal(short_h)
	# A gap that would run into the facts: a full row of its own under them, the whole text, inside the card.
	d.select_page("dish_radish_salad")
	await _settle()
	assert_str(b.text).is_equal("Need Moonlit Butterhead Lettuce ×1")
	assert_float(b.size.x).is_equal(320.0)   # 8 in from each side
	assert_float(b.size.x).is_greater_equal(b.get_combined_minimum_size().x)
	assert_float(b.position.y).is_greater_equal(effect.position.y + effect.size.y)
	assert_float(_card(d).size.y).is_greater(short_h)
	assert_bool(_card(d).encloses(b.get_global_rect())).override_failure_message("%s in %s" % [b.get_global_rect(), _card(d)]).is_true()
	d.select_page("dish_grilled_crucian")   # back to Cook: the card shrinks again
	await _settle()
	assert_float(_card(d).size.y).is_equal(short_h)

func test_the_might_have_line_sits_under_the_facts() -> void:
	var d := _drawer()
	await _settle()
	d.select_page("dish_grilled_fish")
	await _settle()
	var maybe: Label = d.get("_recipe_maybe")
	var state: Label = d.get("_recipe_state")
	var effect: Label = d.get("_recipe_effect")
	assert_bool(maybe.is_visible_in_tree()).is_true()
	assert_str(maybe.text).is_equal("You might have what it takes")
	assert_object(maybe.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_NEW_INK)
	assert_float(maybe.position.y).is_greater_equal(state.position.y + 13.0)   # under the 13 px fact band
	assert_float(effect.position.y).is_greater_equal(maybe.position.y + maybe.get_combined_minimum_size().y)
	# Try in Experiment › moves down with the effect line: its centred text stays in the card, under the new line.
	var nav: Control = d.get("_recipe_nav")
	var mid := nav.get_global_rect().get_center().y
	assert_float(mid).is_less(_card(d).end.y - 8.0)
	assert_float(mid - 8.0).is_greater_equal(maybe.get_global_rect().position.y + maybe.get_combined_minimum_size().y)
	d.select_page("dish_veggie_plate")   # clued, no maybe
	await _settle()
	assert_bool(maybe.is_visible_in_tree()).is_false()

func test_the_first_page_keeps_cook_in_the_corner_once_the_drawer_has_its_theme() -> void:
	# 256 ⑨: the card is laid out in _init before the theme reaches it; measured in the default font size, the long fact
	# line of a page not cooked yet (Common · First cook +10 XP) sent Cook to a row of its own until another page was
	# picked. It is laid out again once the theme is there.
	var v: Dictionary = auto_free(KL.new())._s5_view()
	var pages: Array = v.cooking.cookbook
	pages[0].can_cook = false
	pages[2].can_cook = true   # Radish Salad, known, never cooked: first in the grid, the page the drawer opens on
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var d := P0KitchenDrawer.new(v)
	host.add_child(d)
	await _settle()
	assert_str(d.selected_page).is_equal("dish_radish_salad")
	assert_str((d.get("_recipe_state") as Label).text).is_equal("Common · First cook +10 XP")
	var b: UiCommandButton = d.get("_recipe_button")
	assert_float(b.size.x).is_equal(90.0)
	assert_float(b.position.x + b.size.x).is_equal(328.0)

func test_the_effect_line_runs_up_to_the_button_and_drops_the_style_then_the_time() -> void:
	# 不知火舞 (256 follow-up): `+N Energy · T s · Style` runs up to 8 px short of the corner button (about 172 beside
	# Cook, not the text box's 142): the longest real line, +70 Energy · 30 s · Dessert (153), fits whole. Beside a wide
	# grey button the style goes first, then the time; the energy stays. A button on a row of its own gives it the card.
	var d := _drawer()
	await _settle()
	var effect: Label = d.get("_recipe_effect")
	var b: UiCommandButton = d.get("_recipe_button")
	d.select_page("dish_grilled_crucian")   # Cook in the corner
	await _settle()
	d.set("_effect_parts", ["+70 Energy", "30 s", "Dessert"])
	d.call("_layout_recipe")
	assert_str(effect.text).is_equal("+70 Energy · 30 s · Dessert")
	assert_float(b.position.x + b.size.x).is_equal(328.0)
	assert_float(effect.position.x + effect.size.x).is_less_equal(b.position.x - 8.0 + 0.01)
	d.call("_fit_effect", 120.0)   # beside a wide grey button
	assert_str(effect.text).is_equal("+70 Energy · 30 s")
	d.call("_fit_effect", 70.0)
	assert_str(effect.text).is_equal("+70 Energy")

## SGODOT-282 (不知火舞 540d59df): a Legendary page shows the empty Buff slot as a capsule at the end of the state line,
## inside the card and clear of the button; other pages do not.
func test_a_legendary_page_shows_the_buff_capsule_on_the_state_line() -> void:
	var d := _drawer()
	d.view.cooking.tiers["4"] = {"energy": 70, "ms": 60000, "first_xp": 80}
	d.view.cooking.cookbook.append({"id": "dish_legend_sashimi", "name": "Legend Sashimi", "rarity": 4, "slots": 1, "state": "tasted",
		"known": true, "in": ["W4"], "cooked": false, "can_cook": false, "lock": null, "buff": "buff_bite_window"})
	d.refresh()
	await _settle()
	var cap: Control = d.get("_recipe_buff")
	var state: Label = d.get("_recipe_state")
	var b: UiCommandButton = d.get("_recipe_button")
	d.select_page("dish_grilled_crucian")
	await _settle()
	assert_bool(cap.visible).is_false()
	d.select_page("dish_legend_sashimi")
	await _settle()
	assert_bool(cap.visible).is_true()
	assert_str((cap.find_child("buff_text", true, false) as Label).text).is_equal("Buff · coming later")
	assert_int(cap.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(_card(d).encloses(cap.get_global_rect())).is_true()
	# The state line is never cut to make room: the capsule follows it on the line, or takes a row under it.
	assert_float(state.size.x).is_greater_equal(P0KitchenDrawer._text_width(state) - 0.5)
	var same_line := absf(cap.get_global_rect().get_center().y - state.get_global_rect().get_center().y) < 2.0
	if same_line: assert_float(cap.position.x).is_greater_equal(state.position.x + state.size.x)
	else: assert_float(cap.position.y).is_greater_equal(state.position.y + state.size.y - 1.0)
	var effect: Label = d.get("_recipe_effect")
	assert_bool(cap.get_global_rect().intersects(effect.get_global_rect())).is_false()
	var nav: Control = d.get("_recipe_nav")
	for other in [b, nav]:
		if (other as Control).visible: assert_bool(cap.get_global_rect().intersects((other as Control).get_global_rect())).is_false()
