extends Node3D
## P0 mine floors 1–2 (SGODOT-231; plan §13.3, LOCK-21, LOCK-24): the old polished mine chambers (MineArt B1 / B2,
## approved 2026-09-24) with the P0 actor, safe-box camera and main action key. The server owns the run (view.mine);
## this world draws it, picks what the player faces and sends mine_* commands. P0MaterialLogic writes every key, row
## and float; rocks, ladders and the elevator never respond to taps (LOCK-02), only to the main action key.

const Art = preload("res://modules/mining/mine_art.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")
const ElasticZoom = preload("res://modules/p0/p0_elastic_zoom.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const PLACE := "Shanghai · Mine · Floor %d"
const REACH := 1.7          # m: a rock, ladder or the elevator in front of the player within this distance
const BREAK_S := 0.45       # rock break: shake, shrink, chips
const STATUS_INTRO_MS := 3000   # "Run 1/2 today" first, then "Rocks 2/6" (MINE-1 / P0-2)

var rt: P0Runtime
var floor_n := 1
var cam: Camera3D
var environment: Environment
var world_env: WorldEnvironment
var actor: P0Actor
var bp: FarmBlueprint
var grid: BlueprintGrid
var scenery: Node3D
var objects: Node3D
var _rocks := {}            # rock index → Node3D (gone once broken)
var _previews := {}         # rock index → Sprite3D torch preview
var _breaking := {}         # rock index → true while its break plays (the view may already say broken)
var _focus := Vector3.ZERO
var _cam_follow := P0Follow.new()
# Camera unification (用户 via 奕星, 2026-10-09; target 哪吒, 65.8 px at 360 × 800): the farm's size and pinch — zoom 1 is
# FarmCamera.player_scale_size at the farm's 43° pitch, rubber-banded 0.8–1.4 about the pinch centre (ElasticZoom).
var _zoom := 1.0
var _room := AABB()          # this floor's walls (the camera's vertical framing, _frame_chamber); empty until built
var _art_points := PackedVector3Array()   # this floor's art vertices incl. the ladders and the elevator (side stops)
var _art_sides := PackedVector3Array()    # of those, the leftmost and rightmost for the camera's right (_side_points)
var _art_right := Vector3.ZERO            # the camera right _art_sides were found for
var _band := Rect2()         # the last camera band seen with no panel up (_camera_band)
var _pinch = ElasticZoom.new(0.8, 1.4)
var _zoom_at := Vector2.INF
var _target := {}           # {kind, rock, at}
var _entered_ms := 0
var _hold_until := 0
var _leaving := false
var _grey := false
var _elevator_to := -1      # the floor an elevator ride asked for: it lands beside the elevator, not at the stairs

func setup(args: Dictionary) -> void:
	floor_n = clampi(int(args.get("floor", 1)), 1, 2)

func _ready() -> void:
	P0Runtime.mark("%s _ready start" % name)
	get_viewport().transparent_bg = false
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())
	_build_light()
	actor = P0Actor.new()
	add_child(actor)
	_build_floor(floor_n)
	actor.setup(bp, grid, cam, Layout.SPAWN)
	_focus = actor.position
	_update_camera()
	_entered_ms = Time.get_ticks_msec()
	rt = P0Runtime.ensure()
	rt.attach(self)
	rt.ui.set_mode("mine")
	rt.ui.set_place(PLACE % floor_n)
	rt.session.state_changed.connect(_on_state)

func _exit_tree() -> void:
	if rt:
		if rt.session.state_changed.is_connected(_on_state): rt.session.state_changed.disconnect(_on_state)
		rt.detach(self)

func p0_surface() -> String: return "mine"
func p0_space() -> String: return "mine"
func p0_energy_verb() -> String: return str(rt.ui.fab_state().get("verb", "Mine"))

# ---------------------------------------------------------------- world
## The old mine's light (scenes/mine/mine.gd 135–155): dark backdrop, warm key light, lantern pools in the chamber.
func _build_light() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("242125")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e8dfea")
	environment.ambient_light_energy = 0.48
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-51, -38, 0)
	sun.light_color = Color("ffe8ce")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.58
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.45
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(cam)
	cam.make_current()

