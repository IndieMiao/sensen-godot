extends GdUnitTestSuite

const COMPACT := "res://tests/fixtures/generated_compact_farm_terrain.json"
const LEGACY := "res://tests/fixtures/generated_farm_terrain.json"

func _compact() -> FarmBlueprint:
	return FarmPlot.register_terrain(JSON.parse_string(FileAccess.get_file_as_string(COMPACT)))

func test_compact_pond_geometry_and_shore_come_from_its_terrain_without_changing_shared_content() -> void:
	var original := FishingModel.site("farm_pond").duplicate(true)
	var bp := _compact()
	assert_object(bp).is_not_null()
	var pond := FishingModel.site_for_plot("farm_pond", bp)
	assert_float(float(pond.center[0])).is_equal_approx(6.4, 0.00001)
	assert_float(float(pond.center[1])).is_equal_approx(-26.4, 0.00001)
	assert_float(float(pond.radii[0])).is_equal_approx(3.84, 0.00001)
	assert_float(float(pond.radii[1])).is_equal_approx(2.48, 0.00001)
	assert_float(FishingModel.stand("farm_pond", pond).x).is_equal_approx(6.8, 0.00001)
	assert_float(FishingModel.stand("farm_pond", pond).z).is_equal_approx(-22.8, 0.00001)
	assert_that(FishingModel.site("farm_pond")).is_equal(original)
	pond.center[0] = -100.0
	assert_that(FishingModel.site("farm_pond")).is_equal(original)
	assert_float(float(FishingModel.site_for_plot("farm_pond", bp).center[0])).is_equal_approx(6.4, 0.00001)

func test_compact_cast_planning_automatically_uses_the_host_grid_and_rejects_the_old_pond() -> void:
	var bp := _compact()
	var grid := BlueprintGrid.new(bp)
	var pond := FishingModel.site_for_plot("farm_pond", bp)
	var center := Vector3(float(pond.center[0]), 0, float(pond.center[1]))
	var plan := FishingModel.plan("farm_pond", bp.cell_to_world(bp.anchor("spawn")), center, grid)
	assert_bool(plan.is_empty()).is_false()
	if plan.is_empty(): return
	assert_bool(FishingModel.valid_cast("farm_pond", plan.origin, plan.target, grid)).is_true()
	assert_bool(grid.point_path(bp.cell_to_world(bp.anchor("spawn")), plan.origin).is_empty()).is_false()
	assert_bool(FishingModel.contains("farm_pond", center, 0.0, pond)).is_true()
	assert_bool(FishingModel.contains("farm_pond", center)).is_false()
	assert_bool(FishingModel.valid_cast("farm_pond", plan.origin, Vector3(9, 0, -30.75), grid)).is_false()

func test_owner_and_private_visitor_receive_identical_pond_geometry() -> void:
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COMPACT))
	var owner := FarmPlot.register_terrain(terrain)
	terrain.erase("source")
	for region in terrain.plot.regions:
		if str(region.get("id", "")).begins_with("geo_"): region.id = "geo_surface"
	var visitor := FarmPlot.register_terrain(terrain)
	assert_object(visitor).is_not_null()
	assert_that(FishingModel.site_for_plot("farm_pond", visitor)).is_equal(FishingModel.site_for_plot("farm_pond", owner))

func test_returning_to_legacy_farms_and_street_water_retains_original_geometry() -> void:
	var old_pond := FishingModel.site("farm_pond").duplicate(true)
	var lake := FishingModel.site("street_lake").duplicate(true)
	var compact := _compact()
	var compact_pond := FishingModel.site_for_plot("farm_pond", compact)
	var old_generated := FarmPlot.register_terrain(JSON.parse_string(FileAccess.get_file_as_string(LEGACY)))
	for bp in [FarmPlot.blueprint_for(), old_generated]:
		assert_that(FishingModel.site_for_plot("farm_pond", bp)).is_equal(old_pond)
		assert_bool(FishingModel.contains("farm_pond", Vector3(9, 0, -30.75))).is_true()
	assert_that(FishingModel.site_for_plot("street_lake", compact)).is_equal(lake)
	assert_that(FishingModel.site("street_lake", compact_pond)).is_equal(lake)

