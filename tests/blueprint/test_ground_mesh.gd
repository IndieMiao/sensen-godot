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

func test_water_beats_buildable_in_priority() -> void:
	## Fixture has no cell that is simultaneously non-walkable and buildable.
	## This test creates a synthetic blueprint where cell (6, 6) is non-walkable but buildable,
	## ensuring water priority over buildable is not accidentally inverted.
	var json_str := FileAccess.get_file_as_string(FIX)
	var data := JSON.parse_string(json_str) as Dictionary
	var bp_data := data.duplicate(true)

	## Modify cell (6, 6) to be non-walkable (already is) but buildable (flip from 0 to 1)
	var buildable_rows := bp_data.masks.buildable as Array
	var row_6 := buildable_rows[6] as String
	buildable_rows[6] = row_6.substr(0, 6) + "1" + row_6.substr(7)

	var bp := FarmBlueprint.from_dict(bp_data)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(6, 6))).is_equal(BlueprintGroundMesh.COLOR_WATER)

func test_build_places_cell_colors_at_expected_offsets() -> void:
	## Validates that build() places colours at the correct mesh vertex offsets.
	## Fixtures grid is 8×8, so (i,j) and (j,i) transpose would not be caught by AABB alone.
	## These cells are chosen to differ from their transpose: (0,1) cultivable vs (1,0) buildable.
	var bp := FarmBlueprint.load_file(FIX)
	var mesh := BlueprintGroundMesh.build(bp)
	var arrays := mesh.surface_get_arrays(0)
	var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray

	## Cell (0, 1): cultivable → COLOR_BED
	var offset_0_1 := (1 * bp.grid.x + 0) * 6
	for idx in range(offset_0_1, offset_0_1 + 6):
		assert_float(colors[idx].r).is_equal_approx(BlueprintGroundMesh.COLOR_BED.r, 0.01)
		assert_float(colors[idx].g).is_equal_approx(BlueprintGroundMesh.COLOR_BED.g, 0.01)
		assert_float(colors[idx].b).is_equal_approx(BlueprintGroundMesh.COLOR_BED.b, 0.01)

	## Cell (1, 0): buildable → COLOR_BLOCK (transpose of (0, 1))
	var offset_1_0 := (0 * bp.grid.x + 1) * 6
	for idx in range(offset_1_0, offset_1_0 + 6):
		assert_float(colors[idx].r).is_equal_approx(BlueprintGroundMesh.COLOR_BLOCK.r, 0.01)
		assert_float(colors[idx].g).is_equal_approx(BlueprintGroundMesh.COLOR_BLOCK.g, 0.01)
		assert_float(colors[idx].b).is_equal_approx(BlueprintGroundMesh.COLOR_BLOCK.b, 0.01)

## 2026-09-04 真机 + 桌面渲染：地表从上方看完全不可见（真机截图里整片黑底、桌面上整片
## 天空色，田畦和房子却都在）。Godot 的正面缠绕是顺时针（Mesh 类文档："Godot uses clockwise
## winding order for front faces of triangle primitive modes"），build() 之前按逆时针写
## 三角形，从 +Y 往下看全是背面，被 StandardMaterial3D 默认的 cull_back 剔掉。以引擎自带、
## 朝 +Y 的 PlaneMesh 为基准比较缠绕方向，不把手算的叉积符号写死进测试。
func test_ground_triangles_wind_like_an_upward_plane_mesh() -> void:
	var plane := PlaneMesh.new().get_mesh_arrays()
	var reference := signf(_cross_y(plane, 0))
	assert_float(reference).is_not_equal(0.0)
	var bp := FarmBlueprint.load_file(FIX)
	var arrays := BlueprintGroundMesh.build(bp).surface_get_arrays(0)
	var tri_count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var flipped := 0
	for t in tri_count:
		if signf(_cross_y(arrays, t)) != reference:
			flipped += 1
	assert_int(flipped).is_equal(0)

## 第 tri 个三角形 (b-a)×(c-a) 的 y 分量：符号即缠绕方向。兼容有/无索引数组两种网格
## （PlaneMesh 带索引，SurfaceTool.commit() 不带）。
static func _cross_y(arrays: Array, tri: int) -> float:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var i0 := tri * 3
	var a: Vector3
	var b: Vector3
	var c: Vector3
	if idx != null and (idx as PackedInt32Array).size() > 0:
		a = v[idx[i0]]
		b = v[idx[i0 + 1]]
		c = v[idx[i0 + 2]]
	else:
		a = v[i0]
		b = v[i0 + 1]
		c = v[i0 + 2]
	return (b - a).cross(c - a).y
