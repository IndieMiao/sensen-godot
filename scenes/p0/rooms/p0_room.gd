class_name P0Room
extends Node3D
## Shell for indoor P0 spaces (SGODOT-226): the farmhouse kitchen corner and the four outposts of SGODOT-227.
## A room = one art instance (the Basic Room placeholder now, the final model later) + world anchors from its
## layout.json and an optional `<space>.anchors.json` (WP7-B F-03 ③), the shared P0Actor walking a grid built
## from the art's collision shapes, the room's own accepted camera with the safe-box follow, and tap-triggered
## facilities (LOCK-07): tap a use_ / npc_ anchor → walk to its stand_ anchor → _on_facility(name). The HUD is
## the facility surface "room" (Bag only, LOCK-04). Rooms open with AppRouter.open_instance like the ponds;
## the door (exit anchor) or Back returns to the world below (farmhouse → farm, outpost → map).
##
## Subclasses fill art_scene / layout_path / anchors_path / place_name in setup(args) or _init(), and override
## the hooks below: _dress_art, _room_ready, _tappable, _on_facility, _marker, _module_visible, _room_frame,
## _on_joystick.

signal facility_tapped(name: String)
signal left()

const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const BASIC_ROOM_ART := "res://scenes/basic_room/basic_room_art.tscn"
const BASIC_ROOM_LAYOUT := "res://assets/rooms/basic_room/layout.json"
## Engineering defaults (SGODOT-226); WP7 v2 finalises the camera numbers from Figma.
const TAP_RADIUS := 64.0          # F-04 screen pick radius (P0 uses 56–80 px)
const MIN_HIT := 44.0             # a facility tapped by its art: at least this box on screen (touch target)
const CARD_NEAR_M := 3.0          # finger cards float up this close (LOCK-07)
const EXIT_RADIUS_M := 0.6        # walking onto the door leaves, no confirmation
const EXIT_ARM_M := 1.0           # … once the player has been this far from it (spawn is one step inside)
const REACH_M := 0.35             # close enough to a stand_ point to use the facility
const FOCUS_S := 0.4              # push-in ease
const HUD_BOTTOM := UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H   # below the safe-area top
const ZOOM_RANGE := Vector2(0.8, 1.6)
const FRAME_W := 0.84             # opening shot: player + facilities within 84 % of the width …
const FRAME_H := 0.60             # … and the middle 60 % of the height (§10.1)
const MIN_VIEW_K := 0.8           # … but never closer than 80 % of the room's accepted view
const SIDE_MARGIN := 18.0         # … and at least this many px clear beside the art on both sides (227: ≥ 16)
const BADGE_SCRIPT := "res://scenes/ui_kit/ui_status_badge.gd"   # UiStatusBadge (SGODOT-221)

var art_scene: PackedScene
var layout_path := BASIC_ROOM_LAYOUT
var anchors_path := ""
var city := "Shanghai"
var place_name := ""
## Finger card over the door; per space (farmhouse "Door · Back to farm", market "Exit · Back to map").
var exit_text := "Door · Back to map"
## Where the door leads, for the world prompts (SGODOT-250: i-door + "Map" / "Farm"); "" keeps the old door card.
var exit_to := ""
## The colours around the room as they must appear on screen (SGODOT-227 美术决定 2b53b84d, sampled from the scene's
## signed render): {top, bottom, blend: [from, to]} in hex; top and bottom flat, a smooth change between those screen
## heights (0 = top, 1 = bottom); `top` alone is one colour. Empty: the kit's review background, else the Basic Room
## plate (#F7F6EA on screen, 248).
var backdrop := {}
## Level the modules show for (module visibility: module_levels[module] <= level).
var level := 1
## Facilities tapped by their art instead of a radius round the anchor (int6 C8, 不知火舞 on 226): anchor name →
## node under `art`. Its screen box (grown up and sideways to MIN_HIT) takes the tap; where boxes overlap the smaller
## one wins (small things first); these anchors never take the radius fallback, so a stove does not reach over the
## shelf beside it.
var hit_nodes := {}
var module_levels := {}
## Tests and previews run without the P0 runtime (no session, HUD or AppRouter).
var use_runtime := true

var rt: P0Runtime
var actor: P0Actor
var cam: Camera3D
var bp: FarmBlueprint
var grid: BlueprintGrid
var layout: Dictionary = {}
var art: Node3D
var room: Node3D          ## layout space: art and anchors live here, placed at the blueprint offset
var floor_y := 0.0
var floor_rect := Rect2()  ## walkable floor footprint in layout space (x, z)
var environment: Environment
var world_env: WorldEnvironment

var _anchors := {}        # name -> Marker3D
var _data := {}           # name -> anchor dictionary
var _cam_dir := Vector3(9.5, 6.8, 11.2).normalized()
var _cam_dist := 16.0
var _cam_size := 10.75
var _focus := Vector3.ZERO
var _follow := P0Follow.new()
var _zoom := 1.0
const ElasticZoom = preload("res://modules/p0/p0_elastic_zoom.gd")
var _pinch = ElasticZoom.new(ZOOM_RANGE.x, ZOOM_RANGE.y)   # rubber band past the range
var _zoom_at := Vector2.INF                              # the last pinch centre (screen)
var _framed := Vector3.ZERO   # the opening shot's centre
var _fits := false            # the whole floor fits the opening shot: hold it instead of following
var _shot := {}           # push-in: {center: Vector3, size: float, release_on_move: bool}
var _shot_k := 0.0
var _shot_tween: Tween
var _walk := {}           # {name, point: Vector3, done: Callable}
var _shown := {}          # marker ids currently on screen
var _card := ""           # the one tappable whose finger card shows (SGODOT-250: one card at a time)
var _exit_armed := false
var _leaving := false
var _perf_left := -1.0    # debug builds with user://p0_perf: log fps / draw calls every 5 s (logcat tag godot)

