extends GdUnitTestSuite

func _state(slot := "nursery", variant := 0) -> Dictionary:
	return {"clock": {"chapter_index": 0, "last_effective_now": 1000}, "wallet": 80, "xp": {"first_harvest_crops": ["R"]},
		"inventory": {"produce": {}, "dishes": {}, "seeds": {"R": {"bound": 3}, "L": {"bound": 2}, "H": {"bound": 2}}},
		"cells": {}, "nursery": {}, "engineering": {"reserved": {}}, "residents": {}, "journey": {"version": 1, "completed": [],
		"facts": ["met_nursery", "met_bistro", "shared_meal", "workbench", "planter_crafted", "planter_placed", "side_path", "planter_planted"],
		"unlocks": ["bistro", "kitchen", "crop_C", "crop_H", "tea", "crafting"], "wood": 0, "materials": {"stone": 0, "fiber": 0},
		"tracked_opportunity": {"slot": slot, "sequence": 4}, "exploration": {"round": 1, "collected": []},
		"opportunities": {slot: {"sequence": 4, "variant": variant, "accepted": true}}}}

func test_mixed_request_keeps_its_purpose_from_materials_to_delivery() -> void:
	var st := _state("restorer", 1)
	var before := st.duplicate(true)
	assert_str(JourneyProgress.next_goal(st).target).is_equal("nursery_west")
	assert_str(JourneyProgress.next_goal(st).label).is_equal("Supplies for the workshop: Wood 0/2")
	assert_dict(st).is_equal(before)
	st.journey.wood = 2
	assert_str(JourneyProgress.next_goal(st).crop).is_equal("R")
	st.inventory.produce.R = 1
	var goal := JourneyProgress.next_goal(st)
	assert_str(goal.resident).is_equal("restorer")
	assert_str(goal.hint).is_equal("Ready to deliver")
	var street := auto_free(JourneyStreet.new()) as JourneyStreet
	street.targets = {"courtyard": {}, "resident:restorer": {}}
	assert_str(street._goal_target_id(goal)).is_equal("resident:restorer")

func test_cooking_request_counts_reserved_produce_and_prepared_dishes() -> void:
	var st := _state("bistro")
	st.inventory.produce = {"C": 1, "L": 1}
	st.engineering.reserved.C = 1
	assert_str(JourneyProgress.next_goal(st).action).is_equal("stall")
	assert_str(JourneyProgress.next_goal(st).crop).is_equal("C")
	st.engineering.reserved.clear()
	assert_str(JourneyProgress.next_goal(st).target).is_equal("counter")
	st.inventory.dishes.salad = 1
	st.inventory.produce.clear()
	assert_int(JourneyRequests.crop_needs(st).get("C", 0)).is_equal(0)
	assert_int(JourneyRequests.crop_needs(st).get("L", 0)).is_equal(0)
	assert_str(JourneyProgress.next_goal(st).target).is_equal("table")

func test_request_crop_recommendations_cover_shortfall_and_respect_manual_seeds() -> void:
	var st := _state()
	st.cells = {"a": {"state": "growing", "crop": "L", "ready_at": 2000}, "b": {"state": "tilled"}}
	var bulk := NextStep.bulk(st.cells, 1000, st, "R", CropInfo.ORDER)
	assert_str(bulk.crop).is_equal("L")
	assert_int(bulk.cells.size()).is_equal(1)
	assert_str(NextStep.bulk(st.cells, 1000, st, "R", CropInfo.ORDER, true).crop).is_equal("R")
	st.cells.b = {"state": "growing", "crop": "L", "ready_at": 2000}
	assert_str(JourneyProgress.needed_crop(st, st.cells)).is_empty()
	assert_str(JourneyProgress.tracked_goal(st, 1000).action).is_equal("wait")
	assert_str(NextStep.bulk(st.cells, 1000, st, "R", CropInfo.ORDER).action).is_equal("explore")
	assert_str(JourneyProgress.tracked_goal(st, 2000).action).is_equal("harvest")
	st.cells.b.state = "sown"
	assert_str(JourneyProgress.tracked_goal(st, 1000).action).is_equal("water")

