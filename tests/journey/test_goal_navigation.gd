extends GdUnitTestSuite

func _state() -> Dictionary:
	var st := {"clock": {"chapter_index": 0}, "xp": {"first_harvest_crops": ["R"]}, "wallet": 80,
		"inventory": {"produce": {}, "dishes": {}, "seeds": {}}, "cells": {}, "engineering": {"reserved": {}},
		"journey": {"version": 1, "completed": [], "wood": 6, "materials": {"stone": 6, "fiber": 6},
			"facts": ["met_nursery", "met_bistro", "workbench", "planter_crafted", "planter_placed", "planter_planted", "side_path", "shared_meal", "workshop_displayed"],
			"unlocks": ["bistro", "kitchen", "crop_C", "crop_H", "tea"], "opportunities": {},
			"exploration": {"round": 3, "collected": ["seedbeds"], "branching_places": ["nursery", "courtyard", "bistro"]},
			"workshop": {"stock": {}, "displays": {}}}}
	for stories in JourneyProgress.data().stories.values():
		for story in stories: st.journey.facts.append("story_" + str(story.id))
	for id in JourneyProgress.data().projects:
		for stage in 2: st.journey.facts.append("project_%s_%d" % [id, stage])
	for id in JourneyProgress.data().workshop.recipes: st.journey.facts.append("crafted_" + str(id))
	for id in JourneyProgress.data().discoveries:
		st.journey.facts.append("discovery_" + str(id))
		st.journey.exploration.collected.append("discovery_" + str(id))
	for node in JourneyProgress.nodes(st): st.journey.exploration.collected.append(node.id)
	st.journey.gathering = {"sequence": 4, "memories": ["garden", "lantern"]}
	return st

func test_completed_facilities_open_a_concrete_gathering_destination() -> void:
	var st := _state()
	st.journey.erase("gathering")
	assert_str(JourneyProgress.next_goal(st).target).is_equal("gathering:garden")
	st.journey.gathering = {"sequence": 2, "memories": ["garden"]}
	assert_str(JourneyProgress.next_goal(st).target).is_equal("gathering:lantern")

func test_ordinary_goals_point_to_actionable_objects_through_the_progression() -> void:
	for spec in [["workbench", "nursery", "workbench"], ["planter_crafted", "nursery", "workbench"],
		["planter_placed", "courtyard", "planter"], ["side_path", "nursery", "path"],
		["planter_planted", "courtyard", "planter"], ["project_seedbeds_1", "nursery", "project_seedbeds"],
		["crafted_fountain", "nursery", "workbench"]]:
		var st := _state()
		st.inventory.produce = {"H": 1, "L": 1}
		st.journey.facts.erase(spec[0])
		var original := st.duplicate(true)
		var goal := JourneyProgress.next_goal(st)
		assert_str(goal.place).is_equal(spec[1])
		assert_str(goal.target).is_equal(spec[2])
		var bulk := NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER)
		assert_str(bulk.action).is_equal("explore")
		assert_str(bulk.target).is_equal(spec[2])
		assert_that(st).is_equal(original)

func test_first_meal_keeps_host_counter_and_table_as_distinct_destinations() -> void:
	var st := _state()
	st.journey.facts.erase("shared_meal")
	st.journey.facts.erase("met_bistro")
	st.inventory.produce = {"C": 1, "L": 1}
	var host := JourneyProgress.first_meal_goal(st)
	assert_str(host.resident).is_equal("bistro_owner")
	assert_str(host.target).is_equal("resident")
	st.journey.facts.append("met_bistro")
	assert_str(NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER).target).is_equal("counter")
	st.inventory.dishes.salad = 1
	assert_str(NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER).target).is_equal("table")

func _opening_state() -> Dictionary:
	var st := _state()
	st.journey.facts = ["met_nursery", "met_bistro", "workbench", "shared_meal"]
	st.journey.wood = 1
	st.journey.materials = {"stone": 0, "fiber": 0}
	st.journey.exploration = {"round": 0, "collected": ["nursery_east", "nursery_west", "courtyard_east", "courtyard_west"]}
	st.journey.erase("gathering")
	return st

func test_opening_material_goals_keep_the_current_purpose_until_ready() -> void:
	for spec in [["workbench", "the workbench", 4, "workbench"],
		["planter_crafted", "your first planter", 2, "workbench"],
		["side_path", "the garden path", 2, "path"]]:
		var st := _opening_state()
		st.journey.facts.append_array(["planter_crafted", "planter_placed"])
		st.journey.facts.erase(spec[0])
		var before := st.duplicate(true)
		var goal := JourneyProgress.next_goal(st)
		assert_str(goal.place).is_equal("bistro")
		assert_str(goal.target).is_equal("bistro_west")
		assert_str(goal.label).is_equal("Wood for %s (1/%d)" % [spec[1], spec[2]])
		assert_str(NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER).target).is_equal("bistro_west")
		assert_that(st).is_equal(before)
		st.journey.wood = spec[2]
		goal = JourneyProgress.next_goal(st)
		assert_str(goal.place).is_equal("nursery")
		assert_str(goal.target).is_equal(spec[3])

func test_first_planter_uses_a_wood_route_after_existing_supplies_are_spent() -> void:
	var st := _opening_state()
	st.journey.exploration.collected.append_array(["bistro_east", "bistro_west"])
	var goal := JourneyProgress.next_goal(st)
	assert_str(goal.place).is_equal("nursery")
	assert_str(goal.target).is_equal("trail")
	assert_str(goal.label).is_equal("Wood for your first planter (1/2)")
	assert_bool(JourneyProgress.route_ready(st, "woodland")).is_true()

