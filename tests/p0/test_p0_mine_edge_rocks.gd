extends GdUnitTestSuite
## SGODOT-421 / q(292): perimeter selection, every allowed full layout navigable, enlarged art and monster clearance.
const L = preload("res://modules/mining/mine_layout.gd")
const Art = preload("res://modules/mining/mine_art.gd")
const Combat = preload("res://modules/mining/p0_mine_combat.gd")
const Fx = preload("res://tests/p0/fixtures/mine_b1_view.gd")
const NAMES := ["N1", "N2", "S1", "S2", "W1", "W2"]
const PAIRS := ["N1-S1", "N1-S2", "N2-S1", "N2-S2", "N2-W1", "N2-W2", "S2-W1", "S2-W2"]
const TRIPLES := ["N2-S1-W1", "N2-S2-W1", "N2-S2-W2"]

func _nodes(points: Array) -> Array:
	var nodes := []
	for i in points.size(): nodes.append({id = str(i), position = points[i]})
	return nodes

func _fits(ids: Array, distance: float) -> bool:
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if L.ROCK_SIDES[ids[i]] == L.ROCK_SIDES[ids[j]] or L.FALLBACK_POSITIONS[ids[i]].distance_to(L.FALLBACK_POSITIONS[ids[j]]) < distance: return false
	return true

func _combinations() -> Array:
	var out := []
	for a in L.FALLBACK_POSITIONS.size():
		for b in range(a + 1, L.FALLBACK_POSITIONS.size()):
			if _fits([a, b], 4.5): out.append([a, b])
			for c in range(b + 1, L.FALLBACK_POSITIONS.size()):
				if _fits([a, b, c], 3.5): out.append([a, b, c])
	return out

func test_new_counts_keep_indices_and_spread_over_distinct_edges_by_day() -> void:
	var layouts := {}
	for count in [2, 3]:
		for i in 100:
			var key := "wd-%d:%d:2026-11-%02d" % [i % 4, i % 40 + 1, i % 28 + 1]
			var points: Array = L.p0_rocks(count, key)
			assert_int(points.size()).is_equal(count)
			assert_array(L.p0_rocks(count, key)).is_equal(points)
			var ids := points.map(func(p): return L.FALLBACK_POSITIONS.find(p))
			assert_bool(_fits(ids, 4.5 if count == 2 else 3.5)).is_true()
			ids.sort()   # count physical layouts, not permutations of the same indexed rocks.
			layouts[str(ids)] = true
			L._navigation(_nodes(points), ["0"], L.ROCK_RADIUS)
			assert_array(L.p0_rocks(count, key)).is_equal(points)
	assert_int(layouts.size()).is_equal(11)
	assert_array(L.p0_rocks(0, "guard")).is_empty()

func test_every_allowed_full_layout_has_no_dead_cells_and_all_approaches_are_walkable() -> void:
	var combinations := _combinations()
	assert_int(combinations.size()).is_equal(11)
	var names := func(ids): return "-".join(ids.map(func(i): return NAMES[i]))
	assert_array(combinations.filter(func(ids): return ids.size() == 2).map(names)).is_equal(PAIRS)
	assert_array(combinations.filter(func(ids): return ids.size() == 3).map(names)).is_equal(TRIPLES)
	for ids in combinations:
		var points: Array = ids.map(func(i): return L.FALLBACK_POSITIONS[i])
		var nodes := _nodes(points)
		var bp := L._navigation(nodes, [], L.ROCK_RADIUS)
		var grid := BlueprintGrid.new(bp)
		var mover := PlayerMover.new(bp, grid)
		mover.position = L.SPAWN
		for y in L.SIZE.y:
			for x in L.SIZE.x:
				var cell := Vector2i(x, y)
				if bp.is_walkable(cell):
					assert_bool(grid.path(bp.world_to_cell(L.SPAWN), cell).is_empty()).override_failure_message("dead cell %s in %s" % [cell, ids]).is_false()
		for target in [L.UP, L.DOWN, L.ELEVATOR] + points:
			mover.position = L.SPAWN
			var approach: Vector3 = L.approach(mover, target)
			assert_float(approach.distance_to(target)).override_failure_message(str(ids)).is_between(0.75, 1.55)
			assert_bool(mover.set_target_position(approach)).override_failure_message("approach %s in %s" % [target, ids]).is_true()
			mover.step(100.0)
			assert_vector(mover.position).is_equal(approach)
		var broken := L._navigation(nodes, nodes.map(func(n): return n.id), L.ROCK_RADIUS)
		for point in points: assert_bool(broken.is_walkable(broken.world_to_cell(point))).is_true()

func test_five_monsters_stay_separate_clear_of_rocks_and_inside_aggro_after_snapping() -> void:
	for ids in _combinations():
		var points: Array = ids.map(func(i): return L.FALLBACK_POSITIONS[i])
		var bp := L._navigation(_nodes(points), [], L.ROCK_RADIUS)
		var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
		mover.position = L.SPAWN
		var fight := Combat.new()
		add_child(fight)
		var mobs := []
		for _i in 5: mobs.append(Fx.mob("mob_rock_beetle", 18, 18))
		fight.sync_p0(Fx.view(3, {mobs = mobs, rocks = points.size()}), 3, mover)
		var positions := []
		for e in fight.enemies.values():
			var p: Vector3 = e.mover.position
			assert_bool(bp.is_walkable(bp.world_to_cell(p))).is_true()
			assert_float(p.distance_to(L.SPAWN)).is_between(3.0, 4.6)
			for rock in points: assert_float(p.distance_to(rock)).is_greater_equal(L.ROCK_RADIUS)
			for other in positions: assert_float(p.distance_to(other)).is_greater_equal(1.2)
			positions.append(p)
		fight.free()

func test_old_day_counts_keep_all_old_rock_indices_and_legacy_size() -> void:
	var all: Array = L.p0_rocks(6, "old-mine:2:2026-11-05")
	for count in [4, 5, 6]:
		assert_array(L.p0_rocks(count, "old-mine:2:2026-11-05")).is_equal(all.slice(0, count))
	for p in all: assert_bool(L.LEGACY_POSITIONS.has(p)).is_true()

func test_new_rock_scales_art_and_shadow_together_without_scaling_its_position_or_break_root() -> void:
	var position := Vector3(8.1, 0, -3.5)
	var old := Art.rock(position, 1, 1, "copper_ore", "mine:1:day")
	var big := Art.rock(position, 1, 1, "copper_ore", "mine:1:day", L.ROCK_SCALE)
	assert_vector(big.position).is_equal(position)
	assert_vector(big.scale).is_equal(Vector3.ONE)
	assert_vector(big.get_node("Rock").scale).is_equal_approx(old.get_node("Rock").scale * 1.3, Vector3.ONE * 0.0001)
	assert_float(big.get_node("Rock").rotation.y).is_equal(old.get_node("Rock").rotation.y)
	var a: PlaneMesh = old.get_node("blob_shadow").mesh
	var b: PlaneMesh = big.get_node("blob_shadow").mesh
	assert_vector(b.size).is_equal_approx(a.size * 1.3, Vector2.ONE * 0.0001)
	old.free()
	big.free()
