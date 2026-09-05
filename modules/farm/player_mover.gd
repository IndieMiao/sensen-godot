class_name PlayerMover
extends RefCounted
## 农场内移动：摇杆直走（逐帧撞墙检查）或点按寻路（沿 BlueprintGrid 路径）。
## 时间不变量按逻辑格：speed 是逻辑米/秒，world_scale 只放大视觉。

var bp: FarmBlueprint
var grid: BlueprintGrid
var world_scale := 1.0
var position := Vector3.ZERO
var speed := 2.5
var facing := Vector3(0, 0, 1)
var joystick := Vector2.ZERO
var _path: Array[Vector2i] = []
var _path_idx := 0

func _init(p_bp: FarmBlueprint, p_grid: BlueprintGrid, p_scale := 1.0) -> void:
	bp = p_bp
	grid = p_grid
	world_scale = p_scale
	position = bp.cell_to_world(bp.anchor("spawn"), world_scale)

func cell() -> Vector2i:
	return bp.world_to_cell(position, world_scale)

func set_target_cell(c: Vector2i) -> bool:
	var p := grid.path(cell(), c)
	if p.is_empty():
		return false
	_path = p
	_path_idx = 1
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

func remaining_path() -> Array[Vector2i]:
	return _path.slice(_path_idx)

func is_moving() -> bool:
	return joystick != Vector2.ZERO or _path_idx < _path.size()

func step(dt: float) -> void:
	var stride := speed * world_scale * dt
	if joystick != Vector2.ZERO:
		var dir := Vector3(joystick.x, 0.0, joystick.y)
		var next := position + dir * stride
		if bp.is_walkable(bp.world_to_cell(next, world_scale)):
			position = next
		facing = dir.normalized()
		return
	if _path_idx >= _path.size():
		return
	var target := bp.cell_to_world(_path[_path_idx], world_scale)
	var to := target - position
	if to.length() <= stride:
		position = target
		_path_idx += 1
	else:
		position += to.normalized() * stride
	if to.length() > 1e-6:
		facing = to.normalized()