func test_first_planter_material_goal_keeps_street_supply_routing() -> void:
	var st := _opening_state()
	st.journey.exploration.routes_by_place = {"bistro": "stone_walk"}
	var goal := JourneyProgress.next_goal(st)
	assert_str(goal.target).is_equal("bistro_west")
	assert_str(goal.surface).is_equal("street")
	assert_str(goal.label).is_equal("Wood for your first planter (1/2)")

func test_player_selected_project_and_ready_meal_still_override_first_planter() -> void:
	var st := _opening_state()
	st.journey.tracked_project = "seedbeds"
	assert_str(JourneyProgress.next_goal(st).project).is_equal("seedbeds")
	st.journey.erase("tracked_project")
	st.journey.facts.erase("shared_meal")
	st.inventory.dishes.salad = 1
	assert_str(JourneyProgress.next_goal(st).target).is_equal("table")

func test_restore_then_harvest_remains_visible_among_material_choices() -> void:
	var st := _state()
	st.journey.exploration.collected = ["seedbeds", "discovery_stone_hollow", "discovery_reed_garden"]
	st.journey.facts.erase("discovery_kitchen_garden")
	st.journey.workshop.stock.fountain = 1
	assert_str(JourneyProgress.bundle_hint(st, "bistro")).is_equal("Wood or reeds")
	assert_str(JourneyProgress.place_hint(st, "bistro")).is_equal("Ready to restore")
	assert_str(JourneyProgress.next_goal(st).target).is_equal("discovery_kitchen_garden")
	st.journey.facts.append("discovery_kitchen_garden")
	st.journey.workshop.stock.fountain = 0
	assert_str(JourneyProgress.place_hint(st, "bistro")).is_equal("Harvest choice")
	assert_str(JourneyProgress.next_goal(st).target).is_equal("discovery_kitchen_garden")
	st.journey.exploration.collected.append("discovery_kitchen_garden")
	assert_str(JourneyProgress.place_hint(st, "bistro")).is_equal("Wood or reeds")

func test_story_and_build_readiness_take_precedence_over_supply_labels() -> void:
	var st := _state()
	st.journey.exploration.collected = []
	st.journey.facts.erase("story_restorer_light")
	assert_str(JourneyProgress.place_hint(st, "courtyard")).is_equal("New story")
	assert_str(JourneyProgress.next_goal(st).resident).is_equal("restorer")
	st.journey.facts.append("story_restorer_light")
	st.journey.facts.erase("project_waystation_1")
	st.inventory.produce.H = 1
	assert_str(JourneyProgress.place_hint(st, "courtyard")).is_equal("Ready to build")
	assert_str(JourneyProgress.next_goal(st).target).is_equal("project_waystation")

func test_baskets_and_exhausted_routes_have_local_targets() -> void:
	var st := _state()
	st.journey.exploration.collected.erase("seedbeds")
	assert_str(JourneyProgress.next_goal(st).target).is_equal("project_seedbeds")
	st.journey.exploration.collected.append("seedbeds")
	assert_str(JourneyProgress.next_goal(st).target).is_equal("trail")

func test_facility_feedback_reports_the_accepted_exchange_and_no_reward_on_failure() -> void:
	for accepted in [false, true]:
		for spec in [["waystation", "fiber", "2 wood for 2 reeds", "-2 wood / +2 reeds"],
			["waystation", "stone", "2 wood for 2 stone", "-2 wood / +2 stone"],
			["seedbeds", "flowers", "Fresh chamomile", "+1 Chamomile"]]:
			var initial := _state()
			initial.journey.exploration.collected.erase("seedbeds")
			var result := initial.duplicate(true)
			if spec[0] == "waystation":
				result.journey.wood -= 2
				result.journey.materials[spec[1]] += 2
			else:
				result.inventory.produce.H = 1
				result.journey.exploration.collected.append("seedbeds")
			var reply := {"status": 200, "json": {"version": 2, "state": result}} if accepted else {"status": 422, "json": {"code": "INSUFFICIENT_ITEMS"}}
			var transport := FakeTransport.new([reply])
			var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
			session.state = initial
			session.version = 1
			var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
			panel.place_id = "courtyard" if spec[0] == "waystation" else "nursery"
			panel.target = "project_" + spec[0]
			panel.setup(session)
			var feedback := []
			var world := []
			panel.feedback.connect(func(message): feedback.append(message))
			panel.world_action_completed.connect(func(id): world.append(id))
			add_child(panel)
			for frame in 3: await get_tree().process_frame
			var buttons := panel.content.find_children("*", "Button", true, false).filter(func(button): return button.text == spec[2])
			assert_int(buttons.size()).is_equal(1)
			if buttons.is_empty(): continue
			buttons[0].pressed.emit()
			for frame in 5: await get_tree().process_frame
			assert_str(transport.last_body().type).is_equal("use_journey_facility")
			assert_str(transport.last_body().payload.choice).is_equal(spec[1])
			assert_array(feedback).is_equal([spec[3] if accepted else "More supplies are needed for this activity."])
			assert_array(world).is_equal(["project_" + spec[0]] if accepted else [])
			assert_that(session.state).is_equal(result if accepted else initial)