func test_missing_seeds_and_restored_garden_are_concrete_destinations() -> void:
	var st := _state("bistro", 1)
	st.inventory.seeds.clear()
	var bulk := NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER)
	assert_str(bulk.action).is_equal("stall")
	assert_str(bulk.crop).is_equal("H")
	st.journey.facts.append_array(["crafted_lantern", "discovery_kitchen_garden"])
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("harvest:kitchen_garden:flowers")
	st.inventory.produce.H = 1
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("counter")

func test_stale_cancelled_or_locked_request_cannot_become_the_next_offer() -> void:
	for change in ["sequence", "cancel", "lock"]:
		var st := _state("bistro", 1)
		match change:
			"sequence": st.journey.opportunities.bistro.sequence += 1
			"cancel": st.journey.erase("tracked_opportunity")
			"lock": st.journey.unlocks.erase("tea")
		var before := st.duplicate(true)
		assert_dict(JourneyRequests.goal(st)).is_empty()
		assert_dict(JourneyRequests.crop_needs(st)).is_empty()
		assert_dict(st).is_equal(before)

func test_surplus_sales_keep_request_ingredients_and_then_its_prepared_meal() -> void:
	var sheet := auto_free(StallSheet.new()) as StallSheet
	add_child(sheet)
	var st := _state("bistro")
	st.inventory.produce = {"R": 2, "C": 2, "L": 1}
	st.engineering.reserved.C = 1
	var trades := []
	sheet.sell_requested.connect(func(items): trades.append(items.duplicate(true)))
	sheet.refresh(st, CropInfo.ORDER)
	sheet._sell_all.pressed.emit()
	assert_array(trades.pop_back()).is_equal([{"kind": "produce", "id": "R", "qty": 2}])
	st.inventory.dishes.salad = 2
	sheet.refresh(st, CropInfo.ORDER)
	sheet._sell_all.pressed.emit()
	assert_array(trades.pop_back()).is_equal([{"kind": "produce", "id": "R", "qty": 2},
		{"kind": "produce", "id": "L", "qty": 1}, {"kind": "produce", "id": "C", "qty": 1}, {"kind": "dish", "id": "salad", "qty": 1}])
	sheet._dish_rows.salad.button.pressed.emit()
	assert_array(trades.pop_back()).is_equal([{"kind": "dish", "id": "salad", "qty": 1}])

func test_tracking_and_cancellation_wait_for_server_acceptance() -> void:
	for tracking in [true, false]:
		for accepted in [true, false]:
			var st := _state()
			if tracking: st.journey.erase("tracked_opportunity")
			var result := st.duplicate(true)
			if tracking: result.journey.tracked_opportunity = {"slot": "nursery", "sequence": 4}
			else: result.journey.erase("tracked_opportunity")
			var reply := {"status": 200, "json": {"version": 2, "state": result}} if accepted else {"status": 422, "json": {"code": "REQUEST_DONE"}}
			var responses := [reply]
			if not accepted: responses.append({"status": 200, "json": {"version": 1, "state": st}})
			var transport := FakeTransport.new(responses)
			var panel := await _panel(st, transport)
			var goals := []
			panel.goal_requested.connect(func(goal): goals.append(goal))
			var button := panel.content.find_child("TrackRequest_nursery", true, false) as Button
			button.pressed.emit()
			for frame in 5: await get_tree().process_frame
			assert_str(transport.requests[0].body.type).is_equal("track_journey_opportunity")
			assert_dict(transport.requests[0].body.payload).is_equal({"slot": "nursery", "sequence": 4.0, "tracking": tracking})
			assert_int(transport.requests.size()).is_equal(1 if accepted else 2)
			if not accepted: assert_str(transport.requests[1].method).is_equal("GET")
			assert_dict(panel.session.state).is_equal(result if accepted else st)
			assert_array(goals).is_empty()

