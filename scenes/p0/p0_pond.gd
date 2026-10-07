extends Node3D
## A map pond for P0 (ponds live at fixed map locations): the old polished pond world — daylight sky,
## PondScenery, the PR #4 water (FishingWater: caustics, foam, lilies, shore stones, reflection), the
## pond nav grid — and the old fishing presentation (pose, rod, line, float, landing arc, close camera)
## driven by P0FishingPanel. Movement, HUD and results follow the new UI flow from P0Runtime.

const FarmCamera = preload("res://modules/farm/farm_camera.gd")

## Pond shapes → P0 fishing sites, kept only for the cast command's old `site` field. The server ignores it and
## takes the template from its own table for the pond the player is at (p0_place, q(36): Reed Pond is a Pond).
const SITE_FOR_TEMPLATE := {"meander": "river"}

var rt: P0Runtime
var entry: Dictionary = {}
var site_spec: Dictionary = {}
var site := "pond"
var bp: FarmBlueprint
var grid: BlueprintGrid
var cam: Camera3D
var environment: Environment
var world_env: WorldEnvironment
var actor: P0Actor
var panel: P0FishingPanel
var view: FishingPresentation
var _focus := Vector3(6, 0, -6)
var _cam_follow := P0Follow.new()
var _zoom := 1.0
var _plan: Dictionary = {}
# Camera blend from the fishing close-up back to the pond framing when the panel closes.
var _blend_from := Transform3D.IDENTITY
var _blend_size := 7.5
var _blend_t := 1.0

## The catalog pond id: the session sends it with the entry read and every command from here (q(36)).
func p0_place() -> String:
	return str(entry.get("id", ""))

static func site_for(template_id: String) -> String:
	return str(SITE_FOR_TEMPLATE.get(template_id, "pond"))

func setup(args: Dictionary) -> void:
	entry = SystemPonds.location(str(args.get("pond_id", "")))

func _ready() -> void:
	P0Runtime.mark("%s _ready start" % name)
	if entry.is_empty():
		push_error("P0 pond: unknown pond id")
		return
	site_spec = SystemPonds.site(entry)
	site = site_for(str(entry.get("template_id", "")))
	get_viewport().transparent_bg = false
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("d8e9ad")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e4f0ff")
	environment.ambient_light_energy = 0.65
	environment.sky = preload("res://assets/ponds/art/pond_daylight_sky.tres")
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "PondSun"
	sun.rotation_degrees = Vector3(-55, -137, 0)
	sun.light_color = Color("fff3dc")
	sun.light_energy = 1.15
	sun.light_specular = 0.13
	sun.shadow_enabled = true
	sun.shadow_blur = 3.0
	sun.shadow_opacity = 0.82
	sun.light_angular_distance = 1.0
	sun.directional_shadow_max_distance = 65
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.05
	cam.far = 80
	add_child(cam)
	cam.make_current()
	add_child(PondScenery.build(entry))
	var water := FishingWater.build(str(entry.id), site_spec)
	water.water_material.set_shader_parameter("sun_direction", sun.global_basis.z.normalized())
	add_child(water)
	bp = SystemPonds.blueprint(entry)
	grid = BlueprintGrid.new(bp)
	actor = P0Actor.new()
	add_child(actor)
	actor.setup(bp, grid, cam)
	_focus = _rest_focus()
	panel = P0FishingPanel.new()
	add_child(panel)
	panel.opened.connect(_begin_fishing)
	panel.closed.connect(_end_fishing)
	_update_camera()
	rt = P0Runtime.ensure()
	rt.attach(self)
	rt.ui.set_mode("fish", "Shanghai · " + str(entry.get("name", "Pond")))

func _exit_tree() -> void:
	_end_fishing()
	if rt: rt.detach(self)

func p0_surface() -> String: return "pond"

# ---------------------------------------------------------------- frame
func p0_joystick(v: Vector2) -> void:
	if actor: actor.set_input(v)
	if v != Vector2.ZERO: _plan = {}

## Old pond taps: water → walk to the nearest bank spot and cast there; grass → walk there.
func p0_tap(screen: Vector2) -> void:
	if panel.visible: return
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.001: return
	var point := origin + dir * (-origin.y / dir.y)
	if FishingModel.contains(str(entry.id), point, 0, site_spec):
		var a := _action_state(rt.session.current())
		if a.get("enabled", false) and str(a.cmd.get("type", "")) == "cast": _go_cast(point)
		elif str(a.cmd.get("type", "")) == "energy_card": rt._on_action(a.cmd)
		else: rt.ui.toast(str(a.get("sub", "")))
	else:
		_plan = {}
		actor.mover.set_target_position(point)

func p0_frame(v: Dictionary, dt: float) -> void:
	if panel.visible: return   # the fishing presentation owns rig and camera
	actor.step(dt)
	# Walking to the cast origin finished: open the panel and cast.
	if not _plan.is_empty() and not actor.mover.is_moving():
		var plan := _plan
		_plan = {}
		if actor.position.distance_to(plan.origin) < 0.35: _open_panel(plan)
	_follow(dt)
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + dt / 0.45)
		var k := ease(_blend_t, -2.0)
		cam.global_transform = _blend_from.interpolate_with(cam.global_transform, k)
		cam.size = lerpf(_blend_size, cam.size, k)
	rt.ui.set_action(_action_state(v))
	if not rt.ui.has_modal():
		rt.ui.teach("cast", "Casting uses 5 Energy. If the fish gets away, most of it comes back.")
		if P0Logic.bag_count(v, "bait_worm") > 0: rt.ui.teach("bait", "Tap Worm Bait to put it on the hook · faster bites, more Fine fish.")

