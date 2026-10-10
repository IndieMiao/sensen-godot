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
	assert_str(P0KitchenLogic.locked_slot_toast(v)).is_equal("Cooking Lv4 · 60 XP to go")   # 256 ⑤ A': a tap on the lock
	assert_str(P0KitchenLogic.cookbook_count(v)).is_equal("3/5")

func test_page_cells_follow_the_kitchen_cell_states() -> void:
	var v := _view()
	var pages := P0KitchenLogic.pages(v)
	var can := P0KitchenLogic.page_cell(v, pages[0])
	assert_int(can.kitchen_state).is_equal(K.DEFAULT)
	assert_bool(can.has("marked")).is_false()   # 256 ⑨: no can-cook check; the chip, the order and Cook say it
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
	assert_str(a.effect).is_equal("+20 Energy · 5 s")   # 256 follow-up: energy · time · style (no style in this view)
	assert_str(a.button).is_equal("Cook")
	assert_str(P0KitchenLogic.page_card(v, pages[1]).reason).is_equal("Need Lettuce ×1")
	# 256 ⑨ / q(92): known, not cooked yet — the one-off first-cook XP of its tier, never the word Tasted.
	assert_str(P0KitchenLogic.page_card(v, pages[1]).state).is_equal("Common · First cook +10 XP")
	assert_str(P0KitchenLogic.first_cook_line(4)).is_equal("First cook +80 XP")
	assert_str(P0KitchenLogic.page_card(v, pages[2]).reason).is_equal("Need River Perch ×1")
	var unknown := P0KitchenLogic.page_card(v, pages[3])
	assert_str(unknown.title).is_equal("Unknown dish")
	assert_array(unknown.effect_parts).is_equal(["+40 Energy"])   # an unknown page: the energy only, no time or style
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
	# 256 ⑤ A': the result line — dish, rarity (a dot) and time; `?` alone with only seasonings; nothing for an empty pot.
	assert_dict(P0KitchenLogic.preview(v, ["fish_crucian"])).is_equal({title = "Grilled Crucian", rarity = 1, time = "5 s"})
	assert_dict(P0KitchenLogic.preview(v, ["fish_crucian", "crop_herb"])).is_equal({title = "Unknown dish", rarity = 2, time = "15 s"})
	assert_dict(P0KitchenLogic.preview(v, ["crop_herb"])).is_equal({title = "?", rarity = 0, time = ""})
	assert_dict(P0KitchenLogic.preview(v, [])).is_equal({title = "", rarity = 0, time = ""})
	assert_str(P0KitchenLogic.experiment_reason(v, [])).is_equal("Add an ingredient")
	assert_str(P0KitchenLogic.experiment_reason(v, ["crop_herb"])).is_equal("Needs a main ingredient")
	assert_str(P0KitchenLogic.experiment_reason(v, ["fish_crucian"])).is_equal("")
	assert_dict(P0KitchenLogic.page_preview(v, P0KitchenLogic.pages(v)[0])).is_equal({title = "Grilled Crucian", rarity = 1, time = "5 s"})

func test_the_stove_reads_the_queue_list_when_the_server_sends_one() -> void:
	var v := _view()
	assert_object(P0KitchenLogic.stove(v)).is_null()
	v.cooking.stove = {"ms": 5000, "ready_in": 1000}
	assert_int(int(P0KitchenLogic.stove(v).ready_in)).is_equal(1000)
	v.cooking.stoves = [{"dish": null, "ms": 15000, "ready_in": 9000, "heats": [], "queued": null}]
	assert_int(int(P0KitchenLogic.stove(v).ready_in)).is_equal(9000)
	v.cooking.stoves = [{"dish": null, "ready_in": null, "queued": null}]
	assert_object(P0KitchenLogic.stove(v)).is_null()