func setup(_args: Dictionary) -> void: pass

## Room kit art by id (SGODOT-227 scene integration): "basic_room" (the default) or a Scene_design kit such as
## "coffee_shop", read from scenes/<id>/<id>_art.tscn and assets/rooms/<id>/layout.json. A kit that is missing
## keeps the Basic Room, so a space never opens empty.
func use_art(id: String) -> void:
	if id == "" or id == "basic_room": return
	var scene := "res://scenes/%s/%s_art.tscn" % [id, id]
	var kit_layout := "res://assets/rooms/%s/layout.json" % id
	if not (ResourceLoader.exists(scene) and FileAccess.file_exists(kit_layout)):
		push_warning("P0Room: no room kit '%s', keeping the Basic Room" % id)
		return
	art_scene = load(scene)
	layout_path = kit_layout

func _ready() -> void:
	if use_runtime: P0Runtime.mark("%s _ready start" % name)
	if art_scene == null: art_scene = load(BASIC_ROOM_ART)
	layout = P0RoomAnchors.read_json(layout_path)
	# Pushed above the map, whose tiles show through a transparent root (SGODOT-248); the map makes it transparent
	# again on its own resume. Same as p0_farm / p0_pond.
	get_viewport().transparent_bg = false
	_build_environment()
	room = Node3D.new()
	room.name = "Room"
	add_child(room)
	_build_hearth_glow()   # before the art: the Basic Room's particle fire (SGODOT-236) takes ../HearthGlow
	art = art_scene.instantiate()
	room.add_child(art)
	_dress_art()
	_apply_module_visibility()
	var nav := P0RoomNav.build(P0RoomNav.shapes_from(art))
	bp = nav.bp
	grid = BlueprintGrid.new(bp)
	floor_y = float(nav.floor_y)
	floor_rect = nav.bounds
	room.position = nav.offset
	_build_lights()
	_build_anchors()
	_build_camera()
	actor = P0Actor.new()
	add_child(actor)
	var spawn := anchor("spawn")
	var at := P0RoomNav.nearest_walkable(bp, spawn.global_position if spawn else bp.cell_to_world(Vector2i(bp.grid.x / 2, bp.grid.y / 2)))
	actor.setup(bp, grid, cam, Vector3(at.x, floor_y, at.z))
	actor.ground_height = func(_p: Vector3) -> float: return floor_y
	if spawn: actor.face(actor.position + yaw_dir(float(_data.spawn.get("yaw_degrees", 180))))
	_room_ready()
	frame_all()   # after the subclass spawned what can be tapped (keepers, residents)
	if OS.is_debug_build() and FileAccess.file_exists("user://p0_perf"): _perf_left = 5.0
	if use_runtime:
		rt = P0Runtime.ensure()
		rt.attach(self)
		rt.ui.set_place(city + " · " + place_name)

func _exit_tree() -> void:
	if rt: rt.detach(self)

# ---------------------------------------------------------------- hooks for subclasses
## Adds props to the art before module visibility and the walkable grid are read. By default the anchors file's
## placeholder props, named as modules and shown from their `level` (module_levels): `from` copies an art piece;
## `scene` instances a model (with `atlas`, its shared albedo; `collider` {at, size} in model units). A prop
## whose source is missing is skipped, so its module and anchors stay hidden.
func _dress_art() -> void:
	for p in P0RoomAnchors.props(P0RoomAnchors.read_json(anchors_path)):
		var copy := _prop_node(p)
		if copy == null: continue
		copy.name = str(p.name)
		copy.position = P0RoomAnchors.vec(p.position)
		copy.rotation = Vector3(0.0, deg_to_rad(float(p.get("yaw_degrees", 0))), 0.0)
		copy.scale = Vector3.ONE * float(p.get("scale", 1.0))
		art.add_child(copy)
		if p.has("level"): module_levels[str(p.name)] = int(p.level)

func _prop_node(p: Dictionary) -> Node3D:
	if p.has("from"):
		var src := art.get_node_or_null(NodePath(str(p.from))) as Node3D
		return src.duplicate() as Node3D if src else null
	var path := str(p.get("scene", ""))
	if path == "" or not ResourceLoader.exists(path): return null
	var holder := Node3D.new()
	var model := (load(path) as PackedScene).instantiate() as Node3D
	holder.add_child(model)
	var atlas := str(p.get("atlas", ""))
	if atlas != "" and ResourceLoader.exists(atlas):
		var mat := StandardMaterial3D.new()   # the Basic Room atlas look (BasicRoomArt._setup_room)
		mat.albedo_texture = load(atlas)
		mat.roughness = 0.8
		mat.metallic_specular = 0.28
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		for m in model.find_children("*", "MeshInstance3D", true, false): (m as MeshInstance3D).material_override = mat
	var c: Dictionary = p.get("collider", {})
	if not c.is_empty():
		var body := StaticBody3D.new()
		body.position = P0RoomAnchors.vec(c.at)
		var shape := BoxShape3D.new()
		shape.size = P0RoomAnchors.vec(c.size)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		holder.add_child(body)
	return holder

func _room_ready() -> void: pass

