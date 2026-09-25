extends GdUnitTestSuite

func test_reclaimed_pond_cells_are_walkable_cultivable_and_placeable() -> void:
	var profiles := [[FarmPlot.blueprint_for(), Vector2i(12,41)]]
	for filename in ["retired_compact_farm_terrain.json", "retired_shoreline_farm_terrain.json"]:
		var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + filename))
		var old_pond: Dictionary = terrain.plot.regions.filter(func(r): return r.get("id") == "pond")[0]
		profiles.append([FarmPlot.register_terrain(terrain),Vector2i(old_pond.ellipse[0],old_pond.ellipse[1])])
	for profile in profiles:
		var bp: FarmBlueprint = profile[0]
		var cell: Vector2i = profile[1]
		assert_bool(FarmPlot.verify_checksum(bp)).is_true()
		assert_bool(bp.is_walkable(cell)).is_true()
		assert_bool(bp.mask_has("cultivable",cell)).is_true()
		assert_bool(bp.mask_has("buildable",cell)).is_true()
		var grid := BlueprintGrid.new(bp)
		assert_array(grid.point_path(bp.cell_to_world(bp.anchor("spawn")),bp.cell_to_world(cell))).is_not_empty()
		var image := FarmTerrainMask.texture_for(bp).get_image()
		var pixel := Vector2i(Vector2(cell) / Vector2(bp.grid) * Vector2(image.get_size()))
		assert_float(image.get_pixelv(pixel).b).is_less(.5)

func test_generation_three_matches_the_server_and_keeps_real_water() -> void:
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_pondless_farm_terrain.json"))
	var bp := FarmPlot.register_terrain(terrain)
	assert_object(bp).is_not_null()
	assert_bool(FarmPlot.verify_checksum(bp)).is_true()
	assert_vector(bp.grid).is_equal(Vector2i(40,40))
	assert_int(int(terrain.source.generator_version)).is_equal(3)
	assert_array(terrain.plot.regions.filter(func(r): return r.get("id") == "pond")).is_empty()
	assert_array(terrain.plot.regions.filter(func(r): return r.kind == "water" and r.has("polygon"))).is_not_empty()