## SGODOT-282: a Legendary page carries the empty Buff slot (§7.14.4); other rarities none.
func test_a_legendary_page_card_names_the_buff_slot() -> void:
	var v := _view()
	v.cooking.tiers["4"] = {"energy": 70, "ms": 60000}
	var legend := {"id": "dish_legend_sashimi", "name": "Legend Sashimi", "rarity": 4, "known": true, "slots": 1, "can_cook": true}
	assert_str(str(P0KitchenLogic.page_card(v, legend).buff)).is_equal("Buff · coming later")
	assert_str(str(P0KitchenLogic.page_card(v, P0KitchenLogic.pages(v)[0]).buff)).is_equal("")

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
	assert_str(none.item_name).is_equal("Ingredients back")
	assert_str(none.rarity_word).is_equal("7 left today")   # its own line under the name (int6 C14: the count was cut off)
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
	assert_array(P0KitchenLogic.cookbook_order(v).map(func(p): return p.id)).is_equal(
		["dish_grilled_crucian", "dish_radish_salad", "dish_veggie_plate", "dish_grilled_fish", "dish_fisher_stew"])
	assert_str(P0KitchenLogic.cookbook_count(v)).is_equal("2/48")
	assert_str(P0KitchenLogic.locked_slot_label(v)).is_equal("Lv4 · 85 XP to go")
	assert_str(P0KitchenLogic.header(v).state).is_equal("Cooking 0:03 · Queued 1")
	assert_str(P0KitchenLogic.page_card(v, P0KitchenLogic.pages(v)[0]).state).is_equal("Common · Cooked ×10")
	assert_str(P0KitchenLogic.page_card(v, P0KitchenLogic.pages(v)[4]).reason).is_equal("Cooking Lv4 · 3rd slot")
	assert_str(P0KitchenLogic.page_card(v, P0KitchenLogic.pages(v)[3]).nav).is_equal("Try in Experiment")

func test_unknown_pages_carry_their_families_clues_and_might_have() -> void:
	# int6 C29 / C41: the cell's family row comes from the page (one dot per slot, a clue lights its slot) and the
	# server's `maybe` is the might-have ring and the card's own line.
	var v := _s5_view()
	var pages := P0KitchenLogic.pages(v)
	pages[1].merge({"families": ["W"], "maybe": true}, true)          # Grilled Fish: any Common fish, the bag has one
	pages[3].merge({"families": ["F"], "maybe": false}, true)         # Veggie Plate: its one slot lit by an F1 clue
	pages[4].merge({"families": ["W", "F", "S"], "in": ["?", "crop_potato", "?"]}, true)   # a clue under the Lv4 lock
	var hidden := P0KitchenLogic.page_cell(v, pages[1])
	assert_array(hidden.families).is_equal(["W"])
	assert_array(hidden.clues).is_equal([null])
	assert_bool(hidden.might_have).is_true()
	var clued := P0KitchenLogic.page_cell(v, pages[3])
	assert_array(clued.clues).is_equal([UiItemCell.family_icon("F")])   # a family clue: the family icon, never a fish
	assert_bool(clued.might_have).is_false()
	var locked := P0KitchenLogic.page_cell(v, pages[4])
	assert_int(locked.kitchen_state).is_equal(UiItemCell.KitchenState.LOCKED)
	assert_array(locked.clues).is_equal([null, P0Logic.icon("crop_potato"), null])
	assert_str(P0KitchenLogic.page_card(v, pages[1]).maybe).is_equal("You might have what it takes")
	assert_str(P0KitchenLogic.page_card(v, pages[3]).maybe).is_equal("")
	assert_str(P0KitchenLogic.page_card(v, pages[0]).maybe).is_equal("")   # known pages never say it

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