func test_rendered_pond_rim_and_bank_roots_stay_aligned_for_compact_and_legacy_farms() -> void:
	var original := FishingModel.site("farm_pond").duplicate(true)
	var compact := FishingModel.site_for_plot("farm_pond", _compact())
	for spec in [compact, original]:
		var unchanged: Dictionary = spec.duplicate(true)
		var water := auto_free(FishingWater.build("farm_pond", spec)) as FishingWater
		var mesh := water.get_node("FishingWaterSurface") as MeshInstance3D
		var center := Vector2(spec.center[0], spec.center[1])
		var radii := Vector2(spec.radii[0], spec.radii[1])
		# Read actual mesh vertices: the bank must follow the rendered outline,
		# not a separate template or a visually shrunken version of the ellipse.
		var surface_vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point in surface_vertices:
			var q := (Vector2(point.x, point.z) - center) / radii
			assert_float(q.length()).is_equal_approx(1.0, 0.0001)
		var plants := water.get_node("NaturalWaterBank/BankReedsAndGrass") as MeshInstance3D
		var arrays := plants.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var root_count := 0
		var sectors := {}
		for triangle in range(0, indices.size(), 3):
			var left := indices[triangle]
			var right := indices[triangle + 1]
			if absf(vertices[left].y) > 0.001 or absf(vertices[right].y) > 0.001: continue
			if absf(uvs[left].x - uvs[right].x) < 0.9: continue
			# A blade has finite width; measure its actual mesh root midpoint,
			# not either outer corner which can naturally overhang the water.
			var point := (vertices[left] + vertices[right]) * 0.5
			var q := (Vector2(point.x, point.z) - center) / radii
			root_count += 1
			sectors[posmod(floori(q.angle() / TAU * 8), 8)] = true
			# The old scaled ring sits 0.1–0.2m inward instead of on the dry lip.
			assert_float(q.length()).is_greater_equal(1.0)
			assert_float(q.length()).is_less_equal(1.07)
		assert_int(root_count).is_greater(1000)
		assert_int(sectors.size()).is_equal(8)
		assert_that(spec).is_equal(unchanged)
	assert_that(FishingModel.site("farm_pond")).is_equal(original)

func test_geographic_water_mask_does_not_draw_a_shifted_second_pond_outside_the_bank() -> void:
	for bp in [_compact(), FarmPlot.blueprint_for(), FarmPlot.register_terrain(JSON.parse_string(FileAccess.get_file_as_string(LEGACY)))]:
		var spec := FishingModel.site_for_plot("farm_pond", bp)
		var center := Vector2(spec.center[0], spec.center[1])
		var radii := Vector2(spec.radii[0], spec.radii[1])
		var mask := FarmTerrainMask.texture_for(bp).get_image()
		# Read the same blue channel that GeographicWater samples. This catches
		# the half-cell shift even when the primary mesh/shore specs are correct.
		for index in 16:
			var angle := TAU * float(index) / 16
			var edge := center + Vector2(cos(angle), sin(angle)) * radii
			var outward := Vector2(cos(angle) / radii.x, sin(angle) / radii.y).normalized()
			for offset in [-0.16, 0.16]:
				var point: Vector2 = edge + outward * float(offset)
				var pixel := Vector2i(floori(point.x / bp.play_area_m * mask.get_width()), floori(-point.y / bp.play_area_m * mask.get_height()))
				var water := mask.get_pixelv(pixel).b > 0.5
				assert_bool(water).override_failure_message("Unexpected water-mask side at angle %s / offset %s in %s" % [angle, offset, bp.layout_patch_id]).is_equal(offset < 0)