## One chamber: B1 (floor 1) / B2 (floor 2) art, the six fixed rock positions (the server's rock index), the up ladder
## (Exit mine on floor 1, Floor 1 on floor 2), the down ladder to floor 2 and an elevator on both floors (q(44)).
func _build_floor(n: int) -> void:
	floor_n = n
	for node in [scenery, objects]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	_rocks.clear()
	_previews.clear()
	_breaking.clear()
	scenery = Art.floor_scenery(n, true)   # adds the up ladder, and the elevator on floor 1
	add_child(scenery)
	_room = _walls_box(scenery)
	objects = Node3D.new()
	objects.name = "MineObjects"
	add_child(objects)
	if n != 1: objects.add_child(Art.elevator(true))
	if n < 2: objects.add_child(Art.ladder(Layout.DOWN, false))
	var broken := _broken(_view(), n)
	for i in Layout.FALLBACK_POSITIONS.size():
		if broken[i]: continue
		var rock := Art.rock(Layout.FALLBACK_POSITIONS[i], i, n)
		rock.name = "Rock%d" % i
		objects.add_child(rock)
		_rocks[i] = rock
	_art_points = _art_vertices(scenery)
	for node in objects.get_children():   # the elevator and the down ladder stand against the walls; rocks are inside
		if not str(node.name).begins_with("Rock"): _art_points.append_array(_art_vertices(node))
	_art_right = Vector3.ZERO
	_rebuild_nav(broken)

func _rebuild_nav(broken: Array) -> void:
	var nodes: Array = []
	var gone: Array = []
	for i in Layout.FALLBACK_POSITIONS.size():
		nodes.append({"id": str(i), "position": Layout.FALLBACK_POSITIONS[i]})
		if broken[i]: gone.append(str(i))
	bp = Layout._navigation(nodes, gone)
	grid = BlueprintGrid.new(bp)
	if actor and actor.mover:
		var at := actor.mover.position
		actor.mover = PlayerMover.new(bp, grid)
		actor.mover.position = at if bp.is_walkable(bp.world_to_cell(at)) else Layout.SPAWN

func _view() -> Dictionary:
	return rt.session.current() if rt else (P0Runtime.ensure().session.current())

func _broken(v: Dictionary, n: int) -> Array:
	var out: Array = []
	out.resize(Layout.FALLBACK_POSITIONS.size())
	out.fill(false)
	var run = v.get("mine", {}).get("run", null)
	if run == null: return out
	for f in run.get("floors", []):
		if int(f.get("floor", 0)) == n:
			var b: Array = f.get("broken", [])
			for i in mini(b.size(), out.size()): out[i] = bool(b[i])
	return out

## Stairs, the elevator or a new floor: rebuild the chamber and land at the spawn (the elevator lands beside it).
func _go_floor(n: int, by_elevator := false) -> void:
	_build_floor(n)
	actor.teleport(Layout.ELEVATOR + Vector3(1.1, 0, 0.6) if by_elevator else Layout.SPAWN)
	_focus = actor.position
	_cam_follow.hold()
	rt.ui.set_place(PLACE % n)
	_entered_ms = Time.get_ticks_msec()

# ---------------------------------------------------------------- frame
func p0_joystick(v: Vector2) -> void:
	if actor and not _leaving: actor.set_input(v)

## Facilities respond to taps, rocks and ladders don't (LOCK-02): taps in the mine only move nothing.
func p0_tap(_screen: Vector2) -> void:
	pass

func p0_frame(v: Dictionary, dt: float) -> void:
	if _leaving: return
	if v.get("mine", {}).get("run", null) == null:
		_kick_out()
		return
	actor.step(dt)
	_follow(dt)
	_sync_rocks(v)
	_pick_target()
	var ctx := {"floor": floor_n, "target": str(_target.get("kind", "")), "rock": int(_target.get("rock", -1)),
		"item": _selected_item()}
	rt.ui.set_action(P0MaterialLogic.mine_action(v, ctx))
	_hold_repeat()
	_marks(v)

