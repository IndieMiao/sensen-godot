extends GdUnitTestSuite

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _mover(world_scale := 1.0) -> PlayerMover:
	var bp := FarmBlueprint.load_file(FIX)
	return PlayerMover.new(bp, BlueprintGrid.new(bp), world_scale)

func test_starts_at_spawn() -> void:
	var m := _mover()
	assert_that(m.cell()).is_equal(Vector2i(3, 3))
	assert_bool(m.is_moving()).is_false()

func test_tap_path_reaches_target_in_expected_time() -> void:
	var m := _mover()
	var start := m.position
	var target := m.bp.cell_to_world(Vector2i(0, 1))
	assert_bool(m.set_target_cell(Vector2i(0, 1))).is_true()
	assert_bool(m.is_moving()).is_true()
	assert_float(m.speed).is_equal(2.5 * 1.5)
	assert_int(m.remaining_path().size()).is_equal(1)
	m.step(0.5)
	assert_bool(m.is_moving()).is_true()
	assert_float(m.position.distance_to(start)).is_equal_approx(1.875, 0.00001)
	assert_float((m.position - start).normalized().distance_to((target - start).normalized())).is_less(0.00001)
	m.step(start.distance_to(target) / 3.75 - 0.5 + 0.00001)
	assert_that(m.cell()).is_equal(Vector2i(0, 1))
	assert_bool(m.is_moving()).is_false()

func test_tap_path_respects_world_scale_in_time() -> void:
	var normal := _mover()
	var scaled := _mover(2.0)
	for m in [normal, scaled]:
		assert_bool(m.set_target_cell(Vector2i(0, 1))).is_true()
		m.step(0.8)
		assert_bool(m.is_moving()).is_true()
	assert_float(scaled.position.distance_to(normal.position * 2)).is_less(0.00001)
	for m in [normal, scaled]:
		m.step(0.2)
		assert_that(m.cell()).is_equal(Vector2i(0, 1))
		assert_bool(m.is_moving()).is_false()

func test_exact_target_and_retarget_do_not_snap_to_cell_centers() -> void:
	var m := _mover()
	assert_bool(m.set_target_position(Vector3(0.23, 0, -1.78))).is_true()
	m.step(0.23)
	var before := m.position
	var target := Vector3(4.18, 0, -2.37)
	assert_bool(m.set_target_position(target)).is_true()
	assert_that(m.position).is_equal(before)
	assert_int(m.remaining_path().size()).is_equal(1)
	m.step(0.1)
	assert_float(m.position.distance_to(before.lerp(target, 0.375 / before.distance_to(target)))).is_less(0.00001)
	m.step(2)
	assert_that(m.position).is_equal(target)
	assert_bool(m.is_moving()).is_false()

func test_obstacle_route_preserves_speed_across_turns_at_low_frame_rate() -> void:
	var fast_frames := _mover()
	var slow_frames := _mover()
	for m in [fast_frames, slow_frames]:
		m.position = m.bp.cell_to_world(Vector2i(5, 7))
		assert_bool(m.set_target_cell(Vector2i(7, 5))).is_true()
		assert_int(m.remaining_path().size()).is_greater(1)
	for i in 60:
		fast_frames.step(1.0 / 60.0)
		assert_bool(fast_frames.bp.is_walkable(fast_frames.cell())).is_true()
	slow_frames.step(1.0)
	assert_float(fast_frames.position.distance_to(slow_frames.position)).is_less(0.00001)
	assert_bool(slow_frames.is_moving()).is_true()
	slow_frames.step(1.0)
	assert_that(slow_frames.cell()).is_equal(Vector2i(7, 5))
	assert_bool(slow_frames.is_moving()).is_false()

func test_blocked_retarget_keeps_existing_destination_and_stop_cancels_it() -> void:
	var m := _mover()
	m.set_target_cell(Vector2i(0, 1))
	m.step(0.1)
	var route := m.remaining_path()
	assert_bool(m.set_target_cell(Vector2i(7, 7))).is_false()
	assert_that(m.remaining_path()).is_equal(route)
	m.stop()
	var stopped := m.position
	m.step(1)
	assert_that(m.position).is_equal(stopped)
	assert_bool(m.is_moving()).is_false()

