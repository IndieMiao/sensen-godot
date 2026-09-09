extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 40, "inventory": {"produce": {"R": 2, "L": 2, "C": 2, "H": 2}, "dishes": {"tea": 2, "salad": 2}},
		"engineering": {"reserved": {}}, "journey": {"version": 1, "facts": ["workbench", "met_nursery", "planter_crafted", "side_path"],
		"unlocks": ["bistro", "gifts"], "completed": [], "wood": 10, "materials": {"stone": 10, "fiber": 10},
		"exploration": {"round": 3, "collected": ["courtyard_west", "courtyard_east"]}, "opportunities": {}}}

func test_each_route_uses_its_own_remaining_nodes_and_reward_history() -> void:
	var st := _state()
	assert_bool(JourneyProgress.route_ready(st, "riverside")).is_true()
	assert_bool(JourneyProgress.route_ready(st, "woodland")).is_false()
	st.journey.exploration.routes_by_place = {"nursery": "woodland", "courtyard": "riverside"}
	st.journey.exploration.route = "gardens"
	assert_int(JourneyProgress.node_materials(st, JourneyProgress.nodes(st, "nursery")[0]).wood).is_equal(2)
	assert_int(JourneyProgress.node_materials(st, JourneyProgress.nodes(st, "courtyard")[0]).stone).is_equal(3)
	assert_int(JourneyProgress.node_materials(st, JourneyProgress.nodes(st, "bistro")[0]).fiber).is_equal(1)

func test_gift_button_reflects_exploration_eligibility_including_old_saves() -> void:
	var st := _state()
	st.residents = {"nursery_keeper": {"gifts_given": 2}}
	assert_bool(JourneyProgress.gift_ready(st, "nursery_keeper")).is_true()
	st.journey.gift_rounds = {"nursery_keeper": 3}
	var session := FarmSession.new(ApiClient.new())
	session.state = st
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "nursery"
	panel.target = "resident"
	panel.setup(session)
	add_child(panel)
	await get_tree().process_frame
	var gift: Button
	for child in panel.content.get_children():
		if child is Button and child.text.begins_with("Give a "): gift = child
	assert_object(gift).is_not_null()
	assert_bool(gift.disabled).is_true()
	st.journey.exploration.round = 4
	assert_bool(JourneyProgress.gift_ready(st, "nursery_keeper")).is_true()

func test_workshop_gates_recipes_by_actions_and_reads_owned_stock() -> void:
	var st := _state()
	var recipes: Dictionary = JourneyProgress.data().workshop.recipes
	assert_bool(JourneyProgress.requirements_met(st, recipes.lantern)).is_true()
	assert_bool(JourneyProgress.requirements_met(st, recipes.fountain)).is_false()
	st.journey.facts.append("crafted_lantern")
	assert_bool(JourneyProgress.requirements_met(st, recipes.fountain)).is_true()
	st.journey.materials.stone = 0
	assert_bool(JourneyProgress.cost_ready(st, recipes.fountain)).is_false()
	st.journey.workshop = {"sequence": 2, "stock": {"planter": 2}, "displays": {"seedbeds": ["lantern", "", ""]}}
	assert_int(JourneyProgress.stock(st, "planter")).is_equal(2)
	assert_array(JourneyProgress.display_items(st, "seedbeds")).is_equal(["lantern", "", ""])

func test_resident_waits_for_the_scene_prerequisite_before_showing_the_next_story() -> void:
	var st := _state()
	st.journey.facts.erase("workbench")
	var session := FarmSession.new(ApiClient.new())
	session.state = st
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "nursery"
	panel.target = "resident"
	panel.setup(session)
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	var story: Dictionary = JourneyProgress.data().stories.nursery_keeper[0]
	var labels := panel.content.find_children("*", "Label", true, false).map(func(label): return label.text)
	assert_bool(labels.has(story.hint)).is_false()
	var buttons := panel.content.find_children("*", "Button", true, false).filter(func(button): return button.text == story.name)
	assert_array(buttons).is_empty()
	st.journey.facts.append("workbench")
	panel.refresh()
	for frame in 3: await get_tree().process_frame
	labels = panel.content.find_children("*", "Label", true, false).map(func(label): return label.text)
	assert_bool(labels.has(story.hint)).is_true()
	buttons = panel.content.find_children("*", "Button", true, false).filter(func(button): return button.text == story.name)
	assert_int(buttons.size()).is_equal(1)
	assert_bool(buttons[0].disabled).is_false()