## Away from the bank the key still casts: it walks to the nearest bank spot first (the old Go fishing).
func _action_state(v: Dictionary) -> Dictionary:
	var a := P0Logic.fish_action(v, rt.ui.selected_bait, site)
	if not _plan.is_empty(): return {"icon": "rod", "verb": "Cast", "sub": "Walking to the shore", "enabled": false, "amber": false, "cmd": {}, "need": 0}
	if not a.get("enabled", false) or str(a.cmd.get("type", "")) != "cast": return a
	if _shore_distance() > float(FishingModel.data().shore_range) + 0.9: a.sub = "Walk to the shore"
	return a

func _shore_distance() -> float:
	var shore := FishingModel.nearest_water(str(entry.id), actor.position, site_spec)
	return Vector2(shore.x - actor.position.x, shore.z - actor.position.z).length()

func p0_action(cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) == "cast": _go_cast(Vector3.INF)

func _go_cast(point: Vector3) -> void:
	var plan := FishingModel.plan(str(entry.id), actor.position, point, grid, site_spec)
	if plan.is_empty():
		rt.ui.toast("Can't reach the water from here")
		return
	if actor.position.distance_to(plan.origin) < 0.35:
		_open_panel(plan)
	elif actor.mover.set_target_position(plan.origin):
		_plan = plan
	else:
		rt.ui.toast("Can't reach that spot")

func p0_energy_verb() -> String: return "Cast"

func _open_panel(plan: Dictionary) -> void:
	actor.face(plan.target)
	panel.open_p0(rt, str(entry.id), site_spec, plan.target, site, "Shanghai · " + str(entry.get("name", "Pond")))

func _begin_fishing(_id: String) -> void:
	actor.lock(true)
	rt.ui.set_surface("busy")
	view = FishingPresentation.new()
	add_child(view)
	view.configure(panel, actor, actor.rig, cam, [])

func _end_fishing() -> void:
	if is_instance_valid(view):
		var close_up := cam.global_transform
		var close_size := cam.size
		view.finish()   # puts the pond camera back at once …
		_blend_from = close_up   # … so ease out of the close-up instead of cutting
		_blend_size = close_size
		_blend_t = 0.0
	view = null
	if actor: actor.lock(false)
	if rt and rt.world == self: rt.ui.set_surface("pond")

## Server events for this world: the cast lands, the catch settles, a refusal resets the panel.
func p0_event(ev: Dictionary, _v: Dictionary) -> bool:
	match str(ev.get("kind", "")):
		"cast":
			if panel.visible: panel.on_cast(ev)
		"cast_refused":
			if panel.visible: panel.on_refused()
		"catch":
			if panel.visible:
				_settle(ev, panel.on_catch(ev), rt.last_first_catch_xp)
				return true
		"fish_abort":
			if panel.visible: panel.on_abort()
		"send_failed":
			if panel.visible: panel.on_send_failed(ev.cmd)
	return false

## After the landing arc (or the ripples), close the panel, ease the camera back to the pond and let the
## runtime show the result card or float at the cast point (FISH-3 / FISH-5).
func _settle(ev: Dictionary, delay: float, first_xp: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree(): return
	var land := panel.landing
	if panel.visible: panel.close()
	var at := cam.unproject_position(land) if not cam.is_position_behind(land) else Vector2.INF
	rt.last_first_catch_xp = first_xp
	rt._on_catch(ev, rt.last_xp_lines, at)

# ---------------------------------------------------------------- camera (old pond framing + safe box)
func _follow(_dt: float) -> void:
	_focus = _cam_follow.step(cam, _focus, actor.position, actor.mover.is_moving(), _dt)
	_update_camera()

## The opening shot leans toward the nearest water so the pond is in the frame (held until the first step).
func _rest_focus() -> Vector3:
	var shore := FishingModel.nearest_water(str(entry.id), actor.position, site_spec)
	var lean := Vector3(shore.x - actor.position.x, 0, shore.z - actor.position.z).limit_length(2.6) * 0.5
	return actor.position + lean

func _update_camera() -> void:
	cam.size = 7.5 / _zoom
	cam.position = _focus + Vector3(0, 1, 1).normalized() * 40
	cam.look_at(_focus, Vector3.UP)

func p0_zoom(f: float) -> void: _zoom = clampf(_zoom / f, 0.5, 1.4)
func p0_recenter() -> void:
	_focus = actor.position
	_cam_follow.held = false

func p0_anchor() -> Vector2:
	return cam.unproject_position(actor.position + Vector3(0, 2.0, 0))

func is_back_navigation_locked() -> bool:
	if panel and panel.visible:
		panel.close()
		return true
	return false

func suspend() -> void:
	_end_fishing()
	panel.hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	cam.current = false
	world_env.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	show()
	get_viewport().transparent_bg = false
	world_env.environment = environment
	cam.make_current()
	if rt: rt.attach(self)

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"goto":
			actor.teleport(Vector3(float(step[1]), 0, float(step[2])))
			_focus = _rest_focus()
		"shore":
			# stand at the plan origin nearest the spawn, facing the water
			var plan := FishingModel.plan(str(entry.id), actor.position, Vector3.INF, grid, site_spec)
			if not plan.is_empty():
				actor.teleport(plan.origin)
				actor.face(plan.target)
				_focus = _rest_focus()
		"cast": _go_cast(Vector3.INF)
		_: return false
	return true

func p0_until(name: String) -> bool:
	match name:
		"bite": return panel.visible and panel.phase == "hook"
		"reel": return panel.visible and panel.phase == "playing"
		"result": return panel.visible and panel.phase == "result"
		"idle": return not panel.visible
	return false