func test_unreachable_target_rejected() -> void:
	var m := _mover()
	assert_bool(m.set_target_cell(Vector2i(7, 7))).is_false()
	assert_bool(m.is_moving()).is_false()

func test_joystick_moves_east_and_stops_at_water() -> void:
	var m := _mover()
	m.set_joystick(Vector2(1, 0))
	m.step(0.5)
	var pos_after_step := m.position.x
	assert_float(pos_after_step).is_greater(3.5)
	m.position = m.bp.cell_to_world(Vector2i(5, 7), m.world_scale)
	for i in 60:
		m.step(1.0 / 60.0)
	assert_that(m.cell()).is_equal(Vector2i(5, 7)) # (6,7) 是水塘，卡在边上
	# Verify position.x advanced close to the wall before stopping
	assert_float(m.position.x).is_greater(m.bp.cell_to_world(Vector2i(5, 7), m.world_scale).x)
	m.set_joystick(Vector2.ZERO)
	assert_bool(m.is_moving()).is_false()

func test_joystick_moves_south() -> void:
	var m := _mover()
	# South is positive y in joystick convention, maps to positive z in world
	# In grid coords: z = -north, so positive z means south (negative row/y)
	m.set_joystick(Vector2(0, 1))
	var start_cell := m.cell()
	m.step(0.5)  # Move for 0.5 seconds
	var after_cell := m.cell()
	# Moving south should decrease the grid y coordinate (row decreases)
	assert_that(after_cell.y).is_less(start_cell.y)

func test_diagonal_joystick_slides_along_a_wall_and_clears_its_corner() -> void:
	var m := _mover()
	m.position = Vector3(5.95, 0, -7.5)
	m.set_joystick(Vector2(1, 1))
	var start := m.position
	for frame in 24:
		m.step(1.0 / 60.0)
		assert_bool(m.bp.is_walkable(m.cell())).is_true()
	assert_float(m.position.x).is_less(6.0)
	assert_float(m.position.z - start.z).is_greater(1.0)
	for frame in 36:
		m.step(1.0 / 60.0)
		assert_bool(m.bp.is_walkable(m.cell())).is_true()
	assert_float(m.position.x).is_greater(6.0)
	assert_float(m.position.z).is_greater(-6.0)

func test_slide_is_similar_at_low_and_high_frame_rates_and_scales_with_world() -> void:
	var results: Array[Vector3] = []
	for scale in [1.0, 2.0]:
		for frames in [1, 10, 30, 60, 120]:
			var m := _mover(scale)
			m.position = Vector3(5.95, 0, -7.5) * scale
			m.set_joystick(Vector2(1, 1))
			for frame in frames:
				m.step(1.0 / frames)
				assert_bool(m.bp.is_walkable(m.cell())).is_true()
			results.append(m.position / scale)
	for point in results:
		assert_float(point.distance_to(results[0])).is_less(0.2)
		assert_float(point.x).is_greater(6.0)

func test_slide_keeps_analog_speed_and_never_crosses_a_wall_in_a_long_frame() -> void:
	for value in [Vector2(1, 1), Vector2(0.25, 0.25)]:
		var m := _mover()
		var start := m.position
		m.set_joystick(value)
		m.step(0.25)
		assert_float(start.distance_to(m.position)).is_equal_approx(m.speed * 0.25 * minf(1, value.length()), 0.00001)
	var m := _mover()
	m.position = Vector3(5.5, 0, -7.5)
	m.set_joystick(Vector2.RIGHT)
	m.step(2.0)
	assert_float(m.position.x).is_greater(5.8)
	assert_float(m.position.x).is_less(6.0)
	assert_float(m.position.z).is_equal(-7.5)
	m.set_joystick(Vector2.LEFT)
	var blocked := m.position
	m.step(0.1)
	assert_float(m.position.x).is_less(blocked.x)

func test_diagonal_slide_stays_inside_world_bounds_and_releases_from_a_corner() -> void:
	var m := _mover()
	m.position = Vector3(7.98, 0, -0.02)
	m.set_joystick(Vector2(1, 1))
	m.step(0.5)
	assert_bool(m.bp.is_walkable(m.cell())).is_true()
	var corner := m.position
	m.set_joystick(Vector2(-1, -1))
	m.step(0.1)
	assert_float(corner.distance_to(m.position)).is_greater(0.3)
