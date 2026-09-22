extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0, "last_effective_now": 1000}, "wallet": 80, "xp": {"first_harvest_crops": ["R"]},
		"inventory": {"produce": {}, "dishes": {}, "seeds": {"R": {"bound": 3}, "L": {"bound": 2}, "H": {"bound": 2}}},
		"cells": {}, "engineering": {"reserved": {}}, "journey": {"version": 1, "completed": [],
		"facts": ["met_nursery", "met_bistro", "shared_meal", "workbench", "planter_crafted", "planter_placed", "side_path", "planter_planted"],
		"unlocks": ["bistro", "kitchen", "crop_C", "crop_H", "tea"], "wood": 3, "materials": {"stone": 0, "fiber": 0},
		"tracked_project": "terrace", "exploration": {"round": 1, "collected": []}, "opportunities": {}}}

func test_project_goal_moves_from_material_to_cooking_to_actual_construction() -> void:
	var st := _state()
	var goal := JourneyProgress.next_goal(st)
	assert_str(goal.place).is_equal("bistro")
	assert_str(goal.target).is_equal("bistro_west")
	assert_str(goal.hint).is_equal("Reeds 0/2")
	st.journey.materials.fiber = 2
	assert_str(JourneyProgress.next_goal(st).target).is_equal("project_terrace")
	st.journey.facts.append("project_terrace_0")
	st.inventory.produce = {"C": 1, "L": 1, "H": 1}
	assert_str(JourneyProgress.next_goal(st).target).is_equal("counter")
	assert_str(JourneyProgress.next_goal(st).hint).is_equal("Prepare Salad")
	st.inventory.dishes.salad = 1
	st.inventory.produce.C = 0
	st.inventory.produce.L = 0
	assert_str(JourneyProgress.next_goal(st).hint).is_equal("Prepare Tea")
	st.inventory.dishes.tea = 1
	st.inventory.produce.H = 0
	assert_str(JourneyProgress.next_goal(st).target).is_equal("project_terrace")
	st.journey.facts.append("project_terrace_1")
	assert_that(JourneyProgress.tracked_goal(st)).is_equal({})

func test_manual_seed_selection_overrides_exploration_and_project_crop_recommendations() -> void:
	var st := _state()
	st.journey.erase("tracked_project")
	var cells := {"a": {"crop": "C", "state": "growing", "ready_at": 2000},
		"b": {"state": "tilled"}, "c": {"state": "tilled"}, "d": {"state": "tilled"}}
	assert_str(NextStep.bulk(cells, 1000, st, "L", CropInfo.ORDER).action).is_equal("explore")
	var manual := NextStep.bulk(cells, 1000, st, "L", CropInfo.ORDER, true)
	assert_str(manual.label).is_equal("Sow 2 Lettuce")
	assert_array(manual.cells).is_equal(["b", "c"])
	st.journey.tracked_project = "terrace"
	st.journey.facts.append("project_terrace_0")
	st.cells = cells
	assert_str(NextStep.bulk(cells, 1000, st, "H", CropInfo.ORDER).crop).is_equal("L")
	manual = NextStep.bulk(cells, 1000, st, "H", CropInfo.ORDER, true)
	assert_str(manual.crop).is_equal("H")
	assert_int(manual.cells.size()).is_equal(2)
	assert_str(st.journey.tracked_project).is_equal("terrace")

func test_manual_seed_selection_keeps_harvest_and_water_priority() -> void:
	var st := _state()
	var cells := {"a": {"crop": "C", "state": "growing", "ready_at": 1000},
		"b": {"crop": "R", "state": "sown"}, "c": {"state": "tilled"}}
	assert_str(NextStep.bulk(cells, 1000, st, "H", CropInfo.ORDER, true).action).is_equal("harvest")
	cells.erase("a")
	assert_str(NextStep.bulk(cells, 1000, st, "H", CropInfo.ORDER, true).action).is_equal("water")
	cells.erase("b")
	assert_str(NextStep.bulk(cells, 1000, st, "H", CropInfo.ORDER, true).crop).is_equal("H")

func test_manual_seed_selection_without_seeds_or_unlock_falls_back_to_guidance() -> void:
	var st := _state()
	var cells := {"a": {"state": "tilled"}}
	var automatic := NextStep.bulk(cells, 1000, st, "C", CropInfo.ORDER)
	assert_dict(NextStep.bulk(cells, 1000, st, "C", CropInfo.ORDER, true)).is_equal(automatic)
	automatic = NextStep.bulk(cells, 1000, st, "H", ["R", "L"])
	assert_dict(NextStep.bulk(cells, 1000, st, "H", ["R", "L"], true)).is_equal(automatic)

func test_manual_seed_selection_preserves_first_harvest_guidance() -> void:
	var st := _state()
	st.xp.first_harvest_crops = []
	st.journey.erase("tracked_project")
	var cells := {"a": {"crop": "R", "state": "growing", "ready_at": 2000}, "b": {"state": "tilled"}}
	assert_dict(NextStep.bulk(cells, 1000, st, "L", CropInfo.ORDER, true)).is_equal(
		NextStep.bulk(cells, 1000, st, "L", CropInfo.ORDER))

