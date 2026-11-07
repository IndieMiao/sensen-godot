extends GdUnitTestSuite
## The walk at a P0 pond (q(297), the user 11-07: the map no bigger, the walk wider): the meadow half a metre in from its
## sides and near edge, to z −16 at the far one (the HUD's), less the water and the bank's tree trunks; Fern Pond's clay walked round; every gathering stand
## reached from the spawn; the templates' walk all still there.

const PondWalk := preload("res://modules/ponds/pond_walk.gd")
const P0Ponds := preload("res://modules/p0/p0_ponds.gd")
const SF := ["pond_san_francisco_01", "pond_san_francisco_02", "pond_san_francisco_03"]
## Fern Pond's six points as 后裔's 409 places them: [x, z, stand x, stand z].
const FERN := [[4, -2.4, 3.88, -3.12], [7.6, -1.4, 6.88, -1.38], [-0.3, -6.6, 0.88, -6.62], [-0.3, -9, 0.88, -8.88],
	[-0.3, -13.8, 0.88, -13.88], [12, -7.6, 11.12, -7.62]]

func _reached(bp: FarmBlueprint, from: Vector3) -> Dictionary:
	var start := bp.world_to_cell(from)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and bp.is_walkable(n):
				seen[n] = true
				queue.append(n)
	return seen

func _spawn(bp: FarmBlueprint) -> Vector3: return bp.cell_to_world(bp.anchors.spawn)

func test_the_walk_is_the_meadow_less_the_water() -> void:
	for id in SF:
		var e := P0Ponds.location(id)
		var bp := PondWalk.blueprint(e)
		var spec := SystemPonds.site(e)
		for corner in [Vector3(-2.3, 0, 1.3), Vector3(14.3, 0, 1.3), Vector3(-2.3, 0, -15.8), Vector3(14.3, 0, -15.8)]:
			assert_bool(bp.is_walkable(bp.world_to_cell(corner))).override_failure_message("%s %s" % [id, corner]).is_true()
		for out in [Vector3(-2.8, 0, -8), Vector3(14.8, 0, -8), Vector3(6, 0, 1.8), Vector3(6, 0, -16.3)]:
			assert_bool(bp.is_walkable(bp.world_to_cell(out))).override_failure_message("%s past the edge %s" % [id, out]).is_false()
		var old := SystemPonds.blueprint(e)
		var lost := 0
		for j in old.grid.y:
			for i in old.grid.x:
				var c := Vector2i(i, j)
				if old.is_walkable(c) and not bp.is_walkable(c): lost += 1
				if bp.is_walkable(c): assert_bool(FishingModel.contains(id, bp.cell_to_world(c), 0.2, spec)).is_false()
		assert_int(lost).override_failure_message(id).is_less(30)   # the templates' walk kept (a few cells of rounding)

func test_fern_ponds_stands_all_reached_and_its_clay_walked_round() -> void:
	var e := P0Ponds.location("pond_san_francisco_03")
	var bp := PondWalk.blueprint(e)
	PondWalk.set_trees(bp, null, e, PondScenery.tree_points(FERN.map(func(p): return Vector3(p[0], 0, p[1]))))
	var seen := _reached(bp, _spawn(bp))
	for p in FERN:
		assert_bool(seen.has(bp.world_to_cell(Vector3(p[2], 0, p[3])))).override_failure_message(str(p)).is_true()
	# past the clay on its far side (east), where the old walk stopped at x 11.25
	assert_bool(seen.has(bp.world_to_cell(Vector3(13.2, 0, -7.6)))).is_true()

func test_trunks_block_and_free_again() -> void:
	var e := P0Ponds.location("pond_san_francisco_01")
	var bp := PondWalk.blueprint(e)
	var grid := BlueprintGrid.new(bp)
	var tree := Vector3(0.1, 0, -4)
	var at := bp.world_to_cell(tree)
	assert_bool(bp.is_walkable(at)).is_true()
	var was := PondWalk.set_trees(bp, grid, e, [tree])
	assert_bool(bp.is_walkable(at)).is_false()
	assert_bool(grid.astar.is_point_solid(at)).is_true()
	PondWalk.set_trees(bp, grid, e, [], was)
	assert_bool(bp.is_walkable(at)).is_true()
	assert_bool(grid.astar.is_point_solid(at)).is_false()
