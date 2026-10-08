extends GdUnitTestSuite
## The cooking drawer's facts (SGODOT-226, LOCK-20 v5): heading order q(31), page cells and cards, the gap on the
## button (LOCK-10), Experiment items (In pot / Not for cooking, F-07), slot counts and the preview capsule.

const K := UiItemCell.KitchenState

func _view() -> Dictionary:
	return {
		"skills": {"cooking": {"level": 1, "xp": 160, "floor": 100, "next": 220}},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
		"bag": {"capacity": 25, "free": 20, "slots": [{"id": "fish_crucian", "qty": 1}, {"id": "crop_herb", "qty": 1}, {"id": "fish_crucian", "qty": 1},
			{"id": "fish_koi", "qty": 1}, {"id": "seed_radish", "qty": 5}, {"id": "crop_radish", "qty": 3}]},
		"items": {
			"fish_crucian": {"name": "Pond Crucian", "kind": "fish", "family": "W", "rarity": 1, "cook": true},
			"crop_herb": {"name": "Wild Herb", "kind": "crop", "family": "S", "rarity": 1, "cook": true},
			"crop_radish": {"name": "Radish", "kind": "crop", "family": "F", "rarity": 1, "cook": true},
			"fish_koi": {"name": "Golden Koi", "kind": "fish", "rarity": 3, "cook": false},
			"seed_radish": {"name": "Radish Seeds", "kind": "seed", "cook": false},
		},
		"names": {"fish_crucian": "Pond Crucian", "crop_herb": "Wild Herb", "crop_radish": "Radish", "crop_lettuce": "Lettuce", "fish_perch": "River Perch"},
		"cooking": {"slots": 2, "stove": null,
			"derive": [[1, 2, 3], [2, 3, 3], [3, 3, 4], [4, 4, 4]],
			"tiers": {"1": {"energy": 20, "ms": 5000}, "2": {"energy": 40, "ms": 15000}, "3": {"energy": 70, "ms": 30000}},
			"cookbook": [
				{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "rarity": 1, "in": ["fish_crucian"], "known": true, "cooked": true, "can_cook": true, "slots": 1},
				{"id": "dish_radish_salad", "name": "Radish Salad", "rarity": 1, "in": ["crop_radish", "crop_lettuce"], "known": true, "cooked": false, "can_cook": false, "slots": 2},
				{"id": "dish_perch", "name": "Herb Baked Perch", "rarity": 2, "in": ["fish_perch", "S1"], "known": true, "cooked": true, "can_cook": false, "slots": 2},
				{"id": "dish_unknown_2", "name": null, "rarity": 2, "in": ["?", "?"], "known": false, "slots": 2},
				{"id": "dish_unknown_3", "name": null, "rarity": 3, "in": ["?", "?", "?"], "known": false, "slots": 3},
			]},
	}

func test_heading_reads_stove_level_state_in_that_order() -> void:
	var v := _view()
	assert_dict(P0KitchenLogic.header(v)).is_equal({stove = "Stove 1/1", level = "Cooking Lv1", state = "Empty"})
	v.cooking.stove = {"ready_in": 22000}
	assert_str(P0KitchenLogic.header(v).state).is_equal("Cooking 0:22")
	v.cooking.stove = {"ready_in": 0}
	assert_str(P0KitchenLogic.header(v).state).is_equal("Ready")
	assert_str(P0KitchenLogic.locked_slot_label(v)).is_equal("Lv4 · 60 XP to go")   # 220 − 160
	assert_str(P0KitchenLogic.cookbook_count(v)).is_equal("3/5")