func test_cook_again_sheet_uses_the_pot_slots_and_its_lock_says_what_opens_it() -> void:
	# 刘邦 on #142: COOK-P0-7 / P0-8 (784:77585) take PotSlot44 too — icons and ×1, no names, 20 apart; the lock alone.
	var v := _again_view()
	var a := P0KitchenLogic.cook_again(v, "dish_herb_grilled_fish")
	var sheet: Control = auto_free(preload("res://scenes/p0/kitchen/p0_cook_again_sheet.gd").new(a))
	var bar: HBoxContainer = sheet.call("_slot_bar")
	auto_free(bar)
	var slots := bar.get_children()
	assert_int(bar.get_theme_constant(&"separation")).is_equal(20)
	assert_array(slots.map(func(sl): return (sl as UiPotSlot).state)).is_equal(
		[UiPotSlot.State.FILLED, UiPotSlot.State.FILLED, UiPotSlot.State.LOCKED])
	assert_bool(slots.all(func(sl): return not (sl as UiPotSlot).removable)).is_true()
	var said := []
	sheet.connect("unavailable", func(r: String): said.append(r))
	(slots[2] as UiPotSlot).locked_tapped.emit()
	assert_array(said).is_equal([P0KitchenLogic.locked_slot_toast(v)])
	assert_str(str(said[0])).starts_with("Cooking Lv4")

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
	assert_bool(salt[0].rack).is_true()   # q(46): real count, a Rack tag (Show rack)
	assert_bool(P0KitchenLogic.can_add(v, ["fish_crucian"], "rock_salt")).is_true()
	assert_array(P0KitchenLogic.experiment_items(v, [], "Fish").map(func(i): return i.id)).not_contains(["rock_salt"])
	assert_array(P0KitchenLogic.experiment_items(v, [], "Seasoning").map(func(i): return i.id)).contains(["rock_salt"])
	# In the pot it keeps the tag (COOK-2b-RACK): ✕ sends it back to the rack.
	var in_pot: Array = P0KitchenLogic.experiment_items(v, ["fish_crucian", "rock_salt"]).filter(func(i): return i.id == "rock_salt")
	assert_int(in_pot[0].kitchen_state).is_equal(UiItemCell.KitchenState.IN_POT)
	assert_bool(in_pot[0].rack).is_true()


func test_a_stored_seasoning_counts_as_a_seasoning_in_the_preview() -> void:
	var v := _view()
	v.cooking["rack"] = {"on": true, "items": [{"id": "rock_salt", "name": "Rock Salt", "qty": 12}]}
	assert_str(P0KitchenLogic.preview(v, ["rock_salt"]).title).is_equal("?")   # not a main: the button says why
	assert_str(P0KitchenLogic.experiment_reason(v, ["rock_salt"])).is_equal("Needs a main ingredient")
	assert_str(P0KitchenLogic.pot_energy(v, ["fish_perch", "rock_salt"])).is_equal("+40 Energy")   # Herb Baked Perch [fish_perch, S1]

func test_a_mix_that_failed_before_says_tried_before() -> void:
	var v := _view()
	v.cooking["mishaps"] = [{"items": ["crop_radish", "crop_radish"], "n": 1, "at": 0}]
	assert_bool(P0KitchenLogic.tried(v, ["crop_radish", "crop_radish"])).is_true()
	assert_str(P0KitchenLogic.preview(v, ["crop_radish", "crop_radish"]).title).is_equal("Tried before")
	assert_bool(P0KitchenLogic.tried(v, ["crop_radish"])).is_false()
	assert_str(P0KitchenLogic.preview(v, ["crop_radish", "fish_koi"]).title).is_equal("Unknown dish")


