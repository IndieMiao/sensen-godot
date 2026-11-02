extends GdUnitTestSuite
## Homestead fence layout (plan §8.3, q(35); 不知火舞 on SGODOT-228 7e1db1f8): the front stretch at every level,
## the ring from Lv3, openings at the door path and the way out; nothing blocks a route.

func _span(seg: Dictionary) -> Vector2:
	var half := P0Garden.FENCE_SEG * float(seg.stretch) * 0.5
	var c: float = seg.pos.x if is_zero_approx(float(seg.yaw)) else seg.pos.z
	return Vector2(c - half, c + half)

func test_front_stretch_flanks_the_door_path_with_a_two_metre_opening() -> void:
	var bp := P0Garden.blueprint()
	var front := P0Garden.fence_front(bp)
	assert_int(front.size()).is_equal(2)
	var door := bp.cell_to_world(bp.anchor("house"))
	var left := _span(front[0])
	var right := _span(front[1])
	assert_float(right.x - left.y).is_greater_equal(2.0 * bp.cell_m)   # at least two path widths
	assert_bool(left.y < door.x and right.x > door.x).is_true()

## The ring is open only at the way out: its west stretch runs unbroken where the mine mouth stood (355 b1, v4q(5) ①).
func test_ring_leaves_the_exit_open_and_the_west_stretch_whole() -> void:
	var bp := P0Garden.blueprint()
	var ring := P0Garden.fence_ring(bp)
	assert_int(ring.size()).is_greater(30)
	var exit := bp.cell_to_world(bp.anchor("exit"))
	var west: Array = []
	for seg in ring:
		var s := _span(seg)
		if is_zero_approx(float(seg.yaw)) and float(seg.pos.z) > -1.0:   # front run
			assert_bool(s.y <= exit.x - 0.65 or s.x >= exit.x + 0.65).is_true()
		if not is_zero_approx(float(seg.yaw)) and float(seg.pos.x) < 1.0: west.append(s)   # west run
	west.sort_custom(func(a, b): return a.x < b.x)
	assert_float(west[0].x).is_equal_approx(P0Garden.FENCE_RING.back, 0.01)
	assert_float(west.back().y).is_equal_approx(P0Garden.FENCE_RING.front, 0.01)
	for i in range(1, west.size()): assert_float(west[i].x).is_equal_approx(west[i - 1].y, 0.01)   # no gap

func test_the_fence_never_cuts_off_a_bed_or_a_facility() -> void:
	var bp := P0Garden.blueprint()
	P0Garden.block_points(bp, P0Garden.fence_block_points(bp))
	var grid := BlueprintGrid.new(bp)
	var spawn := bp.anchor("spawn")
	for id in P0Garden.plot_count():
		assert_bool(bp.is_walkable(P0Garden.cell_of(id))).is_true()
		assert_bool(grid.path(spawn, P0Garden.cell_of(id)).is_empty()).is_false()
	# the cells in front of the door and the stall, and the yard's west corner, stay reachable
	for c in [Vector2i(9, 14), Vector2i(14, 14), Vector2i(3, 13), Vector2i(9, 13)]:
		assert_bool(bp.is_walkable(c)).is_true()
		assert_bool(grid.path(spawn, c).is_empty()).is_false()
	# the stretch itself is solid either side of the opening
	assert_bool(bp.is_walkable(Vector2i(6, 13))).is_false()
	assert_bool(bp.is_walkable(Vector2i(12, 13))).is_false()
