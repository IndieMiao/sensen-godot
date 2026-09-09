extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"journey": {"version": 1, "facts": ["workbench", "side_path"], "unlocks": ["bistro"], "wood": 0,
		"exploration": {"round": 1, "collected": [], "routes_by_place": {"nursery": "woodland", "courtyard": "riverside"}, "branching_places": ["nursery", "courtyard"]}}}

func test_existing_trail_only_keeps_its_original_bundle() -> void:
	var st := _state()
	st.journey.exploration.erase("branching_places")
	var node: Dictionary = JourneyProgress.nodes(st, "nursery")[0]
	var bundles := JourneyProgress.node_bundles(st, node)
	assert_int(bundles.size()).is_equal(1)
	assert_dict(bundles[0].materials).is_equal({"wood": 2})

func test_new_trail_has_distinct_materials_and_physical_targets() -> void:
	var st := _state()
	var node: Dictionary = JourneyProgress.nodes(st, "nursery")[0]
	var bundles := JourneyProgress.node_bundles(st, node)
	assert_int(bundles.size()).is_equal(2)
	assert_str(bundles[1].id).is_equal("bundle:nursery_west")
	assert_dict(bundles[1].materials).is_equal({"stone": 1.0})
	assert_array(bundles[1].position).is_not_equal(bundles[0].position)
	assert_str(JourneyProgress.place_hint(st, "nursery")).is_equal("Wood or stone")
	assert_str(JourneyProgress._material_goal(st, "stone").target).is_equal("bundle:nursery_west")

func test_unlock_and_collected_node_remove_the_alternative_from_guidance() -> void:
	var st := _state()
	st.journey.facts.erase("side_path")
	var node: Dictionary = JourneyProgress.nodes(st, "nursery")[0]
	assert_int(JourneyProgress.node_bundles(st, node).size()).is_equal(1)
	st.journey.facts.append("side_path")
	st.journey.exploration.collected.append("nursery_west")
	assert_str(JourneyProgress._material_goal(st, "stone").target).is_equal("bundle:nursery_east")
	st.journey.exploration.collected.append_array(["nursery_east", "side_path"])
	assert_str(JourneyProgress.bundle_hint(st, "nursery")).is_empty()
	assert_bool(JourneyProgress.route_ready(st, "woodland")).is_true()

func _bistro_choice_state() -> Dictionary:
	var st := _state()
	st.journey.facts.append_array(["met_nursery", "met_bistro", "shared_meal", "planter_crafted", "planter_placed", "planter_planted",
		"project_seedbeds_0", "project_seedbeds_1", "story_nursery_seeds", "story_nursery_bloom", "story_restorer_craft", "story_restorer_light"])
	st.journey.wood = 1
	st.journey.materials = {"stone": 1, "fiber": 1}
	st.journey.exploration.routes_by_place.bistro = "gardens"
	st.journey.exploration.branching_places.append("bistro")
	st.journey.exploration.collected = ["nursery_west", "nursery_east", "side_path", "courtyard_west", "courtyard_east", "bistro_west", "seedbeds"]
	return st

func test_material_guidance_selects_the_larger_matching_bundle_at_the_same_node() -> void:
	var st := _bistro_choice_state()
	var original := st.duplicate(true)
	assert_str(JourneyProgress._material_goal(st, "wood").target).is_equal("bundle:bistro_east")
	assert_str(JourneyProgress._material_goal(st, "fiber").target).is_equal("bistro_east")
	var goal := JourneyProgress.next_goal(st)
	assert_str(goal.target).is_equal("bundle:bistro_east")
	assert_str(goal.label).is_equal("Collect 3 wood for Neighbourhood tea terrace")
	st.journey.tracked_project = "terrace"
	assert_str(JourneyProgress.next_goal(st).target).is_equal("bundle:bistro_east")
	assert_str(JourneyProgress.next_goal(st).hint).is_equal("Wood 1/3")
	st.journey.erase("tracked_project")
	assert_dict(st).is_equal(original)

func test_material_guidance_keeps_old_trails_and_consumed_choices_unavailable() -> void:
	var st := _bistro_choice_state()
	st.journey.exploration.branching_places.erase("bistro")
	assert_str(JourneyProgress._material_goal(st, "wood").target).is_equal("bistro_east")
	st.journey.exploration.branching_places.append("bistro")
	st.journey.exploration.collected.append("bistro_east")
	assert_str(JourneyProgress._material_goal(st, "wood").target).is_equal("trail")
