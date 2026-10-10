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
var _joy := Vector2.ZERO
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
	if state == "labour":
		_labour_left -= dt
		if _labour_left <= 0.0: state = "idle"
	if state in ["labour", "locked"] or cam == null:
		mover.stop()
	else:
		var right := cam.global_basis.x
		right.y = 0
		var fwd := -cam.global_basis.z
		fwd.y = 0
		var dir := right.normalized() * _joy.x - fwd.normalized() * _joy.y
		mover.set_joystick(Vector2(dir.x, dir.z).limit_length(1.0))
		mover.step(dt)
	var y := float(ground_height.call(mover.position)) if ground_height.is_valid() else 0.0
	position = Vector3(mover.position.x, lerpf(position.y, y, clampf(dt * 14.0, 0, 1)), mover.position.z)
	if mover.is_moving():
		look_at(position + mover.facing, Vector3.UP)
		state = "move"
		_attack_left = 0.0   # walking takes the body back from a slash at once
		_play("run")
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

## One swing of Combat's Attack (SGODOT-291): its slash clip over standing still, for `seconds`. Not a lock — walking
## takes the body back to the run at once; the swing itself (its hit, its arc) is the combat's and stands either way.
func attack(clip: String, seconds: float) -> void:
	if state in ["labour", "locked"] or mover.is_moving(): return
	_attack_left = seconds
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

func _play(clip: String, force := false) -> void:
	if rig == null or (clip == _clip and not force): return
	_clip = clip
	rig.play_motion(clip)
