extends Node3D
## P0 homestead: the old polished farm presentation (cottage, well, seed box, garden dressing, thick
## soil beds, procedural crops, rig and labour clips, 43° ortho camera) driven by the P0 server view
## and the new UI flow (joystick, main action, quick bar, cards) from P0Runtime.
## Ponds are on the map; the kitchen is inside the farmhouse (P0Room, SGODOT-226); nothing here is greybox.

const FarmProps = preload("res://modules/farm/farm_props.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const FarmArt = preload("res://modules/farm/farm_art.gd")
const MineArt = preload("res://modules/mining/mine_art.gd")
const GardenScenery = preload("res://scenes/p0/p0_garden_scenery.gd")
const FARMHOUSE := "res://scenes/p0/rooms/p0_farmhouse.tscn"
## Walking into the doorway goes in (mirror of a room's door): inside the walkway cell in front of the door
## (DOOR_HALF either side; the camera-relative joystick drifts sideways), pushing towards the house, after
## having been DOOR_ARM_M away (so stepping out of the farmhouse does not walk straight back in).
const DOOR_HALF := Vector2(0.6, 0.4)
const DOOR_ARM_M := 1.5

const STYLE := "cottage"          # the orange-roof cottage of the polished farm
const PLACE := "Shanghai · Homestead"
const LABOUR_CLIP := {"till": "till", "sow": "sow", "water": "water", "harvest": "harvest"}

@onready var cam: Camera3D = $Camera3D
@onready var ground: MeshInstance3D = $Ground

var rt: P0Runtime
var bp: FarmBlueprint
var grid: BlueprintGrid
var actor: P0Actor
var crops: CropField
var beds: MultiMeshInstance3D
var _hi: MeshInstance3D
var _house := Vector3.ZERO
var _stall := Vector3.ZERO   # the Homestead Stall (unattended, p(6)); the seed box stands in until its model
var _mine := Vector3.ZERO
var _focus := Vector3.ZERO
var _cam_follow := P0Follow.new()
var _zoom := 1.0
var _pinch = preload("res://modules/p0/p0_elastic_zoom.gd").new(0.8, 1.4)   # rubber band past 0.8 / 1.4
var _dev_yaw := -1.0
var _hold_until := 0.0
var _front: Dictionary = {}
var _row: Array = []   # plots a Row Hoe sows from _front (P0Logic.row_plots)
var _front_cell := Vector2i(-1, -1)
var _plot_sig := ""
var _sync_t := 0.0
var _door := Vector3.ZERO     # the walkway cell in front of the farmhouse door
var _door_armed := false
var _inside := false          # the farmhouse is open above this farm

func _ready() -> void:
	P0Runtime.mark("%s _ready start" % name)
	bp = P0Garden.blueprint()
	grid = BlueprintGrid.new(bp)
	get_viewport().transparent_bg = false   # pushed above the map, whose tiles show through a transparent root
	cam.make_current()
	_build_world()
	rt = P0Runtime.ensure()
	rt.attach(self)
	rt.ui.set_mode("farm")
	rt.ui.set_place(PLACE)

func _exit_tree() -> void:
	if rt: rt.detach(self)

## Android Back: the UI's top layer (PinMenu, radial, a card or drawer) closes first, one per press; with nothing
## open, back to the map: AppRouter pops a farm stacked on the map, a farm that is the root scene leaves by itself
## (int5 hand test 012–013 / 023–024, int5b test 2; rooms do the same, p0_room).
func is_back_navigation_locked() -> bool:
	return rt != null and (rt.ui.close_top_layer() or rt.root_back())

## AppRouter stacking: the map below us hands back its camera and environment on resume.
func suspend() -> void:
	set_process(false)
	visible = false

func resume() -> void:
	get_viewport().transparent_bg = false
	visible = true
	set_process(true)
	cam.make_current()
	if rt:
		rt.attach(self)
		rt.ui.set_place(PLACE)   # back from the farmhouse
	if _inside:
		# Out through the farmhouse door: stand on the doorstep facing the field.
		_inside = false
		actor.teleport(_door)
		actor.face(_door + Vector3(0, 0, 1))
		_focus = _door
		_cam_follow.hold()
		_place_camera()
	_door_armed = false

func p0_surface() -> String: return "farm"

# ---------------------------------------------------------------- world
func _build_world() -> void:
	var lawn := PlaneMesh.new()
	lawn.size = Vector2.ONE * 96.0
	ground.mesh = lawn
	ground.position = Vector3(bp.play_area_m * 0.5, -0.008, -bp.play_area_m * 0.5)
	_house = bp.cell_to_world(bp.anchor("house"))
	_door = bp.cell_to_world(bp.anchor("house") + Vector2i(0, -2))
	var grass := ShaderMaterial.new()
	grass.shader = preload("res://modules/farm/shaders/meadow.gdshader")
	grass.set_shader_parameter("meadow_texture", preload("res://assets/farm/art/meadow.png"))
	grass.set_shader_parameter("woodland_start", -_house.z + 3.75)
	ground.material_override = grass
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	props.add_child(FarmProps.build("house", _house, 1.0, STYLE))
	props.add_child(FarmProps.build("storage", bp.cell_to_world(bp.anchor("storage")), 1.0, STYLE))
	props.add_child(FarmProps.build("well", bp.cell_to_world(bp.anchor("well")), 1.0, STYLE))
	_mine = bp.cell_to_world(bp.anchor("mine")) + Vector3(-0.3, 0, 0.3)
	var mine := MineArt.entrance()
	mine.position = _mine
	mine.rotation.y = PI * 0.15
	props.add_child(mine)
	var scenery := GardenScenery.new()
	add_child(scenery)
	scenery.build(bp, STYLE)
	P0Garden.block_points(bp, scenery.rock_points)   # rocks collide; crops and bushes don't
	grid = BlueprintGrid.new(bp)
	# One thick soil bed per plot (plot.glb), tinted per state (watered beds read darker).
	var xfs: Array = []
	var tints := PackedColorArray()
	for id in P0Garden.plot_count():
		xfs.append(Transform3D(Basis.IDENTITY, bp.cell_to_world(P0Garden.cell_of(id))))
		tints.append(Color.WHITE)
	beds = FarmArt.batch("plot", xfs, true, tints)
	beds.name = "Beds"
	add_child(beds)
	crops = CropField.new(bp)
	crops.ground_y = P0Garden.BED_H
	crops.ground_layers = true
	crops.plant_scale = 0.94 / bp.cell_m   # size plants to the 0.94 m bed, as the old 1.3 m-pitch garden did
	add_child(crops)
	_hi = _bed_highlight()
	add_child(_hi)
	_stall = bp.cell_to_world(bp.anchor("storage"))
	actor = P0Actor.new()
	add_child(actor)
	actor.setup(bp, grid, cam)
	actor.ground_height = func(p: Vector3) -> float: return P0Garden.BED_H if P0Garden.on_bed(bp, p) else 0.0
	# Opening shot like the polished farm: cottage on top, beds below, the player at the front edge.
	_focus = actor.position.lerp(_house, 0.42)
	_cam_follow.hold()   # the opening shot stays until the player first moves
	_place_camera()

## A soft mint rounded-square outline on top of the bed in front of the player.
func _bed_highlight() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := _rounded_square(0.50, 0.14)
	var inner := _rounded_square(0.43, 0.09)
	for i in outer.size():
		var j := (i + 1) % outer.size()
		var a := Vector3(outer[i].x, 0, outer[i].y)
		var b := Vector3(outer[j].x, 0, outer[j].y)
		var c := Vector3(inner[i].x, 0, inner[i].y)
		var d := Vector3(inner[j].x, 0, inner[j].y)
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(b); st.add_vertex(d); st.add_vertex(c)
	var mi := MeshInstance3D.new()
	mi.name = "BedHighlight"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.86, 0.98, 0.80, 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

static func _rounded_square(half: float, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var centres := [Vector2(half - radius, half - radius), Vector2(-half + radius, half - radius),
		Vector2(-half + radius, -half + radius), Vector2(half - radius, -half + radius)]
	for k in 4:
		for s in 5:
			var ang := PI * 0.5 * k + PI * 0.5 * float(s) / 4.0
			pts.append(centres[k] + Vector2(cos(ang), sin(ang)) * radius)
	return pts

# ---------------------------------------------------------------- camera (old farm camera + safe box)
func _place_camera() -> void:
	var vp := get_viewport().get_visible_rect().size
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH   # the old farm frames by width (portrait phones)
	cam.size = FarmCamera.close_view_size(vp) * 1.12 / _zoom
	FarmCamera.place(cam, _focus + Vector3.UP * 0.7)
	if _dev_yaw >= 0.0:   # P0_SHOT yaw comparison only (style doc asks 35–45°, the old farm uses 14.5°)
		var c := _focus + Vector3.UP * 0.7
		var pitch := deg_to_rad(FarmCamera.PITCH_DEG)
		var yaw := deg_to_rad(_dev_yaw)
		cam.position = c + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * FarmCamera.DISTANCE
		cam.look_at(c, Vector3.UP)
	FarmCamera.fit_ground_depth(cam)

func _follow(dt: float) -> void:
	_focus = _cam_follow.step(cam, _focus, actor.position, actor.mover.is_moving(), dt)
	if _pinch.step(dt): _zoom = _pinch.value   # springing back from past a limit
	_place_camera()

func p0_zoom(f: float) -> void:
	_pinch.pinch(f)
	_zoom = _pinch.value
func p0_zoom_end() -> void: _pinch.release()
func p0_recenter() -> void:
	_focus = actor.position
	_cam_follow.held = false

func p0_show_spot(where: String) -> void:
	var at := _house if where in ["stove", "bench", "home"] else actor.position
	if where == "stall": at = _stall
	elif where == "plots": at = _plots_center()
	_focus = at
	_cam_follow.hold()
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.08
	ring.mesh = tm
	ring.position = at + Vector3(0, 0.06, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.83, 0.42)
	ring.material_override = m
	add_child(ring)
	var tw := create_tween().set_loops(2)
	tw.tween_property(ring, "scale", Vector3(1.2, 1, 1.2), 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	tw.finished.connect(ring.queue_free)

# ---------------------------------------------------------------- frame
func p0_joystick(v: Vector2) -> void:
	if actor: actor.set_input(v)

func p0_frame(v: Dictionary, dt: float) -> void:
	actor.step(dt)
	_door_check()
	_follow(dt)
	rt.ui.player_screen = cam.unproject_position(actor.position + Vector3(0, 0.9, 0))   # the radial fans out from here
	_sync_plots(v, dt)
	_pick_front(v)
	rt.ui.set_action(P0Logic.main_action(v, _front, rt.ui.selected_seed, _row))
	_hold_repeat()
	_tags(v)
	_teaching(v)

func _sync_plots(v: Dictionary, dt: float) -> void:
	if _plot_sig == "frozen": return
	_sync_t -= dt
	var sig := ""
	for p in v.get("plots", []): sig += "%s%s;" % [str(p.get("state", "")), str(p.get("crop", ""))]
	if sig == _plot_sig and _sync_t > 0.0: return
	_plot_sig = sig
	_sync_t = 1.0
	var now := Time.get_ticks_msec()
	crops.sync(P0Garden.cells(v, now), now)
	for p in v.get("plots", []):
		var id := int(p.get("id", -1))
		if id >= 0 and id < P0Garden.plot_count(): beds.multimesh.set_instance_color(id, P0Garden.bed_tint(str(p.get("state", ""))))

## Middle of the plot beds, for camera-only "Show" from the Today panel and NeedSource (LOCK-08).
func _plots_center() -> Vector3:
	var sum := Vector3.ZERO
	for id in P0Garden.plot_count(): sum += bp.cell_to_world(P0Garden.cell_of(id))
	return sum / maxf(1.0, float(P0Garden.plot_count()))

## The bed the player faces from the walkway: nearest bed ahead within reach.
func _pick_front(v: Dictionary) -> void:
	var best := -1
	var best_score := -INF
	var f := actor.facing()
	for id in P0Garden.plot_count():
		var c := bp.cell_to_world(P0Garden.cell_of(id))
		var to := Vector2(c.x - actor.position.x, c.z - actor.position.z)
		var dist := to.length()
		if dist > 1.05: continue
		var ahead := to.normalized().dot(Vector2(f.x, f.z)) if dist > 0.01 else 1.0
		# Standing on a bed works that bed; otherwise ahead first, and a bed right beside the walkway
		# also counts, so walking a row while holding works.
		var underfoot := dist < 0.42
		if not underfoot and ahead < 0.2 and not (dist < 0.8 and ahead > -0.25): continue
		var score := 10.0 if underfoot else ahead * 0.6 - dist * 0.8
		if score > best_score:
			best_score = score
			best = id
	_front = {}
	if best >= 0:
		for p in v.get("plots", []):
			if int(p.get("id", -1)) == best: _front = p
	# Row Hoe: the bed in front and its tilled neighbours in the row, the way the player faces first (plot ids grow along +x).
	_row = P0Logic.row_plots(v, _front, P0Garden.COLUMNS, 1 if f.x >= 0.0 else -1)
	_hi.visible = not _front.is_empty() and not rt.ui.has_modal()
	if _hi.visible:
		_front_cell = P0Garden.cell_of(best)
		_hi.position = bp.cell_to_world(_front_cell) + Vector3(0, P0Garden.BED_H + 0.012, 0)

# ---------------------------------------------------------------- actions
func p0_action(cmd: Dictionary) -> void:
	var type := str(cmd.get("type", ""))
	var target := int(cmd.get("plot", (cmd.get("plots", [-1]) as Array)[0] if cmd.has("plots") else -1))
	if LABOUR_CLIP.has(type) and target >= 0:
		actor.labour(LABOUR_CLIP[type], bp.cell_to_world(P0Garden.cell_of(target)))
		_hold_until = Time.get_ticks_msec() + P0Actor.LABOUR_S * 1000.0
	rt.session.send(cmd)

func p0_home(choice: String) -> void:
	if choice == "kitchen": enter_farmhouse()

## Into the farmhouse (its stove corner is the kitchen); the farm waits suspended underneath.
func enter_farmhouse() -> void:
	if AppRouter._navigation_pending or (AppRouter.top_instance() != null and AppRouter.top_instance() != self): return
	P0Runtime.nav_started()
	_inside = true
	AppRouter.open_instance(FARMHOUSE, {})

func _door_check() -> void:
	var off := Vector2(actor.position.x - _door.x, actor.position.z - _door.z)
	if off.length() > DOOR_ARM_M: _door_armed = true
	elif _door_armed and absf(off.x) < DOOR_HALF.x and absf(off.y) < DOOR_HALF.y and actor.mover.is_moving() \
			and actor.facing().z < -0.5 and not rt.ui.has_modal():
		_door_armed = false
		enter_farmhouse()

func p0_energy_verb() -> String: return str(rt.ui.fab_state().get("verb", "Sow ×1"))

## Hold to keep sowing (§14.2): the verb pressed first repeats on each new bed, one labour beat apart.
func _hold_repeat() -> void:
	if not rt.ui.fab_held or rt.ui.has_modal() or actor.busy() or rt.session.busy: return
	if Time.get_ticks_msec() < _hold_until: return
	var a: Dictionary = rt.ui.fab_state()
	var cmd: Dictionary = a.get("cmd", {})
	if not a.get("enabled", false) or cmd.is_empty() or str(cmd.get("type", "")) == "energy_card": return
	if rt.ui.fab_verb == "": rt.ui.fab_verb = str(a.get("verb", ""))
	if str(a.get("verb", "")) != rt.ui.fab_verb: return
	rt.holding_repeat = true   # the observation log's "hold" (S7); the first press went out as a tap
	p0_action(cmd)
	rt.holding_repeat = false

## Facilities respond to taps only (§10.2.2): the stall opens its drawer directly (unattended, p(6)), the farmhouse
## takes the player in (its kitchen is inside since SGODOT-226; the door card is gone, int5 hand test 37), the mine.
func p0_tap(screen: Vector2) -> void:
	if rt.ui.has_modal(): return
	if cam.unproject_position(_stall + Vector3(0, 0.4, 0)).distance_to(screen) < 56:
		actor.face(_stall)
		rt.ui.open_stall()
	elif cam.unproject_position(_house + Vector3(0, 1.0, 0.6)).distance_to(screen) < 80:
		actor.face(_door)
		enter_farmhouse()
	elif cam.unproject_position(_mine + Vector3(0, 0.8, 0)).distance_to(screen) < 60:
		rt.ui.toast("The mine opens soon")

## Facility marks (STATE-ICONS) show over the stall; finger cards appear when you walk up (LOCK-07 / LOCK-17).
## Tapping the card is tapping the facility, so it reuses p0_tap's own hit points.
func _tags(v: Dictionary) -> void:
	var stall_top := cam.unproject_position(_stall + Vector3(0, 1.05, 0))
	var request := -1
	for r in v.get("stall", {}).get("board", {}).get("requests", []):
		if str(r.status) == "accepted" and int(r.have) >= int(r.qty): request = UiStatusBadge.State.DELIVERABLE
		elif str(r.status) == "open" and request < 0: request = UiStatusBadge.State.REQUEST
	rt.ui.badge("stall", maxi(request, 0), stall_top, request >= 0)
	rt.ui.tag("stall", "Tap to shop", stall_top - Vector2(0, rt.ui.badge_height("stall")),
		actor.position.distance_to(_stall) < 3.2, cam.unproject_position(_stall + Vector3(0, 0.4, 0)))
	# The farmhouse carries no state badge (不知火舞 on SGODOT-221): the stove's state belongs to the stove inside,
	# and Today already names the dish and its time. Tapping it goes in (the door card is gone; Rest is the bench,
	# SGODOT-224).
	rt.ui.tag("home", "Farmhouse · Tap to go in", cam.unproject_position(_house + Vector3(0, 2.6, 0.4)),
		actor.position.distance_to(_house) < 4.2, cam.unproject_position(_house + Vector3(0, 1.0, 0.6)))

func _teaching(v: Dictionary) -> void:
	if rt.ui.has_modal(): return
	var firsts: Array = v.get("firsts", [])
	if not firsts.any(func(f): return str(f).begins_with("harvest:")) and not v.get("plots", []).any(func(p): return str(p.state) in ["sown", "growing", "ready"]):
		rt.ui.teach("sow", "Pick a seed, walk up to a bed and press Sow. Hold to keep sowing.")

func p0_anchor() -> Vector2:
	if not _front.is_empty():
		return cam.unproject_position(bp.cell_to_world(_front_cell) + Vector3(0, 0.7, 0))
	return cam.unproject_position(actor.position + Vector3(0, 2.0, 0))

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"yaw": _dev_yaw = float(step[1])
		"goto":
			actor.teleport(Vector3(float(step[1]), 0, float(step[2])))
			_focus = actor.position
		"gocell":
			actor.teleport(bp.cell_to_world(Vector2i(int(step[1]), int(step[2]))))
			_focus = actor.position
		"face":
			actor.face(actor.position + Vector3(float(step[1]), 0, float(step[2])))
		"farmhouse": enter_farmhouse()
		"democrops":
			# Visual check only: every P0 crop at every stage across the first rows (no server state).
			var fake := {}
			var codes := P0Garden.CROP_CODES.values()
			var now := Time.get_ticks_msec()
			for i in codes.size():
				for stage in 3:
					var id := stage * P0Garden.COLUMNS + i if i < P0Garden.COLUMNS else (stage + 3) * P0Garden.COLUMNS + i - P0Garden.COLUMNS
					if id >= P0Garden.plot_count(): continue
					var span := 3600000
					var started := now - int(span * [0.2, 0.55, 1.2][stage])
					fake[P0Garden.cell_id(P0Garden.cell_of(id))] = {"state": "growing", "crop": codes[i], "watered_at": started, "ready_at": started + span}
			crops.sync(fake, now)
			_plot_sig = "frozen"
			_sync_t = 9999.0
		"home": rt.ui.open_home_card()
		"spot": p0_show_spot(step[1])
		_: return false
	return true

func p0_until(name: String) -> bool:
	match name:
		"idle": return not actor.busy()
	return false
