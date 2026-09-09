extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 40, "inventory": {"produce": {"R": 2, "L": 0, "C": 0, "H": 1}, "dishes": {"tea": 1, "salad": 0}},
		"engineering": {"reserved": {}}, "residents": {"nursery_keeper": {"points": 17}, "bistro_owner": {"points": 27}},
		"journey": {"version": 1, "facts": ["met_nursery", "met_bistro", "workbench", "planter_crafted", "planter_placed", "planter_planted", "side_path", "shared_meal", "story_nursery_seeds", "project_seedbeds_0", "project_seedbeds_1"],
		"unlocks": ["bistro", "kitchen", "tea", "gifts", "crop_H"], "completed": [], "wood": 0, "materials": {},
		"exploration": {"round": 3, "collected": ["seedbeds"]}, "opportunities": {"nursery": {"sequence": 1, "variant": 1}, "bistro": {"sequence": 0, "variant": 0}}}}

func test_goal_routes_to_the_same_resident_or_their_place_when_absent() -> void:
	var goal := JourneyProgress.next_goal(_state())
	assert_str(goal.resident).is_equal("nursery_keeper")
	assert_str(goal.target).is_equal("resident")
	var street := auto_free(JourneyStreet.new()) as JourneyStreet
	street.targets = {"nursery": {}, "resident:nursery": {}, "bundle:nursery_east": {}}
	assert_str(street._goal_target_id(goal)).is_equal("resident:nursery")
	goal.label = "A different localized title"
	assert_str(street._goal_target_id(goal)).is_equal("resident:nursery")
	street.targets.erase("resident:nursery")
	assert_str(street._goal_target_id(goal)).is_equal("nursery")
	assert_str(street._goal_target_id({"place": "nursery", "target": "bundle:nursery_east"})).is_equal("bundle:nursery_east")
	assert_str(street._goal_target_id({"place": "nursery", "target": "workbench"})).is_equal("nursery")
	assert_str(street._goal_target_id({"place": "unknown"})).is_empty()

func test_early_nursery_conversation_prioritizes_workbench_but_keeps_requests_available() -> void:
	for surface in ["street", "nursery"]:
		var initial := _state()
		initial.journey.facts = ["met_nursery"]
		initial.journey.unlocks = []
		var original := initial.duplicate(true)
		var session := FarmSession.new(ApiClient.new())
		session.state = initial
		var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
		panel.place_id = surface
		panel.target = "resident:nursery_keeper"
		panel.setup(session)
		var destinations := []
		panel.destination_requested.connect(func(id): destinations.append(id))
		panel.target_requested.connect(func(id): destinations.append(id))
		add_child(panel)
		for frame in 3: await get_tree().process_frame
		var buttons := panel.content.find_children("*", "Button", true, false)
		assert_bool(buttons.any(func(button): return button.text.begins_with("Deliver -"))).is_false()
		var visit: Button = buttons.filter(func(button): return button.text == ("Visit the nursery" if surface == "street" else "Inspect the workbench"))[0]
		visit.pressed.emit()
		assert_array(destinations).is_equal(["nursery" if surface == "street" else "workbench"])
		var optional: Button = buttons.filter(func(button): return button.text == "Anything else you need?")[0]
		optional.pressed.emit()
		for frame in 3: await get_tree().process_frame
		buttons = panel.content.find_children("*", "Button", true, false)
		assert_bool(buttons.any(func(button): return button.text.begins_with("Deliver -"))).is_true()
		assert_that(session.state).is_equal(original)
		panel.refresh()
		for frame in 3: await get_tree().process_frame
		buttons = panel.content.find_children("*", "Button", true, false)
		assert_bool(buttons.any(func(button): return button.text.begins_with("Deliver -"))).is_true()
		initial.journey.facts.append("workbench")
		panel.refresh()
		for frame in 3: await get_tree().process_frame
		buttons = panel.content.find_children("*", "Button", true, false)
		assert_bool(buttons.any(func(button): return button.text == "Inspect the workbench" or button.text == "Visit the nursery")).is_false()
		assert_bool(buttons.any(func(button): return button.text.begins_with("Deliver -"))).is_true()

