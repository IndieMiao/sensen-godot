extends GdUnitTestSuite

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func test_mesh_has_six_vertices_per_cell() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var mesh := BlueprintGroundMesh.build(bp)
	assert_int(mesh.get_surface_count()).is_equal(1)
	var arrays := mesh.surface_get_arrays(0)
	assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(8 * 8 * 6)
	assert_int((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size()).is_equal(8 * 8 * 6)

func test_cell_colors_by_type() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(1, 1))).is_equal(BlueprintGroundMesh.COLOR_BED)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(3, 3))).is_equal(BlueprintGroundMesh.COLOR_PATH)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(1, 0))).is_equal(BlueprintGroundMesh.COLOR_BLOCK)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(7, 7))).is_equal(BlueprintGroundMesh.COLOR_WATER)

func test_scale_expands_extent() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var aabb := BlueprintGroundMesh.build(bp, 2.0).get_aabb()
	assert_float(aabb.size.x).is_equal_approx(16.0, 1e-4)
	assert_float(aabb.size.z).is_equal_approx(16.0, 1e-4)
	assert_bool(BlueprintGroundMesh.material().vertex_color_use_as_albedo).is_true()
