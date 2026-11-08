class_name PlayerMover
extends RefCounted
## 点按按可直达路段移动，障碍处保留寻路转折；摇杆使用相同碰撞检查。
## 时间不变量按逻辑格：speed 是逻辑米/秒，world_scale 只放大视觉。

var bp: FarmBlueprint
var grid: BlueprintGrid
var world_scale := 1.0
var position := Vector3.ZERO
var speed := 3.75
var facing := Vector3(0, 0, 1)
var joystick := Vector2.ZERO
var _path: Array[Vector3] = []
var _path_idx := 0
## SGODOT-306: whether the last joystick step went nowhere (blocked both ways, or square against a wall) — under
## STUCK_RATIO of the step the stick asked for, so a sliver of jitter along a wall is not a walk. Paths never block.
var stuck := false
const STUCK_RATIO := 0.05

const JOYSTICK_STEP_CELL_RATIO := 0.2

## 不知火舞's stick-slide spec v1 (the user 11-08, bot 463): a stick step with a wall SLIDE_LOOK_CELLS ahead goes along
## it. The wall is taken whole (BlueprintGrid.hit_normal: a straight face's own normal, a lone step's a line fitted
## through the faces about it), so a 45° row — a staircase of cells — is the one slanted wall it is. Pushed square-on (θ, the push's angle off the normal, under
## SLIDE_MIN_DEG) it walks on to the wall and stops there, but for a wall's end within YIELD_M to one side, stepped round
## at sin SLIDE_MIN_DEG. Pushed at a slant it turns, to the wall's open side, by the least angle φ (SLIDE_STEP_DEG at a
## time) that keeps that much ahead clear, at the step × cos φ — sin θ along the wall, more on the way in — so it comes
## onto the wall without walking into a row's notches; into a corner it creeps on and stops, never turning back.
const SLIDE_MIN_DEG := 15.0
const SLIDE_STEP_DEG := 3.0
const SLIDE_LOOK_CELLS := 1.5
const SLIDE_NORMAL_CELLS := 2.0   # the radius a lone step's wall is fitted over
const YIELD_M := 0.25
const YIELD_STEP_M := 0.05
## The run clip's speed while sliding: the slide's speed over the walk's, never under this (feet that skate).
const SLIDE_RUN_MIN := 0.6
## The last stick step went along a wall (or turned to it) rather than straight.
var sliding := false
## The last stick step's distance over the step the stick asked for: 1 walking free, sin θ sliding, 0 stopped.
var stick_ratio := 1.0
var _slid := Vector3.ZERO   # the way the last slide went: a slide the other way stops instead (a corner, no jitter)

func _init(p_bp: FarmBlueprint, p_grid: BlueprintGrid, p_scale := 1.0) -> void:
	bp = p_bp
	grid = p_grid
	world_scale = p_scale
	position = bp.cell_to_world(bp.anchor("spawn"), world_scale)

func cell() -> Vector2i:
	return bp.world_to_cell(position, world_scale)

func set_target_cell(c: Vector2i) -> bool:
	return set_target_position(bp.cell_to_world(c, world_scale))

func set_target_position(target: Vector3) -> bool:
	var p := grid.point_path(position, target, world_scale)
	if p.is_empty():
		return false
	_path = p
	_path_idx = 0
	joystick = Vector2.ZERO
	return true

func set_joystick(v: Vector2) -> void:
	joystick = v
	if v != Vector2.ZERO:
		_path.clear()
		_path_idx = 0
	else:
		sliding = false
		stick_ratio = 1.0
		_slid = Vector3.ZERO

func stop() -> void:
	joystick = Vector2.ZERO
	sliding = false
	stick_ratio = 1.0
	_slid = Vector3.ZERO
	_path.clear()
	_path_idx = 0

func remaining_path() -> Array[Vector3]:
	return _path.slice(_path_idx)

func is_moving() -> bool:
	return joystick != Vector2.ZERO or _path_idx < _path.size()

func step(dt: float) -> void:
	var stride := speed * world_scale * maxf(dt, 0.0)
	stuck = false
	if joystick != Vector2.ZERO:
		var dir := Vector3(joystick.x, 0.0, joystick.y).limit_length(1.0)
		var was := position
		_move_joystick(dir * stride)
		var asked := (dir * stride).length()
		var went := Vector3(position.x - was.x, 0.0, position.z - was.z)
		stick_ratio = went.length() / asked if asked > 0.0 else 1.0
		stuck = asked > 0.0 and stick_ratio < STUCK_RATIO
		# Facing the way it goes (a slide along the wall, not sideways into it); stopped, the way the stick pushes.
		facing = went.normalized() if not stuck else dir.normalized()
		return
	# Carry unused distance across turns so frame rate does not change travel speed.
	while _path_idx < _path.size():
		var target := _path[_path_idx]
		var to := target - position
		var distance := to.length()
		if distance > 1e-6: facing = to / distance
		if distance <= stride:
			position = target
			_path_idx += 1
			stride -= distance
		else:
			position += facing * stride
			break

