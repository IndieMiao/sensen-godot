extends GdUnitTestSuite
## 不知火舞's stick-slide spec v1 (the user 11-08, bot 463): a push into a wall slides along it at sin θ, square-on
## (θ < 15°) it stops, a 45° row is one slanted wall, a corner stops it still, a wall's end close by is stepped round,
## a door along the wall is walked into. Maps in cells (x east, y north), the farm's 0.65 m cells.

const CELL := 0.65
const DT := 1.0 / 60.0

## A mover on a `w` × `h` map whose cell (x, y) is blocked when `blocked.call(x, y)`, stood at cell point `at`.
func _mover(w: int, h: int, blocked: Callable, at: Vector2) -> PlayerMover:
	var rows := PackedStringArray()
	for y in h:
		var row := ""
		for x in w: row += "0" if blocked.call(x, y) else "1"
		rows.append(row)
	var bp := FarmBlueprint.new()
	bp.cell_m = CELL
	bp.cell_mm = roundi(CELL * 1000)
	bp.grid = Vector2i(w, h)
	bp.masks = {"walkable": rows}
	var m := PlayerMover.new(bp, BlueprintGrid.new(bp))
	m.position = _world(at)
	return m

func _world(cell: Vector2) -> Vector3: return Vector3(cell.x * CELL, 0.0, -cell.y * CELL)
func _cell(m: PlayerMover) -> Vector2: return Vector2(m.position.x, -m.position.z) / CELL
## The stick pushing at `deg` (0 east, 90 north) in the map.
func _stick(deg: float) -> Vector2: return Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)))

func _frames(m: PlayerMover, n: int) -> Array[float]:
	var went: Array[float] = []
	for i in n:
		var was := m.position
		m.step(DT)
		went.append(was.distance_to(m.position))
		assert_float(went[-1]).is_less_equal(m.speed * DT + 0.00001)   # never faster than the walk (the server's reach)
		assert_bool(m.bp.is_walkable(m.cell())).is_true()
	return went

func _sum(a: Array[float]) -> float:
	var s := 0.0
	for v in a: s += v
	return s

## A wall along y = 10: at 30°, 60°, 90° off square-on the slide goes at sin θ once against it, facing along it; at
## 10° it walks on to the wall and stops there (stuck, so the actor stands after 0.1 s).
func test_against_a_straight_wall_it_slides_at_sin_theta_and_stops_square_on() -> void:
	var wall := func(_x: int, y: int) -> bool: return y == 10
	for theta in [30.0, 60.0, 90.0]:
		var m := _mover(60, 14, wall, Vector2(10, 8))
		m.set_joystick(_stick(90.0 - theta))   # north, turned theta toward east
		_frames(m, 90)   # on to the wall
		var went := _sum(_frames(m, 30))
		var why := "theta %d" % theta
		assert_float(went).override_failure_message(why).is_equal_approx(m.speed * 0.5 * sin(deg_to_rad(theta)), m.speed * 0.5 * 0.08)
		assert_float(m.stick_ratio).override_failure_message(why).is_equal_approx(sin(deg_to_rad(theta)), 0.08)
		assert_float(m.facing.x).override_failure_message(why).is_greater(0.99)   # along the wall, not into it
		assert_bool(m.stuck).is_false()
	var m := _mover(60, 14, wall, Vector2(10, 8))
	m.set_joystick(_stick(80.0))
	_frames(m, 90)
	var still := m.position
	_frames(m, 30)
	assert_float(still.distance_to(m.position)).is_less(0.01)
	assert_bool(m.stuck).is_true()
	assert_float(_cell(m).y).is_greater(9.9)   # right up against it

## A 45° row (a staircase of cells, y − x of 5 and 6) pushed at 45° — straight north, into its notches: on the row it
## moves every frame, never into a notch, at sin 45° within ±15 %.
func test_a_45_degree_row_is_one_slanted_wall() -> void:
	var row := func(x: int, y: int) -> bool: return y - x in [5, 6]
	var m := _mover(40, 40, row, Vector2(20.5, 18.5))
	m.set_joystick(_stick(90.0))
	_frames(m, 120)   # on to the row
	var went := _frames(m, 120)
	var mean := _sum(went) / went.size()
	for v in went:
		assert_float(v).is_greater(0.0)
		assert_float(v).is_between(mean * 0.85, mean * 1.15)
	assert_float(mean / (m.speed * DT)).is_between(0.6, 0.8)
	var at := _cell(m)
	assert_float(at.y - at.x).is_between(3.5, 4.05)   # along its steps' corners (y − x = 4), not in a notch (to 5)
	assert_float(m.facing.dot(Vector3(1, 0, -1).normalized())).is_greater(0.95)

## Into a corner (walls along y = 10 and x = 20), square-on and at a slant: still to the centimetre, facing steady.
func test_a_corner_stops_it_still() -> void:
	var corner := func(x: int, y: int) -> bool: return y == 10 or x == 20
	for deg in [45.0, 60.0, 30.0, 80.0]:
		var m := _mover(30, 14, corner, Vector2(16, 6))
		m.set_joystick(_stick(deg))
		_frames(m, 240)
		var still := m.position
		var facing := m.facing
		_frames(m, 120)
		var why := "%d°" % deg
		assert_float(still.distance_to(m.position)).override_failure_message(why).is_less(0.01)
		assert_float(facing.dot(m.facing)).override_failure_message(why).is_greater(0.99)

## A wall's end (the wall along y = 10 up to x = 16): square-on within 0.25 m of it, the push steps round it and on; half
## a metre off, it stops.
func test_a_walls_end_close_by_is_stepped_round() -> void:
	var wall := func(x: int, y: int) -> bool: return y == 10 and x < 16
	var m := _mover(30, 14, wall, Vector2(16.0 - 0.2 / CELL, 8))
	m.set_joystick(_stick(90.0))
	_frames(m, 120)
	assert_float(_cell(m).y).is_greater(10.5)
	m = _mover(30, 14, wall, Vector2(16.0 - 0.5 / CELL, 8))
	m.set_joystick(_stick(90.0))
	_frames(m, 120)
	assert_float(_cell(m).y).is_less(10.0)
	assert_bool(m.stuck).is_true()

## Sliding along a wall pushed into it at 45°, a door in it (cell (15, 10) open) is walked into, not slid past.
func test_a_door_along_the_wall_is_walked_into() -> void:
	var wall := func(x: int, y: int) -> bool: return y == 10 and x != 15
	var m := _mover(30, 14, wall, Vector2(8, 9))
	m.set_joystick(_stick(45.0))
	var through := false
	for i in 240:
		_frames(m, 1)
		var at := _cell(m)
		if at.y > 11.0 and at.x < 18.0: through = true   # past the wall, by the door
	assert_bool(through).is_true()

## Let go, the slide's state goes with the stick; a walk is a walk.
func test_letting_go_clears_the_slide() -> void:
	var wall := func(_x: int, y: int) -> bool: return y == 10
	var m := _mover(60, 14, wall, Vector2(10, 9.5))
	m.set_joystick(_stick(60.0))
	_frames(m, 30)
	assert_bool(m.sliding).is_true()
	m.set_joystick(Vector2.ZERO)
	assert_bool(m.sliding).is_false()
	assert_float(m.stick_ratio).is_equal(1.0)
	m.set_joystick(_stick(-90.0))
	_frames(m, 5)
	assert_bool(m.sliding).is_false()
	assert_float(m.stick_ratio).is_equal_approx(1.0, 0.001)