func test_lost_tracking_response_recovers_exact_command_and_ui() -> void:
	var st := _state()
	var result := st.duplicate(true)
	st.journey.erase("tracked_opportunity")
	var transport := FakeTransport.new([
		{"error": "lost confirmation"}, {"error": "lost confirmation"},
		{"status": 200, "json": {"version": 2, "state": result}},
		{"status": 200, "json": {"version": 2, "state": result}}])
	var panel := await _panel(st, transport)
	var button := panel.content.find_child("TrackRequest_nursery", true, false) as Button
	button.pressed.emit()
	for frame in 5: await get_tree().process_frame
	assert_bool(panel.session.has_unconfirmed_command()).is_true()
	assert_dict(panel.session.state).is_equal(st)
	var reconnect := panel.content.find_child("ReconnectSession", true, false) as Button
	reconnect.pressed.emit()
	for frame in 5: await get_tree().process_frame
	assert_bool(panel.session.has_unconfirmed_command()).is_false()
	assert_dict(panel.session.state).is_equal(result)
	assert_int(transport.requests.size()).is_equal(4)
	for request in transport.requests.slice(0, 3): assert_dict(request.body).is_equal(transport.requests[0].body)
	button = panel.content.find_child("TrackRequest_nursery", true, false) as Button
	assert_str(button.tooltip_text).is_equal("Stop tracking request")
	assert_str(JourneyProgress.tracked_goal(panel.session.state).crop).is_equal("L")

func test_place_request_navigation_closes_panel_and_runs_to_local_material() -> void:
	var st := _state("restorer")
	var scene := auto_free(JourneyPlace.new()) as JourneyPlace
	scene.place_id = "nursery"
	scene.session = FarmSession.new(ApiClient.new("https://example.test/v1", FakeTransport.new().callable()))
	scene.session.state = st
	add_child(scene)
	scene.set_process(false)
	for frame in 3: await get_tree().process_frame
	scene._show_panel("street_offer:restorer")
	for frame in 3: await get_tree().process_frame
	scene.active_panel.goal_requested.emit(JourneyRequests.goal(st))
	assert_bool(scene.panel.visible).is_false()
	assert_str(scene.pending_target).is_equal("nursery_west")
	assert_bool(scene.mover.is_moving()).is_true()

func test_street_request_navigation_preserves_seed_purchase_and_table_target() -> void:
	var st := _state("bistro")
	st.inventory.produce.L = 1
	var street := auto_free(JourneyStreet.new()) as JourneyStreet
	street.session = FarmSession.new(ApiClient.new("https://example.test/v1", FakeTransport.new().callable()))
	street.session.layout_patch_id = "sh_a"
	street.session.blueprint_revision = 2
	street.session.state = st
	add_child(street)
	street.set_process(false)
	for frame in 3: await get_tree().process_frame
	for prepared in [false, true]:
		if prepared: st.inventory.dishes.salad = 1
		street._show_dialogue("bistro")
		for frame in 3: await get_tree().process_frame
		var goal := JourneyRequests.goal(st)
		street.active_panel.goal_requested.emit(goal)
		assert_bool(street.dialogue.visible).is_false()
		assert_str(street.pending).is_equal("bistro" if prepared else "farm")
		assert_dict(street._destination_goal).is_equal(goal)
		if prepared: assert_str(street._destination_goal.target).is_equal("table")
		else:
			assert_str(street._destination_goal.action).is_equal("stall")
			assert_str(street._destination_goal.crop).is_equal("C")

func _panel(st: Dictionary, transport: FakeTransport) -> JourneyActivityPanel:
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "street"
	panel.target = "street_offer:nursery"
	panel.setup(FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable())))
	panel.session.state = st
	panel.session.version = 1
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	return panel
