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

## row 99 (S1 2731:153980, grid 2733:158489; 不知火舞 on 286 20438543): one grid for every page — 336 × 110; the medallion
## 44 at x 12; name and state at x 68; `+N Energy` right-aligned to x 324; the divider 1 × 34 at x 248; row 2 (touch 44
## at y 59): Cook at x 256–324, a gap right-aligned there as wide as it says.
func test_the_card_keeps_the_row_99_grid() -> void:
	var d := _drawer()
	await _settle()
	d.select_page("dish_grilled_crucian")
	await _settle()
	var at := func(n: String) -> Rect2: return Rect2((d.get(n) as Control).position, (d.get(n) as Control).size)
	assert_vector(_card(d).size).is_equal(Vector2(336, 110))
	assert_that(at.call("_medallion")).is_equal(Rect2(12, 12, 44, 44))
	assert_that([at.call("_recipe_title").position.x, at.call("_recipe_state").position.x]).is_equal([68.0, 68.0])
	assert_float(at.call("_recipe_effect").end.x).is_equal(324.0)
	assert_int((d.get("_recipe_effect") as Label).horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_RIGHT)
	assert_str((d.get("_recipe_effect") as Label).text).is_equal("+20 Energy")   # the time is on the pot card now
	assert_that(at.call("_divider")).is_equal(Rect2(248, 17, 1, 34))
	var b: UiCommandButton = d.get("_recipe_button")
	assert_that(Rect2(b.position, b.size)).is_equal(Rect2(256, 59, 68, 44))
	assert_str(b.text).is_equal("Cook")

## A gap keeps Cook's corner: right-aligned at x 324, as wide as it says, inside the card; the card stays 110.
func test_a_gap_is_right_aligned_where_cook_is() -> void:
	var d := _drawer()
	d.view.names["crop_lettuce"] = "Moonlit Butterhead Lettuce"
	d.refresh()
	await _settle()
	var b: UiCommandButton = d.get("_recipe_button")
	d.select_page("dish_fisher_stew")   # the 3rd slot locked
	await _settle()
	assert_str(b.text).is_equal("Cooking Lv4 · 3rd slot")
	assert_float(b.position.x + b.size.x).is_equal(324.0)
	assert_float(b.size.x).is_greater_equal(b.get_combined_minimum_size().x)
	d.select_page("dish_radish_salad")
	await _settle()
	assert_str(b.text).is_equal("Need Moonlit Butterhead Lettuce ×1")
	assert_float(b.position.x + b.size.x).is_equal(324.0)
	assert_float(b.position.x).is_greater_equal(12.0)
	assert_float(_card(d).size.y).is_equal(110.0)
	assert_bool(_card(d).encloses(b.get_global_rect())).override_failure_message("%s in %s" % [b.get_global_rect(), _card(d)]).is_true()

## An unknown page on the same grid (S14 2747:159713 / S14b): a light grey medallion, `Try in Experiment ›` right-aligned
## at x 324; `You might have what it takes` is the extra line between the rows (x 68, 16 high, 4 above and below), the
## card 130 and row 2 down 20.
func test_an_unknown_page_and_its_might_have_line() -> void:
	var d := _drawer()
	await _settle()
	d.select_page("dish_grilled_fish")
	await _settle()
	var maybe: Label = d.get("_recipe_maybe")
	var nav: Control = d.get("_recipe_nav")
	assert_bool(maybe.is_visible_in_tree()).is_true()
	assert_str(maybe.text).is_equal("You might have what it takes")
	assert_object(maybe.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_NEW_INK)
	assert_float(maybe.position.x).is_equal(68.0)
	assert_float(maybe.position.y + maybe.get_combined_minimum_size().y * 0.5).is_equal_approx(68.0, 0.6)   # the 60–76 line's middle
	assert_float(_card(d).size.y).is_equal(130.0)
	assert_that([nav.position.x + nav.size.x, nav.position.y]).is_equal([324.0, 79.0])
	assert_object(((d.get("_medallion") as Panel).get_theme_stylebox(&"panel") as UiStyleBox).bg_color).is_equal(Color("E9E7E0"))
	d.select_page("dish_veggie_plate")   # clued, no maybe: back to 110
	await _settle()
	assert_bool(maybe.is_visible_in_tree()).is_false()
	assert_float(_card(d).size.y).is_equal(110.0)

func test_the_first_page_keeps_cook_in_the_corner_once_the_drawer_has_its_theme() -> void:
	# 256 ⑨: the card is laid out in _init before the theme reaches it; it is laid out again once the theme is there.
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
	assert_that(Rect2(b.position, b.size)).is_equal(Rect2(256, 59, 68, 44))

