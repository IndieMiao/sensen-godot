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
	assert_bool(m.set_target_cell(Vector2i(0, 1))).is_true()
	assert_bool(m.is_moving()).is_true()
	# Check still moving at frame 110 (before expected 120-frame arrival)
	for i in 110:
		m.step(1.0 / 60.0)
	assert_bool(m.is_moving()).is_true()
	# Step remaining 20 frames to reach destination
	for i in 20:
		m.step(1.0 / 60.0)
	assert_that(m.cell()).is_equal(Vector2i(0, 1))
	assert_bool(m.is_moving()).is_false()

func test_tap_path_respects_world_scale_in_time() -> void:
	var m := _mover(2.0)  # 2x world scale
	assert_bool(m.set_target_cell(Vector2i(0, 1))).is_true()
	# With world_scale=2.0, stride = 2.5 * 2.0 * dt, so arrival still at frame 120
	for i in 130:  # 5 格 / 2.5 m/s = 2.0 s = 120 帧，留 10 帧余量
		m.step(1.0 / 60.0)
	assert_that(m.cell()).is_equal(Vector2i(0, 1))
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