## Rocks the server says are broken (another device, a reconnect) leave without the break animation.
func _sync_rocks(v: Dictionary) -> void:
	var broken := _broken(v, floor_n)
	var changed := false
	for i in broken.size():
		if broken[i] and _rocks.has(i) and not _breaking.has(i):
			_rocks[i].queue_free()
			_rocks.erase(i)
			changed = true
	if changed: _rebuild_nav(broken)

## The rock, ladder or elevator in front: nearest within reach, favouring what the player faces.
func _pick_target() -> void:
	var best := {}
	var best_score := INF
	var f := actor.facing()
	var candidates: Array = []
	for i in _rocks: candidates.append({"kind": "rock", "rock": int(i), "at": Layout.FALLBACK_POSITIONS[i]})
	candidates.append({"kind": "exit" if floor_n == 1 else "up", "at": Layout.UP})
	if floor_n < 2: candidates.append({"kind": "stairs", "at": Layout.DOWN})
	candidates.append({"kind": "elevator", "at": Layout.ELEVATOR})
	for c in candidates:
		var to: Vector3 = c.at - actor.position
		to.y = 0
		var d := to.length()
		if d > REACH: continue
		var score := d - 0.6 * (f.dot(to.normalized()) if d > 0.01 else 1.0)
		if score < best_score:
			best_score = score
			best = c
	_target = best

## The quick-bar selection in Mining (the torch): like seeds, the non-fishing bar selects into selected_seed.
func _selected_item() -> String:
	return rt.ui.selected_seed if rt.ui.bar_mode == "mine" else ""

## Hold the key to keep mining (the farm's hold-to-repeat): the same verb, one labour beat apart.
func _hold_repeat() -> void:
	if not rt.ui.fab_held or rt.ui.has_modal() or actor.busy() or rt.session.busy: return
	if Time.get_ticks_msec() < _hold_until: return
	var a: Dictionary = rt.ui.fab_state()
	var cmd: Dictionary = a.get("cmd", {})
	if not a.get("enabled", false) or str(cmd.get("type", "")) != "mine_rock": return
	if rt.ui.fab_verb == "": rt.ui.fab_verb = str(a.get("verb", ""))
	if str(a.get("verb", "")) != rt.ui.fab_verb: return
	p0_action(cmd)

## Floor-wide grey on a full bag (q(44)), torch previews over lit rocks, the status line.
func _marks(v: Dictionary) -> void:
	var marks := P0MaterialLogic.rock_marks(v, floor_n)
	var grey := not marks.is_empty() and bool(marks[0].grey)
	if grey != _grey:
		_grey = grey
		for i in _rocks:
			var mesh := (_rocks[i] as Node3D).get_node_or_null("Rock") as MeshInstance3D
			if mesh: mesh.transparency = 0.45 if grey else 0.0
	for i in marks.size():
		var drop = marks[i].preview
		var show: bool = drop != null and str(drop) != "" and _rocks.has(i)
		if show and not _previews.has(i):
			var s := Sprite3D.new()
			s.texture = P0Logic.icon(str(drop))
			s.pixel_size = 0.0045
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.no_depth_test = true
			s.position = Layout.FALLBACK_POSITIONS[i] + Vector3(0, 1.05, 0)
			objects.add_child(s)
			_previews[i] = s
		elif not show and _previews.has(i):
			_previews[i].queue_free()
			_previews.erase(i)
	var intro := Time.get_ticks_msec() - _entered_ms < STATUS_INTRO_MS
	rt.ui.set_status_line(P0MaterialLogic.mine_status(v, floor_n, intro))

# ---------------------------------------------------------------- actions
func p0_action(cmd: Dictionary) -> void:
	match str(cmd.get("type", "")):
		"mine_rock":
			var i := int(cmd.get("rock", -1))
			if _rocks.has(i): actor.labour("till", Layout.FALLBACK_POSITIONS[i])   # the old mine's dig beat (user, 2026-10-08)
			_hold_until = Time.get_ticks_msec() + int(maxf(P0Actor.LABOUR_S, 0.95) * 1000.0)   # server tempo 0.9 s
			rt.session.send(cmd)
		"mine_floor", "mine_torch":
			rt.session.send(cmd)
		"elevator":
			P0MaterialCards.open_elevator(rt.ui, _view(), floor_n, _on_elevator_row)
		"mine_exit", "mine_leave":
			_leave()
		"toast":
			rt.ui.toast(str(cmd.get("text", "")))
		_:
			if not cmd.is_empty(): rt.session.send(cmd)

