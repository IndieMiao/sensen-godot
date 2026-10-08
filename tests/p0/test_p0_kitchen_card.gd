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
