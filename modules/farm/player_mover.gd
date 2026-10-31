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

func stop() -> void:
	joystick = Vector2.ZERO
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
		facing = dir.normalized()
		var asked := (dir * stride).length()
		stuck = asked > 0.0 and (position - was).length() < asked * STUCK_RATIO
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
		if _try_move(increment): continue
		# Preserve the free component of a blocked diagonal without adding sideways input.
		var along_x := Vector3(increment.x, 0, 0)
		var along_z := Vector3(0, 0, increment.z)
		var first := along_x if absf(increment.x) >= absf(increment.z) else along_z
		var second := along_z if absf(increment.x) >= absf(increment.z) else along_x
		var moved := _try_move(first)
		moved = _try_move(second) or moved
		if not moved: break

func _try_move(displacement: Vector3) -> bool:
	if displacement.is_zero_approx(): return false
	var target := position + displacement
	if not grid.segment_walkable(position, target, world_scale): return false
	position = target
	return true