func test_host_leads_first_meal_to_world_objects_before_repeat_orders() -> void:
	var st := _state()
	st.journey.facts.append("met_bistro")
	st.journey.unlocks.append("kitchen")
	st.journey.opportunities.bistro = {"sequence": 0, "variant": 0}
	st.inventory.dishes.salad = 0
	var session := FarmSession.new(ApiClient.new())
	session.state = st
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "bistro"
	panel.target = "resident"
	panel.setup(session)
	var destinations := []
	panel.target_requested.connect(func(id): destinations.append(id))
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	var buttons := panel.content.find_children("*", "Button", true, false)
	assert_bool(buttons.any(func(button): return button.text.begins_with("Deliver"))).is_false()
	var counter: Button = buttons.filter(func(button): return button.text == "Visit the prep counter")[0]
	assert_bool(counter.disabled).is_false()
	var original := st.duplicate(true)
	counter.pressed.emit()
	assert_array(destinations).is_equal(["counter"])
	assert_that(st).is_equal(original)
	st.inventory.dishes.salad = 1
	panel.refresh()
	for frame in 3: await get_tree().process_frame
	buttons = panel.content.find_children("*", "Button", true, false)
	assert_bool(buttons.any(func(button): return button.text.begins_with("Deliver"))).is_false()
	var table: Button = buttons.filter(func(button): return button.text == "Take a seat at the table")[0]
	assert_bool(table.disabled).is_false()
	table.pressed.emit()
	assert_array(destinations).is_equal(["counter", "table"])
	assert_int(st.inventory.dishes.salad).is_equal(1)
	st.journey.facts.append("shared_meal")
	panel.refresh()
	for frame in 3: await get_tree().process_frame
	buttons = panel.content.find_children("*", "Button", true, false)
	assert_bool(buttons.any(func(button): return button.text.begins_with("Deliver"))).is_false()
	var serve: Button = buttons.filter(func(button): return button.text == "Serve at the table")[0]
	serve.pressed.emit()
	assert_array(destinations).is_equal(["counter", "table", "table"])
	assert_int(st.inventory.dishes.salad).is_equal(1)
	assert_bool(buttons.any(func(button): return button.text == "Take a seat at the table")).is_false()

func test_map_opportunities_and_goals_continue_after_basic_milestones() -> void:
	var st := _state()
	st.journey.completed = JourneyProgress.data().milestones.map(func(m): return m.id)
	assert_str(JourneyProgress.place_hint(st, "nursery")).is_equal("New story")
	assert_int(JourneyProgress.goals(st).size()).is_greater(6)
	st.journey.facts.append("story_nursery_seeds")
	assert_str(JourneyProgress.place_hint(st, "nursery")).is_equal("Ready to build")
	st.journey.materials.stone = 0
	assert_bool(JourneyProgress.place_hint(st, "nursery").begins_with("Timber")).is_true()