## Anchor names the player can tap; default every visible use_ / npc_ anchor plus the door.
func _tappable() -> PackedStringArray:
	var out := PackedStringArray()
	for n in _anchors.keys():
		var p := P0RoomAnchors.prefix_of(n)
		if (p == "use" or p == "npc" or n == "exit") and anchor(n) != null: out.append(n)
	return out

## Called once the player stands at the facility (after facility_tapped).
func _on_facility(_name: String) -> void: pass

## Finger card and status badge over a tappable anchor: {text, badge, caption, icon}; badge is a STATE-ICONS
## key ("available", "countdown", "ready", … = UiStatusBadge.State in lower case). Empty = nothing; the
## door's card comes from exit_text.
func _marker(name: String, _view: Dictionary) -> Dictionary:
	if name != "exit": return {}
	return {kind = "facility", icon = P0Logic.icon("door"), name = exit_to} if exit_to != "" else {text = exit_text}

func _module_visible(module: String) -> bool:
	return level >= int(module_levels.get(module, 0))

func _room_frame(_view: Dictionary, _dt: float) -> void: pass

## Joystick input before it moves the player (sitting players stand up here, SGODOT-227).
func _on_joystick(_v: Vector2) -> void: pass

# ---------------------------------------------------------------- anchors
## The anchor node, or null when it does not exist or its module is hidden.
func anchor(n: String) -> Marker3D:
	var m: Marker3D = _anchors.get(n)
	return m if m != null and m.visible else null

