class_name P0Actor
extends Node3D
## The player character shared by every P0 world — the old polished rig, clips and mover, driven by
## the new joystick. States: idle / move / labour (a real labour_* clip, movement locked for one
## beat) / locked (fishing or cooking owns the rig). Walls and plots come from the world's grid.

const LABOUR_S := 0.62   # one labour clip beat; hold-to-repeat waits for it

var rig: AvatarRig
var mover: PlayerMover
var state := "idle"
var _clip := ""
var _labour_left := 0.0
var _attack_left := 0.0
var _attack_lock := 0.0
var _joy := Vector2.ZERO
## SGODOT-306 (不知火舞 2a96260f): the stick held against something the body cannot pass — after PUSH_IDLE_S of steps
## that went nowhere the body stands (idle), still turning with the stick; a step that moves runs again at once.
## Only the clip: state stays "move" and mover.is_moving() keeps its meaning (the camera, doors, auto-walk use it).
const PUSH_IDLE_S := 0.1
var _stuck_s := 0.0
var cam: Camera3D
## Optional ground height under a point (the farm's raised beds); the rig steps up onto it.
var ground_height: Callable

func setup(bp: FarmBlueprint, grid: BlueprintGrid, camera: Camera3D, spawn := Vector3.INF) -> void:
	cam = camera
	mover = PlayerMover.new(bp, grid)
	if spawn != Vector3.INF: mover.position = spawn
	position = mover.position
	rig = Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	rig.rotation.y = PI   # the rig faces +Z; look_at points -Z at the target
	# Default sleep/reduced distances freeze animation at game-camera distance (pond.gd uses 50 / 80).
	for child in rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 50
			child.sleep_distance = 80
	add_child(rig)
	rig.config_applied.connect(func(_c): _play("idle", true))
	Avatar.follow_saved_outfit(rig)

## Joystick in screen space → world direction relative to the camera, so "up" walks away from it.
func set_input(v: Vector2) -> void:
	_joy = v

func facing() -> Vector3:
	return mover.facing

func busy() -> bool:
	return state in ["labour", "locked"]

func step(dt: float) -> void:
	_attack_left = maxf(0.0, _attack_left - dt)
	_attack_lock = maxf(0.0, _attack_lock - dt)
	if state == "labour":
		_labour_left -= dt
		if _labour_left <= 0.0: state = "idle"
	var stepped := false
	if state in ["labour", "locked"] or cam == null:
		mover.stop()
	elif _attack_lock > 0.0:
		pass   # a slash holds still to its strike; a walk tapped meanwhile keeps its path and goes after it (苏烈 on #299)
	else:
		var right := cam.global_basis.x
		right.y = 0
		var fwd := -cam.global_basis.z
		fwd.y = 0
		var dir := right.normalized() * _joy.x - fwd.normalized() * _joy.y
		mover.set_joystick(Vector2(dir.x, dir.z).limit_length(1.0))
		mover.step(dt)
		stepped = true
	var y := float(ground_height.call(mover.position)) if ground_height.is_valid() else 0.0
	position = Vector3(mover.position.x, lerpf(position.y, y, clampf(dt * 14.0, 0, 1)), mover.position.z)
	_stuck_s = _stuck_s + dt if stepped and mover.stuck else 0.0
	if mover.is_moving() and _attack_lock <= 0.0:
		look_at(position + mover.facing, Vector3.UP)
		state = "move"
		_attack_left = 0.0   # the stick past the strike takes the body back from the slash's follow-through
		_play("idle" if _stuck_s >= PUSH_IDLE_S else "run")
		# The slide spec: along a wall the run goes at the slide's speed over the walk's, not under SLIDE_RUN_MIN.
		if _clip == "run" and mover.sliding: _speed(maxf(PlayerMover.SLIDE_RUN_MIN, mover.stick_ratio))
		elif _clip == "run": _speed(1.0)
	elif state == "move":
		state = "idle"
	if state == "idle" and _attack_left <= 0.0: _play("idle")

## Face a world point and play one labour beat (till / sow / water / harvest).
func labour(verb: String, target: Vector3) -> void:
	var to := target - position
	to.y = 0
	if to.length() > 0.01:
		mover.facing = to.normalized()
		look_at(position + mover.facing, Vector3.UP)
	state = "labour"
	_labour_left = LABOUR_S
	_play(AnimPlaceholders.clip_for(verb), true)

## One swing of Combat's Attack (SGODOT-291; 不知火舞 on 291): its slash clip for `seconds`, the body held still — even
## on the move — until `lock` (its strike); past it the stick cancels the follow-through and the body moves at once,
## while with the stick let go the clip plays out. The swing itself (its hit, its arc) is the combat's.
func attack(clip: String, seconds: float, lock := 0.0) -> void:
	if state in ["labour", "locked"]: return
	mover.stop()
	if state == "move": state = "idle"
	_attack_left = seconds
	_attack_lock = minf(lock, seconds)
	_play(clip, true)

## A slash clip is playing (the sword shows in hand only then).
func attacking() -> bool: return _attack_left > 0.0

func face(target: Vector3) -> void:
	var to := target - position
	to.y = 0
	if to.length() > 0.01:
		mover.facing = to.normalized()
		look_at(position + mover.facing, Vector3.UP)

## Fishing presentation and the cooking stage take the rig over; release returns to idle.
func lock(on: bool) -> void:
	state = "locked" if on else "idle"
	if not on: _play("idle", true)

## Stop where one stands, in the idle pose this very frame (play_motion applies it at once): for a presentation that
## keeps the pose it finds as its base — a Cast on the move froze the run clip mid-stride, one foot up (Joey, 296 #8).
func stand_still() -> void:
	mover.stop()
	if state == "move": state = "idle"
	_play("idle", true)

## The player on screen through `camera` (SGODOT-266, 不知火舞 on #190), for UI that keeps off them: from the feet to the
## top of the head — the outfit's own top (hair, a hat) once the rig has drawn, else HEAD_M — and HALF_WIDTH_M either side
## of the body's axis (P0Pond's player box for the reel gauge). Not the rig's box projected whole: its rest-pose arms
## and its depth would make it half again as wide and tall as the figure.
const HEAD_M := 1.8
const HALF_WIDTH_M := 0.3
func screen_box(camera: Camera3D) -> Rect2:
	var box := DressingCamera.merged_aabb(rig) if rig != null else AABB()
	var top := box.end.y if box.has_volume() else position.y + HEAD_M
	var feet := camera.unproject_position(position)
	var head := camera.unproject_position(Vector3(position.x, top, position.z))
	var side := camera.unproject_position(position + camera.global_basis.x * HALF_WIDTH_M).x - feet.x
	var r := Rect2(feet, Vector2.ZERO).expand(head)
	return Rect2(r.position.x - absf(side), r.position.y, r.size.x + absf(side) * 2.0, r.size.y)

func teleport(p: Vector3) -> void:
	mover.stop()
	mover.position = p
	position = p

## The rig's clips' speed (1 but for a slide's run).
func _speed(scale: float) -> void:
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer if rig != null else null
	if ap != null and ap.speed_scale != scale: ap.speed_scale = scale

func _play(clip: String, force := false) -> void:
	if rig == null or (clip == _clip and not force): return
	_clip = clip
	_speed(1.0)
	rig.play_motion(clip)
