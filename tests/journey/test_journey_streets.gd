extends GdUnitTestSuite

func test_packaged_streets_connect_four_distinct_entrances_and_cache_choices() -> void:
	for id in ["sh_a", "sh_b", "sh_c", "la_a", "la_b", "la_c", "safe_grid"]:
		var source := FarmBlueprint.load_file(FarmBlueprint.asset_path(id, 2))
		var streets := JourneyStreets.new(source)
		assert_int(streets.roads.size()).is_equal(source.paths.size() + int(streets.has_farm_access))
		assert_vector(streets.offset_for("farm")).is_equal(Vector3.ZERO)
		for place in streets.entrances:
			var entrance: Vector3 = streets.entrances[place]
			assert_float(streets.road_distance(entrance)).is_less_equal(JourneyStreets.WIDTH)
			assert_array(streets.grid.point_path(streets.entrances.farm, entrance)).is_not_empty()
			for other in streets.entrances:
				if other != place: assert_float(entrance.distance_to(streets.entrances[other])).is_greater_equal(7)
		for pair in streets.caches.values():
			for point in pair: assert_array(streets.grid.point_path(streets.entrances.farm, point)).is_not_empty()

func test_restored_shortcut_changes_walkable_connections_without_relocating_places() -> void:
	var source := FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b", 2))
	var before := JourneyStreets.new(source)
	var after := JourneyStreets.new(source, true)
	assert_that(after.entrances).is_equal(before.entrances)
	assert_that(after.caches).is_equal(before.caches)
	assert_int(after.roads.size()).is_equal(before.roads.size() + 1)
	assert_that(after.nav.masks).is_not_equal(before.nav.masks)
	var old_path := before.grid.path(before.nav.world_to_cell(before.entrances.nursery), before.nav.world_to_cell(before.entrances.courtyard))
	var new_path := after.grid.path(after.nav.world_to_cell(after.entrances.nursery), after.nav.world_to_cell(after.entrances.courtyard))
	assert_int(new_path.size()).is_less(old_path.size())

func test_street_and_place_supply_represent_the_same_receipt() -> void:
	var state := {"journey": {"version": 1, "facts": ["workbench", "side_path"], "unlocks": ["bistro"],
		"exploration": {"round": 3, "collected": [], "branching_places": ["nursery"]}}}
	var node := JourneyStreets.street_node(state, "nursery")
	assert_str(node.id).is_equal("nursery_east")
	assert_int(JourneyProgress.node_bundles(state, node).size()).is_equal(2)
	state.journey.exploration.collected.append("nursery_east")
	assert_dict(JourneyStreets.street_node(state, "nursery")).is_empty()

func test_work_areas_leave_roads_and_existing_targets_clear_in_every_layout() -> void:
	for id in ["sh_a", "sh_b", "sh_c", "la_a", "la_b", "la_c", "safe_grid"]:
		var source := FarmBlueprint.load_file(FarmBlueprint.asset_path(id, 2))
		var before := JourneyStreets.new(source)
		var after := JourneyStreets.new(source, true)
		assert_that(after.commons).is_equal(before.commons)
		for common in after.commons.values():
			assert_array(after.grid.point_path(after.entrances.farm, common.approach)).is_not_empty()
			for point in after.entrances.values(): assert_float(point.distance_to(common.approach)).is_greater_equal(2.4)
			assert_float(after.road_distance(common.position)).is_greater_equal(2.1)
			for point in after.buildings.values(): assert_float(point.distance_to(common.position)).is_greater_equal(4.5)
			for pair in after.caches.values():
				for point in pair:
					assert_float(point.distance_to(common.position)).is_greater_equal(3)
					assert_float(point.distance_to(common.approach)).is_greater_equal(2.4)

func test_street_growth_uses_only_completed_contributions_and_changes_geometry() -> void:
	var state := {"journey": {"opportunities": {"restorer": {"sequence": 99}}}}
	assert_int(StreetCommons.count(state, "benches")).is_equal(0)
	for slot in StreetCommons.PLACES:
		var surfaces: Array = []
		for stage in [0, 1, 3]:
			state.journey.contributions = {}
			for effect in StreetCommons.EFFECTS: state.journey.contributions[effect] = stage
			var area := StreetCommons.build(slot, state)
			var mesh := area.get_child(0) as MeshInstance3D
			surfaces.append(mesh.mesh.surface_get_array_len(0))
			area.free()
		assert_int(surfaces[1]).is_greater(surfaces[0])
		assert_int(surfaces[2]).is_greater(surfaces[1])