func test_crop_plan_avoids_duplicate_planting_and_returns_to_natural_harvest() -> void:
	var st := _state()
	st.journey.facts.append("project_terrace_0")
	st.cells = {"0,0": {"crop": "C", "state": "growing", "ready_at": 2000}, "1,0": {"crop": null, "state": "tilled"}}
	assert_str(JourneyProgress.needed_crop(st, st.cells)).is_equal("L")
	assert_str(JourneyProgress.tracked_goal(st, 1000).hint).is_equal("Grow Lettuce")
	var bulk := NextStep.bulk(st.cells, 1000, st, "R", ["R", "L", "C", "H"])
	assert_str(bulk.action).is_equal("sow")
	assert_str(bulk.crop).is_equal("L")
	assert_int(bulk.cells.size()).is_equal(1)
	assert_str(JourneyProgress.tracked_goal(st, 2000).action).is_equal("harvest")
	assert_str(JourneyProgress.tracked_goal(st, 2000).crop).is_equal("C")

func test_missing_seeds_opens_stall_and_growing_crops_leave_an_active_alternative() -> void:
	var st := _state()
	st.journey.facts.append("project_terrace_0")
	st.inventory.dishes.tea = 1
	st.inventory.produce.L = 1
	st.cells = {"0,0": {"crop": null, "state": "tilled"}}
	var bulk := NextStep.bulk(st.cells, 1000, st, "R", ["R", "L", "C", "H"])
	assert_str(bulk.action).is_equal("stall")
	assert_str(bulk.crop).is_equal("C")
	assert_bool(bulk.label.contains("Carrot")).is_true()
	st.cells["0,0"] = {"crop": "C", "state": "growing", "ready_at": 2000}
	assert_str(JourneyProgress.tracked_goal(st, 1000).action).is_equal("wait")
	bulk = NextStep.bulk(st.cells, 1000, st, "R", ["R", "L", "C", "H"])
	assert_str(bulk.action).is_equal("explore")
	assert_str(bulk.place).is_not_equal("farm")

func test_owned_facilities_and_spent_routes_point_to_the_real_source() -> void:
	var st := _state()
	st.journey.facts.append_array(["project_terrace_0", "project_seedbeds_0", "project_seedbeds_1"])
	st.inventory.dishes.salad = 1
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("project_seedbeds")
	st.journey.exploration.collected.append("seedbeds")
	assert_str(JourneyProgress.tracked_goal(st).place).is_equal("farm")
	st.journey.facts.append_array(["crafted_lantern", "discovery_kitchen_garden"])
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("harvest:kitchen_garden:flowers")
	st.journey.facts.erase("project_terrace_0")
	st.journey.exploration.collected.append_array(["bistro_west", "bistro_east"])
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("trail")

func test_project_cost_plan_counts_prepared_dishes_and_reservations() -> void:
	var st := _state()
	st.journey.facts.append("project_terrace_0")
	st.inventory.dishes.salad = 1
	assert_int(JourneyProgress.project_crop_needs(st, "terrace").get("C", 0)).is_equal(0)
	assert_int(JourneyProgress.project_crop_needs(st, "terrace").H).is_equal(1)
	st.inventory.produce.H = 1
	st.engineering.reserved.H = 1
	assert_str(JourneyProgress.tracked_goal(st).hint).is_equal("Grow Chamomile")

func test_tea_preparation_can_refresh_an_exhausted_nursery_basket_without_waiting() -> void:
	var st := _state()
	st.journey.facts.append_array(["project_terrace_0", "project_seedbeds_0", "project_seedbeds_1"])
	st.inventory.dishes.salad = 1
	st.inventory.seeds.H = {"bound": 0}
	st.journey.exploration.collected = ["nursery_west", "nursery_east", "side_path", "seedbeds"]
	var original := st.duplicate(true)
	var goal := JourneyProgress.tracked_goal(st, 1000)
	assert_str(goal.place).is_equal("nursery")
	assert_str(goal.target).is_equal("trail")
	assert_str(goal.hint).is_equal("Start a nursery trail for chamomile")
	assert_str(goal.action).is_equal("gather")
	assert_str(NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER).target).is_equal("trail")
	assert_dict(st).is_equal(original)
	st.journey.exploration.collected = []
	assert_str(JourneyProgress.tracked_goal(st, 1000).target).is_equal("project_seedbeds")
	st.inventory.produce.H = 1
	assert_str(JourneyProgress.tracked_goal(st, 1000).target).is_equal("counter")

func test_ready_or_uncared_chamomile_keeps_priority_over_refreshing_the_nursery() -> void:
	var st := _state()
	st.journey.facts.append_array(["project_terrace_0", "project_seedbeds_0", "project_seedbeds_1"])
	st.inventory.dishes.salad = 1
	st.journey.exploration.collected = ["nursery_west", "nursery_east", "side_path", "seedbeds"]
	st.cells = {"0,0": {"crop": "H", "state": "growing", "ready_at": 1000}}
	assert_str(JourneyProgress.tracked_goal(st, 1000).action).is_equal("harvest")
	st.cells["0,0"].state = "sown"
	assert_str(JourneyProgress.tracked_goal(st, 1000).action).is_equal("water")

