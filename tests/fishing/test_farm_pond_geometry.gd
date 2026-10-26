extends GdUnitTestSuite

func test_legacy_farm_and_street_water_keep_their_original_geometry() -> void:
	var old_pond := FishingModel.site("farm_pond").duplicate(true)
	var lake := FishingModel.site("street_lake").duplicate(true)
	var bp := FarmPlot.blueprint_for()
	assert_that(FishingModel.site_for_plot("farm_pond", bp)).is_equal(old_pond)
	assert_bool(FishingModel.contains("farm_pond", Vector3(9, 0, -30.75))).is_true()
	assert_that(FishingModel.site_for_plot("street_lake", bp)).is_equal(lake)

func test_rendered_pond_rim_and_bank_roots_stay_aligned() -> void:
	var original := FishingModel.site("farm_pond").duplicate(true)
	for spec in [original]:
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