func _on_elevator_row(cmd: Dictionary) -> void:
	rt.ui.close_modal()
	match str(cmd.get("type", "")):
		"mine_leave": _leave()
		"mine_floor":
			if int(cmd.get("floor", 0)) == floor_n: return
			_elevator_to = int(cmd.get("floor", 0))
			rt.session.send(cmd)
		"energy_card": rt._on_action(cmd)

## Server results for this world: a rock breaks, a floor is reached or cleared, a torch lights the floor.
func _on_state(v: Dictionary, events: Array) -> void:
	if rt.world != self: return
	for e in events:
		if str(e.get("kind", "")) != "mine": continue
		var text := P0MaterialLogic.mine_event_text(e)
		if text != "":
			if str(e.get("action", "")) == "cleared": rt.ui.toast_success(text)   # MINE-P0-3 banner, §4.8.6 Toast Success
			else:   # the floor fee `Floor 2 · −2 Energy` (q(46)): the Energy line of the reply's three (q(49) ①)
				rt.ui.queue_floats([{kind = "energy", key = text, text = text, tone = UiFloatText.Tone.ENERGY_COST}], rt.anchor())
		match str(e.get("action", "")):
			"rock": _break_rock(int(e.get("rock", -1)), v)
			"floor":
				var n := int(e.get("floor", floor_n))
				if n != floor_n: _go_floor(n, n == _elevator_to)
				_elevator_to = -1

