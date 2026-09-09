extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 50, "engineering": {"reserved": {}},
		"inventory": {"produce": {}, "dishes": {}}, "journey": {"version": 1, "completed": [],
		"facts": ["workbench", "planter_crafted", "planter_placed", "met_bistro", "shared_meal", "side_path", "crafted_lantern"],
		"unlocks": ["bistro", "crop_H"], "wood": 4, "materials": {"stone": 0, "fiber": 3},
		"exploration": {"round": 2, "collected": []}, "workshop": {"sequence": 0, "stock": {}, "displays": {}}}}

func test_pinned_goal_follows_materials_craft_and_install_instead_of_generic_supplies() -> void:
	var st := _state()
	st.journey.tracked_discovery = "stone_hollow"
	assert_str(JourneyProgress.next_goal(st).place).is_equal("courtyard")
	assert_str(JourneyProgress.place_hint(st, "courtyard")).is_equal("Stone 0/2")
	st.journey.materials.stone = 2
	assert_str(JourneyProgress.next_goal(st).place).is_equal("nursery")
	assert_str(JourneyProgress.place_hint(st, "nursery")).is_equal("Ready to make")
	st.journey.workshop.stock.lantern = 1
	assert_bool(JourneyProgress.discovery_ready(st, "stone_hollow")).is_true()
	assert_str(JourneyProgress.place_hint(st, "nursery")).is_equal("Ready to restore")
	st.journey.facts.append("discovery_stone_hollow")
	assert_that(JourneyProgress.tracked_goal(st)).is_equal({})
	var goals := JourneyProgress.goals(st).filter(func(goal): return str(goal.id).begins_with("discovery_"))
	assert_int(goals.size()).is_equal(3)
	assert_int(goals.filter(func(goal): return goal.done).size()).is_equal(1)

func test_tracking_reuses_a_displayed_piece_and_completed_corners_supply_future_crafts() -> void:
	var st := _state()
	st.journey.tracked_discovery = "stone_hollow"
	st.journey.workshop.displays.terrace = ["lantern", "", ""]
	assert_str(JourneyProgress.tracked_goal(st).place).is_equal("bistro")
	assert_str(JourneyProgress.tracked_goal(st).hint).is_equal("Collect your piece")
	st.journey.workshop.displays = {}
	st.journey.facts.append("discovery_stone_hollow")
	st.journey.tracked_discovery = "kitchen_garden"
	assert_str(JourneyProgress.tracked_goal(st).place).is_equal("nursery")
	st.journey.exploration.collected.append("discovery_stone_hollow")
	assert_str(JourneyProgress.tracked_goal(st).place).is_equal("courtyard")

func test_claimed_corner_offers_no_second_reward_and_only_enables_its_local_route() -> void:
	var st := _state()
	st.journey.facts.append("discovery_reed_garden")
	st.journey.discovery_choices = {"reed_garden": "seeds"}
	st.journey.exploration.collected = ["discovery_reed_garden", "courtyard_west", "courtyard_east"]
	assert_bool(JourneyProgress.discovery_harvest_ready(st, "reed_garden")).is_false()
	var session := FarmSession.new(ApiClient.new())
	session.state = st
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.target = "discovery_reed_garden"
	panel.place_id = "courtyard"
	panel.setup(session)
	add_child(panel)
	await get_tree().process_frame
	var buttons: Array = panel.content.find_children("*", "Button", true, false)
	assert_int(buttons.size()).is_equal(1)
	assert_bool(buttons[0].disabled).is_false()
	assert_str(buttons[0].text).is_equal("Start another courtyard trail")

func test_all_corners_have_visible_world_changes_and_reachable_approaches() -> void:
	for id in JourneyProgress.data().discoveries:
		var st := _state()
		var before := auto_free(JourneyProjects.build_discovery(str(id), st)) as Node3D
		assert_bool(before.has_node("InstalledPiece")).is_false()
		st.journey.facts.append("discovery_" + str(id))
		var after := auto_free(JourneyProjects.build_discovery(str(id), st)) as Node3D
		assert_bool(after.has_node("InstalledPiece")).is_true()
		assert_bool(after.get_meta("harvest_ready")).is_true()
		var scene := auto_free(JourneyPlace.new()) as JourneyPlace
		scene.place_id = str(JourneyProgress.data().discoveries[id].place)
		scene.session = FarmSession.new(ApiClient.new())
		scene.session.state = st
		scene._build_navigation()
		var position := JourneyProjects.discovery_position(str(id))
		assert_bool(scene.nav.is_walkable(scene.nav.world_to_cell(position - JourneyPlace.NAV_ORIGIN))).is_false()
		scene.marker_layer = Control.new()
		scene.add_child(scene.marker_layer)
		scene._add_target(str(id), str(id), "compass", position, position + Vector3(0, 0, 1.05))
		var approach: Vector3 = scene.targets[id].approach - JourneyPlace.NAV_ORIGIN
		assert_bool(scene.mover.set_target_cell(scene.nav.world_to_cell(approach))).is_true()
