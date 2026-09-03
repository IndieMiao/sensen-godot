extends GdUnitTestSuite

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _mover() -> PlayerMover:
	var bp := FarmBlueprint.load_file(FIX)
	return PlayerMover.new(bp, BlueprintGrid.new(bp))

func test_starts_at_spawn() -> void:
	var m := _mover()
	assert_that(m.cell()).is_equal(Vector2i(3, 3))
	assert_bool(m.is_moving()).is_false()

func test_tap_path_reaches_target_in_expected_time() -> void:
	var m := _mover()
	assert_bool(m.set_target_cell(Vector2i(0, 1))).is_true()
	assert_bool(m.is_moving()).is_true()
	for i in 130: # 5 격 / 2.5 m/s = 2.0 s = 120 帧，留 10 帧余量
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
	assert_float(m.position.x).is_greater(3.5)
	m.position = m.bp.cell_to_world(Vector2i(5, 7), m.world_scale)
	for i in 60:
		m.step(1.0 / 60.0)
	assert_that(m.cell()).is_equal(Vector2i(5, 7)) # (6,7) 是水塘，卡在边上
	m.set_joystick(Vector2.ZERO)
	assert_bool(m.is_moving()).is_false()
