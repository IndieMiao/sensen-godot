extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 80, "xp": {"first_harvest_crops": ["R"]},
		"cells": {}, "inventory": {"produce": {}, "dishes": {}, "seeds": {}}, "engineering": {"reserved": {}},
		"journey": {"version": 1, "facts": ["met_nursery", "met_bistro", "workbench", "side_path"],
			"unlocks": ["bistro", "crafting"], "wood": 0, "materials": {}, "completed": [],
			"tracked_project": "waystation", "exploration": {"round": 3,
				"collected": ["nursery_west", "nursery_east", "side_path", "courtyard_west", "courtyard_east"],
				"routes_by_place": {"bistro": "stone_walk"}, "branching_places": ["bistro"]}}}

func test_walk_stops_are_distinct_reachable_and_do_not_move_when_shortcut_opens() -> void:
	for id in ["sh_a", "sh_b", "sh_c", "la_a", "la_b", "la_c", "safe_grid"]:
		var source := FarmBlueprint.load_file(FarmBlueprint.asset_path(id, 2))
		var closed := JourneyStreets.new(source)
		var opened := JourneyStreets.new(source, true)
		assert_dict(opened.walk_caches).is_equal(closed.walk_caches)
		var west: Vector3 = opened.walk_caches.bistro_west[0]
		var east: Vector3 = opened.walk_caches.bistro_east[0]
		assert_float(west.distance_to(east)).is_greater(5)
		for pair in opened.walk_caches.values():
			for point in pair:
				assert_array(opened.grid.point_path(opened.entrances.farm, point)).is_not_empty()
				for building in opened.buildings.values(): assert_float(point.distance_to(building)).is_greater(3.5)
				for common in opened.commons.values(): assert_float(point.distance_to(common.position)).is_greater(3.5)

func test_material_goal_and_farm_recommendation_retain_the_street_destination() -> void:
	var st := _state()
	var goal := JourneyProgress.tracked_goal(st)
	assert_str(goal.surface).is_equal("street")
	assert_str(goal.target).is_equal("bistro_west")
	assert_str(goal.hint).is_equal("Stone 0/3")
	var action := NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER)
	assert_str(action.action).is_equal("explore")
	assert_str(action.surface).is_equal("street")
	assert_str(action.target).is_equal("bistro_west")
	assert_dict(JourneyProgress.node_materials(st, JourneyProgress.remaining_nodes(st, "bistro")[0])).is_equal({"wood": 1, "stone": 2, "fiber": 1})
	st.journey.exploration.routes_by_place.bistro = "gardens"
	assert_bool(JourneyProgress.tracked_goal(st).has("surface")).is_false()

func test_map_exposes_only_unclaimed_walk_stops_at_stable_world_anchors() -> void:
	var st := _state()
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(390, 844)
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var map := JourneyMap.new()
	map.configure(FarmBlueprint.load_file(FarmBlueprint.asset_path("safe_grid", 2)))
	viewport.add_child(map)
	var destinations := []
	map.street_requested.connect(func(id): destinations.append(id))
	var area := Rect2(0, 100, 390, 620)
	map.sync(camera, Vector3.ZERO, area, st, true)
	var west: Button = map._walk_buttons.bistro_west
	var east: Button = map._walk_buttons.bistro_east
	assert_bool(west.visible).is_true()
	assert_bool(east.visible).is_true()
	var original := east.position
	assert_bool(map.activate_at(west.get_global_rect().get_center())).is_true()
	assert_array(destinations).is_equal(["bistro_west"])
	st.journey.exploration.collected.append("bistro_west")
	map.sync(camera, Vector3.ZERO, area, st, true)
	assert_bool(west.visible).is_false()
	assert_vector(east.position).is_equal(original)
	st.journey.exploration.routes_by_place.bistro = "gardens"
	map.sync(camera, Vector3.ZERO, area, st, true)
	assert_bool(east.visible).is_false()

func test_ongoing_walk_can_resume_without_issuing_a_refresh_command() -> void:
	var session := FarmSession.new(ApiClient.new())
	session.state = _state()
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "bistro"
	panel.target = "trail"
	panel.setup(session)
	var destinations := []
	panel.destination_requested.connect(func(id): destinations.append(id))
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	var buttons := panel.content.find_children("*", "Button", true, false)
	var resume: Button = buttons.filter(func(b): return b.text == "Continue the stone walk")[0]
	assert_bool(resume.disabled).is_false()
	resume.pressed.emit()
	assert_array(destinations).is_equal(["street"])
	assert_int(session.state.journey.exploration.round).is_equal(3)