func test_every_cookable_dish_has_an_icon() -> void:
	# int6 C7: four P0 dishes had no file, so P0Logic.icon fell back to the field sprout (a plate that looks like
	# seeds) on the page cell, the detail card, COOK-4 and the plate in the scene. 安其拉 drew them (226 d4d629f7).
	# SGODOT-282: all 48 pages are recipes; every page that cooks in this build (every ingredient exists, not buy-only)
	# has its own icon or a P0 dish standing in (P0Logic.DISH_STANDIN) until its own is drawn.
	var content := P0Logic.content()
	var known := {}
	for f in content.get("fish", []): known[str(f.id)] = true
	for c in content.get("crops", []): known[str(c.id)] = true
	for m in content.get("materials", {}): known[str(m)] = true
	var tag := RegEx.create_from_string("^[WFOS][1-4]$")
	var cooks := 0
	for r in content.get("cooking", {}).get("recipes", []):
		var ins: Array = r.get("in", [])
		if r.get("cookable", true) == false or ins.is_empty() or ins.any(func(t): return tag.search(str(t)) == null and not known.has(str(t))): continue
		cooks += 1
		var id := str(r.id)
		var own := ResourceLoader.exists(P0Logic.ICON_DIR % id)
		var stand := P0Logic.DISH_STANDIN.has(id) and ResourceLoader.exists(P0Logic.ICON_DIR % P0Logic.DISH_STANDIN[id])
		assert_bool(own or stand).override_failure_message(id + " has no icon").is_true()
	assert_int(cooks).is_equal(24)

func test_queue_two_entry_state_line_and_turn_over_toast() -> void:
	# q(71) / q(82): Queue next › only from Cooking Lv5 with a pot cooking and none waiting; the watch sheet says
	# Queued 1; the toast is "<kept> · <next> cooking" for the plain and the three edge cases (and their mixes).
	var v := _s5_view()
	assert_bool(P0KitchenLogic.can_queue(v)).is_false()   # no queue_two yet
	v.cooking.conveniences = ["cook_again", "queue_two"]
	assert_bool(P0KitchenLogic.can_queue(v)).is_false()    # _s5_view already has a pot waiting
	v.cooking.erase("queued")
	assert_bool(P0KitchenLogic.can_queue(v)).is_true()
	assert_str(P0KitchenLogic.watch_state(v)).is_equal("Cooking")
	v.cooking.queued = {"id": 9, "dish": null, "rarity": 2, "ms": 15000, "starts_in": 3000}
	assert_bool(P0KitchenLogic.can_queue(v)).is_false()    # full: no button at all
	assert_str(P0KitchenLogic.watch_state(v)).is_equal("Cooking · Queued 1")
	var empty := _s5_view()
	empty.cooking.conveniences = ["queue_two"]
	empty.cooking.stove = null
	empty.cooking.erase("queued")
	assert_bool(P0KitchenLogic.can_queue(empty)).is_false()   # nothing cooking: plain Cook, not Queue
	v.names["dish_grilled_crucian"] = "Grilled Crucian"
	v.names["dish_herb_grilled_fish"] = "Herb Grilled Fish"
	v.names["dish_mystery"] = "Mystery Dish"
	var crucian := {"kind": "dish", "dish": "dish_grilled_crucian", "quality": 0}
	assert_str(P0KitchenLogic.rotation_line(v, crucian, "dish_herb_grilled_fish")).is_equal("Grilled Crucian kept · Herb Grilled Fish cooking")
	assert_str(P0KitchenLogic.rotation_line(v, crucian, null)).is_equal("Grilled Crucian kept · Unknown dish cooking")
	var mystery := {"kind": "dish", "dish": "dish_mystery", "mystery": true}
	assert_str(P0KitchenLogic.rotation_line(v, mystery, "dish_herb_grilled_fish")).is_equal("Mystery Dish kept · Herb Grilled Fish cooking")
	var none := {"kind": "dish", "dish": "dish_mystery", "mystery": true, "none": true, "trial_left": 7}
	assert_str(P0KitchenLogic.rotation_line(v, none, "dish_herb_grilled_fish")).is_equal("Ingredients back · Herb Grilled Fish cooking")
	assert_str(P0KitchenLogic.rotation_line(v, none, null)).is_equal("Ingredients back · Unknown dish cooking")