## SGODOT-282 (不知火舞 540d59df; S13 2747:159481): a Legendary page's `Buff · coming later` capsule is the extra line
## between the rows — x 68, inside the card, the card 130; other pages have none.
func test_a_legendary_page_shows_the_buff_capsule_on_the_extra_line() -> void:
	var d := _drawer()
	d.view.cooking.tiers["4"] = {"energy": 70, "ms": 60000, "first_xp": 80}
	d.view.cooking.cookbook.append({"id": "dish_legend_sashimi", "name": "Legend Sashimi", "rarity": 4, "slots": 1, "state": "tasted",
		"known": true, "in": ["W4"], "cooked": false, "can_cook": false, "lock": null, "buff": "buff_bite_window"})
	d.refresh()
	await _settle()
	var cap: Control = d.get("_recipe_buff")
	d.select_page("dish_grilled_crucian")
	await _settle()
	assert_bool(cap.visible).is_false()
	d.select_page("dish_legend_sashimi")
	await _settle()
	assert_bool(cap.visible).is_true()
	assert_str((cap.find_child("buff_text", true, false) as Label).text).is_equal("Buff · coming later")
	assert_int(cap.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_float(cap.position.x).is_equal(68.0)
	assert_float(cap.position.y + cap.size.y * 0.5).is_equal_approx(68.0, 0.6)   # the 60–76 line's middle
	assert_float(_card(d).size.y).is_equal(130.0)
	assert_bool(_card(d).encloses(cap.get_global_rect())).is_true()
	var b: UiCommandButton = d.get("_recipe_button")
	assert_float(b.position.y).is_equal(79.0)
	assert_bool(cap.get_global_rect().intersects(b.get_global_rect())).is_false()

## 不知火舞 02ad95bc ①: stove buttons that crowd (< 44 px apart) go in a row 1 / 2 / 3, 44 apart, centred; with a strip
## open, the buttons before its stove step left of the strip and those after it right of it, all kept on screen.
func test_crowded_stove_buttons_go_in_a_row() -> void:
	var FH := preload("res://scenes/p0/rooms/p0_farmhouse.gd")
	var spots := {"use_stove_1": Vector2(92, 309), "use_stove_2": Vector2(105, 317), "use_stove_3": Vector2(115, 300)}
	var row: Dictionary = FH.stove_row(spots, [0, 1, 2], -1, Rect2(), 360.0)
	assert_float(row.use_stove_1.y).is_equal(300.0)
	assert_float(row.use_stove_2.x - row.use_stove_1.x).is_equal(44.0)
	assert_float(row.use_stove_3.x - row.use_stove_2.x).is_equal(44.0)
	assert_float((row.use_stove_1.x + row.use_stove_3.x) * 0.5).is_equal_approx((92.0 + 105.0 + 115.0) / 3.0, 0.01)
	# 6e798a27 ②: the row keeps 44 from the Spice Rack and Warming Cabinet buttons, moving right as a whole
	var rack := Vector2(35.4, 323.9)
	var cabinet := Vector2(47.4, 356.7)
	var clear: Dictionary = FH.stove_row(spots, [0, 1, 2], -1, Rect2(), 360.0, [rack, cabinet])
	for n in ["use_stove_1", "use_stove_2", "use_stove_3"]:
		for a in [rack, cabinet]: assert_float((clear[n] as Vector2).distance_to(a)).is_greater_equal(43.99)
	assert_float(clear.use_stove_1.x).is_greater(row.use_stove_1.x)
	assert_float(clear.use_stove_2.x - clear.use_stove_1.x).is_equal_approx(44.0, 0.01)
	assert_float(clear.use_stove_3.x - clear.use_stove_2.x).is_equal_approx(44.0, 0.01)
	assert_float(clear.use_stove_1.y).is_equal(300.0)
	var far: Dictionary = FH.stove_row(spots, [0, 1, 2], -1, Rect2(), 360.0, [Vector2(300, 300)])
	assert_vector(far.use_stove_1).is_equal(row.use_stove_1)
	# stove 3's strip open: it stays at its own pot; 1 and 2, in order, centred over the strip, 44 apart, 6 above it
	var s3 := Rect2(98, 284, 210, 32)
	var open: Dictionary = FH.stove_row(spots, [0, 1, 2], 2, s3, 360.0, [rack, cabinet])
	assert_vector(open.use_stove_3).is_equal(spots.use_stove_3)
	assert_float(open.use_stove_1.y).is_equal(284.0 - 6.0 - 14.0)
	assert_float(open.use_stove_2.y).is_equal(284.0 - 6.0 - 14.0)
	assert_float(open.use_stove_2.x - open.use_stove_1.x).is_equal_approx(44.0, 0.01)
	assert_float((open.use_stove_1.x + open.use_stove_2.x) * 0.5).is_equal_approx(s3.get_center().x, 0.01)
	# stove 1 open: 2 and 3 above it the same way
	var s1 := Rect2(70, 293, 180, 32)
	var one: Dictionary = FH.stove_row(spots, [0, 1, 2], 0, s1, 360.0)
	assert_vector(one.use_stove_1).is_equal(spots.use_stove_1)
	assert_float(one.use_stove_3.x - one.use_stove_2.x).is_equal_approx(44.0, 0.01)
	assert_float((one.use_stove_2.x + one.use_stove_3.x) * 0.5).is_equal_approx(s1.get_center().x, 0.01)
	# stove 1 open in the Standard Room (282): the Spice Rack's button sits where stove 2's lines up over the strip — the row
	# moves the shorter way (here left) to keep 44 from it, still over the strip
	var two := {"use_stove_1": Vector2(235.3, 374.7), "use_stove_2": Vector2(247.0, 382.2)}
	var shelf := Vector2(209.0, 338.8)
	var strip1 := Rect2(101.3, 358.7, 150, 32)
	var apart: Dictionary = FH.stove_row(two, [0, 1], 0, strip1, 360.0, [shelf])
	assert_float((apart.use_stove_2 as Vector2).distance_to(shelf)).is_greater_equal(43.99)
	assert_float(apart.use_stove_2.x).is_less(strip1.get_center().x)
	assert_bool(strip1.position.x <= apart.use_stove_2.x and apart.use_stove_2.x <= strip1.end.x).is_true()
	assert_vector(apart.use_stove_1).is_equal(two.use_stove_1)
	# the strip's first frame (no rect yet): the open stove still keeps its own spot
	var first: Dictionary = FH.stove_row(spots, [0, 1, 2], 2, Rect2(), 360.0)
	assert_vector(first.use_stove_3).is_equal(spots.use_stove_3)

## 6e798a27 ① (02ad95bc ③): a Ready stove's strip shows the Ready badge in the pot's place, a cooking one the clock;
## empty keeps i-pot.
func test_a_ready_stove_strip_shows_the_ready_badge() -> void:
	var FH := preload("res://scenes/p0/rooms/p0_farmhouse.gd")
	var pot := func(ready_in: float) -> Dictionary: return {"id": 1, "dish": "dish_grilled_crucian", "ready_in": ready_in}
	var v := {"cooking": {"stoves": [pot.call(0.0), pot.call(12000.0), null]}}
	var ready: Dictionary = FH.stove_marker(v, 0)
	assert_str(str(ready.badge)).is_equal("ready")
	assert_bool(bool(ready.strip_badge)).is_true()
	var cooking: Dictionary = FH.stove_marker(v, 1)
	assert_str(str(cooking.badge)).is_equal("countdown")
	assert_bool(bool(cooking.strip_badge)).is_true()   # the clock folded and open (不知火舞 on #231)
	var empty: Dictionary = FH.stove_marker(v, 2)
	assert_bool(empty.has("badge")).is_false()
	assert_str(str(empty.fact)).is_equal("Empty")

## ④: the pot card's corner tag (q(201): `2 servings` on a Big Pot stove) shows in its top right and takes no layout room.
func test_pot_card_tag_sits_in_the_corner() -> void:
	var card := UiPotCard.new()
	card.theme = UiKit.theme()
	add_child(auto_free(card))
	card.set_slots([UiPotSlot.new(UiPotSlot.State.FILLED)])
	card.show_result("Grilled Crucian", 1, "4 s")
	await _settle()
	var before := card.get_combined_minimum_size()
	card.tag = "12" + P0KitchenLogic.NBSP + "servings"   # the longest (q(201) ④)
	await _settle()
	assert_vector(card.get_combined_minimum_size()).is_equal(before)
	var r := card.tag_rect()
	assert_bool(r.has_area()).is_true()
	assert_bool(Rect2(Vector2.ZERO, card.size).encloses(r)).is_true()
	assert_float(r.end.x).is_greater(card.size.x - 20.0)
	assert_float(r.position.y).is_less(10.0)
	card.tag = ""
	assert_bool(card.tag_rect().has_area()).is_false()
