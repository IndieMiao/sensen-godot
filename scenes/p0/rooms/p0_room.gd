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

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const BASIC_ROOM_ART := "res://scenes/basic_room/basic_room_art.tscn"
const BASIC_ROOM_LAYOUT := "res://assets/rooms/basic_room/layout.json"
## Engineering defaults (SGODOT-226); WP7 v2 finalises the camera numbers from Figma.
const TAP_RADIUS := 64.0          # F-04 screen pick radius (P0 uses 56–80 px)
const MIN_HIT := 44.0             # a facility tapped by its art: at least this box on screen (touch target)
const CARD_NEAR_M := 3.0          # the nearest prompt within this opens (LOCK-07 v2)
const EXIT_RADIUS_M := 0.6        # walking onto the door leaves, no confirmation
const EXIT_ARM_M := 1.0           # … once the player has been this far from it (spawn is one step inside)
const REACH_M := 0.35             # close enough to a stand_ point to use the facility
const FOCUS_S := 0.4              # push-in ease
const HUD_BOTTOM := UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H   # below the safe-area top
const ZOOM_RANGE := Vector2(0.8, 1.4)   # the farm's (P0Farm._pinch), one player scale everywhere (不知火舞 on 226)
const FRAME_W := 0.84             # opening shot: player + facilities within 84 % of the width …
const FRAME_H := 0.60             # … and the middle 60 % of the height (§10.1)
const MIN_VIEW_K := 0.8           # … but never closer than 80 % of the room's accepted view
const SIDE_MARGIN := 18.0         # … and at least this many px clear beside the art on both sides (227: ≥ 16)
const BADGE_SCRIPT := "res://scenes/ui_kit/ui_status_badge.gd"   # UiStatusBadge (SGODOT-221)

var art_scene: PackedScene
var layout_path := BASIC_ROOM_LAYOUT
var anchors_path := ""
var place_name := ""
## Where the door leads, for the world prompts (SGODOT-250: i-door + "Map" / "Farm").
var exit_to := "Map"
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
var _diorama_size := 10.75   # the whole room's opening width: what push-in presets are fractions of (view_size)
var _bounds_lo := Vector2(-INF, -INF)   # the room's art on the screen plane (right, up), the camera kept inside it
var _bounds_hi := Vector2(INF, INF)
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
var _pan_tween: Tween   # a focused shot sliding to another anchor (opts.ease_s)
var _shot_tween: Tween
var _walk := {}           # {name, point: Vector3, done: Callable}
var _shown := {}          # marker ids currently on screen
var _card := ""           # the one tappable whose prompt is open (SGODOT-250: one at a time)
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
		rt.ui.set_place(P0City.chip(place_name))

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

## World prompt and status badge over a tappable anchor: {kind, …, badge, caption, icon} (see _markers); badge is a
## STATE-ICONS key ("available", "countdown", "ready", … = UiStatusBadge.State in lower case). Empty = nothing; the
## door is i-door + exit_to.
func _marker(name: String, _view: Dictionary) -> Dictionary:
	if name != "exit": return {}
	return {kind = "facility", icon = P0Logic.icon("door"), name = exit_to}

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

## Where the room's sun shines from (room metres, towards the room origin): the kit's review sun (review_lighting.
## sun_position − sun_target, as signed), else layout.sun_direction (the Basic Room's), else the benchmark. Farm Tools
## Store and Post Office also carry the Basic Room's sun_direction; their signed sun is the review one.
func sun_direction() -> Vector3:
	var review: Dictionary = layout.get("review_lighting", {})
	if review.get("sun_position", null) is Array:
		return P0RoomAnchors.vec(review.sun_position) - P0RoomAnchors.vec(review.get("sun_target", [0, 0, 0]))
	if layout.get("sun_direction", null) is Array: return P0RoomAnchors.vec(layout.sun_direction)
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

