extends GdUnitTestSuite

func test_entrances_track_world_positions_without_reflow_and_activate_nearest() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	add_child(auto_free(viewport))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 800
	viewport.add_child(camera)
	camera.position = Vector3(0, 500, 500)
	camera.look_at(Vector3.ZERO)
	var map := JourneyMap.new()
	viewport.add_child(map)
	var area := Rect2(0, 110, 390, 650)
	var state := {"journey": {"version": 1, "unlocks": ["bistro"], "facts": []}, "clock": {"chapter_index": 0}}
	var selected := []
	map.place_requested.connect(func(id): selected.append(id))
	for shift in [0, 20, 80, 100]:
		camera.position.x = shift
		map.sync(camera, Vector3.ZERO, area, state, false)
		for id in map.buttons:
			var button: Button = map.buttons[id]
			if not button.visible: continue
			assert_vector(button.position + Vector2(40, 16)).is_equal_approx(camera.unproject_position(JourneyMap.OFFSETS[id]), Vector2.ONE * 0.01)
			assert_vector(button.size).is_equal(Vector2(80, 54))
		var bistro: Button = map.buttons.bistro
		assert_bool(map.activate_at(bistro.get_global_rect().get_center())).is_true()
	assert_array(selected).is_equal(["bistro", "bistro", "bistro", "bistro"])

func test_farm_marker_reports_maturity_without_moving_or_resizing() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	add_child(auto_free(viewport))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 800
	viewport.add_child(camera)
	camera.position = Vector3(0, 500, 500)
	camera.look_at(Vector3.ZERO)
	var map := JourneyMap.new()
	viewport.add_child(map)
	var st := {"journey": {"version": 1, "facts": [], "unlocks": []},
		"cells": {"a": {"state": "growing", "ready_at": 1000}}}
	var area := Rect2(0, 110, 360, 480)
	map.sync(camera, Vector3.ZERO, area, st, true, 999)
	assert_str(map.status_labels.farm.text).is_equal("Growing")
	var rect: Rect2 = map.buttons.farm.get_global_rect()
	map.sync(camera, Vector3.ZERO, area, st, true, 1000)
	assert_str(map.status_labels.farm.text).is_equal("1 ready")
	assert_that(map.buttons.farm.get_global_rect()).is_equal(rect)
	st.cells.a = {"state": "tilled"}
	map.sync(camera, Vector3.ZERO, area, st, true, 1001)
	assert_str(map.status_labels.farm.text).is_empty()

func test_configured_map_projects_the_street_entrances_without_repositioning_them() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	add_child(auto_free(viewport))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 800
	viewport.add_child(camera)
	camera.position = Vector3(0, 500, 500)
	camera.look_at(Vector3.ZERO)
	var map := JourneyMap.new()
	map.configure(FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b", 2)))
	viewport.add_child(map)
	var state := {"journey": {"version": 1, "unlocks": ["bistro"], "facts": [], "exploration": {"collected": []}}, "clock": {"chapter_index": 0}}
	var area := Rect2(0, 110, 390, 650)
	for shift in [0, 20, 80]:
		camera.position.x = shift
		map.sync(camera, Vector3.ZERO, area, state, false)
		for id in map.points:
			assert_vector(map.points[id]).is_equal_approx(camera.unproject_position(map.streets.offset_for(id)), Vector2.ONE * 0.01)
		assert_int(map._roads.size()).is_equal(map.streets.roads.size())
	map.sync(camera, Vector3.ZERO, area, state, true)
	var before: Dictionary = map.points.duplicate()
	state.journey.facts.append("side_path")
	map.sync(camera, Vector3.ZERO, area, state, true)
	assert_that(map.points).is_equal(before)
