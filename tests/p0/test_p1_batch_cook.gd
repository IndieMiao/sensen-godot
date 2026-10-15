extends GdUnitTestSuite
## Batch Cook (Cooking Lv8, q(200)) and the Big Pot as a stove state (Homestead Lv6, q(201)), SGODOT-282: the recipe
## card's numbers — where a batch's pots go, how many the stock and the stoves allow, the servings, the slots' ×N, the
## kept items' toast — worked out from the view (batch.room, a page's picks and saved) as the server will cook them.

const NB := P0KitchenLogic.NBSP

func _view(stoves: Array = [null, null, null], extra := {}) -> Dictionary:
	var v := {
		"skills": {"cooking": {"level": 8}},
		"bag": {"capacity": 25, "slots": [{"id": "fish_crucian", "qty": 5}, {"id": "fish_carp", "qty": 1}]},
		"names": {"fish_crucian": "Pond Crucian", "fish_carp": "Common Carp", "dish_grilled_fish": "Grilled Fish",
			"dish_herb_grilled_fish": "Herb Grilled Fish", "dish_grilled_crucian": "Grilled Crucian", "fish_salmon": "Atlantic Salmon", "crop_herb": "Wild Herb"},
		"items": {"fish_crucian": {"name": "Pond Crucian", "kind": "fish", "family": "W", "rarity": 1, "cook": true},
			"fish_carp": {"name": "Common Carp", "kind": "fish", "family": "W", "rarity": 1, "cook": true}},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
		"cooking": {"slots": 3, "stoves": stoves, "big_pot": true, "batch": {"room": 6},
			"conveniences": ["queue_two", "batch_cook"], "tiers": {"1": {"energy": 20, "ms": 5000}}},
	}
	v.merge(extra, true)
	return v

func _crucian(n := 5) -> Dictionary:
	var picks: Array = []
	for i in n: picks.append(["fish_crucian"])
	return {"id": "dish_grilled_crucian", "name": "Grilled Crucian", "known": true, "rarity": 1, "in": ["fish_crucian"],
		"can_cook": true, "picks": picks, "saved": {}, "today": 0}

func test_a_batch_fills_the_current_stove_then_the_empty_ones_then_the_queues() -> void:
	var spots := P0KitchenLogic.batch_spots(_view(), 1, 6)
	assert_array(spots.map(func(s): return [s.stove, s.queued])).is_equal([[1, false], [0, false], [2, false], [0, true], [1, true], [2, true]])
	var busy := _view([{"ms": 5000, "ready_in": 3000, "dish": "dish_x"}, null, null])
	assert_array(P0KitchenLogic.batch_spots(busy, 0, 9).map(func(s): return [s.stove, s.queued])).is_equal([[1, false], [2, false], [0, true], [1, true], [2, true]])
	var one := _view([null])   # Homestead Lv1–3: a pot and its queue
	assert_int(P0KitchenLogic.batch_spots(one, 0, 9).size()).is_equal(2)

func test_the_stepper_stops_at_the_ingredients_or_the_room_and_says_which() -> void:
	var plan := P0KitchenLogic.batch_plan(_view(), _crucian(3), 1, 0, [])
	assert_that([plan.max, plan.limit]).is_equal([3, "ingredients"])
	assert_str(P0KitchenLogic.batch_limit_toast(plan)).is_equal("Ingredients for 3" + NB + "pots")
	var one := _view([null])
	plan = P0KitchenLogic.batch_plan(one, _crucian(5), 1, 0, [])
	assert_that([plan.max, plan.limit]).is_equal([2, "room"])
	assert_str(P0KitchenLogic.batch_limit_toast(plan)).is_equal("Room for 2" + NB + "pots")
	plan = P0KitchenLogic.batch_plan(one, _crucian(2), 1, 0, [])   # both stop at 2: the ingredients are said first
	assert_str(plan.limit).is_equal("ingredients")

func test_a_big_pot_stove_takes_two_servings_while_two_are_left() -> void:
	var plan := P0KitchenLogic.batch_plan(_view(), _crucian(5), 3, 0, [0, 2])
	assert_array(plan.pots.map(func(p): return [p.stove, p.servings])).is_equal([[0, 2], [1, 1], [2, 2]])
	assert_int(plan.servings).is_equal(5)
	assert_str(P0KitchenLogic.servings_tag(_view(), _crucian(5), plan)).is_equal("5" + NB + "servings")
	var four := P0KitchenLogic.batch_plan(_view(), _crucian(4), 3, 0, [0, 2])
	assert_array(four.pots.map(func(p): return p.servings)).is_equal([2, 1, 1])
	assert_bool(P0KitchenLogic.short_of_two(_view(), _crucian(4), four)).is_true()
	var single := P0KitchenLogic.batch_plan(_view(), _crucian(1), 1, 0, [0])
	assert_str(P0KitchenLogic.servings_tag(_view(), _crucian(1), single)).is_equal("1" + NB + "serving")
	var plain := P0KitchenLogic.batch_plan(_view(), _crucian(5), 2, 0, [])
	assert_str(P0KitchenLogic.servings_tag(_view(), _crucian(5), plain)).is_equal("")   # no Big Pot in the batch
	var legend := _crucian(4)
	legend.rarity = 4
	assert_array(P0KitchenLogic.batch_plan(_view(), legend, 2, 0, [0]).pots.map(func(p): return p.servings)).is_equal([1, 1])

