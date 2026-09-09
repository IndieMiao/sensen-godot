extends GdUnitTestSuite
## 4 邻接寻路，与 Node 侧 BFS 距离一致。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _grid() -> BlueprintGrid:
	return BlueprintGrid.new(FarmBlueprint.load_file(FIX))

func test_manhattan_distance_on_open_grid() -> void:
	var g := _grid()
	assert_float(g.distance_cells(Vector2i(3, 3), Vector2i(0, 1))).is_equal(5.0)
	assert_float(g.walk_time(Vector2i(3, 3), Vector2i(0, 1))).is_equal(2.0)
	assert_float(g.distance_cells(Vector2i(3, 3), Vector2i(3, 3))).is_equal(0.0)

func test_path_cells_are_walkable_and_contiguous() -> void:
	var g := _grid()
	var p := g.path(Vector2i(5, 7), Vector2i(7, 5))
	assert_int(p.size()).is_equal(5) # 4 步
	for i in p.size():
		assert_bool(g.bp.is_walkable(p[i])).is_true()
		if i > 0:
			assert_int(absi(p[i].x - p[i - 1].x) + absi(p[i].y - p[i - 1].y)).is_equal(1)

func test_unreachable_and_out_of_bounds() -> void:
	var g := _grid()
	assert_int(g.path(Vector2i(3, 3), Vector2i(7, 7)).size()).is_equal(0) # 水塘
	assert_float(g.distance_cells(Vector2i(3, 3), Vector2i(7, 7))).is_equal(INF)
	assert_int(g.path(Vector2i(3, 3), Vector2i(9, 9)).size()).is_equal(0)

func test_point_path_is_direct_when_clear_and_routes_around_water() -> void:
	var g := _grid()
	assert_int(g.point_path(Vector3(3.2, 0, -3.8), Vector3(0.17, 0, -1.24)).size()).is_equal(1)
	var start := g.bp.cell_to_world(Vector2i(5, 7))
	var end := g.bp.cell_to_world(Vector2i(7, 5))
	assert_bool(g.segment_walkable(start, end)).is_false()
	var route := g.point_path(start, end)
	assert_int(route.size()).is_greater(1)
	var previous := start
	for point in route:
		for i in 101:
			assert_bool(g.bp.is_walkable(g.bp.world_to_cell(previous.lerp(point, i / 100.0)))).is_true()
		previous = point
	assert_that(route.back()).is_equal(end)

func test_diagonal_cannot_squeeze_between_blocked_corners() -> void:
	var bp := FarmBlueprint.new()
	bp.grid = Vector2i(2, 2)
	bp.cell_m = 1
	bp.masks = {"walkable": ["10", "01"]}
	var g := BlueprintGrid.new(bp)
	assert_bool(g.segment_walkable(Vector3(0.5, 0, -0.5), Vector3(1.5, 0, -1.5))).is_false()
	assert_int(g.point_path(Vector3(0.5, 0, -0.5), Vector3(1.5, 0, -1.5)).size()).is_equal(0)

func test_segment_rejects_tunneling_through_one_cell_wall() -> void:
	var bp := FarmBlueprint.new()
	bp.grid = Vector2i(3, 1)
	bp.cell_m = 1
	bp.masks = {"walkable": ["101"]}
	var g := BlueprintGrid.new(bp)
	assert_bool(g.segment_walkable(Vector3(0.5, 0, -0.5), Vector3(2.5, 0, -0.5))).is_false()