## The camera's clip planes as each kit's signed render had them (near, far): Godot fits the sun's shadow to the camera
## range, so the far plane decides whether the Post Office's west wall shades the floor by its door (signed: it does
## not, with review_room.gd's default camera; with this room's old 70 m it did). Basic Room: 0.1 / 70 as before;
## review_room.gd (review shadow values): Godot's defaults 0.05 / 4000; render_r1: 0.05 / 150.
static func review_clip(review: Dictionary) -> Vector2:
	if review.is_empty(): return Vector2(0.1, 70.0)
	if SHADOW_KEYS.any(func(k): return review.has(k)): return Vector2(0.05, 4000.0)
	return Vector2(0.05, 150.0)

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
## One camera pitch everywhere (用户 2026-10-09, camera unification step 2): a room keeps its kit's yaw (about 45°, the
## corner view its art was built for — the user kept it) and distance, and looks down at the farm's pitch
## (FarmCamera.PITCH_DEG) instead of its kit's 25–37°. All three spaces are orthographic, so with the farm's player
## scale (frame_all) the picture is the farm's too. The kit's own camera stays for the reviewcam shot step.
static func at_farm_pitch(dir: Vector3) -> Vector3:
	var flat := Vector2(dir.x, dir.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector2(0.0, 1.0)
	var p := deg_to_rad(FarmCamera.PITCH_DEG)
	return Vector3(flat.x * cos(p), sin(p), flat.y * cos(p))

func _build_camera() -> void:
	var spec: Dictionary = layout.get("camera", {})
	if spec.has("position") and spec.has("target"):
		var off := P0RoomAnchors.vec(spec.position) - P0RoomAnchors.vec(spec.target)
		_cam_dir = off.normalized()
		_cam_dist = off.length()
	_kit_dir = _cam_dir
	_cam_dir = at_farm_pitch(_cam_dir)
	_cam_size = float(spec.get("size", _cam_size))
	cam = Camera3D.new()
	cam.name = "RoomCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	var clip := review_clip(review_lighting())
	cam.near = clip.x
	cam.far = clip.y
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

## Opening shot. One player scale everywhere (用户, 2026-10-09; FarmCamera.player_scale_size): the room's camera
## shows the player as tall as the farm does at zoom 1, which supersedes the whole-room diorama opening (§10.1;
## 不知火舞's "whole art centred, ≥ 16 px clear" on 227). A room that still fits at that scale holds its framing; any
## other follows the player with the safe box, kept inside the room's art (no backdrop past the walls). The whole
## room's width is still worked out: push-ins (the kitchen stage) are fractions of it, so they frame as before.
## Re-run when a room changes what can be tapped.
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
	_diorama_size = clampf(need, base * MIN_VIEW_K, base)
	_cam_size = FarmCamera.player_scale_size(view, rad_to_deg(asin(_cam_dir.y)))
	var art_up := art_span(up)
	_bounds_lo = Vector2(lo.x, minf(lo.y, art_up.x) if art_up.y > art_up.x else lo.y)
	_bounds_hi = Vector2(hi.x, maxf(hi.y, art_up.y) if art_up.y > art_up.x else hi.y)
	cam.size = _cam_size / _zoom
	# Fits: the art fits the free band both ways at the player's scale, so the room holds still, centred in it.
	_framed = _clamp_focus(_on_floor(right, up, forward, (_bounds_lo + _bounds_hi) * 0.5))
	_fits = _clamp_focus(_on_floor(right, up, forward, _bounds_lo)).is_equal_approx(_framed)
	# Otherwise on the player and who the room is for (opening_focus, no slide in), kept inside the art (_update_camera).
	_focus = _framed if _fits else opening_focus(right, up, forward)
	_follow.hold()
	_update_camera()

## What the opening shot shows besides the player, most important first: groups of world points (an outpost's keeper
## with the name tag over their head, then the counter; P0Outpost). [] keeps the opening on the player alone.
func opening_subjects() -> Array:
	return []

## The opening shot of a room that does not fit at the player's scale (不知火舞 on 227, int12-pre: the tea house opened
## with Ama off screen). Priority player > keeper and counter > the rest: the player with every opening_subjects()
## group when they fit the free band together (the band _clamp_focus keeps: SIDE_MARGIN across, the HUD's bottom to
## the bottom controls down), centred in it; otherwise the middle of the player and the first group (the keeper),
## centred the same way. _update_camera then keeps it inside the art, as for any followed shot.
func opening_focus(right: Vector3, up: Vector3, forward: Vector3) -> Vector3:
	var groups := opening_subjects()
	if groups.is_empty(): return actor.position
	var view := _view()
	var m := cam.size / maxf(view.x, 1.0)   # metres per px
	var band_lo := Vector2(-(view.x * 0.5 - SIDE_MARGIN), -(view.y * 0.5 - _bottom_px().x)) * m
	var band_hi := Vector2(view.x * 0.5 - SIDE_MARGIN, view.y * 0.5 - (_safe_top() + HUD_BOTTOM)) * m
	var player := _screen_box([actor.position, actor.position + Vector3(0, 1.75, 0)], right, up)
	var all := player
	for g in groups: all = all.merge(_screen_box(g, right, up))
	var mid := all.get_center()
	if all.size.x > band_hi.x - band_lo.x or all.size.y > band_hi.y - band_lo.y:
		mid = (player.get_center() + _screen_box(groups[0], right, up).get_center()) * 0.5
	return _on_floor(right, up, forward, mid - (band_lo + band_hi) * 0.5)

## The points' extent on the screen plane (along right; along up), in metres.
func _screen_box(points: Array, right: Vector3, up: Vector3) -> Rect2:
	var box := Rect2()
	for i in points.size():
		var q := Vector2((points[i] as Vector3).dot(right), (points[i] as Vector3).dot(up))
		box = Rect2(q, Vector2.ZERO) if i == 0 else box.expand(q)
	return box

## The point on the floor under the screen-plane point q = (along right, along up): moved along the view axis.
func _on_floor(right: Vector3, up: Vector3, forward: Vector3, q: Vector2) -> Vector3:
	var t := (floor_y - up.y * q.y) / forward.y
	return right * q.x + up * q.y + forward * t

## The camera's centre per screen axis (不知火舞 on 226 / #127): an axis where the room's art fits between its limit
## lines — across, SIDE_MARGIN in from both edges; down, the HUD's bottom and the bottom controls' (_bottom_px) — holds
## it centred (down, in the band _bottom_px gives), never past those lines; an axis where it does not follows (the
## safe box) but stops where the art's edge meets a limit line, so no backdrop shows past the walls. The outposts
## mostly fit down and pan across, which keeps the small-room look.
func _clamp_focus(f: Vector3) -> Vector3:
	if _bounds_lo.x == -INF: return f
	var forward := -_cam_dir
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var view := _view()
	var m := cam.size / maxf(view.x, 1.0)   # metres per px
	var bottom := _bottom_px()
	# The limit lines and the centring band, in metres from the screen's centre along each axis (right; up).
	var limit_lo := Vector2(-(view.x * 0.5 - SIDE_MARGIN), -(view.y * 0.5 - bottom.x)) * m
	var limit_hi := Vector2(view.x * 0.5 - SIDE_MARGIN, view.y * 0.5 - (_safe_top() + HUD_BOTTOM)) * m
	var centre_lo := Vector2(limit_lo.x, -(view.y * 0.5 - bottom.y) * m)
	var q := Vector2(f.dot(right), f.dot(up))
	for i in 2:
		var lo := _bounds_lo[i] - limit_lo[i]   # q from here up: no backdrop between the art's low edge and the low line
		var hi := _bounds_hi[i] - limit_hi[i]   # q up to here: none between its high edge and the high line
		if lo > hi:   # it fits: centred in the band, kept inside the limit lines
			q[i] = clampf(((_bounds_lo[i] + _bounds_hi[i]) - (centre_lo[i] + limit_hi[i])) * 0.5, hi, lo)
		else:
			q[i] = clampf(q[i], lo, hi)
	return _on_floor(right, up, forward, q)

## The bottom controls, in px from the screen's bottom: (the art's lowest line, the centring band's bottom). With the
## quick bar (or the main key) both are its top. With Bag alone (a room, 不知火舞 on #127) the room centres down to the
## safe bottom's 24 px but its lowest point keeps 8 px above Bag's top.
func _bottom_px() -> Vector2:
	var inset := rt.ui.safe_bottom() if rt else 0.0
	var bar := UiTokens.SIZE_QUICK_BAR_BOTTOM + UiTokens.SIZE_QUICK_BAR_H + inset
	if rt and rt.ui.bag_only(): return Vector2(bar + BAG_CLEAR, UiTokens.SIZE_QUICK_BAR_BOTTOM + inset)
	return Vector2(bar, bar)
const BAG_CLEAR := 8.0

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
	cam.size = follow_size
	if not (_fits and _zoom <= 1.0): _focus = _clamp_focus(_focus)   # following: kept inside the room's art
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
	var size := float(opts.get("size", _diorama_size * 0.45))
	var visible_h := size * view.y / maxf(view.x, 1.0)
	var forward := -_cam_dir
	var up := (Vector3.UP - forward * forward.dot(Vector3.UP)).normalized()
	var to := m.global_position + up * (band.get_center().y - 0.5) * visible_h
	# Already pushed in and asked to pan (opts.ease_s: the kitchen's stove switch, 0.25 s ease-out, SGODOT-282): the
	# shot slides from where it is to the new pot instead of jumping.
	var pan := float(opts.get("ease_s", 0.0))
	var from: Vector3 = _shot.get("center", to) if pan > 0.0 and is_focused() else to
	_shot = {center = from, size = size, release_on_move = bool(opts.get("release_on_move", true)), anchor = cam_anchor}
	if from != to and is_inside_tree():
		if _pan_tween and _pan_tween.is_valid(): _pan_tween.kill()
		_pan_tween = create_tween()
		_pan_tween.tween_method(func(c: Vector3): if not _shot.is_empty(): _shot.center = c, from, to, pan) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_shot.center = to
	_ease_shot(1.0)

func release_focus() -> void:
	if _shot.is_empty(): return
	_ease_shot(0.0)

func is_focused() -> bool: return not _shot.is_empty() and _shot_k > 0.0

## Orthographic width of the whole room's view, in metres: push-in sizes are fractions of it, so the kitchen stage
## and the corner shots frame as they did before the player scale (frame_all).
func view_size() -> float: return _diorama_size

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

## What a tap at `screen` asks for: a world prompt's own anchor by id, not through the point test
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

## SGODOT-250 (spec 370794d2 item 5, LOCK-07 v2): one open prompt at a time in a room as on the farm — the nearest
## anchor with a prompt within CARD_NEAR_M; the open one keeps it unless another is clearly nearer, so standing
## between the keeper, a seat and the door never opens two or three (hand test 246 pictures 06 / 07).
## `marks` maps anchor names to their _marker(); returns the anchor whose card shows, or "".
func card_pick(marks: Dictionary) -> String:
	var cands: Array = []
	for n in marks:
		var m: Dictionary = marks[n]
		if m.has("kind") and anchor(n): cands.append([n, anchor(n).global_position, CARD_NEAR_M])
	_card = P0Garden.pick_card(cands, actor.position, _card)
	return _card

## World prompts and status badges over tappable anchors (SGODOT-250, LOCK-07 / 16 / 30 v2; rt.ui.badge when present),
## with the one in reach (`_card`) the only one opened:
##   "npc"      {name, head}: the name over the head (NpcNameTag), highlighted while it is the one in reach; `talking`
##              keeps it up and highlighted over the greeting card / dialogue bar (P0Ui.npc_tag, #57);
##   "seat"     {icon}: an icon button that goes Near, never a strip;
##   "facility" {icon, name, fact?, count?, strip_badge?}: an icon button (count: its small count tag) that opens into
##              a name strip. strip_badge false: the strip keeps the facility icon and the state stays in the far
##              button's badge and the fact (the stove, like the bench; 不知火舞 on #104, 1760:103708).
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
		var state := badge_state(str(m.get("badge", "")))
		var kind := str(m.get("kind", ""))
		now[id] = kind
		if kind == "seat":
			rt.ui.world_icon(id, m.icon, screen, true, n == _card, state)
			continue
		if kind == "facility":
			if n == _card: rt.ui.name_bar(id, m.icon, str(m.name), str(m.get("fact", "")), screen, true, -1, false,
				state if bool(m.get("strip_badge", true)) else -1)
			else: rt.ui.world_icon(id, m.icon, screen, true, false, state, Vector2.INF, str(m.get("count", "")))
			continue
		if state >= 0 and rt.ui.has_method("badge"):
			rt.ui.call("badge", id, state, screen, true, str(m.get("caption", "")), m.get("icon", null))
		if kind == "npc":
			rt.ui.npc_tag(id, str(m.name), cam.unproject_position(m.head), true, n == _card, bool(m.get("talking", false)))
	for id in _shown.keys():
		if now.has(id): continue
		match str(_shown[id]):
			"seat": rt.ui.world_icon(id, null, Vector2.ZERO, false)
			"facility":
				rt.ui.name_bar(id, null, "", "", Vector2.ZERO, false)
				rt.ui.world_icon(id, null, Vector2.ZERO, false)
			"npc": rt.ui.npc_tag(id, "", Vector2.ZERO, false)
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

## Back = tapping the door, once the UI has nothing open. The UI's top layer goes first, one per press, as on the
## farm (P0Ui.close_top_layer): a dragged quick slot flies back, the radial closes, an InfoSheet laid over a panel
## closes, then the layer takes its own way back (a Fish-dex card back to the Fish-dex, a resident's Gift drawer back
## to the bar; 李元芳 int7) or closes. Whenever the room handles Back itself (walking out, or already leaving) it
## returns true, so AppRouter never pops a second level (the room may have popped itself synchronously when
## the player stood at the door; SGODOT-227 found this sending the app to the old map).
func is_back_navigation_locked() -> bool:
	if rt and rt.ui.close_top_layer(): return true
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
		rt.ui.set_place(P0City.chip(place_name))

# ---------------------------------------------------------------- light sampling across cameras (dev)
## Camera unification step 2's light check (美术总监: the same face of the same object, the signed render against the
## 43° game view). `spec` {image: [w, h], points: {name: [x, y]}}: pixels of an image this camera rendered (the
## reviewcam / kitpitch framing of the signed render) cast onto the art's visible surfaces after "calibmesh" (else the
## room's colliders), else the floor plane; {name: [x, y, z]}.
func calib_rays(spec: Dictionary) -> Dictionary:
	var out := {}
	var view := _view()
	var img := Vector2(float(spec.image[0]), float(spec.image[1]))
	var space := get_world_3d().direct_space_state
	for n in spec.points:
		var p: Array = spec.points[n]
		var at := Vector2(float(p[0]), float(p[1])) * view / img
		var from := cam.project_ray_origin(at)
		var dir := cam.project_ray_normal(at)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 500.0, CALIB_LAYER if _calib_meshed else 0xFFFFFFFF))
		var q: Vector3
		if not hit.is_empty(): q = hit.position
		else: q = from + dir * ((floor_y - from.y) / dir.y if absf(dir.y) > 0.0001 else 0.0)
		out[n] = [q.x, q.y, q.z, "hit" if not hit.is_empty() else "floor"]
	return out

