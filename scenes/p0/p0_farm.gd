extends Node3D
## P0 homestead: the old polished farm presentation (cottage, well, seed box, garden dressing, thick
## soil beds, procedural crops, rig and labour clips, 43° ortho camera) driven by the P0 server view
## and the new UI flow (joystick, main action, quick bar, cards) from P0Runtime.
## Ponds are on the map; the kitchen is inside the farmhouse (P0Room, SGODOT-226); nothing here is greybox.

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const FarmProps = preload("res://modules/farm/farm_props.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const FarmArt = preload("res://modules/farm/farm_art.gd")
const MineArt = preload("res://modules/mining/mine_art.gd")
const GardenScenery = preload("res://scenes/p0/p0_garden_scenery.gd")
const Fence = preload("res://scenes/p0/p0_fence.gd")
const HomePanel = preload("res://scenes/p0/home/p0_home_panel.gd")
const SIGN_BADGE := Vector3(0, 1.15, 0)   # the Homestead sign's mark, just above the board
const SIGN_NEAR := 2.6                    # metres: the sign's and the plaque's finger cards show this close
const FARMHOUSE := "res://scenes/p0/rooms/p0_farmhouse.tscn"
## Walking into the doorway goes in (mirror of a room's door): inside the walkway cell in front of the door
## (DOOR_HALF either side; the camera-relative joystick drifts sideways), pushing towards the house, after
## having been DOOR_ARM_M away (so stepping out of the farmhouse does not walk straight back in).
const DOOR_HALF := Vector2(0.6, 0.4)
const DOOR_ARM_M := 1.5

const STYLE := "cottage"          # the orange-roof cottage of the polished farm
var PLACE := P0City.chip("Homestead")
const BENCH_TAP_PX := 44.0   # a 44 px touch target around the bench seat (engineering default)
const BENCH_NEAR_M := 2.6    # the bench's finger card shows within this distance (stall 3.2, house 4.2)
const LABOUR_CLIP := {"till": "till", "sow": "sow", "water": "water", "harvest": "harvest"}
const MAILBOX_DIR := "res://assets/props/mailbox_placeholder/"
const MAILBOX_SCALE := 0.65
const MAILBOX_MARK := Vector3(0, 1.45, 0)   # its icon button, just over the 1.16 m post box
const MAILBOX_HIT := Vector3(0, 0.6, 0)     # its own tap point, the box's middle (use_mailbox is the slot)
const MAILBOX_TAP_PX := 40.0

@onready var cam: Camera3D = $Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var world_env: WorldEnvironment = $WorldEnvironment

var rt: P0Runtime
var bp: FarmBlueprint
var grid: BlueprintGrid
var actor: P0Actor
var crops: CropField
var _saved_env: Environment   # handed over while a room (the farmhouse) is on top, see suspend()
var beds: MultiMeshInstance3D
var _hi: MeshInstance3D
var _house := Vector3.ZERO
var _stall := Vector3.ZERO   # the Homestead Stall (unattended, p(6)); the seed box stands in until its model
var _mine := Vector3.ZERO
var _bench := Vector3.ZERO   # the rest bench by the farmhouse (FARM-7, q(30)): Basic Room's bench.glb
var _materials: P0FarmMaterials   # SGODOT-231: mine mouth, gathering spots and the workbench
var _facilities: P0FarmFacilities   # P1 SGODOT-241: sprinklers, placement mode, Coverage
var _card := ""   # LOCK-07 v2: the one facility whose name strip is open this frame (P0Garden.pick_card)
var _strip_side := UiWorldNameBar.Dir.RIGHT   # the side the strip opens to: the way the character faces on screen
var _focus := Vector3.ZERO
var _cam_follow := P0Follow.new()
var _opening := false   # the opening shot waits for the HUD's area to keep the farmhouse mark clear of it (_fit_opening)
var _zoom := 1.0
const ElasticZoom = preload("res://modules/p0/p0_elastic_zoom.gd")
var _pinch = ElasticZoom.new(0.8, 1.4)   # rubber band past 0.8 / 1.4
var _zoom_at := Vector2.INF            # the last pinch centre (screen)
var _dev_yaw := -1.0
var _hold_until := 0.0
var _front: Dictionary = {}
var _row: Array = []   # plots a Row Hoe sows from _front (P0Logic.row_plots)
var _front_cell := Vector2i(-1, -1)
var _plot_sig := ""
var _sync_t := 0.0
var _fence: Node3D   # p0_fence.gd: front stretch always, the ring from Homestead Lv3
var _sign := Vector3.ZERO   # Homestead sign right of the farmhouse door (WorldBadges · Farm 1135:79267): HOME-1
var _plaque := Vector3.ZERO   # Upgrade Plaque left of the door (1510:97492), shown from the first upgrade: PLAQUE-READ
var _plaque_node: Node3D
var _mailbox := Vector3.ZERO   # the farmhouse Mailbox (§12.5.2; SGODOT-234 C): opens the Inbox, as the bell does
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

## Android Back: the UI's top layer (a dragged slot, radial, a card or drawer) closes first, one per press; with nothing
## open, back to the map: AppRouter pops a farm stacked on the map, a farm that is the root scene leaves by itself
## (int5 hand test 012–013 / 023–024, int5b test 2; rooms do the same, p0_room).
func is_back_navigation_locked() -> bool:
	return rt != null and (rt.ui.close_top_layer() or rt.root_back())

## AppRouter stacking: the map below us hands back its camera and environment on resume. Going under a room we hand
## ours over as well: the viewport uses the first WorldEnvironment in the tree, so the farmhouse otherwise lit with the
## farm's cool ambient and green backdrop (SGODOT-249; farm.gd and P0Room.suspend() do the same). The canvas layers
## go too: FarmBackground (layer −1) is the farm's backdrop only under its BG_CANVAS environment; under the room's
## colour background it would cover the room, and hiding the farm does not hide a CanvasLayer. They leave the tree
## while we are suspended: hidden is not enough — a hidden CanvasLayer at −1 still took part in the dressing room's
## canvas background (BG_CANVAS, max layer −1), which then drew its backdrop over its 3D character (SGODOT-256 ⑥).
var _held_layers: Array = []   # [CanvasLayer, its index], out of the tree while suspended

func suspend() -> void:
	set_process(false)
	visible = false
	if world_env.environment: _saved_env = world_env.environment
	world_env.environment = null
	if _held_layers.is_empty():
		for c in get_children():
			if c is CanvasLayer: _held_layers.append([c, c.get_index()])
		for held in _held_layers: remove_child(held[0])

## Freed while suspended (the root swapped away under the dressing room): the layers out of the tree go with us.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for held in _held_layers:
			if is_instance_valid(held[0]): (held[0] as Node).free()
		_held_layers.clear()

func resume() -> void:
	get_viewport().transparent_bg = false
	if _saved_env: world_env.environment = _saved_env
	for held in _held_layers:   # back in their places, in the order they were taken
		add_child(held[0])
		move_child(held[0], mini(int(held[1]), get_child_count() - 1))
	_held_layers.clear()
	visible = true
	set_process(true)
	cam.make_current()
	if rt:
		rt.attach(self)
		rt.ui.set_mode("farm")   # back from the mine (SGODOT-231): seeds on the bar, the farm's chip
		rt.ui.set_place(PLACE)   # back from the farmhouse or the mine
	if _inside:
		# Out through the farmhouse door: stand on the doorstep facing the field.
		_inside = false
		actor.teleport(_door)
		actor.face(_door + Vector3(0, 0, 1))
		_opening = false
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
	# The bench is two cells wide: its centre sits half a cell right of its anchor cell, facing the field (+z).
	_bench = bp.cell_to_world(bp.anchor("bench")) + Vector3(bp.cell_m * 0.5, 0, 0)
	props.add_child(_bench_prop(_bench))
	_mine = bp.cell_to_world(bp.anchor("mine")) + Vector3(-0.3, 0, 0.3)
	var mine := MineArt.entrance()
	mine.position = _mine
	mine.rotation.y = PI * 0.15
	props.add_child(mine)
	_materials = P0FarmMaterials.new().setup(self, _mine, mine)
	add_child(_materials)
	var scenery := GardenScenery.new()
	add_child(scenery)
	scenery.build(bp, STYLE)
	P0Garden.block_points(bp, scenery.rock_points)   # rocks collide; crops and bushes don't
	_fence = Fence.new()
	add_child(_fence)
	_fence.build(bp)
	P0Garden.block_points(bp, P0Garden.fence_block_points(bp))   # the yard fence in front of the house collides
	# The Homestead sign: its own tap target beside the door, not the door (LOCK-11 / LOCK-07).
	_sign = P0Garden.sign_point(bp)
	props.add_child(FarmArt.instance("sign", _sign, 0.8))
	P0Garden.block_points(bp, [_sign])
	# The Upgrade Plaque: art placeholder (a smaller sign.glb) until its model lands. Not solid: it appears only after
	# the first upgrade, and an invisible block before then would stop the player for no visible reason.
	_plaque = P0Garden.plaque_point(bp)
	_plaque_node = FarmArt.instance("sign", _plaque, 0.6)
	_plaque_node.rotation.y = 0.35
	_plaque_node.visible = false
	props.add_child(_plaque_node)
	_mailbox = P0Garden.mailbox_point(bp)
	props.add_child(_mailbox_prop(_mailbox))
	P0Garden.block_points(bp, [_mailbox])
	grid = BlueprintGrid.new(bp)
	# One thick soil bed per plot (plot.glb), tinted per state (watered beds read darker).
	var xfs: Array = []
	var tints := PackedColorArray()
	for id in P0Garden.plot_count():
		xfs.append(Transform3D(Basis.IDENTITY, bp.cell_to_world(P0Garden.cell_of(id))))
		tints.append(Color.WHITE)
	beds = FarmArt.batch("plot", xfs, true, tints)
	beds.multimesh.visible_instance_count = P0Garden.P0_PLOTS   # all 40 laid out; the view's garden.plots shows them
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
	# The beds the homestead has (garden.plots, 30 or 40): read from the session's last view, never current() — that
	# copies the whole view, and this runs every frame (亚瑟 on #215; the map's heat in 260 was the same copy).
	actor.ground_height = func(p: Vector3) -> float:
		return P0Garden.BED_H if P0Garden.on_bed(bp, p, rt.session.view if rt != null and rt.session != null else null) else 0.0
	# Opening shot like the polished farm: cottage on top, beds below, the player at the front edge.
	_focus = actor.position.lerp(_house, 0.42)
	_cam_follow.hold()   # the opening shot stays until the player first moves
	_opening = true
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
	cam.size = FarmCamera.close_view_size(vp) * FarmCamera.P0_VIEW_K / _zoom
	FarmCamera.place(cam, _focus + Vector3.UP * 0.7)
	if _dev_yaw >= 0.0:   # P0_SHOT yaw comparison only (style doc asks 35–45°, the old farm uses 14.5°)
		var c := _focus + Vector3.UP * 0.7
		var pitch := deg_to_rad(FarmCamera.PITCH_DEG)
		var yaw := deg_to_rad(_dev_yaw)
		cam.position = c + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * FarmCamera.DISTANCE
		cam.look_at(c, Vector3.UP)
	FarmCamera.fit_ground_depth(cam)

## The opening shot keeps the farmhouse's mark clear of the HUD (李元芳 int12-pre on 256): framed from the walk-in point
## alone, a phone's status-bar inset brought the HUD down over the roof, and the mark — hidden there, as every mark
## outside the HUD's marker area — only showed after a few steps. Once the HUD has laid out, the picture moves down just
## enough for the mark to sit MARK_ROOM inside that area as it is with the HUD up (P0Ui.open_marker_area: a panel open
## on arrival changes nothing when it closes, 后裔 on #166), never bringing the player's feet within FEET_ROOM of the
## quick bar. Once: a later step, pinch or Show leaves the framing alone.
const HOME_MARK := Vector3(0, 2.6, 0.4)   # the farmhouse prompt's anchor (world_prompt "home")
const MARK_ROOM := 24.0   # half the near icon disc (28 × 1.1) and the 8 px edge gap prompts keep
const FEET_ROOM := 16.0
func _fit_opening() -> void:
	if not _opening: return
	if not _cam_follow.held:   # walking already: the safe box has the camera
		_opening = false
		return
	if rt == null or not rt.ui.is_node_ready(): return
	var area := rt.ui.open_marker_area()
	if not area.has_area(): return   # the HUD has not laid out yet
	_opening = false
	_place_camera()
	_focus = opening_focus(cam, _focus, _house + HOME_MARK, actor.position, area)
	_place_camera()

## `focus` moved along the ground, away from the camera, by as much as the mark needs to sit MARK_ROOM below the area's
## top — at most what keeps `feet` FEET_ROOM above its bottom (opening_shift). `cam` is placed at `focus` already.
static func opening_focus(cam: Camera3D, focus: Vector3, mark: Vector3, feet: Vector3, area: Rect2) -> Vector3:
	var dy := opening_shift(cam.unproject_position(mark).y, cam.unproject_position(feet).y, area)
	if dy <= 0.0: return focus
	var px := cam.get_viewport().get_visible_rect().size.x / cam.size   # px per metre (KEEP_WIDTH)
	var ahead := -cam.global_basis.z
	ahead.y = 0.0
	return focus + ahead.normalized() * dy / (px * sin(deg_to_rad(FarmCamera.PITCH_DEG)))

## How far (px) the opening picture moves down: the mark's shortfall below `area`'s top + MARK_ROOM, capped by the room
## the feet have above its bottom − FEET_ROOM; 0 when the mark is clear already.
static func opening_shift(mark_y: float, feet_y: float, area: Rect2) -> float:
	var need := area.position.y + MARK_ROOM - mark_y
	var room := area.end.y - FEET_ROOM - feet_y
	return clampf(need, 0.0, maxf(0.0, room))

func _follow(dt: float) -> void:
	_fit_opening()
	_focus = _cam_follow.step(cam, _focus, actor.position, actor.mover.is_moving(), dt)
	if _pinch.step(dt): _set_zoom(_pinch.value)   # springing back from past a limit, about the same point
	else: _place_camera()

## Zoom about the last pinch centre: the ground point under the fingers stays put (ScenePan's focal pinch).
func _set_zoom(value: float) -> void:
	_zoom = value
	if cam == null or not is_inside_tree(): return   # not placed yet: the next frame frames it
	var before = ElasticZoom.ground_at(cam, _zoom_at, _focus.y)
	_place_camera()
	var d := ElasticZoom.shift(before, ElasticZoom.ground_at(cam, _zoom_at, _focus.y))
	if d != Vector3.ZERO:
		_focus += d
		_place_camera()

func p0_zoom(f: float, at := Vector2.INF) -> void:
	_opening = false
	_zoom_at = at
	_pinch.pinch(f)
	_cam_follow.hold()   # the pinched framing stays until the player walks (the safe box takes over then)
	_set_zoom(_pinch.value)
func p0_zoom_end() -> void: _pinch.release()
func p0_recenter() -> void:
	_opening = false
	_focus = actor.position
	_cam_follow.held = false

func p0_show_spot(where: String) -> void:
	var at := _bench if where == "bench" else (_house if where in ["stove", "home"] else actor.position)
	if where == "stall": at = _stall
	elif where == "plots": at = _plots_center()
	elif _materials.spot_at(where) != null: at = _materials.spot_at(where)   # SGODOT-231: spot_*, mine, workbench
	_opening = false
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
	if v != Vector2.ZERO and _materials: _materials.cancel_walk()   # a tapped walk to the mine mouth stops (266)

func p0_frame(v: Dictionary, dt: float) -> void:
	actor.step(dt)
	_door_check()
	_follow(dt)
	rt.ui.player_screen = cam.unproject_position(actor.position + Vector3(0, 0.9, 0))   # the radial fans out from here
	_sync_plots(v, dt)
	_fence.sync(v)
	if _facilities == null and bp != null and cam != null and actor != null:
		_facilities = P0FarmFacilities.new().setup(self)
		add_child(_facilities)
	_facilities.frame(v)
	if not _facilities.placing.is_empty(): return   # placement mode: no bed, key, card or prompt (q(23))
	_pick_front(v)
	# The key is Farming here even at the mine mouth: the mouth is tapped like any facility (SGODOT-266, user on 263 ③).
	rt.ui.set_action(P0Logic.main_action(v, _front, rt.ui.selected_seed, _row))
	_card = P0Garden.pick_card(_card_candidates(), actor.position, _card)
	# The mouth's EntryCard holds the farm's one card while it is up (LOCK-07: one at a time; 亚瑟 on #190): a gathering
	# spot or the bench nearby keeps its button, never opens its strip beside it.
	if _materials.card_wanted(): _card = "mine"
	_materials.frame(v, _card)
	_hold_repeat()
	_prompts(v)
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
		if id >= 0 and id < P0Garden.plot_count(v): beds.multimesh.set_instance_color(id, P0Garden.bed_tint(str(p.get("state", ""))))
	# P1 (q(59) §1.1): beds 30–39 stand from Homestead Lv3 (the view's garden.plots); before that the batch draws 30.
	beds.multimesh.visible_instance_count = P0Garden.plot_count(v)

## Middle of the plot beds, for camera-only "Show" from the Today panel and NeedSource (LOCK-08).
func _plots_center() -> Vector3:
	var sum := Vector3.ZERO
	var n := P0Garden.plot_count(rt.session.view if rt != null and rt.session != null else null)
	for id in n: sum += bp.cell_to_world(P0Garden.cell_of(id))
	return sum / maxf(1.0, float(n))

## The bed the player faces from the walkway: nearest bed ahead within reach.
func _pick_front(v: Dictionary) -> void:
	var best := -1
	var best_score := -INF
	var f := actor.facing()
	var taken := {}   # P1: a plot with a facility is no bed to work (the key shows no farming verb there)
	for p in v.get("plots", []): if p.get("facility", null) != null: taken[int(p.id)] = true
	for id in P0Garden.plot_count(v):
		if taken.has(id): continue
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
	if _materials.act(cmd): return
	var type := str(cmd.get("type", ""))
	var target := int(cmd.get("plot", (cmd.get("plots", [-1]) as Array)[0] if cmd.has("plots") else -1))
	if LABOUR_CLIP.has(type) and target >= 0:
		actor.labour(LABOUR_CLIP[type], bp.cell_to_world(P0Garden.cell_of(target)))
		_hold_until = Time.get_ticks_msec() + P0Actor.LABOUR_S * 1000.0
	rt.session.send(cmd)

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
	var card := str(rt.ui.tapped_card)
	# The mine's EntryCard sits over the scene (passive, SGODOT-231): a tap on it is its button's; any other tap folds
	# it and goes on (SGODOT-266).
	if card == "" and _materials.tap_entry(screen): return
	if card != "": _materials.close_card()
	if _tap_card(card): return
	if _facilities != null and _facilities.tap(screen): return   # P1: a sprinkler's status card (SGODOT-241)
	if _sign_hit(screen):
		actor.face(_sign)
		HomePanel.open(rt.ui)
	elif _plaque_node.visible and cam.unproject_position(_plaque + Vector3(0, 0.35, 0)).distance_to(screen) < 34:
		actor.face(_plaque)
		HomePanel.plaque(rt.ui)
	# The Mailbox and the bench stand beside the house: before the stall and the house, so the house's wider radius
	# doesn't take them.
	elif cam.unproject_position(_mailbox + MAILBOX_HIT).distance_to(screen) < MAILBOX_TAP_PX:
		actor.face(_mailbox)
		rt.ui.open_inbox()
	elif cam.unproject_position(_bench + Vector3(0, 0.35, 0)).distance_to(screen) < BENCH_TAP_PX:
		actor.face(_bench)
		rt.ui.open_rest_card()
	elif cam.unproject_position(_stall + Vector3(0, 0.4, 0)).distance_to(screen) < 56:
		actor.face(_stall)
		rt.ui.open_stall()
	elif cam.unproject_position(_house + Vector3(0, 1.0, 0.6)).distance_to(screen) < 80:
		actor.face(_door)
		enter_farmhouse()
	elif _materials.tap(screen): pass   # SGODOT-231: mine mouth sheet, gathering spots, workbench (last: smallest targets)

## A finger card's tap goes to its own facility by id, never through the point test: the point of one facility can
## sit under another's mark (the farmhouse card's point under the sign's caption, PR #21 review).
func _tap_card(id: String) -> bool:
	match id:
		"sign":
			actor.face(_sign)
			HomePanel.open(rt.ui)
		"plaque":
			actor.face(_plaque)
			HomePanel.plaque(rt.ui)
		"stall":
			actor.face(_stall)
			rt.ui.open_stall()
		"home":
			actor.face(_door)
			enter_farmhouse()
		"bench":
			actor.face(_bench)
			rt.ui.open_rest_card()
		"mailbox":
			actor.face(_mailbox)
			rt.ui.open_inbox()
		_:
			return _materials.tap_card(id)   # SGODOT-231: spot_* and workbench cards
	return true

## The sign itself (its icon button and strip arrive by id, _tap_card); small, so the door beside it stays the house.
## Nothing above the board: with the button hidden (beyond 8 m) that spot is not the sign's (苏烈 on #59).
func _sign_hit(screen: Vector2) -> bool:
	return cam.unproject_position(_sign + Vector3(0, 0.45, 0)).distance_to(screen) < 34

## World prompts (SGODOT-250; LOCK-07 v2 / LOCK-11 / LOCK-17 v2; q(62); WORLD-HINT-1…5): every facility within
## P0WorldPrompts.RANGE shows its icon button (a state shows from anywhere and takes the icon's place); the one nearest
## in reach (_card) opens its name strip toward the way the character faces. No "Tap to …": tapping the button, the
## strip or the object is tapping the facility (_tap_card by id). Anchors are the former finger cards' and marks'.
func _prompts(v: Dictionary) -> void:
	_strip_side = _facing_side()
	world_prompt("stall", P0WorldPrompts.stall(v, rt.ui.stall_has_new()), _stall, Vector3(0, 1.05, 0), Vector3(0, 0.4, 0))
	world_prompt("home", P0WorldPrompts.farmhouse(v), _house, HOME_MARK, Vector3(0, 1.0, 0.6))
	world_prompt("sign", P0WorldPrompts.sign(v), _sign, SIGN_BADGE, Vector3(0, 0.45, 0))
	_plaque_node.visible = not v.get("homestead", {}).get("plaque", []).is_empty()
	world_prompt("plaque", P0WorldPrompts.plaque(v), _plaque, Vector3(0, 0.85, 0), Vector3(0, 0.35, 0), _plaque_node.visible)
	world_prompt("bench", P0WorldPrompts.bench(v), _bench, Vector3(0, 0.95, 0), Vector3(0, 0.35, 0))
	world_prompt("mailbox", P0WorldPrompts.mailbox(v), _mailbox, MAILBOX_MARK, MAILBOX_HIT)

## One facility's prompt at `at` + `mark` (the former finger card's / mark's anchor): its strip when it is the open
## one, else its icon button (P0WorldPrompts.show). The button and strip forward their taps to `at` + `hit` by id.
func world_prompt(id: String, prompt: Dictionary, at: Vector3, mark: Vector3, hit: Vector3, present := true) -> void:
	var screen := cam.unproject_position(at + mark)
	var tap := cam.unproject_position(at + hit)
	var show := P0WorldPrompts.show(id, _card, P0FarmMaterials.flat(actor.position, at), prompt) \
		if present and not rt.ui.has_modal() else P0WorldPrompts.Show.NONE
	if show == P0WorldPrompts.Show.BAR:
		rt.ui.name_bar(id, prompt.icon, str(prompt.text), str(prompt.fact), screen, true, _strip_side, bool(prompt.dimmed),
			int(prompt.status), tap)
	else:
		rt.ui.world_icon(id, prompt.icon, screen, show == P0WorldPrompts.Show.ICON, false, int(prompt.status), tap,
			str(prompt.get("count", "")))

## The side a strip opens to: the character's facing on screen; facing the camera or away keeps the last side.
func _facing_side() -> UiWorldNameBar.Dir:
	var from := cam.unproject_position(actor.position)
	var dx := cam.unproject_position(actor.position + actor.facing()).x - from.x
	if absf(dx) < 6.0: return _strip_side
	return UiWorldNameBar.Dir.LEFT if dx < 0.0 else UiWorldNameBar.Dir.RIGHT

## Every facility that can open its name strip on the farm, [id, position, reach m] in a fixed order (LOCK-07 v2: one
## strip, the nearest in reach): the rest bench, and SGODOT-231's five gathering spots and the workbench.
func _card_candidates() -> Array:
	var out: Array = [["stall", _stall, 3.2], ["home", _house, 4.2], ["sign", _sign, SIGN_NEAR], ["bench", _bench, BENCH_NEAR_M],
		["mailbox", _mailbox, SIGN_NEAR]]
	if _plaque_node.visible: out.append(["plaque", _plaque, SIGN_NEAR])
	out.append_array(_materials.card_candidates())   # SGODOT-231: the five gathering spots and the workbench
	return out

## Basic Room's bench (648 tris; q(30)) with the room's shared atlas material.
func _bench_prop(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Bench"
	root.position = at
	var model := (load("res://assets/rooms/basic_room/bench.glb") as PackedScene).instantiate() as Node3D
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/rooms/basic_room/room_albedo_ao.png")
	mat.roughness = 0.8
	mat.metallic_specular = 0.28
	for m in model.find_children("*", "MeshInstance3D", true, false): (m as MeshInstance3D).material_override = mat
	root.add_child(model)
	return root

## The Mailbox placeholder (SGODOT-234 C; assets/props/mailbox_placeholder): the post office's red post box at 0.65 —
## 0.51 m wide, 1.16 m tall, one cell — with its room atlas; front (local +Z) toward the camera.
func _mailbox_prop(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Mailbox"
	root.position = at
	root.scale = Vector3.ONE * MAILBOX_SCALE
	var model := (load(MAILBOX_DIR + "red_post_box.glb") as PackedScene).instantiate() as Node3D
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(MAILBOX_DIR + "room_albedo_ao.png")
	mat.roughness = 0.9
	for m in model.find_children("*", "MeshInstance3D", true, false): (m as MeshInstance3D).material_override = mat
	root.add_child(model)
	return root

func _teaching(v: Dictionary) -> void:
	if rt.ui.has_modal(): return
	var firsts: Array = v.get("firsts", [])
	if not firsts.any(func(f): return str(f).begins_with("harvest:")) and not v.get("plots", []).any(func(p): return str(p.state) in ["sown", "growing", "ready"]):
		rt.ui.teach("sow")   # copy in P0Guide.TIPS (q(44))

func p0_anchor() -> Vector2:
	if not _front.is_empty():
		return cam.unproject_position(bp.cell_to_world(_front_cell) + Vector3(0, 0.7, 0))
	return cam.unproject_position(actor.position + Vector3(0, 2.0, 0))

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	if step[0] in ["goto", "gocell", "near"]: _opening = false   # a teleport frames itself
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
		"sign": p0_tap(cam.unproject_position(_sign + Vector3(0, 0.45, 0)))   # HOME-1 through the sign's own tap
		"plaque": p0_tap(cam.unproject_position(_plaque + Vector3(0, 0.35, 0)))   # PLAQUE-READ
		"mailbox": p0_tap(cam.unproject_position(_mailbox + MAILBOX_HIT))   # the Inbox through the Mailbox's own tap (234 C)
		"mouth": p0_tap(cam.unproject_position(_mine + Vector3(0, 1.6, 0)))   # the mine mouth's model, high on the arch (int11 ②)
		"cardtap", "cardnew":   # a real tap on the mouth's EntryCard: its main button / New run (SGODOT-266)
			var e: UiEntryCard = _materials._entry if _materials.card_open() else null
			if e != null: p0_tap((e.main_rect() if step[0] == "cardtap" else e.second_rect()).get_center() - rt.ui.root.global_position)
		"zoomto": _zoom = clampf(float(step[1]), 0.8, 1.4)   # zoomto:0.8 (widest) … 1.4 (closest)
		# P1 placement (SGODOT-241): build:<recipe> opens it as the Facilities card's Build does; placeat:<plot> moves
		# the preview as a finger on that bed would; placeok / placecancel press the bar; factap:<id> taps a sprinkler.
		"build": _facilities.begin_build(step[1] if step.size() > 1 else "craft_sprinkler")
		"placeat": rt.ui.placement_point.emit(cam.unproject_position(bp.cell_to_world(P0Garden.cell_of(int(step[1]))) + Vector3(0, P0Garden.BED_H, 0)), "drag")
		"placeok": rt.ui.placement_done.emit(true)
		"placecancel": rt.ui.placement_done.emit(false)
		"factap":
			for f in rt.session.current().get("facilities", []):
				if int(f.get("id", 0)) == int(step[1]): _facilities.open_card(f)
		"near":   # near:<id> — stand 1.2 m in front of a facility, so its name strip opens (250 review shots)
			for c in _card_candidates():
				if str(c[0]) == step[1]:
					actor.teleport((c[1] as Vector3) + Vector3(0, 0, 1.2))
					_focus = actor.position
		"tapprompt":   # tapprompt[:id] — a real tap on a shown world prompt (default: the open strip)
			var r := rt.ui.prompt_rect(step[1] if step.size() > 1 else _card)
			if r.has_area(): rt.ui._tap_at(r.get_center(), false)
		"moment":   # HOME-2 as after Lv2 → Lv3, without spending anything
			HomePanel.moment(rt.ui, P0Logic.home_moment(rt.session.current(), {"level": 3, "unlocks": ["warming_cabinet", "bag_upgrade_1"]}))
		"spot": p0_show_spot(step[1])
		_: return false
	return true

func p0_until(name: String) -> bool:
	match name:
		"idle": return not actor.busy()
		"card": return _materials.card_open()
	return false