func test_the_result_line_names_the_dish_and_queue_mode_never_reads_stove_busy() -> void:
	# 256 ⑤ A' / q(92): `Ready to cook` / `Ready to queue` (q(84)) are retired: the line names the dish, can cook or not;
	# q(71): the Experiment button in the drawer opened from Queue next › is not stopped by the pot on the stove — that
	# pot is why the drawer is open.
	var v := _view()
	assert_str(P0KitchenLogic.page_preview(v, P0KitchenLogic.pages(v)[0]).title).is_equal("Grilled Crucian")   # can cook
	assert_str(P0KitchenLogic.page_preview(v, P0KitchenLogic.pages(v)[1]).title).is_equal("Radish Salad")   # short
	v.cooking.stove = {"id": 3, "ms": 15000, "ready_in": 9000, "heats": []}
	assert_str(P0KitchenLogic.experiment_reason(v, ["fish_crucian"])).is_equal("Stove busy")
	assert_str(P0KitchenLogic.experiment_reason(v, ["fish_crucian"], true)).is_equal("")
	assert_str(P0KitchenLogic.experiment_reason(v, [], true)).is_equal("Add an ingredient")

func test_a_new_recipe_kept_by_a_turn_over_has_its_own_line() -> void:
	# q(85) (不知火舞 on 226, option ②): no COOK-4 on a turn-over, so a first-time dish says `New recipe! <dish> kept`,
	# without the next pot (it would wrap to three lines); anything else keeps the turn-over line.
	var v := _view()
	v.names["dish_herb_grilled_fish"] = "Herb Grilled Fish"
	v.names["dish_grilled_crucian"] = "Grilled Crucian"
	var first := {"kind": "dish", "dish": "dish_herb_grilled_fish", "quality": 1, "first": true, "mystery": false}
	assert_str(P0KitchenLogic.new_recipe_line(v, first)).is_equal("New recipe! Herb Grilled Fish kept")
	assert_str(P0KitchenLogic.rotation_line(v, first, "dish_grilled_crucian")).is_equal("Herb Grilled Fish kept · Grilled Crucian cooking")
	first.first = false
	assert_str(P0KitchenLogic.new_recipe_line(v, first)).is_equal("")
	assert_str(P0KitchenLogic.new_recipe_line(v, {"kind": "dish", "dish": "dish_mystery", "mystery": true, "first": true})).is_equal("")

