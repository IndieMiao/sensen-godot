extends GdUnitTestSuite

const Layout = preload("res://modules/mining/mine_layout.gd")

func test_layout_keeps_shared_rock_ids_and_is_stable_after_save_roundtrip() -> void:
	var original := Layout.rocks(3, 7, "saved-farm")
	var saved: Dictionary = JSON.parse_string(JSON.stringify({"floor": 3, "run": 7, "farm_id": "saved-farm"}))
	assert_that(Layout.rocks(int(saved.floor), int(saved.run), str(saved.farm_id))).is_equal(original)
	assert_that(original.map(func(rock): return rock.id)).is_equal(Layout.data().rocks.map(func(rock): return str(rock.id)))
	for broken in [[], ["rock_1", "rock_4"], original.map(func(rock): return rock.id)]:
		Layout.navigation(3, broken, 7, "saved-farm")
		assert_that(Layout.rocks(3, 7, "saved-farm")).is_equal(original)
	var modified := Layout.rocks(3, 7, "saved-farm")
	modified[0].position = Vector3.ZERO
	modified[0].id = "changed"
	modified.pop_back()
	assert_that(Layout.rocks(3, 7, "saved-farm")).is_equal(original)
	for run in range(Layout.CACHE_LIMIT + 1): Layout.rocks(1, run, "cache-eviction")
	assert_int(Layout._layouts.size()).is_less_equal(Layout.CACHE_LIMIT)
	assert_that(Layout.rocks(3, 7, "saved-farm")).is_equal(original)

func test_floor_run_and_farm_each_change_positions_without_changing_rock_ids() -> void:
	var original := Layout.rocks(1, 0, "farm-a")
	for nodes in [Layout.rocks(2, 0, "farm-a"), Layout.rocks(1, 1, "farm-a"), Layout.rocks(1, 0, "farm-b")]:
		assert_that(nodes).is_not_equal(original)
		assert_that(nodes.map(func(rock): return rock.id)).is_equal(original.map(func(rock): return rock.id))
	assert_that(Layout.rocks(1)).is_equal(Layout.rocks(1, 0, ""))

func test_random_layouts_have_clearance_and_variety_across_floors_and_runs() -> void:
	var signatures: Dictionary = {}
	for seed_number in 36:
		for floor_number in range(1, 5):
			var nodes := Layout.rocks(floor_number, seed_number, "layout-farm-%d" % (seed_number % 3))
			var label := "run %d floor %d" % [seed_number, floor_number]
			assert_int(nodes.size()).override_failure_message(label).is_equal(6)
			var signature := str(nodes)
			assert_bool(signatures.has(signature)).override_failure_message("Repeated layout: " + label).is_false()
			signatures[signature] = true
			var xs: Dictionary = {}
			var zs: Dictionary = {}
			for index in nodes.size():
				var point: Vector3 = nodes[index].position
				assert_bool(Layout.ROCK_BOUNDS.has_point(Vector2(point.x, point.z))).override_failure_message(label).is_true()
				for anchor in [Layout.SPAWN, Layout.UP, Layout.DOWN, Layout.ELEVATOR]:
					assert_float(point.distance_to(anchor)).override_failure_message(label).is_greater_equal(Layout.ANCHOR_CLEARANCE)
				for other in range(index):
					assert_float(point.distance_to(nodes[other].position)).override_failure_message(label).is_greater_equal(Layout.MIN_ROCK_SPACING)
				xs[snappedf(point.x, 0.25)] = true
				zs[snappedf(point.z, 0.25)] = true
			assert_int(xs.size()).override_failure_message("Column-aligned layout: " + label).is_greater_equal(3)
			assert_int(zs.size()).override_failure_message("Row-aligned layout: " + label).is_greater_equal(3)

