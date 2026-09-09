class_name ResidentMoment
extends RefCounted
## A short world response yields to player movement and dialogue, then returns home.

var actor: Node3D
var home := Vector3.ZERO
var destination := Vector3.ZERO
var facing_point := Vector3.ZERO
var phase := "idle"
var movement: PlayerMover
var origin := Vector3.ZERO
var _reaction_left := 0.0
var _retry_left := 0.0
var _paused := false
var _home_rotation := 0.0
var reaction_animation := "emote_wave"

func _init(value: Node3D, world_origin: Vector3) -> void:
	actor = value
	home = actor.position
	_home_rotation = actor.rotation.y
	origin = world_origin

func start(point: Vector3, look_at_point: Vector3, animation := "emote_wave", seconds := 3.0) -> void:
	destination = point
	facing_point = look_at_point
	phase = "approaching"
	movement = null
	_retry_left = 0
	reaction_animation = animation
	_reaction_left = maxf(0.0, seconds)

func active() -> bool:
	return phase != "idle" and is_instance_valid(actor)

func finish() -> void:
	if phase in ["approaching", "reacting"]:
		phase = "returning"
		movement = null
		_retry_left = 0

func step(dt: float, paused: bool, route: Callable, can_move := Callable()) -> void:
	if not active(): return
	if paused:
		_paused = true
		_play("idle")
		return
	if _paused:
		_paused = false
		movement = null
		_retry_left = 0
	if phase == "reacting":
		_face(facing_point)
		_play(reaction_animation)
		_reaction_left -= dt
		if _reaction_left <= 0:
			phase = "returning"
			movement = null
		return
	if movement == null:
		_retry_left -= dt
		if _retry_left > 0: return
		movement = route.call(home if phase == "returning" else destination)
		_retry_left = 0.5
		if movement == null:
			_play("idle")
			return
	movement.step(dt)
	var position := movement.position + origin
	position.y = home.y
	if can_move.is_valid() and not can_move.call(actor.position, position):
		movement = null
		_play("idle")
		return
	actor.position = position
	if movement.is_moving():
		actor.rotation.y = atan2(movement.facing.x, movement.facing.z)
		_play("run")
	elif phase == "approaching":
		phase = "reacting"
		_face(facing_point)
		_play(reaction_animation)
	else:
		phase = "idle"
		actor.rotation.y = _home_rotation
		_play("idle")

func _face(point: Vector3) -> void:
	var direction := point - actor.position
	actor.rotation.y = atan2(direction.x, direction.z)

func _play(id: String) -> void:
	var animation := actor.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation and animation.has_animation(id) and animation.current_animation != id:
		animation.play(id)