## The break the old mine never had: a short shake, shrink and stone chips, then only this rock goes (no floor rebuild).
func _break_rock(i: int, v: Dictionary) -> void:
	if not _rocks.has(i): return
	var rock: Node3D = _rocks[i]
	_breaking[i] = true
	_chips(rock.position)
	var tw := create_tween()
	tw.tween_property(rock, "rotation:z", 0.12, BREAK_S * 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(rock, "rotation:z", -0.1, BREAK_S * 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(rock, "scale", Vector3(0.2, 0.05, 0.2), BREAK_S * 0.64).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.finished.connect(func():
		if is_instance_valid(rock): rock.queue_free()
		_rocks.erase(i)
		_breaking.erase(i)
		if _previews.has(i):
			_previews[i].queue_free()
			_previews.erase(i)
		_rebuild_nav(_broken(rt.session.current(), floor_n)))

func _chips(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.position = at + Vector3(0, 0.35, 0)
	p.direction = Vector3.UP
	p.spread = 70
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.11
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("687376")
	mat.roughness = 0.95
	mesh.material = mat
	p.mesh = mesh
	objects.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

## Out of the mine: back to the farm (this world sits above it), 0 Energy (q(44)). The run stays until 04:00. One
## layer down, like a room's door: leave_world goes all the way to the map (the place chip's path), which took the
## exit ladder and the elevator's Ground to the map (user int11 ①, 不知火舞 on 231).
func _leave() -> void:
	if _leaving: return
	_leaving = true
	actor.set_input(Vector2.ZERO)
	rt.leave_room()

## 04:00 while inside: back outside the mouth, where the farm floats "Run ended at daily reset" once (q(44)).
func _kick_out() -> void:
	_leave()

# ---------------------------------------------------------------- camera (old mine framing + safe box)
func _follow(dt: float) -> void:
	_focus = _cam_follow.step(cam, _focus, actor.position, actor.mover.is_moving(), dt)
	if _pinch.step(dt): _set_zoom(_pinch.value)   # springing back from past a limit, about the same point
	else: _update_camera()

func _update_camera() -> void:
	cam.size = FarmCamera.player_scale_size(get_viewport().get_visible_rect().size, FarmCamera.PITCH_DEG) / _zoom
	FarmCamera.place(cam, _focus + Vector3.UP * 0.7)
	_frame_chamber()
	FarmCamera.fit_ground_depth(cam)

## Framing (不知火舞 on 231, the rooms' rule of #127). Down: the four corners of the band between the HUD and the quick
## bar / main key (_camera_band) land in the room — the top corners at the wall tops within the back wall, the bottom
## corners on the floor within the front edge; the room is wider than that band, so the focus stays at the middle of
## the range this gives (fixed). Across: the room is wider than the screen, so the safe box follows, but stops where the
## art's outer edge — the walls, the ladders and the elevator on them — comes P0Room.SIDE_MARGIN (18 px) from the
## screen's side, the mine's dark backdrop showing past it. Moves `_focus` itself, so the follow and the pinch carry on.
func _frame_chamber() -> void:
	if _room.size == Vector3.ZERO: return
	var vp := get_viewport().get_visible_rect().size
	var band := _camera_band(rt.ui if rt != null else null, vp)
	if band.size.x <= 0.0 or band.size.y <= 0.0: return
	var lo := -INF
	var hi := INF
	for c in [band.position, Vector2(band.end.x, band.position.y), Vector2(band.position.x, band.end.y), band.end]:
		var far: bool = c.y == band.position.y
		var off := _ray_at(c, _room.end.y if far else _room.position.y) - _focus
		if far: lo = maxf(lo, _room.position.z - off.z)
		else: hi = minf(hi, _room.end.z - off.z)
	var z := clamp_or_centre(_focus.z, lo, hi)
	if not is_equal_approx(z, _focus.z):
		_focus.z = z
		FarmCamera.place(cam, _focus + Vector3.UP * 0.7)
	# Across, on screen: the art's outermost points against the side margins. Moving the focus along the ground's x
	# moves the picture across by cos(yaw) of it (orthographic: the same everywhere), so one step lands it.
	var sides := _side_points()
	if sides.is_empty(): return
	var dx := side_shift(cam.unproject_position(sides[0]).x, cam.unproject_position(sides[1]).x, vp.x, P0Room.SIDE_MARGIN)
	if is_zero_approx(dx): return
	var px_per_x := cam.global_basis.x.x * vp.x / cam.size   # screen px per metre of ground x
	if absf(px_per_x) < 0.0001: return
	_focus.x -= dx / px_per_x
	FarmCamera.place(cam, _focus + Vector3.UP * 0.7)

## How far (px) the art spanning left..right must move across a screen `width` wide: into the middle when it fits
## inside the margins, else only so far that neither side shows more than `margin` of backdrop.
static func side_shift(left: float, right: float, width: float, margin: float) -> float:
	if right - left <= width - 2.0 * margin: return (width - left - right) * 0.5
	if left > margin: return margin - left
	if right < width - margin: return width - margin - right
	return 0.0

## The band to frame into: P0Ui.camera_band while no panel is up, else the last one seen then (苏烈 on #129). A panel
## that hides the quick bar and the key (the inbox, the profile, the skills) would stretch the band to the screen's
## foot and the fixed middle would move — the room jumping behind the panel and back. The whole viewport until a band
## has been seen.
func _camera_band(ui: P0Ui, viewport: Vector2) -> Rect2:
	if ui != null and ui.is_node_ready() and not ui.has_modal(): _band = ui.camera_band()
	return _band if _band.has_area() else Rect2(Vector2.ZERO, viewport)

## Where the camera ray through a screen point (this UI's coordinates) crosses the plane at height y.
func _ray_at(screen: Vector2, y: float) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var n := cam.project_ray_normal(screen)
	return o + n * ((y - o.y) / n.y) if absf(n.y) > 0.0001 else o

## The allowed range's middle when it is empty (the band is wider than the room: that axis stays fixed), else v clamped.
static func clamp_or_centre(v: float, lo: float, hi: float) -> float:
	return (lo + hi) * 0.5 if lo > hi else clampf(v, lo, hi)

## The floor's walls: of the art's meshes, the one standing taller than half a metre with the widest footprint — the
## carved walls; Art.VIEW_BOUNDS if none is found.
static func _walls_box(root: Node3D) -> AABB:
	var best := AABB()
	for b in _art_boxes(root):
		if b.size.y > 0.5 and b.size.x * b.size.z > best.size.x * best.size.z: best = b
	return best if best.size != Vector3.ZERO else Art.VIEW_BOUNDS

## The art's leftmost and rightmost vertex on screen. The camera only turns with the yaw, which is fixed, so they are
## found once per floor (and again only if the camera's right changes) and projected each frame — the real outer edge,
## not a box corner standing out past a rounded wall end.
func _side_points() -> PackedVector3Array:
	var r := cam.global_basis.x
	if _art_points.is_empty(): return PackedVector3Array()
	if r.is_equal_approx(_art_right) and _art_sides.size() == 2: return _art_sides
	var lo := _art_points[0]
	var hi := _art_points[0]
	for p in _art_points:
		if p.dot(r) < lo.dot(r): lo = p
		if p.dot(r) > hi.dot(r): hi = p
	_art_right = r
	_art_sides = PackedVector3Array([lo, hi])
	return _art_sides

## Every mesh vertex under `root` in world space (MeshInstance3D and MultiMeshInstance3D); lights and decals have none
## that matter here, the wall contact shade lies flat inside the walls' reach.
static func _art_vertices(root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	if root == null: return out
	var nodes: Array = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D: nodes.append(root)
	for g in nodes:
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var xf: Transform3D = (g as Node3D).global_transform
			if (g as MeshInstance3D).get_aabb().size.y <= 0.01: continue   # flat decals
			for v in (g as MeshInstance3D).mesh.get_faces(): out.append(xf * v)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm.mesh == null: continue
			var faces := mm.mesh.get_faces()
			var base: Transform3D = (g as Node3D).global_transform
			for i in mm.instance_count:
				var xf := base * mm.get_instance_transform(i)
				for v in faces: out.append(xf * v)
	return out

## One world box per mesh under `root` — lights and flat decals left out (the wall contact shade reaches past the
## walls); not merged, so a tall piece inside (the elevator) does not raise the walls' corners.
static func _art_boxes(root: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	if root == null: return out
	for vi in root.find_children("*", "VisualInstance3D", true, false):
		if vi is Light3D: continue
		var b: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		if b.size.y > 0.01: out.append(b)
	return out

## Zoom about the last pinch centre: the ground point under the fingers stays put (the farm's _set_zoom).
func _set_zoom(value: float) -> void:
	_zoom = value
	if cam == null or not is_inside_tree(): return
	var before = ElasticZoom.ground_at(cam, _zoom_at, _focus.y)
	_update_camera()
	var d := ElasticZoom.shift(before, ElasticZoom.ground_at(cam, _zoom_at, _focus.y))
	if d != Vector3.ZERO:
		_focus += d
		_update_camera()

func p0_zoom(f: float, at := Vector2.INF) -> void:
	_zoom_at = at
	_pinch.pinch(f)
	_cam_follow.hold()   # the pinched framing stays until the player walks (the safe box takes over then)
	_set_zoom(_pinch.value)
func p0_zoom_end() -> void: _pinch.release()
func p0_recenter() -> void:
	_focus = actor.position
	_cam_follow.held = false

func p0_anchor() -> Vector2:
	var at: Vector3 = _target.get("at", actor.position) if not _target.is_empty() else actor.position
	return cam.unproject_position(at + Vector3(0, 1.0, 0))

func is_back_navigation_locked() -> bool: return false

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
	if rt: rt.attach(self)

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"goto":
			actor.teleport(Vector3(float(step[1]), 0, float(step[2])))
			_focus = actor.position
		"rock":
			var i := int(step[1])
			actor.teleport(Layout.approach(actor.mover, Layout.FALLBACK_POSITIONS[i]))
			actor.face(Layout.FALLBACK_POSITIONS[i])
			_focus = actor.position
		"floor": _go_floor(int(step[1]))
		"elevator": p0_action({"type": "elevator"})
		"elevrow":   # elevrow:0 — press that row of the open elevator panel (row 0 is Ground)
			for n in rt.ui.find_children("*", "", true, false):
				if n is UiElevatorPanel and (n as UiElevatorPanel).row(int(step[1])) != null:
					(n as UiElevatorPanel).row(int(step[1])).pressed.emit()
					break
		"exit": _leave()
		_: return false
	return true

func p0_until(name: String) -> bool:
	match name:
		"floor2": return floor_n == 2
		"idle": return not actor.busy()
	return false