func test_unavailable_and_complete_projects_are_not_trackable_client_goals() -> void:
	var st := _state()
	st.journey.facts.erase("shared_meal")
	assert_that(JourneyProgress.tracked_goal(st)).is_equal({})
	assert_that(JourneyProgress.project_goal(st, "missing")).is_equal({})
	var goals := JourneyProgress.goals(st).filter(func(goal): return str(goal.id).begins_with("project_"))
	assert_int(goals.size()).is_equal(3)

func test_available_project_seeds_take_priority_over_unrelated_selected_radishes() -> void:
	var st := _state()
	st.journey.facts.append("project_terrace_0")
	st.cells = {"0,0": {"state": "tilled", "crop": null}, "1,0": {"state": "tilled", "crop": null}}
	assert_str(JourneyProgress.tracked_goal(st).hint).is_equal("Grow Lettuce")
	var bulk := NextStep.bulk(st.cells, 1000, st, "R", ["R", "L", "C", "H"])
	assert_str(bulk.crop).is_equal("L")
	assert_int(bulk.cells.size()).is_equal(1)

func test_map_tracks_crop_maturity_without_moving_entrances_or_changing_state() -> void:
	var st := _state()
	st.journey.facts.append("project_terrace_0")
	st.inventory.dishes.salad = 1
	st.cells = {"0,0": {"state": "growing", "crop": "H", "ready_at": 2000}}
	var original := st.duplicate(true)
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(360, 640)
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 12, 10)
	camera.look_at(Vector3.ZERO)
	var map := JourneyMap.new()
	viewport.add_child(map)
	var area := Rect2(0, 110, 360, 480)
	map.sync(camera, Vector3.ZERO, area, st, true, 1999)
	assert_str(map.status_labels.farm.text).is_equal("Chamomile growing")
	var positions := {}
	for id in map.buttons: positions[id] = map.buttons[id].get_global_rect()
	map.sync(camera, Vector3.ZERO, area, st, true, 2000)
	assert_str(map.status_labels.farm.text).is_equal("Harvest Chamomile")
	assert_str(map.buttons.farm.tooltip_text).is_equal("My farm: Harvest Chamomile")
	for id in map.buttons: assert_that(map.buttons[id].get_global_rect()).is_equal(positions[id])
	assert_that(st).is_equal(original)

func test_goal_seed_purchase_is_visible_without_scrolling_or_an_automatic_trade() -> void:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(360, 640)
	add_child(viewport)
	var sheet := StallSheet.new()
	viewport.add_child(sheet)
	var st := _state()
	st.inventory.produce = {"R": 2, "L": 2, "C": 2, "H": 2}
	st.inventory.dishes = {"salad": 2, "tea": 2}
	sheet.refresh(st, ["R", "L", "C", "H"])
	sheet.open()
	sheet.fit_height(Vector2(340, 620))
	var trades := []
	sheet.buy_requested.connect(func(crop, qty): trades.append([crop, qty]))
	await sheet.focus_seed("H")
	for frame in 3: await get_tree().process_frame
	assert_bool(sheet._scroll.get_global_rect().encloses(sheet._seed_rows.H.box.get_global_rect())).is_true()
	assert_int(sheet._buy_qty).is_equal(1)
	assert_array(trades).is_empty()

func test_surplus_sales_preserve_tracked_ingredients_then_prepared_dishes() -> void:
	var sheet := auto_free(StallSheet.new()) as StallSheet
	add_child(sheet)
	var st := _state()
	st.journey.facts.append("project_terrace_0")
	st.inventory.produce = {"R": 2, "C": 2, "L": 1, "H": 1}
	st.engineering.reserved.C = 1
	var trades := []
	sheet.sell_requested.connect(func(items): trades.append(items.duplicate(true)))
	sheet.refresh(st, ["R", "L", "C", "H"])
	sheet._sell_all.pressed.emit()
	assert_that(trades.pop_back()).is_equal([{"kind": "produce", "id": "R", "qty": 2}])
	sheet._produce_rows.C.button.pressed.emit()
	assert_that(trades.pop_back()).is_equal([{"kind": "produce", "id": "C", "qty": 1}])
	st.inventory.dishes = {"salad": 2, "tea": 1}
	sheet.refresh(st, ["R", "L", "C", "H"])
	sheet._sell_all.pressed.emit()
	var expected := [{"kind": "produce", "id": "R", "qty": 2},
		{"kind": "produce", "id": "L", "qty": 1}, {"kind": "produce", "id": "C", "qty": 1},
		{"kind": "produce", "id": "H", "qty": 1}, {"kind": "dish", "id": "salad", "qty": 1}]
	assert_that(trades.pop_back()).is_equal(expected)
	st.journey.erase("tracked_project")
	sheet.refresh(st, ["R", "L", "C", "H"])
	sheet._sell_all.pressed.emit()
	expected[-1].qty = 2
	expected.append({"kind": "dish", "id": "tea", "qty": 1})
	assert_that(trades.pop_back()).is_equal(expected)