func test_page_cells_follow_the_kitchen_cell_states() -> void:
	var v := _view()
	var pages := P0KitchenLogic.pages(v)
	var can := P0KitchenLogic.page_cell(v, pages[0])
	assert_int(can.kitchen_state).is_equal(K.DEFAULT)
	assert_bool(can.marked).is_true()   # can-cook = green check (WP1b B1-02)
	assert_int(P0KitchenLogic.page_cell(v, pages[1]).kitchen_state).is_equal(K.TASTED)   # known, never cooked
	assert_int(P0KitchenLogic.page_cell(v, pages[3]).kitchen_state).is_equal(K.HIDDEN)
	var locked := P0KitchenLogic.page_cell(v, pages[4])
	assert_int(locked.kitchen_state).is_equal(K.LOCKED)
	assert_bool(locked.has("icon")).is_false()   # never the real dish art
	# Can cook first, then known but short, then unknown.
	var order := P0KitchenLogic.cookbook_order(v).map(func(p): return str(p.id))
	assert_str(order[0]).is_equal("dish_grilled_crucian")
	assert_array(order.slice(3)).contains_exactly(["dish_unknown_2", "dish_unknown_3"])
	assert_array(P0KitchenLogic.cookbook_order(v, "Can cook").map(func(p): return str(p.id))).is_equal(["dish_grilled_crucian"])
	assert_array(P0KitchenLogic.cookbook_order(v, "Fine").map(func(p): return str(p.id))).contains_exactly_in_any_order(["dish_perch", "dish_unknown_2"])

func test_page_cards_put_the_gap_on_the_button() -> void:
	var v := _view()
	var pages := P0KitchenLogic.pages(v)
	var a := P0KitchenLogic.page_card(v, pages[0])
	assert_str(a.title).is_equal("Grilled Crucian")
	assert_str(a.state).is_equal("Common · Cooked")
	assert_str(a.effect).is_equal("+20 Energy")
	assert_str(a.button).is_equal("Cook")
	assert_str(P0KitchenLogic.page_card(v, pages[1]).reason).is_equal("Need Lettuce ×1")
	assert_str(P0KitchenLogic.page_card(v, pages[2]).reason).is_equal("Need River Perch ×1")
	var unknown := P0KitchenLogic.page_card(v, pages[3])
	assert_str(unknown.title).is_equal("Unknown dish")
	assert_str(unknown.state).is_equal("Fine · 2 ingredients")
	assert_str(unknown.nav).is_equal("Try in Experiment")
	assert_str(P0KitchenLogic.page_card(v, pages[4]).reason).is_equal("Cooking Lv4 · 3rd slot")

func test_experiment_lists_cookables_greys_ornamental_fish_and_marks_the_pot() -> void:
	var v := _view()
	var items := P0KitchenLogic.experiment_items(v, ["fish_crucian"])
	var by_id := {}
	for it in items: by_id[str(it.id)] = it
	assert_bool(by_id.has("seed_radish")).is_false()
	assert_int(by_id.fish_koi.kitchen_state).is_equal(K.NOT_FOR_COOKING)
	assert_int(by_id.fish_crucian.kitchen_state).is_equal(K.IN_POT)
	assert_int(by_id.fish_crucian.qty).is_equal(1)   # 2 in the bag (two stacks, one cell), 1 in the pot
	assert_int(items.filter(func(i): return str(i.id) == "fish_crucian").size()).is_equal(1)
	assert_int(by_id.crop_herb.kitchen_state).is_equal(K.DEFAULT)
	assert_array(P0KitchenLogic.experiment_items(v, [], "Seasoning").map(func(i): return str(i.id))).is_equal(["crop_herb"])
	assert_array(P0KitchenLogic.experiment_items(v, [], "Fish").map(func(i): return str(i.id))).contains_exactly_in_any_order(["fish_crucian", "fish_koi"])