func test_random_navigation_matches_rocks_and_keeps_routes_before_and_after_mining() -> void:
	for seed_number in 36:
		for floor_number in range(1, 6):
			var farm_id := "navigation-farm-%d" % (seed_number % 3)
			var nodes := Layout.rocks(floor_number, seed_number, farm_id)
			for broken in [[], ["rock_2", "rock_4", "rock_6"], nodes.map(func(rock): return rock.id)]:
				var bp := Layout.navigation(floor_number, broken, seed_number, farm_id)
				var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
				var label := "run %d floor %d broken %s" % [seed_number, floor_number, broken]
				assert_vector(mover.position).override_failure_message(label).is_equal(Layout.SPAWN)
				for rock in nodes:
					assert_bool(bp.is_walkable(bp.world_to_cell(rock.position))).override_failure_message(label).is_equal(broken.has(rock.id))
				var targets: Array = [Layout.UP, Layout.DOWN, Layout.ELEVATOR]
				for rock in nodes:
					if not broken.has(rock.id): targets.append(rock.position)
				for target in targets:
					var point := Layout.approach(mover, target)
					assert_float(point.distance_to(target)).override_failure_message(label).is_greater_equal(0.75)
					assert_float(point.distance_to(target)).override_failure_message(label).is_less_equal(1.55)
					assert_bool(mover.set_target_position(point)).override_failure_message(label).is_true()
					mover.step(100.0)
					assert_vector(mover.position).override_failure_message(label).is_equal(point)
					assert_bool(mover.is_moving()).override_failure_message(label).is_false()
				if broken.is_empty():
					for y in Layout.SIZE.y:
						for x in Layout.SIZE.x:
							var cell := Vector2i(x, y)
							if bp.is_walkable(cell):
								assert_bool(mover.grid.path(bp.world_to_cell(Layout.SPAWN), cell).is_empty()).override_failure_message(label).is_false()

func test_bounded_generation_fallback_is_safe() -> void:
	var nodes: Array = []
	var sources: Array = Layout.data().rocks
	for index in sources.size(): nodes.append({"id": str(sources[index].id), "position": Layout.LEGACY_POSITIONS[index]})
	assert_bool(Layout._layout_is_reachable(nodes)).is_true()
	for index in nodes.size():
		assert_bool(Layout._position_is_clear(nodes[index].position, nodes.slice(0, index))).is_true()

func test_elite_floor_has_no_rocks_or_old_rock_collisions() -> void:
	assert_array(Layout.rocks(5, 9, "boss-farm")).is_empty()
	assert_int(Layout.rock_count(5)).is_zero()
	var fresh := Layout.navigation(5, [], 9, "boss-farm")
	var old := Layout.navigation(5, ["rock_1", "rock_6"], 9, "boss-farm")
	assert_that(fresh.masks).is_equal(old.masks)
	for point in Layout.LEGACY_POSITIONS:
		assert_bool(fresh.is_walkable(fresh.world_to_cell(point))).is_true()

func test_joystick_slides_at_generated_rock_faces_without_entering_blocked_cells() -> void:
	var checked := 0
	for run in 3:
		for floor_number in range(1, 6):
			var bp := Layout.navigation(floor_number, [], run, "slide-regression")
			var grid := BlueprintGrid.new(bp)
			for rock in Layout.rocks(floor_number, run, "slide-regression"):
				var center := bp.cell_to_world(bp.world_to_cell(rock.position))
				for outward in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
					var tangent := Vector3(-outward.z, 0, outward.x)
					var start: Vector3 = center + outward * (bp.cell_m * 0.5 + 0.015)
					if not grid.segment_walkable(start, start + tangent * bp.cell_m): continue
					var input: Vector3 = (-outward + tangent).normalized()
					if grid.segment_walkable(start, start + input * 3.75 / 30.0): continue
					var mover := PlayerMover.new(bp, grid)
					mover.position = start
					mover.set_joystick(Vector2(input.x, input.z))
					for frame in 6:
						mover.step(1.0 / 30.0)
						assert_bool(bp.is_walkable(mover.cell())).is_true()
					assert_float((mover.position - start).dot(tangent)).is_greater(0.3)
					checked += 1
	assert_int(checked).is_greater(30)