func test_the_pot_card_slots_count_the_batch_and_name_a_mixed_tag_slot() -> void:
	var page := {"id": "dish_grilled_fish", "known": true, "rarity": 1, "in": ["W1"],
		"picks": [["fish_crucian"], ["fish_crucian"], ["fish_carp"]], "saved": {"fish_crucian": "dish_grilled_crucian"}}
	var slots := P0KitchenLogic.batch_slots(_view(), page, page.picks)
	assert_that([slots[0].item, slots[0].total, slots[0].detail, slots[0].saved]).is_equal(["fish_crucian", 3, "Pond Crucian ×2 · Common Carp ×1", true])
	assert_str(P0KitchenLogic.saved_toast(_view(), page, page.picks)).is_equal("Uses Pond Crucian saved for Grilled Crucian")
	page.saved = {"fish_crucian": "request", "fish_carp": "dish_herb_grilled_fish"}
	assert_str(P0KitchenLogic.saved_toast(_view(), page, page.picks)).is_equal("Uses Pond Crucian saved for a request · +1 more")
	assert_str(P0KitchenLogic.saved_toast(_view(), page, [])).is_equal("")

func test_the_stepper_says_the_2nd_and_3rd_pot_of_a_page_today() -> void:
	var page := _crucian(5)
	page.today = 1
	assert_int(P0KitchenLogic.page_pot_today(_view(), page, 1)).is_equal(2)
	var cooking := _view([{"ms": 5000, "ready_in": 3000, "dish": "dish_grilled_crucian"}, null, null])
	assert_int(P0KitchenLogic.page_pot_today(cooking, page, 1)).is_equal(3)
	assert_that([P0KitchenLogic.nth_today_toast(2), P0KitchenLogic.nth_today_toast(3), P0KitchenLogic.nth_today_toast(4)]) \
		.is_equal(["2nd pot today · half XP", "3rd pot today · no XP", ""])

func test_the_big_pot_key_shows_greys_and_hides() -> void:
	var v := _view()
	assert_that(P0KitchenLogic.big_pot_key(v, 0, true, false, false)).is_equal({shown = true, on = true, enabled = true, toast = ""})
	var busy := _view([{"ms": 5000, "ready_in": 3000, "dish": "d"}, null, null])
	assert_str(str(P0KitchenLogic.big_pot_key(busy, 0, true, false, false).toast)).is_equal("Swap pots when the stove is empty")
	assert_str(str(P0KitchenLogic.big_pot_key(v, 0, false, true, false).toast)).is_equal("Swap pots when the stove is empty")
	assert_that(P0KitchenLogic.big_pot_key(v, 0, false, false, true)).is_equal({shown = true, on = false, enabled = false, toast = "Legendary dishes make 1" + NB + "serving"})
	assert_bool(P0KitchenLogic.big_pot_key(v, 0, false, false, false, false).shown).is_false()   # only `Need …`
	var early := _view()
	early.cooking.big_pot = false
	assert_bool(P0KitchenLogic.big_pot_key(early, 0, false, false, false).shown).is_false()

func test_the_confirm_line_and_the_command() -> void:
	var page := {"id": "dish_herb_salmon", "known": true, "rarity": 3, "in": ["fish_salmon", "crop_herb"],
		"picks": [["fish_salmon", "crop_herb"], ["fish_salmon", "crop_herb"], ["fish_salmon", "crop_herb"], ["fish_salmon", "crop_herb"]]}
	var plan := P0KitchenLogic.batch_plan(_view(), page, 3, 0, [])
	assert_str(P0KitchenLogic.batch_confirm_line(_view(), plan)).is_equal("Uses Atlantic Salmon ×3 and Wild Herb ×3 for 3" + NB + "pots.")
	plan = P0KitchenLogic.batch_plan(_view(), page, 3, 0, [0])
	assert_str(P0KitchenLogic.batch_confirm_line(_view(), plan)).is_equal("Uses Atlantic Salmon ×4 and Wild Herb ×4 for 3" + NB + "pots · 4" + NB + "servings.")
	assert_that(P0KitchenLogic.card_command(page, 1, 2, [2], true)).is_equal({"type": "cook", "recipe": "dish_herb_salmon", "stove": 2, "double": true})
	assert_that(P0KitchenLogic.card_command(page, 1, 0, [], false)).is_equal({"type": "cook", "recipe": "dish_herb_salmon"})
	assert_that(P0KitchenLogic.card_command(page, 3, 1, [0, 2], true)).is_equal({"type": "batch_cook", "recipe": "dish_herb_salmon", "pots": 3, "stove": 1, "big": [0, 2]})

func test_experiment_on_a_big_pot_stove_says_its_servings() -> void:
	var v := _view()
	v.cooking.cookbook = [{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "known": true, "rarity": 1, "in": ["fish_crucian"]}]
	assert_str(P0KitchenLogic.experiment_servings(v, ["fish_crucian"])).is_equal("2" + NB + "servings")
	assert_str(P0KitchenLogic.experiment_servings(v, ["fish_carp"])).is_equal("")   # not a known page

func test_the_big_pot_stoves_are_kept_per_player_on_this_device() -> void:
	var player := "test-big-pot-%d" % Time.get_ticks_usec()
	assert_array(P0KitchenLogic.load_big_stoves(player)).is_empty()
	P0KitchenLogic.save_big_stoves(player, [2, 0])
	assert_array(P0KitchenLogic.load_big_stoves(player)).is_equal([0, 2])
	assert_array(P0KitchenLogic.load_big_stoves(player + "-other")).is_empty()
	P0KitchenLogic.save_big_stoves(player, [])
