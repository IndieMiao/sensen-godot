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