func test_the_events_of_a_pot_kept_on_its_own_are_told_from_the_commands() -> void:
	# The server settles the stove before a command and again after it (reducer settleStove), so a pot Queue ×2 kept on
	# its own sits among the command's events; away from the kitchen exactly its events go quiet (不知火舞 on 226).
	var bagged := {"kind": "item", "id": "dish_grilled_crucian", "delta": 1}
	var dish := {"kind": "dish", "pot": 3, "dish": "dish_grilled_crucian", "quality": 0, "first": false, "mystery": false, "auto": true}
	var xp := {"kind": "xp", "skill": "cooking", "amount": 5, "percent": 100}
	var level := {"kind": "level", "skill": "cooking", "level": 3, "energy": 0, "gifts": [["spice_pepper", 2]]}
	var gift := {"kind": "parcel", "id": "spice_pepper", "qty": 2, "key": "level:cooking:3:0"}
	var fired := {"kind": "queue", "id": 4, "dish": null, "started_at": 0, "ms": 60000}
	var crop := {"kind": "item", "id": "crop_radish", "delta": 2}
	var farm_xp := {"kind": "xp", "skill": "farming", "amount": 4, "percent": 100}
	var spent := {"kind": "energy", "delta": -2, "reason": "harvest"}
	# Before the command: the harvest's items and XP stay.
	var events := [bagged, dish, xp, level, gift, fired, spent, crop, farm_xp]
	assert_array(P0KitchenLogic.auto_kept_events(events)).is_equal([bagged, dish, xp, level, fired])   # the gift is the level-up's
	# After it, and a pot with plates left on the stove (no `queue`): the next command's XP is not the pot's.
	var plate := {"kind": "plate", "ids": ["dish_grilled_crucian"], "cabinet": false}
	assert_array(P0KitchenLogic.auto_kept_events([crop, farm_xp, plate, dish, xp])).is_equal([plate, dish, xp])
	assert_array(P0KitchenLogic.auto_kept_events([plate, dish, xp, crop, farm_xp])).is_equal([plate, dish, xp])
	# A dish the command took out (eaten from the bag or the Warming Cabinet) just before is the command's (后裔 on #108).
	var eaten := {"kind": "item", "id": "dish_grilled_crucian", "delta": -1}
	var taken := {"kind": "cabinet", "id": "dish_grilled_crucian", "delta": -1, "to_bag": 0, "have": 0, "cap": 6}
	assert_array(P0KitchenLogic.auto_kept_events([eaten, taken, plate, dish, xp])).is_equal([plate, dish, xp])
	# A full Warming Cabinet sends the dish on to the bag: the cabinet says delta 0, to_bag 1 (server routeDish).
	var past := {"kind": "cabinet", "id": "dish_grilled_crucian", "delta": 0, "to_bag": 1, "have": 6, "cap": 6}
	assert_array(P0KitchenLogic.auto_kept_events([eaten, bagged, past, dish, xp])).is_equal([bagged, past, dish, xp])
	# `Take one` from the cabinet into the bag (item +1, then the cabinet −1 with to_bag 1) is the command's too.
	var took := {"kind": "cabinet", "id": "dish_grilled_crucian", "delta": -1, "to_bag": 1, "have": 5, "cap": 6}
	assert_array(P0KitchenLogic.auto_kept_events([bagged, took, bagged.duplicate(), past, dish])).is_equal([bagged, past, dish])
	# A Mystery Dish: the ingredients it gives back, then its Mishap, then the waiting pot.
	var odd := dish.duplicate()
	odd.mystery = true
	var back := {"kind": "item", "id": "fish_crucian", "delta": 1}
	var mishap := {"kind": "mishap", "items": ["fish_crucian"], "tried": false, "refund": ["fish_crucian"]}
	assert_array(P0KitchenLogic.auto_kept_events([odd, back, mishap, fired, crop])).is_equal([odd, back, mishap, fired])
	# A pot collected at the stove (no `auto`) is not one.
	var served := dish.duplicate()
	served.erase("auto")
	assert_array(P0KitchenLogic.auto_kept_events([bagged, served, xp])).is_empty()

func test_the_effect_line_reads_energy_time_and_style_and_quick_fire_shortens_every_time() -> void:
	# 不知火舞 (256 follow-up): a known page reads `+40 Energy · 15 s · Soup`; the time is the stove's own, 4 / 12 / 24 / 48 s
	# after Quick Fire (Cooking Lv6), as the pot card's result line and Cook Again say it.
	var v := _view()
	var perch: Dictionary = P0KitchenLogic.pages(v)[2]   # Herb Baked Perch, Fine
	perch["style"] = "Grilled"
	var card := P0KitchenLogic.page_card(v, perch)
	assert_array(card.effect_parts).is_equal(["+40 Energy", "15 s", "Grilled"])
	assert_str(card.effect).is_equal("+40 Energy · 15 s · Grilled")
	v.cooking.conveniences = ["cook_again", "quick_fire"]
	v.cooking.tiers["4"] = {"energy": 70, "ms": 60000}
	assert_str(P0KitchenLogic.cook_time(v, 1)).is_equal("4 s")
	assert_str(P0KitchenLogic.cook_time(v, 2)).is_equal("12 s")
	assert_str(P0KitchenLogic.cook_time(v, 3)).is_equal("24 s")
	assert_str(P0KitchenLogic.cook_time(v, 4)).is_equal("48 s")
	assert_str(P0KitchenLogic.page_card(v, perch).effect).is_equal("+40 Energy · 12 s · Grilled")
	assert_str(P0KitchenLogic.preview(v, ["fish_crucian"]).time).is_equal("4 s")
	assert_str(P0KitchenLogic.page_preview(v, perch).time).is_equal("12 s")
