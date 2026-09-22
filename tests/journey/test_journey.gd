extends GdUnitTestSuite

func after_test() -> void:
	for index in 3: await get_tree().process_frame

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 180, "engineering": {"reserved": {}},
		"inventory": {"produce": {"R": 0, "L": 0, "C": 0, "H": 0}, "dishes": {"salad": 0, "tea": 0},
			"seeds": {"R": {"bound": 6}, "L": {"bound": 3}, "C": {"bound": 2}, "H": {"bound": 0}}},
		"xp": {"first_harvest_crops": []}, "journey": {"version": 1, "facts": [], "unlocks": [],
			"wood": 0, "completed": [], "exploration": {"round": 0, "collected": []}, "opportunities": {}}}

func test_first_batch_recommends_tilled_plots_then_an_available_world_action() -> void:
	var st := _state()
	var cells := {}
	# 自由种植：荒地不进状态，CTA 只对已开垦的地提建议。
	for i in 3: cells["%d,0" % i] = {"state": "tilled", "crop": null}
	var first := NextStep.bulk(cells, 0, st, "R", ["R", "L"])
	assert_int(first.cells.size()).is_equal(3)
	for id in first.cells: cells[id] = {"state": "growing", "crop": "R", "ready_at": 180000}
	var next := NextStep.bulk(cells, 1000, st, "R", ["R", "L"])
	assert_str(next.action).is_equal("explore")
	assert_str(next.place).is_equal("nursery")
	assert_bool(PlaceCatalog.available(next.place, st)).is_true()