## Shot step "calibmesh": the art's visible surfaces as trimesh bodies on a layer of their own, so "calibrays" (a later
## step: bodies join the space on the next physics frame) lands on what the picture shows, not the nav's walls.
const CALIB_LAYER := 1 << 19
var _calib_meshed := false
func calib_mesh() -> int:
	var n := 0
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree() or (mi as MeshInstance3D).mesh == null: continue
		var body := StaticBody3D.new()
		body.collision_layer = CALIB_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)
		body.global_transform = (mi as MeshInstance3D).global_transform
		n += 1
	_calib_meshed = true
	return n

## {name: [x, y, z, …]} to {view: [w, h], points: {name: [x, y]}} in this view's coordinates (scale them by the saved
## image's size over `view`; the texture's size reads differently on a HiDPI desktop), -1 when behind the camera.
func calib_project(points: Dictionary) -> Dictionary:
	var out := {}
	var view := _view()
	for n in points:
		var p: Array = points[n]
		var w := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var s := Vector2(-1, -1) if cam.is_position_behind(w) else cam.unproject_position(w)
		out[n] = [snappedf(s.x, 0.01), snappedf(s.y, 0.01)]
	return {view = [view.x, view.y], points = out}

# ---------------------------------------------------------------- dev steps for P0_SHOT
var _review_view := false
var _kit_dir := Vector3.ZERO   # the kit's own direction, before the farm's pitch (shot step "kitpitch")
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"kitpitch":   # back to the kit's own pitch (light sampling against renders signed at it)
			_cam_dir = _kit_dir
			_update_camera()
		"reviewcam":   # the kit's layout.camera, as its signed render framed it (art comparisons, SGODOT-227)
			var spec: Dictionary = layout.get("camera", {})
			_review_view = true
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.size = float(spec.get("size", cam.size)) * (float(step[1]) if step.size() > 1 else 1.0)
			cam.position = room.global_position + P0RoomAnchors.vec(spec.position)
			cam.look_at(room.global_position + P0RoomAnchors.vec(spec.target), Vector3.UP)
		"noui": if rt: rt.ui.visible = false
		"calibmesh": print("P0_CALIBMESH ", calib_mesh())
		"calibrays":   # light sampling (camera unification step 2): P0_CALIB's points, px of its image, to 3D points
			print("P0_CALIB3D ", JSON.stringify(calib_rays(JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("P0_CALIB"))))))
		"calibproject":   # … and P0_CALIB3D's 3D points to px of this shot
			print("P0_CALIBPX ", JSON.stringify(calib_project(JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("P0_CALIB3D"))))))
		"goto":
			actor.teleport(Vector3(float(step[1]), floor_y, float(step[2])))
			_focus = actor.position
		"at":
			var m := anchor(step[1])
			if m:
				actor.teleport(Vector3(m.global_position.x, floor_y, m.global_position.z))
				_focus = actor.position   # as if walked there: the view comes along (at 43° the room stands taller on screen)
				_follow.held = false
		"wholeview":   # the whole room in view at this camera (shots: the art review's panorama, exposed backs)
			var view := _view()
			var need := maxf((_bounds_hi.x - _bounds_lo.x) / FRAME_W, (_bounds_hi.y - _bounds_lo.y) / (FRAME_H * view.y / maxf(view.x, 1.0)))
			_zoom = _cam_size / maxf(need, 0.01)
			var forward := -_cam_dir
			var right := forward.cross(Vector3.UP).normalized()
			_focus = _on_floor(right, right.cross(forward).normalized(), forward, (_bounds_lo + _bounds_hi) * 0.5)
			_follow.hold()
			_update_camera()
		"atedge":   # atedge:top|bottom|left|right — the walkable spot nearest the floor's corner furthest that way (shots)
			var forward := -_cam_dir
			var right := forward.cross(Vector3.UP).normalized()
			var axis: Vector3 = {"top": right.cross(forward).normalized(), "bottom": -right.cross(forward).normalized(),
				"left": -right, "right": right}.get(step[1], right)
			var best := Vector3.ZERO
			for c in [floor_rect.position, floor_rect.end, Vector2(floor_rect.position.x, floor_rect.end.y), Vector2(floor_rect.end.x, floor_rect.position.y)]:
				var p := room.position + Vector3(c.x, floor_y, c.y)
				if best == Vector3.ZERO or p.dot(axis) > best.dot(axis): best = p
			actor.teleport(P0RoomNav.nearest_walkable(bp, best))
			_focus = actor.position   # as if walked there: the view comes along (kept inside the art)
			_follow.held = false
		"tap": walk_to(step[1])
		"focus": focus(step[1])
		"exit": leave()
		_: return false
	return true

func p0_until(n: String) -> bool:
	match n:
		"idle": return _walk.is_empty() and not actor.mover.is_moving()
	return false