func test_street_story_has_the_same_command_and_only_responds_after_acceptance() -> void:
	for accepted in [false, true]:
		var initial := _state()
		var result := initial.duplicate(true)
		result.inventory.produce.H = 0
		result.journey.facts.append("story_nursery_bloom")
		result.residents.nursery_keeper.points += 25
		var reply := {"status": 200, "json": {"version": 2, "state": result}} if accepted else {"status": 422, "json": {"code": "INSUFFICIENT_ITEMS"}}
		var transport := FakeTransport.new([reply])
		var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
		session.state = initial
		session.version = 1
		var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
		panel.place_id = "street"
		panel.target = "resident:nursery_keeper"
		panel.setup(session)
		var responses := []
		panel.resident_interaction_completed.connect(func(id): responses.append(id))
		add_child(panel)
		for frame in 3: await get_tree().process_frame
		var buttons := panel.content.find_children("*", "Button", true, false)
		var story: Button = buttons.filter(func(button): return button.text == "A garden together")[0]
		assert_bool(story.disabled).is_false()
		assert_bool(buttons.any(func(button): return button.text == "Deliver - 18 coins")).is_true()
		story.pressed.emit()
		for frame in 5: await get_tree().process_frame
		assert_int(transport.requests.size()).is_equal(1)
		assert_str(transport.last_body().type).is_equal("complete_journey_story")
		assert_str(transport.last_body().payload.resident_id).is_equal("nursery_keeper")
		assert_str(transport.last_body().payload.story).is_equal("nursery_bloom")
		assert_array(responses).is_equal(["nursery_keeper"] if accepted else [])
		assert_that(session.state).is_equal(result if accepted else initial)

func test_street_gift_uses_shared_eligibility_and_success_feedback() -> void:
	var initial := _state()
	var result := initial.duplicate(true)
	result.inventory.produce.R -= 1
	result.journey.gift_rounds = {"bistro_owner": 3}
	var transport := FakeTransport.new([{"status": 200, "json": {"version": 2, "state": result}}])
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = initial
	session.version = 1
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "street"
	panel.target = "resident:bistro_owner"
	panel.setup(session)
	var responses := []
	panel.resident_interaction_completed.connect(func(id): responses.append(id))
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	var buttons := panel.content.find_children("*", "Button", true, false)
	var gift: Button = buttons.filter(func(button): return button.text == "Give a Radish")[0]
	gift.pressed.emit()
	for frame in 5: await get_tree().process_frame
	assert_str(transport.last_body().type).is_equal("give_gift")
	assert_str(transport.last_body().payload.resident_id).is_equal("bistro_owner")
	assert_str(transport.last_body().payload.crop).is_equal("R")
	assert_array(responses).is_equal(["bistro_owner"])
	buttons = panel.content.find_children("*", "Button", true, false)
	gift = buttons.filter(func(button): return button.text == "Give a Radish")[0]
	assert_bool(gift.disabled).is_true()

func test_street_host_sends_first_meal_to_bistro_and_keeps_repeat_delivery_in_street() -> void:
	var initial := _state()
	initial.journey.facts.erase("shared_meal")
	var session := FarmSession.new(ApiClient.new())
	session.state = initial
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "street"
	panel.target = "resident:bistro_owner"
	panel.setup(session)
	var destinations := []
	panel.destination_requested.connect(func(id): destinations.append(id))
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	var buttons := panel.content.find_children("*", "Button", true, false)
	var meet: Button = buttons.filter(func(button): return button.text == "Meet at the bistro")[0]
	meet.pressed.emit()
	assert_array(destinations).is_equal(["bistro"])
	initial.journey.facts.append("shared_meal")
	initial.inventory.dishes.salad = 1
	panel.refresh()
	for frame in 3: await get_tree().process_frame
	buttons = panel.content.find_children("*", "Button", true, false)
	assert_bool(buttons.any(func(button): return button.text == "Deliver - 28 coins" and not button.disabled)).is_true()
	assert_bool(buttons.any(func(button): return button.text == "Meet at the bistro")).is_false()

func test_resident_works_beside_an_occupied_work_spot_without_crossing_player() -> void:
	for layout_id in ["sh_a", "safe_grid"]:
		var layout := JourneyStreets.new(FarmBlueprint.load_file(FarmBlueprint.asset_path(layout_id, 2)), true)
		for slot in StreetCommons.PLACES:
			var residents := auto_free(StreetResidents.new()) as StreetResidents
			residents.layout = layout
			residents.player_position = layout.commons[slot].approach
			var actor := auto_free(Node3D.new()) as Node3D
			for point in residents.nearby(residents.player_position, 5):
				if point.distance_to(residents.player_position) >= 2.4:
					actor.position = point
					break
			var moment := ResidentMoment.new(actor, Vector3.ZERO)
			residents.moments[slot] = moment
			residents.respond(slot)
			var movement := residents.route(moment.destination, slot)
			assert_object(movement).is_not_null()
			for frame in 300:
				var before := actor.position
				moment.step(1.0 / 60, false, residents.route.bind(slot), residents.step_clear.bind(slot))
				assert_float(actor.position.distance_to(before)).is_less_equal(3.75 / 60 + 0.001)
				assert_float(actor.position.distance_to(residents.player_position)).is_greater_equal(StreetResidents.CLEARANCE)
				if moment.phase == "reacting": break
			assert_str(moment.phase).is_equal("reacting")
			assert_float(actor.position.distance_to(layout.commons[slot].approach)).is_less_equal(1.5)
			moment.home = residents.player_position
			moment.finish()
			assert_object(residents.route(moment.home, slot)).is_null()