func anchors(prefix: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for n in _anchors.keys():
		if str(n).begins_with(prefix) and anchor(n) != null: out.append(_anchors[n])
	return out

func anchor_data(n: String) -> Dictionary: return _data.get(n, {})

## Re-applies module visibility to the art and its anchors (call after `level` or module_levels change; the
## walkable grid keeps the modules shown when the room opened).
func refresh_modules() -> void:
	_apply_module_visibility()
	for n in _anchors.keys():
		var m: Marker3D = _anchors[n]
		var mod := str(_data[n].get("module", ""))
		m.visible = mod == "" or (art.has_node(NodePath(mod)) and (art.get_node(NodePath(mod)) as Node3D).visible)

func _apply_module_visibility() -> void:
	for c in art.get_children():
		if c is Node3D: (c as Node3D).visible = _module_visible(str(c.name))

func _build_anchors() -> void:
	var holder := Node3D.new()
	holder.name = "Anchors"
	room.add_child(holder)
	for a in P0RoomAnchors.merge(layout, P0RoomAnchors.read_json(anchors_path)):
		var m := Marker3D.new()
		m.name = str(a.name)
		m.position = P0RoomAnchors.vec(a.get("position"))
		if a.has("yaw_degrees"): m.rotation.y = deg_to_rad(float(a.yaw_degrees))
		holder.add_child(m)
		_anchors[str(a.name)] = m
		_data[str(a.name)] = a
	refresh_modules()

## yaw_degrees → facing (WP7-B §4): 0 = −Z (back wall), 90 = −X, 180 = +Z (camera side), −90 = +X.
static func yaw_dir(yaw_degrees: float) -> Vector3:
	var r := deg_to_rad(yaw_degrees)
	return Vector3(-sin(r), 0.0, -cos(r))

# ---------------------------------------------------------------- world (lighting from the Basic Room benchmark)
func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = backdrop_color()   # also the Backdrop plate's colour, see _backdrop()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var review := review_lighting()   # empty for the Basic Room: the benchmark values below (249)
	environment.ambient_light_color = Color(str(review.get("ambient_color", "fff0dc")))
	environment.ambient_light_energy = float(review.get("ambient", 0.70))
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

## A scene kit's lighting as it was signed off (layout.review_lighting, SGODOT-227 美术决定 2b53b84d); empty for the
## Basic Room, which keeps the P0Room benchmark (249).
func review_lighting() -> Dictionary:
	return layout.get("review_lighting", {}) as Dictionary

## A review lamp this close to layout.fire_position is the hearth's own: HearthGlow already lights it, and the fire
## effect brightens only that one lamp (PR #29 / #32), so the review lamp is not added twice.
const HEARTH_LAMP_M := 0.5

func _build_lights() -> void:
	var review := review_lighting()
	var sun := DirectionalLight3D.new()
	sun.name = "RoomSun"
	sun.light_color = Color(str(review.get("sun_color", "ffe6c2")))
	sun.light_energy = float(review.get("sun", 1.05))
	sun.shadow_enabled = true
	_set_sun_shadow(sun, review)
	sun.light_angular_distance = float((layout.get("lighting", {}) as Dictionary).get("angular_distance", 1.4))
	room.add_child(sun)
	sun.position = sun_direction()
	sun.look_at(room.global_position)
	var fire = layout.get("fire_position", null)
	var i := 0
	for lamp in review.get("points", []):
		var at := P0RoomAnchors.vec(lamp.position)   # scene metres, like the art: the lamp moves with the room
		if fire is Array and at.distance_to(P0RoomAnchors.vec(fire)) < HEARTH_LAMP_M: continue
		var light := OmniLight3D.new()
		light.name = "ReviewLamp%d" % i
		light.position = at
		light.light_color = Color(str(lamp.get("color", "ffb85e")))
		light.light_energy = float(lamp.get("energy", 1.0))
		light.omni_range = float(lamp.get("range", 2.4))
		light.shadow_enabled = false
		room.add_child(light)
		i += 1

## Where the room's sun shines from (room metres, towards the room origin): layout.sun_direction, else the kit's
## review sun (review_lighting.sun_position − sun_target), else the Basic Room benchmark.
func sun_direction() -> Vector3:
	if layout.get("sun_direction", null) is Array: return P0RoomAnchors.vec(layout.sun_direction)
	var review: Dictionary = layout.get("review_lighting", {})
	if review.get("sun_position", null) is Array:
		return P0RoomAnchors.vec(review.sun_position) - P0RoomAnchors.vec(review.get("sun_target", [0, 0, 0]))
	return Vector3(-6, 7, 1.5)

## The sun's shadow as each kit's signed render cast it (SGODOT-227): the Basic Room keeps the P0Room benchmark; a review
## with shadow values was signed through review_room.gd (orthogonal, its values, defaults 35 m / 0.025 / 0.18:
## Farm Tools Store, Post Office); a review without them through render_r1 with Godot's own shadow (four splits, 40 m,
## bias 0.1 / 2.0: Coffee Shop, Fruit Shop). The single orthogonal map lost the Coffee Shop's window and vine shadows.
const SHADOW_KEYS := ["shadow_distance", "shadow_bias", "shadow_normal_bias"]
static func _set_sun_shadow(sun: DirectionalLight3D, review: Dictionary) -> void:
	if review.is_empty():
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 30.0
		sun.shadow_bias = 0.045
		sun.shadow_normal_bias = 0.4
	elif SHADOW_KEYS.any(func(k): return review.has(k)):
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = float(review.get("shadow_distance", 35.0))
		sun.shadow_bias = float(review.get("shadow_bias", 0.025))
		sun.shadow_normal_bias = float(review.get("shadow_normal_bias", 0.18))
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 40.0
		sun.shadow_bias = 0.1
		sun.shadow_normal_bias = 2.0

## The one hearth lamp at layout.fire_position. It exists before the art enters the tree, so the art's fire effect
## drives this lamp instead of adding a second one (PR #29, SGODOT-236).
func _build_hearth_glow() -> void:
	if not (layout.get("fire_position", null) is Array): return
	var glow := OmniLight3D.new()
	glow.name = "HearthGlow"
	glow.position = P0RoomAnchors.vec(layout.fire_position)
	glow.light_color = Color("ff9b35")
	glow.light_energy = 0.75
	glow.omni_range = 1.25
	glow.omni_attenuation = 1.6
	room.add_child(glow)

# ---------------------------------------------------------------- camera: the room's accepted view + safe box
func _build_camera() -> void:
	var spec: Dictionary = layout.get("camera", {})
	if spec.has("position") and spec.has("target"):
		var off := P0RoomAnchors.vec(spec.position) - P0RoomAnchors.vec(spec.target)
		_cam_dir = off.normalized()
		_cam_dist = off.length()
	_cam_size = float(spec.get("size", _cam_size))
	cam = Camera3D.new()
	cam.name = "RoomCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.1
	cam.far = 70.0
	add_child(cam)
	cam.make_current()
	cam.add_child(_backdrop())

## The plate's input colour at the top of the screen (sRGB): from `backdrop` (screen colours, reversed through the
## tonemapper), else the kit's review background, else the Basic Room's.
func backdrop_color() -> Color:
	if backdrop.has("top"):
		var v := aces_input(Color(str(backdrop.top)))
		return Color(v.x, v.y, v.z).linear_to_srgb()
	var hex := str(review_lighting().get("background", ""))
	return Color.from_string(hex, BACKDROP) if hex != "" else BACKDROP

## Godot's ACES tonemapper (BakingLab fit, exposure bias 1.8, white 1, exposure 1), reversed: the linear colour an
## unshaded surface needs so that `screen` (sRGB) shows. The model gives exactly what 248 and 227 measured on screen:
## e8e4c8 → #F7F6EA and D3E7D8 → #EFF7F1.
const ACES_A := 0.0245786
const ACES_B := 0.000090537
const ACES_C := 0.983729
const ACES_D := 0.432951
const ACES_E := 0.238081
static func _aces_rows(r0: Vector3, r1: Vector3, r2: Vector3) -> Basis:
	return Basis(r0, r1, r2).transposed()   # Basis * v = (r0·v, r1·v, r2·v)
static func _rrt(x: float) -> float:
	return (x * (x + ACES_A) - ACES_B) / (x * (ACES_C * x + ACES_D) + ACES_E)
static func _rrt_inv(t: float) -> float:
	var a := 1.0 - t * ACES_C
	var b := ACES_A - t * ACES_D
	var c := -(ACES_B + t * ACES_E)
	return (-b + sqrt(b * b - 4.0 * a * c)) / (2.0 * a)
static func _aces_in() -> Basis:
	return _aces_rows(Vector3(0.59719, 0.35458, 0.04823), Vector3(0.07600, 0.90834, 0.01566), Vector3(0.02840, 0.13383, 0.83777))
static func _aces_out() -> Basis:
	return _aces_rows(Vector3(1.60475, -0.53108, -0.07367), Vector3(-0.10208, 1.10813, -0.00605), Vector3(-0.00327, -0.07276, 1.07602))
static func aces_input(screen: Color) -> Vector3:
	var lin := screen.srgb_to_linear()
	var o := Vector3(lin.r, lin.g, lin.b) * _rrt(1.8)
	var t := _aces_out().inverse() * o
	var c := Vector3(_rrt_inv(t.x), _rrt_inv(t.y), _rrt_inv(t.z))
	return (_aces_in().inverse() * c) / 1.8
## The forward model (linear input → sRGB on screen), for tests and the calibration notes.
static func aces_screen(input: Vector3) -> Color:
	var c := _aces_in() * (input * 1.8)
	var o := _aces_out() * Vector3(_rrt(c.x), _rrt(c.y), _rrt(c.z)) / _rrt(1.8)
	return Color(clampf(o.x, 0, 1), clampf(o.y, 0, 1), clampf(o.z, 0, 1)).linear_to_srgb()

## The colour around the room (SGODOT-248 R1.1): an unshaded plate just inside the far plane, so it is tone-mapped the
## same way as the room on every renderer. The environment's clear colour alone came out #F7F6EA through ACES on Metal
## but pure white on Android Vulkan; the plate keeps both at #F7F6EA. It belongs to the room, so it hides with it.
const BACKDROP := Color("e8e4c8")
func _backdrop() -> MeshInstance3D:
	var plate := MeshInstance3D.new()
	plate.name = "Backdrop"
	var quad := QuadMesh.new()
	quad.size = Vector2(400, 400)   # well past any room's orthographic view
	plate.mesh = quad
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if backdrop.has("top"):
		plate.material_override = _backdrop_gradient()
		plate.position = Vector3(0, 0, -(cam.far - 1.0))
		return plate
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = backdrop_color()
	mat.disable_fog = true
	plate.material_override = mat
	plate.position = Vector3(0, 0, -(cam.far - 1.0))
	return plate

## Screen-space vertical two-colour plate (SGODOT-227 美术决定 2b53b84d): linear inputs reversed from the screen colours.
const BACKDROP_SHADER := """shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;
uniform vec3 top_input;
uniform vec3 bottom_input;
uniform vec2 blend = vec2(0.5, 0.85);
void fragment() {
	ALBEDO = mix(top_input, bottom_input, smoothstep(blend.x, blend.y, SCREEN_UV.y));
}
"""
func _backdrop_gradient() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = BACKDROP_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var top := aces_input(Color(str(backdrop.top)))
	mat.set_shader_parameter("top_input", top)
	mat.set_shader_parameter("bottom_input", aces_input(Color(str(backdrop.bottom))) if backdrop.has("bottom") else top)
	var blend: Array = backdrop.get("blend", [0.5, 0.85])
	mat.set_shader_parameter("blend", Vector2(float(blend[0]), float(blend[1])))
	return mat

## Opening shot (§10.1): the player, every tappable anchor and the room's floor (a cut-away diorama reads
## wrong cropped) in the middle of the screen; held until the player first moves. Re-run when a room changes
## what can be tapped.
func frame_all() -> void:
	var pts: Array[Vector3] = [actor.position, actor.position + Vector3(0, 1.75, 0)]
	for n in _tappable(): pts.append(anchor(n).global_position)
	for c in [floor_rect.position, floor_rect.end, Vector2(floor_rect.position.x, floor_rect.end.y), Vector2(floor_rect.end.x, floor_rect.position.y)]:
		pts.append(room.position + Vector3(c.x, floor_y, c.y))
	var forward := -_cam_dir
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var q := Vector2(p.dot(right), p.dot(up))
		lo = lo.min(q)
		hi = hi.max(q)
	var view := _view()
	var tall := view.y / maxf(view.x, 1.0)
	var base := float(layout.get("camera", {}).get("size", _cam_size))
	# The art's own width (flowers, signs, pillars past the floor) sets the opening view's sides: centred on it,
	# with SIDE_MARGIN px clear on both sides, wider than the kit's camera when that is tighter (不知火舞 on 227).
	var span := art_span(right)
	if span.y > span.x:
		lo.x = minf(lo.x, span.x)
		hi.x = maxf(hi.x, span.y)
		base = maxf(base, (span.y - span.x) / maxf(1.0 - 2.0 * SIDE_MARGIN / maxf(view.x, 1.0), 0.5))
	var need := maxf((hi.x - lo.x) / FRAME_W, (hi.y - lo.y) / (FRAME_H * tall))
	# Fits: everything is on screen at the room's accepted view, even if tighter than the opening margins.
	_fits = hi.x - lo.x <= base and hi.y - lo.y <= base * tall * 0.85
	_cam_size = clampf(need, base * MIN_VIEW_K, base)
	var mid := (lo + hi) * 0.5
	# The screen centre on the floor plane: move along the view axis until y = floor.
	var t := (floor_y - up.y * mid.y) / forward.y
	_focus = right * mid.x + up * mid.y + forward * t
	_framed = _focus
	_follow.hold()
	_update_camera()

## The visible art's extent along the screen's right axis (world metres), as (min, max); (0, 0) without meshes.
func art_span(right: Vector3) -> Vector2:
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in art.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null: continue
		var b := mi.global_transform * mi.get_aabb()
		for i in 8:
			var x := b.get_endpoint(i).dot(right)
			lo = minf(lo, x)
			hi = maxf(hi, x)
	return Vector2(lo, hi) if hi > lo else Vector2.ZERO

func _view() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(360, 800)

func _update_camera() -> void:
	if _review_view: return   # P0_SHOT "reviewcam": held on the kit's review camera
	var follow_size := _cam_size / _zoom
	var center := _focus
	var size := follow_size
	if not _shot.is_empty():
		center = _focus.lerp(_shot.center, _shot_k)
		size = lerpf(follow_size, float(_shot.size), _shot_k)
	cam.size = size
	cam.position = center + _cam_dir * _cam_dist
	cam.look_at(center, Vector3.UP)

## Push-in preset (kitchen stage): ease the camera onto a cam_ anchor so that it sits at the centre of the
## screen band `opts.band` (Rect2 in 0..1 screen fractions; default the strip from the HUD's bottom to 40 %).
## opts.size: orthographic width in metres (default 45 % of the room view); opts.release_on_move (default true).
func focus(cam_anchor: String, opts := {}) -> void:
	var m := anchor(cam_anchor)
	if m == null: return
	var view := _view()
	var band: Rect2 = opts.get("band", band_below_hud(0.40))
	var size := float(opts.get("size", _cam_size * 0.45))
	var visible_h := size * view.y / maxf(view.x, 1.0)
	var forward := -_cam_dir
	var up := (Vector3.UP - forward * forward.dot(Vector3.UP)).normalized()
	_shot = {center = m.global_position + up * (band.get_center().y - 0.5) * visible_h, size = size,
		release_on_move = bool(opts.get("release_on_move", true)), anchor = cam_anchor}
	_ease_shot(1.0)

func release_focus() -> void:
	if _shot.is_empty(): return
	_ease_shot(0.0)

func is_focused() -> bool: return not _shot.is_empty() and _shot_k > 0.0

## Orthographic width of the room's opening view, in metres (push-in sizes are fractions of it).
func view_size() -> float: return _cam_size

## Screen band from the HUD's bottom edge to `bottom` (fraction of the screen height).
func band_below_hud(bottom: float) -> Rect2:
	var view := _view()
	var top := (_safe_top() + HUD_BOTTOM) / maxf(view.y, 1.0)
	return Rect2(0.0, top, 1.0, maxf(0.01, bottom - top))

func _safe_top() -> float:
	if not (OS.has_feature("android") or OS.has_feature("ios")) or not is_inside_tree(): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(), _view(), 0.0).y