func test_bag_shows_owned_supplies_and_refreshes_without_gameplay_commands() -> void:
	var st := _state()
	st.journey.unlocks = ["bistro", "kitchen", "crop_C", "crop_H"]
	st.journey.wood = 4
	st.journey.materials = {"stone": 2, "fiber": 3}
	st.journey.workshop = {"stock": {"lantern": 2}}
	st.inventory.produce.C = 2
	st.engineering.reserved.C = 1
	st.inventory.dishes = {"salad": 1, "tea": 2}
	var transport := FakeTransport.new([])
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = st
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.target = "supplies"
	panel.setup(session)
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var texts := panel.content.find_children("*", "Label", true, false).map(func(label): return label.text)
	for expected in ["Carrot\n2 seeds / 2 harvested", "1 reserved", "Wood: 4", "Stone: 2", "Reeds: 3",
			"Copper ore: 0", "Rock salt: 0", "Vegetable salad: 1", "Chamomile tea: 2", "Rock-salt vegetable soup: 0"]:
		assert_array(texts).contains([expected])
	assert_array(texts).contains([str(JourneyProgress.data().workshop.recipes.lantern.name) + ": 2"])
	st.inventory.produce.C = 3
	st.journey.materials.copper_ore = 2
	st.journey.materials.rock_salt = 1
	st.inventory.dishes.vegetable_soup = 1
	session.state_changed.emit(st, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	texts = panel.content.find_children("*", "Label", true, false).map(func(label): return label.text)
	assert_array(texts).contains(["Carrot\n2 seeds / 3 harvested", "Copper ore: 2", "Rock salt: 1", "Rock-salt vegetable soup: 1"])
	assert_int(transport.requests.size()).is_equal(0)

func test_farm_hint_uses_the_supplied_clock_without_changing_crop_state() -> void:
	var st := _state()
	st.cells = {"a": {"state": "growing", "crop": "R", "ready_at": 180000},
		"b": {"state": "growing", "crop": "L", "ready_at": 360000},
		"c": {"state": "growing", "crop": "R", "ready_at": null}}
	var original := st.duplicate(true)
	assert_str(JourneyProgress.farm_hint(st)).is_equal("Growing")
	assert_str(JourneyProgress.farm_hint(st, 179999)).is_equal("Growing")
	assert_str(JourneyProgress.farm_hint(st, 180000)).is_equal("1 ready")
	assert_str(JourneyProgress.farm_hint(st, 360000)).is_equal("2 ready")
	assert_that(st).is_equal(original)
	st.cells.a = {"state": "tilled"}
	assert_str(JourneyProgress.farm_hint(st, 180000)).is_equal("Growing")
	st.cells.b = {"state": "sown", "crop": "L"}
	assert_str(JourneyProgress.farm_hint(st, 180000)).is_equal("Needs care")
	st.cells.clear()
	assert_str(JourneyProgress.farm_hint(st, 180000)).is_empty()

func test_next_batch_keeps_room_for_both_salad_ingredients() -> void:
	var st := _state()
	st.journey.unlocks = ["crop_C", "kitchen", "bistro"]
	st.xp.first_harvest_crops = ["R"]
	var cells := {"a": {"state": "tilled"}, "b": {"state": "tilled"}, "c": {"state": "tilled"}}
	var next := NextStep.bulk(cells, 0, st, "R", JourneyProgress.crops(st))
	assert_str(next.crop).is_equal("C")
	assert_int(next.cells.size()).is_equal(1)
	cells.a = {"state": "growing", "crop": "C", "ready_at": 720000}
	next = NextStep.bulk(cells, 0, st, "R", JourneyProgress.crops(st))
	assert_str(next.crop).is_equal("L")
	assert_int(next.cells.size()).is_equal(1)

func test_first_meal_ready_takes_priority_over_replanting_but_not_harvest_or_care() -> void:
	var st := _state()
	st.journey.unlocks = ["crop_C", "kitchen", "bistro"]
	st.journey.facts = ["met_nursery", "met_bistro", "workbench", "planter_crafted"]
	st.xp.first_harvest_crops = ["R"]
	st.inventory.produce.C = 1
	st.inventory.produce.L = 1
	var cells := {"a": {"state": "tilled"}, "b": {"state": "wild"}}
	var original := st.duplicate(true)
	var next := NextStep.bulk(cells, 1000, st, "R", JourneyProgress.crops(st))
	assert_str(next.action).is_equal("explore")
	assert_str(next.place).is_equal("bistro")
	assert_str(next.label).is_equal("Prepare a fresh salad")
	assert_str(JourneyProgress.next_goal(st).label).is_equal(next.label)
	assert_that(st).is_equal(original)
	cells.a = {"state": "growing", "ready_at": 1000}
	assert_str(NextStep.bulk(cells, 1000, st, "R", JourneyProgress.crops(st)).action).is_equal("harvest")
	cells.a = {"state": "sown", "crop": "R"}
	assert_str(NextStep.bulk(cells, 1000, st, "R", JourneyProgress.crops(st)).action).is_equal("water")
	cells.a = {"state": "tilled"}
	st.inventory.dishes.salad = 1
	assert_str(NextStep.bulk(cells, 1000, st, "R", JourneyProgress.crops(st)).label).is_equal("Share your first meal")
	st.journey.facts.append("shared_meal")
	assert_str(NextStep.bulk(cells, 1000, st, "R", JourneyProgress.crops(st)).action).is_equal("sow")
	st.journey.facts.erase("shared_meal")
	st.inventory.dishes.salad = 0
	st.engineering.reserved.C = 1
	assert_that(JourneyProgress.first_meal_goal(st)).is_empty()

func test_surplus_sale_preserves_first_meal_and_first_flower() -> void:
	var st := _state()
	st.inventory.produce = {"R": 3, "L": 2, "C": 1, "H": 1}
	st.inventory.dishes.salad = 1
	var stall := auto_free(StallSheet.new()) as StallSheet
	add_child(stall)
	stall.refresh(st, ["R", "L", "C", "H"])
	assert_that(stall._sell_items).is_equal([{"kind": "produce", "id": "R", "qty": 3}, {"kind": "produce", "id": "L", "qty": 1}])
	assert_int(st.inventory.produce.C).is_equal(1)

func test_growing_recipe_ingredients_offer_a_world_goal_with_empty_plots_left() -> void:
	var st := _state()
	st.journey.unlocks = ["crop_C", "kitchen", "bistro"]
	st.xp.first_harvest_crops = ["R"]
	var cells := {"a": {"state": "growing", "crop": "C", "ready_at": 720000},
		"b": {"state": "growing", "crop": "L", "ready_at": 360000}, "c": {"state": "tilled"}}
	assert_str(NextStep.bulk(cells, 0, st, "R", JourneyProgress.crops(st)).action).is_equal("explore")
	assert_str(NextStep.step_for(cells.c, 0)).is_equal("sow")

func test_material_trails_and_project_readiness_match_the_inventory() -> void:
	var st := _state()
	st.journey.exploration.route = "riverside"
	var node: Dictionary = JourneyProgress.nodes(st, "courtyard")[0]
	assert_that(JourneyProgress.node_materials(st, node)).is_equal({"wood": 1, "stone": 3})
	st.journey.facts = ["workbench"]
	st.journey.wood = 2
	st.journey.materials = {"stone": 2, "fiber": 0}
	assert_bool(JourneyProgress.project_ready(st, "seedbeds")).is_true()
	st.journey.facts.append("project_seedbeds_0")
	assert_bool(JourneyProgress.project_ready(st, "seedbeds")).is_false()
	st.inventory.produce.L = 1
	st.journey.materials.fiber = 2
	assert_bool(JourneyProgress.project_ready(st, "seedbeds")).is_true()

func test_planter_can_rotate_move_undo_and_save_its_orientation() -> void:
	var st := _state()
	st.journey.facts = ["planter_crafted"]
	var session := FarmSession.new(ApiClient.new())
	session.state = st
	var panel := auto_free(DecorationPanel.new()) as DecorationPanel
	panel.setup(session)
	add_child(panel)
	await get_tree().process_frame
	assert_str(panel.selected_prop).is_equal("planter")
	assert_bool(panel.place_selected()).is_true()
	assert_bool(panel.rotate_selected()).is_true()
	assert_int(panel.preview()[0].rotation_q).is_equal(1)
	assert_bool(panel.place_at(Vector3(-2, 0, 2))).is_true()
	assert_int(panel.preview()[0].rotation_q).is_equal(1)
	panel.undo()
	var want: Array = DecorationLayout.data().props.planter.default_cell
	assert_that(panel.preview()[0].cell).is_equal([int(want[0]), int(want[1])])
	var saved := panel.preview()
	assert_bool(DecorationLayout.is_valid(saved)).is_true()
	saved[0].rotation_q = 4
	assert_bool(DecorationLayout.is_valid(saved)).is_false()

func test_one_undo_restores_an_entire_drag_and_canceled_drag_keeps_the_original() -> void:
	var st := _state()
	st.journey.facts = ["planter_crafted"]
	var session := FarmSession.new(ApiClient.new())
	session.state = st
	var panel := auto_free(DecorationPanel.new()) as DecorationPanel
	panel.setup(session)
	add_child(panel)
	await get_tree().process_frame
	panel.place_selected()
	var original := panel.preview()
	panel.begin_drag()
	panel.place_at(Vector3(-2.5, 0, 2))
	panel.place_at(Vector3(-2, 0, 1.5))
	panel.end_drag()
	panel.undo()
	assert_that(panel.preview()).is_equal(original)
	panel.begin_drag()
	panel.place_at(Vector3(-2, 0, 1.5))
	panel.end_drag(true)
	assert_that(panel.preview()).is_equal(original)