func test_pot_rules_slots_and_preview() -> void:
	var v := _view()
	assert_bool(P0KitchenLogic.can_add(v, [], "fish_koi")).is_false()
	assert_bool(P0KitchenLogic.can_add(v, ["fish_crucian"], "fish_crucian")).is_true()   # two in the bag
	assert_bool(P0KitchenLogic.can_add(v, ["fish_crucian", "fish_crucian"], "crop_herb")).is_false()   # 2 slots
	assert_bool(P0KitchenLogic.can_add(v, ["crop_herb"], "crop_herb")).is_false()   # only one herb
	assert_str(P0KitchenLogic.slots_used_line(v, ["fish_crucian"])).is_equal("1 / 2 slots used")
	assert_dict(P0KitchenLogic.preview(v, ["fish_crucian"])).is_equal({title = "Grilled Crucian", state = "Common", time = "5 s"})
	assert_dict(P0KitchenLogic.preview(v, ["fish_crucian", "crop_herb"])).is_equal({title = "Unknown dish", state = "Fine", time = "15 s"})
	assert_str(P0KitchenLogic.preview(v, ["crop_herb"]).title).is_equal("Needs a main ingredient")
	assert_str(P0KitchenLogic.experiment_reason(v, [])).is_equal("Add an ingredient")
	assert_str(P0KitchenLogic.experiment_reason(v, ["crop_herb"])).is_equal("Needs a main ingredient")
	assert_str(P0KitchenLogic.experiment_reason(v, ["fish_crucian"])).is_equal("")
	assert_dict(P0KitchenLogic.page_preview(v, P0KitchenLogic.pages(v)[0])).is_equal({title = "Ready to cook", state = "Common", time = "5 s"})

func test_the_stove_reads_the_queue_list_when_the_server_sends_one() -> void:
	var v := _view()
	assert_object(P0KitchenLogic.stove(v)).is_null()
	v.cooking.stove = {"ms": 5000, "ready_in": 1000}
	assert_int(int(P0KitchenLogic.stove(v).ready_in)).is_equal(1000)
	v.cooking.stoves = [{"dish": null, "ms": 15000, "ready_in": 9000, "heats": [], "queued": null}]
	assert_int(int(P0KitchenLogic.stove(v).ready_in)).is_equal(9000)
	v.cooking.stoves = [{"dish": null, "ready_in": null, "queued": null}]
	assert_object(P0KitchenLogic.stove(v)).is_null()

# ---------------------------------------------------------------- the dish comes out (COOK-4 / 6 / P0-9, COOK-7-2)
func _eat_view(energy: int, used: int, meal: int) -> Dictionary:
	var v := _view()
	v["energy"] = {"value": energy, "max": 210}
	v["meals"] = {"used": used, "cap": 210, "resets_in": 33120000, "eaten": {}}
	v.items["dish_perch@good"] = {"name": "Herb Baked Perch", "kind": "dish", "quality": 1, "meal": meal, "full": 45}
	return v

func test_eating_states_follow_cook_7_2_first_match_wins() -> void:
	var id := "dish_perch@good"
	# 1 Energy full (bonus counts as full): unavailable with the reason on the button.
	assert_dict(P0KitchenLogic.eat_state(_eat_view(210, 100, 45), id)).is_equal({text = "Energy full", reason = "Energy full"})
	# 2 food limit used up, 3 the third serving today: eats for nothing.
	assert_str(P0KitchenLogic.eat_state(_eat_view(142, 210, 45), id).text).is_equal("Eat · no Energy today")
	assert_str(P0KitchenLogic.eat_state(_eat_view(142, 100, 0), id).text).is_equal("Eat · no Energy today")
	# 4 the second serving is half (the server's meal value).
	assert_str(P0KitchenLogic.eat_state(_eat_view(142, 100, 23), id).text).is_equal("Eat · +23 Energy")
	# 5 Energy room smaller than the meal: what it really gives, one tap (q(10), no "Eat anyway?").
	assert_dict(P0KitchenLogic.eat_state(_eat_view(198, 100, 45), id)).is_equal({text = "Eat · +12 Energy", reason = ""})
	# 6 food-limit room smaller than the meal: the smaller value.
	assert_dict(P0KitchenLogic.eat_state(_eat_view(142, 190, 45), id)).is_equal({text = "Eat · +20 Energy", reason = ""})
	# 7 plain.
	assert_dict(P0KitchenLogic.eat_state(_eat_view(142, 100, 45), id)).is_equal({text = "Eat · +45 Energy", reason = ""})

