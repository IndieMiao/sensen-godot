class_name P0LandmarkVisit
extends RefCounted
## q(295) ④: a landmark scene (LandmarkScenes: Alcatraz, Griffith) opened from the P0 map is a P0 world with no
## function — P0's HUD and place chip over it (the chip and Android Back go back to the map), the stick and a tap on the
## ground walk, a pinch zooms, and the scene's own Journey chrome (title, Overview, Follow, + / −) is not built. Nothing
## is sent: its space is "" (P0Runtime.space_of), which the server ignores, and where the player is stays as it was.
## Where the scene has a way out on the ground (Alcatraz's dock, layout `exit`) it wears the rooms' door prompt — i-door,
## and Map as its strip once near (SGODOT-250) — and walking onto it leaves, as a room's door does.
## The scene holds one of these from setup(args) and hands it its p0_* calls.

const EXIT_ID := "landmark:exit"
## The door strip opens within this of the dock (a room's CARD_NEAR_M is for a room; the dock is out in the open).
const NEAR_M := 4.0
## Walking onto the dock leaves once the player has been this far from it (P0Room.EXIT_ARM_M / EXIT_RADIUS_M; wider
## here: Alcatraz lands the player 1.1 m from its dock).
const EXIT_ARM_M := 2.5
const EXIT_RADIUS_M := 0.8

var scene: Node3D
var chip := ""
var rt: P0Runtime
var stick := Vector2.ZERO
var _armed := false
var _to_exit := false
var _leaving := false

## What the map hands AppRouter.open_instance: the chip (`San Francisco · Alcatraz Island`, also the loading cover's
## destination) and the landmark.
static func args_for(entry: Dictionary, city: String) -> Dictionary:
	var place := str(entry.get("name", ""))
	return {"p0_visit": true, "landmark": str(entry.get("id", "")), "chip": "%s · %s" % [city, place] if city != "" else place}

static func wanted(args: Dictionary) -> bool: return bool(args.get("p0_visit", false))

func _init(s: Node3D, args: Dictionary) -> void:
	scene = s
	chip = str(args.get("chip", ""))

## From the scene's _ready, once it stands: the world P0 drives.
func start() -> void:
	rt = P0Runtime.ensure()
	rt.attach(scene)
	rt.ui.set_place(chip)
	_armed = false

func resume() -> void:
	if rt == null: return
	rt.attach(scene)
	rt.ui.set_place(chip)

func exit_at() -> Vector3:
	return scene.call("exit_position")

func frame(dt: float) -> void:
	# popped (the chip, Back) before the map below takes the world back: nothing of it is left to drive
	if _leaving or rt == null or not scene.is_inside_tree(): return
	scene.call("step_stick", stick, dt)   # let go: the run stops (unless a tap's walk goes on)
	var exit := exit_at()
	if exit == Vector3.INF: return
	var d := _flat(scene.call("player_position"), exit)
	if d > EXIT_ARM_M: _armed = true
	elif _armed and d <= EXIT_RADIUS_M:
		leave()
		return
	if _to_exit and not bool(scene.call("walking")): _to_exit = false
	var cam := scene.get_viewport().get_camera_3d()
	var on := cam != null and not cam.is_position_behind(exit)
	var at := cam.unproject_position(exit + Vector3.UP * 0.6) if on else Vector2.ZERO
	var door := P0Logic.icon("door")
	if on and d <= NEAR_M: rt.ui.name_bar(EXIT_ID, door, "Map", "", at, true)
	else: rt.ui.world_icon(EXIT_ID, door, at, on)

func tap(screen: Vector2) -> void:
	if rt and rt.ui.has_modal(): return
	if rt and str(rt.ui.tapped_card) == EXIT_ID and exit_at() != Vector3.INF:
		_to_exit = true
		_armed = true   # going there on purpose: arriving leaves
		scene.call("walk_to", exit_at())
		return
	scene.call("walk_to_screen", screen)

func leave() -> void:
	if _leaving: return
	_leaving = true
	clear()
	if rt: rt.leave_world()

## The door prompt goes with the scene (a world's prompts are the HUD's).
func clear() -> void:
	if rt == null: return
	rt.ui.name_bar(EXIT_ID, null, "", "", Vector2.ZERO, false)
	rt.ui.world_icon(EXIT_ID, null, Vector2.ZERO, false)

## The stick moves `player` along the ground as `cam` faces, at `speed` scaled by how far it is pushed, kept on the
## navigation `nav` (its nearest point, so a push into a wall slides along it). False when the push is too small.
static func stick_step(player: Node3D, nav: RID, cam: Camera3D, speed: float, v: Vector2, dt: float) -> bool:
	var right := cam.global_basis.x
	right.y = 0
	var ahead := -cam.global_basis.z
	ahead.y = 0
	var dir := right.normalized() * v.x - ahead.normalized() * v.y
	if dir.length() > 1.0: dir = dir.normalized()
	if dir.length() < 0.05: return false
	player.position = NavigationServer3D.map_get_closest_point(nav, player.position + dir * speed * dt)
	player.look_at(player.position + dir, Vector3.UP)
	return true

## Shot steps (P0Runtime._dev_shot hands its unknown ones to the world): lmtap:x:y a tap at that viewport point;
## lmzoom:f a pinch by f; lmgoto:<point> the player stood at one of the scene's review points (dev_point), lmwalk:<point>
## walked there; lmexit walked to the way out.
func dev(step: Array) -> bool:
	match str(step[0]):
		"lmtap": tap(Vector2(float(step[1]), float(step[2])))
		"lmzoom": scene.call("p0_zoom", float(step[1]))
		"lmgoto":
			var at: Vector3 = scene.call("dev_point", str(step[1]))
			if at == Vector3.INF: return false
			scene.call("dev_stand", at)
		"lmwalk":
			var at: Vector3 = scene.call("dev_point", str(step[1]))
			if at == Vector3.INF: return false
			scene.call("walk_to", at)
		"lmexit":
			_to_exit = true
			_armed = true
			scene.call("walk_to", exit_at())
		_: return false
	return true

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