func test_displayed_pieces_block_walking_without_cutting_off_facilities() -> void:
	var st := _state()
	st.journey.workshop = {"displays": {"seedbeds": ["planter", "lantern", "fountain"], "terrace": ["planter", "lantern", "fountain"], "waystation": ["planter", "lantern", "fountain"]}}
	for id in JourneyProgress.data().projects:
		var project: Dictionary = JourneyProgress.data().projects[id]
		var scene := auto_free(JourneyPlace.new()) as JourneyPlace
		scene.place_id = str(project.place)
		scene.session = FarmSession.new(ApiClient.new())
		scene.session.state = st
		scene._build_navigation()
		for slot in 3:
			var position := JourneyProjects.display_position(str(id), slot)
			assert_bool(scene.nav.is_walkable(scene.nav.world_to_cell(position - JourneyPlace.NAV_ORIGIN))).is_false()
		scene.marker_layer = Control.new()
		scene.add_child(scene.marker_layer)
		var project_position := Vector3(project.position[0], 0, project.position[1])
		scene._add_target(str(id), str(project.name), "hammer", project_position, project_position + Vector3(0, 0, 1.5))
		var approach: Vector3 = scene.targets[id].approach - JourneyPlace.NAV_ORIGIN
		var grid := BlueprintGrid.new(scene.nav)
		assert_bool(grid.path(scene.nav.anchors.spawn, scene.nav.world_to_cell(approach)).is_empty()).is_false()

func test_side_path_repair_opens_a_connected_passage_beside_the_well() -> void:
	var st := _state()
	st.journey.facts.erase("side_path")
	var scene := auto_free(JourneyPlace.new()) as JourneyPlace
	scene.session = FarmSession.new(ApiClient.new())
	scene.session.state = st
	scene._build_navigation()
	var exit := Vector3(4.2, 0, -1.5) - JourneyPlace.NAV_ORIGIN
	assert_bool(scene.mover.set_target_position(exit)).is_false()
	st.journey.facts.append("side_path")
	scene._build_navigation()
	assert_bool(scene.mover.set_target_position(exit)).is_true()
	var previous := scene.mover.position
	var grid := BlueprintGrid.new(scene.nav)
	for waypoint in scene.mover.remaining_path():
		assert_bool(grid.segment_walkable(previous, waypoint)).is_true()
		previous = waypoint
	assert_bool(scene.nav.is_walkable(scene.nav.world_to_cell(Vector3(3.15, 0, -1.1) - JourneyPlace.NAV_ORIGIN))).is_false()
	assert_bool(scene.nav.is_walkable(scene.nav.world_to_cell(Vector3(4.2, 0, -2.3) - JourneyPlace.NAV_ORIGIN))).is_false()

func test_visiting_keeper_uses_own_story_and_gift_eligibility() -> void:
	var st := _state()
	st.journey.gift_rounds = {"nursery_keeper": 3}
	var session := FarmSession.new(ApiClient.new())
	session.state = st
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "bistro"
	panel.target = "resident:nursery_keeper"
	panel.setup(session)
	add_child(panel)
	await get_tree().process_frame
	assert_str(panel.content.get_child(0).text).is_equal(str(ResidentCast.definition("nursery_keeper").name))
	var gifts := panel.content.find_children("*", "Button", true, false).filter(func(button): return button.text.begins_with("Give a "))
	assert_bool(gifts.is_empty()).is_false()
	for gift in gifts: assert_bool(gift.disabled).is_true()

func test_visiting_resident_reserves_the_standing_area_when_terrace_opens() -> void:
	var st := _state()
	var scene := auto_free(JourneyPlace.new()) as JourneyPlace
	scene.place_id = "bistro"
	scene.session = FarmSession.new(ApiClient.new())
	scene.session.state = st
	scene._build_navigation()
	var guest := scene.nav.world_to_cell(ResidentCast.journey_position("bistro", "nursery_keeper") - JourneyPlace.NAV_ORIGIN)
	assert_bool(scene.nav.is_walkable(guest)).is_true()
	for chair_x in [1.19, 2.81]:
		assert_bool(scene.nav.is_walkable(scene.nav.world_to_cell(Vector3(chair_x, 0, 0.3) - JourneyPlace.NAV_ORIGIN))).is_false()
	st.journey.facts.append_array(["project_terrace_0", "project_terrace_1"])
	scene._build_navigation()
	assert_bool(scene.nav.is_walkable(guest)).is_false()
	assert_bool(scene.mover.set_target_position(Vector3(0, 0, 1.2) - JourneyPlace.NAV_ORIGIN)).is_true()