func test_a_portion_left_on_the_stove_is_worth_its_tier_halved_for_a_second_serving() -> void:
	var v := _view()
	v.cooking.tiers["2"]["bonus"] = [0, 5, 10]
	v["meals"] = {"used": 0, "cap": 210, "eaten": {}}
	assert_int(P0KitchenLogic.meal_value(v, "dish_perch@good")).is_equal(45)   # not in the bag: tier 40 + Good 5
	v.meals.eaten["dish_perch"] = 1
	assert_int(P0KitchenLogic.meal_value(v, "dish_perch@good")).is_equal(23)
	v.cooking["cabinet"] = {"cap": 6, "have": 1, "items": [{"id": "dish_perch@good", "qty": 1, "energy": 30}]}
	assert_int(P0KitchenLogic.meal_value(v, "dish_perch@good")).is_equal(30)   # the cabinet row's own number

func test_routes_say_where_each_portion_went() -> void:
	var events := [
		{"kind": "cabinet", "id": "dish_perch@perfect", "delta": 1, "to_bag": 0, "have": 5, "cap": 6},
		{"kind": "item", "id": "dish_perch", "delta": 1},
		{"kind": "cabinet", "id": "dish_perch", "delta": 0, "to_bag": 1, "have": 5, "cap": 6},
		{"kind": "dish", "dish": "dish_perch", "quality": 2},
	]
	assert_dict(P0KitchenLogic.routes(events)).is_equal({"dish_perch@perfect": "cabinet", "dish_perch": "bag"})
	assert_dict(P0KitchenLogic.routes([{"kind": "plate", "ids": ["dish_perch"], "cabinet": false}])).is_equal({"dish_perch": "stove"})
	assert_dict(P0KitchenLogic.eat_command("dish_perch", "cabinet")).is_equal({"type": "eat", "item": "dish_perch", "from": "cabinet"})
	assert_dict(P0KitchenLogic.eat_command("dish_perch", "stove")).is_equal({"type": "collect", "eat": true})
	assert_dict(P0KitchenLogic.eat_command("dish_perch", "bag")).is_equal({"type": "eat", "item": "dish_perch"})

func test_keep_lines_follow_keep_states() -> void:
	var v := _view()
	v.items["dish_perch"] = {"name": "Herb Baked Perch", "kind": "dish"}
	assert_str(P0KitchenLogic.keep_line(v, "dish_perch", "bag").text).is_equal("Herb Baked Perch · saved to your bag")
	assert_str(P0KitchenLogic.keep_line(v, "dish_perch", "stove").text).is_equal("Bag full · dish left on the stove")
	v.cooking["cabinet"] = {"cap": 6, "have": 5, "items": []}
	assert_str(P0KitchenLogic.keep_line(v, "dish_perch", "cabinet").text).is_equal("Kept · Warming Cabinet 5/6")
	assert_str(P0KitchenLogic.keep_line(v, "dish_perch", "bag").text).is_equal("Cabinet full · Herb Baked Perch sent to bag")
	assert_str(P0KitchenLogic.keep_line(v, "dish_perch", "stove").text).is_equal("Cabinet and bag full · dish left on the stove")

func test_dish_cards_say_new_recipe_mystery_or_ready() -> void:
	var v := _view()
	var first := P0KitchenLogic.dish_card(v, {"dish": "dish_perch", "quality": 1, "first": true}, 20, false)
	assert_str(first.event).is_equal("New recipe!")
	assert_str(first.item_name).is_equal("Herb Baked Perch")
	assert_str(first.rarity_word).is_equal("Fine")
	assert_int(first.quality).is_equal(1)
	assert_str(first.strip).is_equal("First cooked · +20 Cooking XP · Cookbook 3/5")
	assert_str(first.note).is_equal("Gift later from your bag")
	assert_str(first.dish_id).is_equal("dish_perch@good")
	var back := P0KitchenLogic.dish_card(v, {"dish": "dish_grilled_crucian", "quality": 0}, 0, true)
	assert_str(back.event).is_equal("Dish ready")
	assert_str(back.strip).is_equal("Collected from Stove 1")
	var mystery := P0KitchenLogic.dish_card(v, {"dish": "dish_mystery", "quality": 0, "mystery": true, "clue": {"page": "dish_perch"}}, 0, false)
	assert_int(mystery.tone).is_equal(UiRewardMoment.Tone.NEUTRAL)
	assert_str(mystery.strip).is_equal("A clue was added to your Cookbook")
	assert_str(mystery.note).is_equal("Can't be sold or delivered")
	var none := P0KitchenLogic.dish_card(v, {"dish": "dish_mystery", "mystery": true, "qty": 0, "none": true, "trial_left": 7}, 0, false)
	assert_str(none.event).is_equal("No dish this time")
	assert_str(none.item_name).is_equal("Ingredients back (7 left today)")
	assert_bool(none.none).is_true()