func _ease_shot(to: float) -> void:
	if _shot_tween and _shot_tween.is_valid(): _shot_tween.kill()
	if not is_inside_tree():
		_shot_k = to
		if to == 0.0: _shot = {}
		return
	_shot_tween = create_tween()
	_shot_tween.tween_property(self, "_shot_k", to, FOCUS_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if to == 0.0: _shot_tween.tween_callback(func(): _shot = {})

# ---------------------------------------------------------------- walking to facilities and the door
## Walk to where `n` is used (its stand_ anchor, else the walkable cell nearest to it), face it, then `done`.
func walk_to(n: String, done := Callable()) -> void:
	var target := anchor(n)
	if target == null: return
	var stand := P0RoomAnchors.stand_for(n, _anchors.keys())
	var point := anchor(stand).global_position if stand != "" and anchor(stand) else P0RoomNav.nearest_walkable(bp, target.global_position)
	if point == Vector3.INF: return
	point.y = 0.0
	_walk = {name = n, point = point, done = done}
	if _flat_distance(actor.position, point) <= REACH_M or not actor.mover.set_target_position(point):
		_arrive()

func _arrive() -> void:
	var w := _walk
	_walk = {}
	var target := anchor(str(w.name))
	if target: actor.face(target.global_position)
	if str(w.name) == "exit":
		leave()
		return
	facility_tapped.emit(str(w.name))
	_on_facility(str(w.name))
	if (w.done as Callable).is_valid(): (w.done as Callable).call()

## Back to the world below. The runtime pops this instance (AppRouter); standalone rooms just free.
func leave() -> void:
	if _leaving: return
	_leaving = true
	left.emit()
	if rt and rt.has_method("leave_room"): rt.leave_room()
	elif use_runtime and AppRouter.top_instance() == self: AppRouter.pop_instance()

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## The facility under a screen point: the smallest art box (hit_nodes) holding it, else the tappable anchor nearest
## to it within TAP_RADIUS among the others, or "".
func pick(screen: Vector2) -> String:
	var best := ""
	var best_area := INF
	var boxed := {}
	for n in _tappable():
		if not hit_nodes.has(n): continue
		var r := hit_rect(n)
		if not r.has_area(): continue
		boxed[n] = true
		if r.has_point(screen) and r.get_area() < best_area:
			best = n
			best_area = r.get_area()
	if best != "": return best
	var best_d := TAP_RADIUS
	for n in _tappable():
		if boxed.has(n): continue   # tapped by its art only
		var m := anchor(n)
		if m == null or cam.is_position_behind(m.global_position): continue
		var d := cam.unproject_position(pick_point(n)).distance_to(screen)
		if d < best_d:
			best_d = d
			best = n
	return best

## The screen box of a hit_nodes facility: its meshes' bounds projected, grown to MIN_HIT (upwards, and evenly to
## the sides); an empty Rect2 when the node is missing or hidden.
func hit_rect(n: String) -> Rect2:
	var node := art.get_node_or_null(NodePath(str(hit_nodes.get(n, "")))) as Node3D if art and hit_nodes.has(n) else null
	if node == null or not node.is_visible_in_tree(): return Rect2()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree(): continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first: return Rect2()
	var r := Rect2()
	var seen := false
	for i in 8:
		var c := box.get_endpoint(i)
		if cam.is_position_behind(c): continue
		var at := cam.unproject_position(c)
		r = r.expand(at) if seen else Rect2(at, Vector2.ZERO)
		seen = true
	if not seen: return Rect2()
	if r.size.x < MIN_HIT:
		r.position.x -= (MIN_HIT - r.size.x) * 0.5
		r.size.x = MIN_HIT
	if r.size.y < MIN_HIT:
		r.position.y -= MIN_HIT - r.size.y
		r.size.y = MIN_HIT
	return r

## Where a tappable is picked on screen: its anchor, lifted for NPCs and the door. A door with its own badge_exit
## point is picked there, where its prompt shows: a front door's prompt sits on the steps, below the player who
## comes in (Coffee Shop, SGODOT-227), instead of 1.1 m over the threshold.
func pick_point(n: String) -> Vector3:
	if n == "exit" and anchor("badge_exit"): return anchor("badge_exit").global_position
	return anchor(n).global_position + _hit_lift(n)

## NPCs and the door are picked at body / door height; use_ anchors already sit on the object's top.
static func _hit_lift(n: String) -> Vector3:
	var p := P0RoomAnchors.prefix_of(n)
	return Vector3(0, 1.0, 0) if p == "npc" or n == "exit" else Vector3.ZERO

# ---------------------------------------------------------------- P0Runtime world protocol
func p0_surface() -> String: return "room"

func p0_joystick(v: Vector2) -> void:
	_on_joystick(v)
	if actor: actor.set_input(v)
	if v != Vector2.ZERO:
		_walk = {}
		if not _shot.is_empty() and bool(_shot.release_on_move): release_focus()

func p0_tap(screen: Vector2) -> void:
	if rt and rt.ui.has_modal(): return
	var n := tap_target(screen)
	if n != "": walk_to(n)

## What a tap at `screen` asks for: a finger card's or world prompt's own anchor by id, not through the point test
## (PR #21's rule for the farm), else pick(screen); "" for nothing.
func tap_target(screen: Vector2) -> String:
	var card := str(rt.ui.tapped_card) if rt else ""
	return card.trim_prefix("room:") if card.begins_with("room:") and anchor(card.trim_prefix("room:")) else pick(screen)

func p0_frame(v: Dictionary, dt: float) -> void:
	if _leaving or not is_inside_tree(): return
	actor.step(dt)
	if not _walk.is_empty() and not actor.mover.is_moving():
		if _flat_distance(actor.position, _walk.point) <= REACH_M: _arrive()
		else: _walk = {}
	_door_check()
	if _leaving or not is_inside_tree(): return   # the door popped this room mid-frame
	# A room that fits the screen holds its diorama framing (following would crop it); zoomed in, or in
	# a space larger than the screen (the market square), the safe box follows the player (§10.1).
	if _fits and _zoom <= 1.0: _focus = _framed
	else: _focus = _follow.step(cam, _focus, actor.position, actor.mover.is_moving(), dt)
	if _pinch.step(dt): _set_zoom(_pinch.value)   # springing back from past a zoom limit, about the same point
	else: _update_camera()
	if rt: _markers(v)
	_room_frame(v, dt)
	if _perf_left >= 0.0:
		_perf_left -= dt
		if _perf_left < 0.0:
			_perf_left = 5.0
			print("P0_PERF %s fps=%d draws=%d prims=%d" % [name, Performance.get_monitor(Performance.TIME_FPS),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])

## Walking onto the door leaves (no confirmation); it arms once the player has stepped away from it.
func _door_check() -> void:
	var door := anchor("exit")
	if door == null or _leaving: return
	var d := _flat_distance(actor.position, door.global_position)
	if d > EXIT_ARM_M: _exit_armed = true
	elif _exit_armed and d <= EXIT_RADIUS_M: leave()

## SGODOT-250 (spec 370794d2 item 5, LOCK-07 v2): one finger card at a time in a room as on the farm — the nearest
## anchor with a card within CARD_NEAR_M; the one showing keeps it unless another is clearly nearer, so standing
## between the keeper, a seat and the door never shows two or three cards (hand test 246 pictures 06 / 07).
## `marks` maps anchor names to their _marker(); returns the anchor whose card shows, or "".
func card_pick(marks: Dictionary) -> String:
	var cands: Array = []
	for n in marks:
		var m: Dictionary = marks[n]
		if (m.has("text") or m.has("kind")) and anchor(n): cands.append([n, anchor(n).global_position, CARD_NEAR_M])
	_card = P0Garden.pick_card(cands, actor.position, _card)
	return _card

## Finger cards and status badges over tappable anchors (221's rt.ui.tag / rt.ui.badge when present).
## A marker with `kind` uses the world prompts instead of a finger card (SGODOT-250, LOCK-07 / 16 / 30 v2), with the
## one in reach (`_card`) the only one opened:
##   "npc"      {name, head}: the name over the head (NpcNameTag), highlighted while it is the one in reach; `talking`
##              keeps it up and highlighted over the greeting card / dialogue bar (P0Ui.npc_tag, #57);
##   "seat"     {icon}: an icon button that goes Near, never a strip;
##   "facility" {icon, name, fact?, count?}: an icon button (count: its small count tag) that opens into a name strip.
## `badge` on a seat or facility rides in the button / strip (StatusBadge World 28); an NPC's stays a badge.
func _markers(v: Dictionary) -> void:
	var now := {}
	var marks := {}
	for n in _tappable():
		var m := _marker(n, v)
		if not m.is_empty(): marks[n] = m
	card_pick(marks)
	for n in marks:
		var m: Dictionary = marks[n]
		var id: String = "room:" + n
		var at := anchor(n).global_position + _hit_lift(n) * 1.1
		var badge_at := anchor("badge_" + (P0RoomAnchors.object_of(n) if P0RoomAnchors.object_of(n) != "" else n))   # badge_exit for the door
		var screen := cam.unproject_position(badge_at.global_position if badge_at else at)
		var lift := 0.0
		var state := badge_state(str(m.get("badge", "")))
		var kind := str(m.get("kind", ""))
		now[id] = kind
		if kind == "seat":
			rt.ui.world_icon(id, m.icon, screen, true, n == _card, state)
			continue
		if kind == "facility":
			if n == _card: rt.ui.name_bar(id, m.icon, str(m.name), str(m.get("fact", "")), screen, true, -1, false, state)
			else: rt.ui.world_icon(id, m.icon, screen, true, false, state, Vector2.INF, str(m.get("count", "")))
			continue
		if state >= 0 and rt.ui.has_method("badge"):
			rt.ui.call("badge", id, state, screen, true, str(m.get("caption", "")), m.get("icon", null))
			if rt.ui.has_method("badge_height"): lift = float(rt.ui.call("badge_height", id))
		if kind == "npc":
			rt.ui.npc_tag(id, str(m.name), cam.unproject_position(m.head), true, n == _card, bool(m.get("talking", false)))
		elif m.has("text"):
			rt.ui.tag(id, str(m.text), screen - Vector2(0, lift), n == _card)
	for id in _shown.keys():
		if now.has(id): continue
		match str(_shown[id]):
			"seat": rt.ui.world_icon(id, null, Vector2.ZERO, false)
			"facility":
				rt.ui.name_bar(id, null, "", "", Vector2.ZERO, false)
				rt.ui.world_icon(id, null, Vector2.ZERO, false)
			"npc": rt.ui.npc_tag(id, "", Vector2.ZERO, false)
			_: rt.ui.tag(id, "", Vector2.ZERO, false)
		if rt.ui.has_method("badge"): rt.ui.call("badge", id, 0, Vector2.ZERO, false)
	_shown = now

## UiStatusBadge.State for a STATE-ICONS key, or -1 (unknown key, or the badge component is not in this build).
static func badge_state(key: String) -> int:
	if key == "" or not ResourceLoader.exists(BADGE_SCRIPT): return -1
	var states: Dictionary = (load(BADGE_SCRIPT) as Script).get_script_constant_map().get("State", {})
	return int(states.get(key.to_upper(), -1))

func p0_anchor() -> Vector2:
	return cam.unproject_position(actor.position + Vector3(0, 2.0, 0))

## Zoom about the last pinch centre (ScenePan's focal pinch). A room that fits the screen keeps its diorama framing
## at zoom ≤ 1, so the shift only holds once zoomed in.
func _set_zoom(value: float) -> void:
	_zoom = value
	if cam == null or not is_inside_tree(): return   # not placed yet: the next frame frames it
	var before = ElasticZoom.ground_at(cam, _zoom_at, _focus.y)
	_update_camera()
	var d := ElasticZoom.shift(before, ElasticZoom.ground_at(cam, _zoom_at, _focus.y))
	if d != Vector3.ZERO and not (_fits and _zoom <= 1.0):
		_focus += d
		_update_camera()

func p0_zoom(f: float, at := Vector2.INF) -> void:
	_zoom_at = at
	_pinch.pinch(f)
	_follow.hold()   # the pinched framing stays until the player walks
	_set_zoom(_pinch.value)

func p0_zoom_end() -> void: _pinch.release()

func p0_recenter() -> void:
	if _fits and _zoom <= 1.0: return   # the whole room is already in view
	_focus = actor.position
	_follow.held = false

## Whether p0_show_spot has something to show here (the runtime steps out of the farmhouse for farm targets).
func p0_has_spot(where: String) -> bool:
	return ["cam_" + where, "use_" + where, "use_" + where + "_1"].any(func(n): return anchor(n) != null)

## Energy card guidance (LOCK-08: only moves the camera): show cam_<where>, else use_<where>[_1].
func p0_show_spot(where: String) -> void:
	for n in ["cam_" + where, "use_" + where, "use_" + where + "_1"]:
		var m := anchor(n)
		if m:
			_focus = Vector3(m.global_position.x, floor_y, m.global_position.z)
			_follow.hold()
			return

## Back = tapping the door. Whenever the room handles Back itself (walking out, or already leaving) it
## returns true, so AppRouter never pops a second level (the room may have popped itself synchronously when
## the player stood at the door; SGODOT-227 found this sending the app to the old map).
func is_back_navigation_locked() -> bool:
	if rt and rt.ui.has_modal():
		rt.ui.close_modal()
		return true
	if _leaving: return true
	if anchor("exit"):
		if not _walk.is_empty() and str(_walk.name) == "exit": leave()   # Back again while walking out
		else: walk_to("exit")
		return true
	return false

func suspend() -> void:
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
	if rt:
		rt.attach(self)
		rt.ui.set_place(city + " · " + place_name)

# ---------------------------------------------------------------- dev steps for P0_SHOT
var _review_view := false
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"reviewcam":   # the kit's layout.camera, as its signed render framed it (art comparisons, SGODOT-227)
			var spec: Dictionary = layout.get("camera", {})
			_review_view = true
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.size = float(spec.get("size", cam.size)) * (float(step[1]) if step.size() > 1 else 1.0)
			cam.position = room.global_position + P0RoomAnchors.vec(spec.position)
			cam.look_at(room.global_position + P0RoomAnchors.vec(spec.target), Vector3.UP)
		"noui": if rt: rt.ui.visible = false
		"goto":
			actor.teleport(Vector3(float(step[1]), floor_y, float(step[2])))
			_focus = actor.position
		"at":
			var m := anchor(step[1])
			if m: actor.teleport(Vector3(m.global_position.x, floor_y, m.global_position.z))
		"tap": walk_to(step[1])
		"focus": focus(step[1])
		"exit": leave()
		_: return false
	return true

func p0_until(n: String) -> bool:
	match n:
		"idle": return _walk.is_empty() and not actor.mover.is_moving()
	return false