func _move_joystick(displacement: Vector3) -> void:
	var max_step := bp.cell_m * world_scale * JOYSTICK_STEP_CELL_RATIO
	var steps := maxi(1, ceili(displacement.length() / max_step))
	var increment := displacement / steps
	for index in steps:
		if not _stick_increment(increment): break

## One stick increment: straight on, or along the wall (the slide spec), or nowhere (false).
func _stick_increment(increment: Vector3) -> bool:
	var length := increment.length()
	if length <= 0.0: return false
	var ahead := increment / length
	var look := maxf(length, bp.cell_m * world_scale * SLIDE_LOOK_CELLS)
	var hit := grid.trace_hit(position, position + ahead * look, world_scale)
	var n := Vector3.ZERO
	if hit <= 1.0:   # about where the look meets the wall, just short of it
		var at := maxf(0.0, look * hit - bp.cell_m * world_scale * 0.05)
		n = grid.hit_normal(position + ahead * at, SLIDE_NORMAL_CELLS, world_scale)
	# Nothing ahead, or nothing that reads as a wall to slide along (pushed away from it, a gap between two): straight on.
	if n == Vector3.ZERO or ahead.dot(n) >= 0.0: return _straight(increment)
	if -ahead.dot(n) > cos(deg_to_rad(SLIDE_MIN_DEG)):   # square-on: on to the wall, then a near end stepped round
		if _straight(increment): return true
		return _go(_yield(ahead, n, length, look))
	var side := 1.0 if ahead.rotated(Vector3.UP, 0.01).dot(n) > ahead.rotated(Vector3.UP, -0.01).dot(n) else -1.0
	var along := _turned(ahead, side, length, look)
	if along == Vector3.ZERO:
		if _straight(increment): return true   # into a corner's pocket
		along = _turned(ahead, side, length, 0.0)   # … and along its wall to the corner
	if along == Vector3.ZERO or along.dot(_slid) < 0.0: return false
	if not _go(along): return false
	_slid = along
	return true

func _straight(increment: Vector3) -> bool:
	if not _try_move(increment): return false
	sliding = false
	_slid = Vector3.ZERO
	return true

func _go(along: Vector3) -> bool:
	if along == Vector3.ZERO or not _try_move(along): return false
	sliding = true
	return true

## The step turned off `ahead` to `side` by the least φ up to 90° − SLIDE_MIN_DEG that walks clear `reach` (at least
## the step itself), as long as cos φ of the step; ZERO when none does.
func _turned(ahead: Vector3, side: float, length: float, reach: float) -> Vector3:
	var phi := SLIDE_STEP_DEG
	while phi <= 90.0 - SLIDE_MIN_DEG + 0.001:
		var go := length * cos(deg_to_rad(phi))
		var dir := ahead.rotated(Vector3.UP, side * deg_to_rad(phi))
		if grid.trace_walkable(position, position + dir * maxf(go, reach), world_scale): return dir * go
		phi += SLIDE_STEP_DEG
	return Vector3.ZERO

## Square-on against the wall `n`: a step round its end when that is within YIELD_M along it (the nearer side, at
## sin SLIDE_MIN_DEG of the step), else ZERO.
func _yield(ahead: Vector3, n: Vector3, length: float, look: float) -> Vector3:
	var along := n.cross(Vector3.UP).normalized()
	var k := YIELD_STEP_M * world_scale
	while k <= YIELD_M * world_scale + 0.0001:
		for side in [1.0, -1.0]:
			var off: Vector3 = position + along * side * k
			if grid.trace_walkable(position, off, world_scale) and grid.trace_walkable(off, off + ahead * look, world_scale):
				return along * side * length * sin(deg_to_rad(SLIDE_MIN_DEG))
		k += YIELD_STEP_M * world_scale
	return Vector3.ZERO

func _try_move(displacement: Vector3) -> bool:
	if displacement.is_zero_approx(): return false
	var target := position + displacement
	if not grid.segment_walkable(position, target, world_scale): return false
	position = target
	return true