func test_keep_room_spares_a_retry_that_would_be_refused() -> void:
	var v := _view()
	v.bag.free = 0
	assert_bool(P0KitchenLogic.keep_room(v, "dish_perch")).is_false()
	v.bag.slots.append({"id": "dish_perch", "qty": 4})
	assert_bool(P0KitchenLogic.keep_room(v, "dish_perch")).is_true()   # a dish stack (5) with room
	v.bag.slots[-1].qty = 5
	v.cooking["cabinet"] = {"cap": 6, "have": 5, "items": []}
	assert_bool(P0KitchenLogic.keep_room(v, "dish_perch")).is_true()
	assert_array(P0KitchenLogic.stove_left(v)).is_empty()
	v.cooking.stove = {"ready_in": 0, "left": ["dish_perch"]}
	assert_array(P0KitchenLogic.stove_left(v)).contains_exactly(["dish_perch"])

# ---------------------------------------------------------------- Spice Rack / Warming Cabinet (COOK-P0-5 / P0-6)
func test_the_spice_rack_lists_stored_seasonings_with_their_real_count() -> void:
	var v := _view()
	assert_array(P0KitchenLogic.rack_rows(v)).is_empty()   # no rack in the view (before Lv2)
	v.cooking["rack"] = {"on": true, "items": [{"id": "rock_salt", "name": "Rock Salt", "qty": 42}, {"id": "wild_herb", "name": "Wild Herb", "qty": 3}]}
	assert_array(P0KitchenLogic.rack_rows(v)).is_equal([
		{id = "rock_salt", title = "Rock Salt", quantity = "42", unit = "items"},   # q(46): no 30 cap
		{id = "wild_herb", title = "Wild Herb", quantity = "3", unit = "items"}])

func test_the_warming_cabinet_sheet_badge_and_buttons() -> void:
	var v := _eat_view(142, 100, 45)
	assert_dict(P0KitchenLogic.cabinet_sheet(v)).is_empty()   # before Lv3
	assert_str(P0KitchenLogic.cabinet_badge(v)).is_equal("")
	v.cooking["cabinet"] = {"cap": 6, "have": 4, "items": [
		{"id": "dish_perch@good", "name": "Herb Baked Perch", "qty": 1, "energy": 45},
		{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "qty": 3, "energy": 20}]}
	var sheet := P0KitchenLogic.cabinet_sheet(v)
	assert_str(sheet.title).is_equal("Warming Cabinet 4/6")
	assert_dict(sheet.rows[0]).is_equal({id = "dish_perch@good", title = "Herb Baked Perch", state = "★ Good", effect = "+45 Energy", quantity = "×1"})
	assert_str(sheet.rows[1].state).is_equal("")   # Plain: no badge
	assert_str(P0KitchenLogic.cabinet_badge(v)).is_equal("4/6")
	v.cooking.cabinet.have = 6
	assert_str(P0KitchenLogic.cabinet_badge(v)).is_equal("Full")
	var a := P0KitchenLogic.cabinet_actions(v, "dish_perch@good")
	assert_str(a.eat.text).is_equal("Eat · +45 Energy")
	assert_str(a.take_reason).is_equal("")
	v.bag.free = 0
	assert_str(P0KitchenLogic.cabinet_actions(v, "dish_perch@good").take_reason).is_equal("Bag full")

# ---------------------------------------------------------------- S5 Cookbook fields (SGODOT-232, PR #22 sample)
func _s5_view() -> Dictionary:
	var v := _view()
	v.cooking.merge({"slots": 2, "pages_total": 48, "discovered": 2, "third_slot": {"level": 4, "xp_to_go": 85},
		"queued": {"dish": null, "rarity": 2, "ms": 15000, "starts_in": 3000}}, true)
	v.cooking.stove = {"dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "elapsed": 2000, "ready_in": 3000, "heats": [], "left": null}
	v.cooking.cookbook = [
		{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "rarity": 1, "slots": 1, "state": "mastered", "known": true, "in": ["fish_crucian"], "cooked": true, "cooked_total": 10, "can_cook": true, "lock": null},
		{"id": "dish_grilled_fish", "name": null, "rarity": 1, "slots": 1, "state": "hidden", "known": false, "in": ["?"], "cooked": false, "can_cook": false, "lock": null},
		{"id": "dish_radish_salad", "name": "Radish Salad", "rarity": 1, "slots": 2, "state": "tasted", "known": true, "in": ["crop_radish", "crop_lettuce"], "cooked": false, "can_cook": false, "lock": null},
		{"id": "dish_veggie_plate", "name": null, "rarity": 1, "slots": 1, "state": "clued", "known": false, "in": ["F1"], "cooked": false, "can_cook": false, "lock": null},
		{"id": "dish_fisher_stew", "name": null, "rarity": 3, "slots": 3, "state": "hidden", "known": false, "in": ["?", "?", "?"], "cooked": false, "can_cook": false, "lock": {"level": 4, "xp_to_go": 85}},
	]
	return v

func test_s5_page_states_drive_the_cells_order_and_counts() -> void:
	var v := _s5_view()
	var K := UiItemCell.KitchenState
	var states := P0KitchenLogic.pages(v).map(func(p): return P0KitchenLogic.page_cell(v, p).kitchen_state)
	assert_array(states).is_equal([K.MASTERED, K.HIDDEN, K.TASTED, K.CLUED, K.LOCKED])
	assert_bool(P0KitchenLogic.page_cell(v, P0KitchenLogic.pages(v)[0]).marked).is_true()   # mastered and can cook
	assert_array(P0KitchenLogic.cookbook_order(v).map(func(p): return p.id)).is_equal(
		["dish_grilled_crucian", "dish_radish_salad", "dish_veggie_plate", "dish_grilled_fish", "dish_fisher_stew"])
	assert_str(P0KitchenLogic.cookbook_count(v)).is_equal("2/48")
	assert_str(P0KitchenLogic.locked_slot_label(v)).is_equal("Lv4 · 85 XP to go")
	assert_str(P0KitchenLogic.header(v).state).is_equal("Cooking 0:03 · Queued 1")
	assert_str(P0KitchenLogic.page_card(v, P0KitchenLogic.pages(v)[0]).state).is_equal("Common · Cooked ×10")
	assert_str(P0KitchenLogic.page_card(v, P0KitchenLogic.pages(v)[4]).reason).is_equal("Cooking Lv4 · 3rd slot")
	assert_str(P0KitchenLogic.page_card(v, P0KitchenLogic.pages(v)[3]).nav).is_equal("Try in Experiment")

func test_the_cook_row_shows_the_energy_of_a_known_pot_only() -> void:
	var v := _view()
	assert_str(P0KitchenLogic.pot_energy(v, [])).is_equal("")
	assert_str(P0KitchenLogic.pot_energy(v, ["fish_crucian"])).is_equal("+20 Energy")   # Grilled Crucian (COOK-P0-2)
	assert_str(P0KitchenLogic.pot_energy(v, ["fish_crucian", "crop_radish"])).is_equal("")   # unknown mix (COOK-2b)


# ---------------------------------------------------------------- Cook Again (COOK-P0-7 / P0-8)
func _again_view() -> Dictionary:
	var v := _view()
	v.cooking["conveniences"] = ["cook_again"]
	v.cooking.cookbook.append({"id": "dish_herb_grilled_fish", "name": "Herb Grilled Fish", "rarity": 2, "slots": 2,
		"in": ["W1", "S1"], "known": true, "cooked": true, "can_cook": true, "today": 1})
	v.items["fish_perch"] = {"name": "River Perch", "kind": "fish", "family": "W", "rarity": 1, "cook": true}
	v.bag.slots = [{"id": "fish_crucian", "qty": 1}, {"id": "fish_perch", "qty": 1}]
	v.cooking["rack"] = {"on": true, "items": [{"id": "wild_herb", "name": "Wild Herb", "qty": 2}]}
	v.items["wild_herb"] = {"name": "Wild Herb", "kind": "material"}
	return v

func test_cook_again_lists_facts_tiles_and_the_command() -> void:
	var v := _again_view()
	assert_bool(P0KitchenLogic.cook_again_on(v)).is_true()
	var a := P0KitchenLogic.cook_again(v, "dish_herb_grilled_fish")
	assert_str(a.state).is_equal("Can cook again")
	assert_array(a.facts).is_equal([["Cooking", "15 s"], ["Cooks today", "2nd"], ["Cooking XP", "Half"]])
	assert_str(a.section).is_equal("Ingredients · 2/2")
	assert_array(a.tiles.map(func(t): return [t.name, t.have, t.need])).is_equal([["Fish", 2, 1], ["Wild Herb", 2, 1]])
	# A specific ingredient names itself on the button (An Qi La on 226): Need 1 more Pond Crucian.
	var crucian := P0KitchenLogic.cook_again(_again_view_without_crucian(), "dish_grilled_crucian")
	assert_str(crucian.reason).is_equal("Need 1 more Pond Crucian")
	assert_str(a.reason).is_equal("")
	assert_dict(a.command).is_equal({"type": "cook", "recipe": "dish_herb_grilled_fish"})

func test_cook_again_short_names_the_gap_and_drops_the_time() -> void:
	var v := _again_view()
	v.bag.slots = []
	var a := P0KitchenLogic.cook_again(v, "dish_herb_grilled_fish")
	assert_str(a.state).is_equal("Materials short")
	assert_str(a.effect).is_equal("Add fish to cook this recipe again.")
	assert_array(a.facts).is_equal([["Cooks today", "2nd"], ["Cooking XP", "Half"]])
	assert_str(a.reason).is_equal("Need 1 more Fish")
	assert_str(a.section).is_equal("Ingredients · 1/2")

func _again_view_without_crucian() -> Dictionary:
	var v := _again_view()
	v.bag.slots = [{"id": "fish_perch", "qty": 1}]
	return v

func test_experiment_lists_the_spice_racks_stored_seasonings() -> void:
	var v := _view()
	v.cooking["rack"] = {"on": true, "items": [{"id": "rock_salt", "name": "Rock Salt", "qty": 12}]}
	var salt: Array = P0KitchenLogic.experiment_items(v, []).filter(func(i): return i.id == "rock_salt")
	assert_int(salt.size()).is_equal(1)
	assert_int(salt[0].qty).is_equal(12)
	assert_str(salt[0].status).is_equal("Rack")   # q(46): real count, a Rack tag
	assert_bool(P0KitchenLogic.can_add(v, ["fish_crucian"], "rock_salt")).is_true()
	assert_array(P0KitchenLogic.experiment_items(v, [], "Fish").map(func(i): return i.id)).not_contains(["rock_salt"])
	assert_array(P0KitchenLogic.experiment_items(v, [], "Seasoning").map(func(i): return i.id)).contains(["rock_salt"])


func test_a_stored_seasoning_counts_as_a_seasoning_in_the_preview() -> void:
	var v := _view()
	v.cooking["rack"] = {"on": true, "items": [{"id": "rock_salt", "name": "Rock Salt", "qty": 12}]}
	assert_str(P0KitchenLogic.preview(v, ["rock_salt"]).title).is_equal("Needs a main ingredient")   # not a main
	assert_str(P0KitchenLogic.experiment_reason(v, ["rock_salt"])).is_equal("Needs a main ingredient")
	assert_str(P0KitchenLogic.pot_energy(v, ["fish_perch", "rock_salt"])).is_equal("+40 Energy")   # Herb Baked Perch [fish_perch, S1]
