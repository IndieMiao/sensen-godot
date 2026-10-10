class_name P0FarmFacilities
extends Node
## P1 facilities on the homestead (q(59) §1.4–1.5, SGODOT-241): sprinklers standing on plots, Build and Move through
## the shared placement mode (P0Ui.begin_placement), the sprinkler's status card and the Coverage Overlay.
## One child node of the farm, like P0FarmMaterials: p0_farm.gd keeps one-line hooks. Facts come from the server view
## (plots[].covered / facility, facilities[].covers); the preview judges a spot with the same rules the place command
## checks (an empty plot of the homestead's, ring8 cover), so a Build the bar allows is one the server accepts.
## Placeholder art (a post and a head of simple meshes) until the modelled sprinkler (q(59) §4: 美术总监).

const TAP_PX := 40.0            # a tap this close to a sprinkler's head opens its card
const HEAD := Vector3(0, 0.55, 0)
const SNAP_PX := 70.0           # a finger this close to a bed's centre on screen points at that bed
const COVER_TINT := Color(0.55, 0.78, 0.95, 0.55)   # Coverage: light blue (q(59) §1.5)
const BAD_TINT := Color(0.86, 0.36, 0.30, 0.65)

var farm: Node3D                # p0_farm.gd: bp, cam, actor
var rt: P0Runtime
var _art := {}                  # facility id → Node3D
var _sig := ""
## Placement in progress: {recipe, facility (Move), plot (the spot shown), ok}; empty when not placing.
var placing := {}
var _preview: Node3D
var _cells: Array = []          # preview / highlight squares, reused
var _overlay: Array = []        # Coverage Overlay outlines, reused
var _highlight := -1            # a tapped sprinkler: its covered plots show until the card closes
var _finger := Vector2.INF      # placement: where the finger holds (the farm's edge pan), INF when lifted

func setup(farm_node: Node3D) -> P0FarmFacilities:
	farm = farm_node
	name = "FarmFacilities"
	return self

func _ready() -> void:
	rt = P0Runtime.ensure()
	rt.ui.placement_point.connect(_on_point)
	rt.ui.placement_done.connect(_on_done)
	rt.ui.placement_requested.connect(begin_build)
	rt.ui.placement_pan.connect(_on_pan)

func _exit_tree() -> void:
	if rt == null: return
	for s in [[rt.ui.placement_point, _on_point], [rt.ui.placement_done, _on_done], [rt.ui.placement_requested, begin_build],
			[rt.ui.placement_pan, _on_pan]]:
		if (s[0] as Signal).is_connected(s[1]): (s[0] as Signal).disconnect(s[1])
	if not placing.is_empty(): rt.ui.end_placement()

# ---------------------------------------------------------------- the view → art
func frame(v: Dictionary, dt := 0.0) -> void:
	_edge_pan(v, dt)
	var list: Array = v.get("facilities", [])
	var sig := str(list)
	if sig != _sig:
		_sig = sig
		_sync_art(list)
	_draw_overlay(v)

func _sync_art(list: Array) -> void:
	var keep := {}
	for f in list:
		var id := int(f.get("id", 0))
		keep[id] = true
		var node: Node3D = _art.get(id)
		if node == null:
			node = _sprinkler_art()
			farm.add_child(node)
			_art[id] = node
		node.position = _bed_top(int(f.get("plot", 0)))
	for id in _art.keys():
		if not keep.has(id):
			(_art[id] as Node3D).queue_free()
			_art.erase(id)

## Placeholder sprinkler: a grey post with a blue head (simple meshes, no new asset).
static func _sprinkler_art() -> Node3D:
	var root := Node3D.new()
	root.name = "Sprinkler"
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.05
	pm.height = 0.45
	post.mesh = pm
	post.position = Vector3(0, 0.225, 0)
	post.material_override = _mat(Color(0.55, 0.57, 0.6))
	root.add_child(post)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.09
	hm.height = 0.12
	head.mesh = hm
	head.position = HEAD
	head.material_override = _mat(Color(0.32, 0.58, 0.86))
	root.add_child(head)
	return root

static func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _bed_top(plot: int) -> Vector3:
	return farm.bp.cell_to_world(P0Garden.cell_of(plot)) + Vector3(0, P0Garden.BED_H, 0)

# ---------------------------------------------------------------- rules shared with the place command
static func cover_of(view: Dictionary, plot: int) -> Array:
	var at := P0Garden.grid_of(plot)
	var out: Array = []
	for id in P0Garden.plot_count(view):
		var g := P0Garden.grid_of(id)
		if id != plot and absi(g.x - at.x) <= 1 and absi(g.y - at.y) <= 1: out.append(id)
	return out

## "" when a facility may stand on `plot` (the server's spot rules), else the bar's reason (q(59) §5).
static func spot_reason(view: Dictionary, plot: int, moving := -1) -> String:
	if plot < 0 or plot >= P0Garden.plot_count(view): return "Outside your fields"
	for p in view.get("plots", []):
		if int(p.get("id", -1)) != plot: continue
		var f = p.get("facility", null)
		if f != null and int(f) != moving: return "Plot occupied"
		if p.get("crop", null) != null or str(p.get("state", "")) in ["sown", "growing", "ready"]: return "Plot occupied"
		return ""
	return "Outside your fields"

static func caption(view: Dictionary, plot: int) -> String:
	var n := cover_of(view, plot).size() if plot >= 0 and plot < P0Garden.plot_count(view) else 0
	return "Coverage preview · %d plot%s" % [n, "" if n == 1 else "s"]

# ---------------------------------------------------------------- placement
## A Facilities card's Build (P0Ui.placement_requested): placement mode on the nearest empty plot.
func begin_build(recipe: String) -> void:
	_begin({"recipe": recipe, "facility": -1, "confirm": "Build"})

## The status card's Move: the same mode, the sprinkler's own plot excluded from "occupied".
func begin_move(facility: int) -> void:
	_begin({"recipe": "", "facility": facility, "confirm": "Move"})

func _begin(p: Dictionary) -> void:
	var v := rt.session.view
	placing = p
	placing.plot = nearest_spot(v, farm.actor.position, int(p.facility))
	_preview = _sprinkler_art()
	_preview.name = "PlacementPreview"
	farm.add_child(_preview)
	rt.ui.begin_placement({"confirm": p.confirm})
	if int(placing.plot) >= 0: farm.placement_camera_begin(_bed_top(int(placing.plot)))
	else: farm.placement_camera_begin(farm.actor.position)
	_show_spot(v, int(placing.plot))

## The empty plot nearest the player (q(59) §4: the preview starts there); -1 when there is none.
func nearest_spot(v: Dictionary, at: Vector3, moving := -1) -> int:
	var best := -1
	var best_d := INF
	for id in P0Garden.plot_count(v):
		if spot_reason(v, id, moving) != "": continue
		var d: float = (farm.bp as FarmBlueprint).cell_to_world(P0Garden.cell_of(id)).distance_to(at)
		if d < best_d:
			best_d = d
			best = id
	return best

func _on_point(screen: Vector2, phase: String) -> void:
	if placing.is_empty(): return
	_finger = Vector2.INF if phase == "release" else screen
	if rt.ui.placement_bar_rect().has_point(screen): return
	_snap(screen)

func _snap(screen: Vector2) -> void:
	var v := rt.session.view
	var id := plot_at_screen(v, screen)
	if id == int(placing.plot): return
	placing.plot = id
	_show_spot(v, id)

## The bed under (or nearest within SNAP_PX of) a screen point; -1 off the field.
func plot_at_screen(v: Dictionary, screen: Vector2) -> int:
	var best := -1
	var best_d := SNAP_PX
	for id in P0Garden.plot_count(v):
		var d: float = (farm.cam as Camera3D).unproject_position(_bed_top(id)).distance_to(screen)
		if d < best_d:
			best_d = d
			best = id
	return best

## Two fingers moved the picture: the camera follows them, in the yard.
func _on_pan(px: Vector2, at: Vector2) -> void:
	if not placing.is_empty(): farm.placement_drag(px, at)

## A finger held at a screen edge pans the camera (the farm's placement_edge); the preview keeps snapping to the bed
## under the finger as the ground moves under it.
func _edge_pan(_v: Dictionary, dt: float) -> void:
	if placing.is_empty(): return
	if farm.placement_edge(_finger, dt): _snap(_finger)

func _show_spot(v: Dictionary, id: int) -> void:
	var reason := spot_reason(v, id, int(placing.facility))
	placing.ok = reason == ""
	_preview.visible = id >= 0
	if id >= 0: _preview.position = _bed_top(id)
	_paint([id] if id >= 0 else [], cover_of(v, id) if reason == "" else [], reason != "")
	rt.ui.set_placement({"caption": caption(v, id) if reason == "" else "", "reason": reason})

func _on_done(ok: bool) -> void:
	if placing.is_empty(): return
	var p := placing
	_end()
	if not ok or not bool(p.get("ok", false)): return
	if int(p.facility) >= 0: rt.session.send({"type": "move_facility", "facility": int(p.facility), "plot": int(p.plot), "space": "home"})
	else: rt.session.send({"type": "place", "recipe": str(p.recipe), "plot": int(p.plot), "space": "home"})

func _end() -> void:
	placing = {}
	_finger = Vector2.INF
	farm.placement_camera_end()
	if is_instance_valid(_preview): _preview.queue_free()
	_preview = null
	_paint([], [], false)
	rt.ui.end_placement()

# ---------------------------------------------------------------- squares on beds
## centre: the spot's bed (red when bad); cover: light blue beds round it.
func _paint(centre: Array, cover: Array, bad: bool) -> void:
	var want := centre.size() + cover.size()
	while _cells.size() < want:
		var q := _square()
		farm.add_child(q)
		_cells.append(q)
	var i := 0
	for id in centre:
		_place_square(_cells[i], id, BAD_TINT if bad else COVER_TINT.lightened(0.3))
		i += 1
	for id in cover:
		_place_square(_cells[i], id, COVER_TINT)
		i += 1
	for k in range(i, _cells.size()): (_cells[k] as MeshInstance3D).visible = false

func _place_square(q: MeshInstance3D, id: int, tint: Color) -> void:
	q.visible = true
	q.position = _bed_top(id) + Vector3(0, 0.014, 0)
	(q.material_override as StandardMaterial3D).albedo_color = tint

static func _square() -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var m := PlaneMesh.new()
	m.size = Vector2(0.9, 0.9)
	q.mesh = m
	q.material_override = _mat(COVER_TINT, true)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q

# ---------------------------------------------------------------- Coverage Overlay (Farming Lv6, §1.5)
## Standing in the field in Farming: beds a sprinkler waters wear a light blue ring; a tapped sprinkler's beds while
## its card shows. Placement draws its own preview instead.
func _draw_overlay(v: Dictionary) -> void:
	var ids: Array = []
	if placing.is_empty():
		if _highlight >= 0 and rt.ui.modal_kind == "facility":
			for f in v.get("facilities", []):
				if int(f.get("id", 0)) == _highlight: ids = f.get("covers", [])
		elif _near_field(v):
			for p in v.get("plots", []): if p.get("covered", false): ids.append(int(p.id))
	while _overlay.size() < ids.size():
		var o := _ring()
		farm.add_child(o)
		_overlay.append(o)
	for k in _overlay.size():
		var o: MeshInstance3D = _overlay[k]
		o.visible = k < ids.size()
		if o.visible: o.position = _bed_top(int(ids[k])) + Vector3(0, 0.016, 0)
	if _highlight >= 0 and rt.ui.modal_kind != "facility": _highlight = -1

## In Farming and on a bed or within a step of one (q(59) §1.5: standing in the field).
func _near_field(v: Dictionary) -> bool:
	if rt.ui.bar_mode != "farm" or rt.ui.has_modal(): return false
	if P0Garden.on_bed(farm.bp, farm.actor.position, v): return true   # the beds the view has (亚瑟 on #217)
	for id in P0Garden.plot_count(v):
		if (farm.bp as FarmBlueprint).cell_to_world(P0Garden.cell_of(id)).distance_to((farm.actor as Node3D).position) < 1.2: return true
	return false

static func _ring() -> MeshInstance3D:
	var r := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.40
	t.outer_radius = 0.46
	t.rings = 4
	t.ring_segments = 24
	r.mesh = t
	r.scale = Vector3(1, 0.05, 1)
	r.material_override = _mat(Color(0.55, 0.78, 0.95), true)
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return r

# ---------------------------------------------------------------- taps
## A tap on a sprinkler's head: its status card (`Sprinkler · Waters 8 plots`, Move) and its beds highlighted.
func tap(screen: Vector2) -> bool:
	var v := rt.session.view
	for f in v.get("facilities", []):
		if farm.cam.unproject_position(_bed_top(int(f.get("plot", 0))) + HEAD).distance_to(screen) > TAP_PX: continue
		open_card(f)
		return true
	return false

func open_card(f: Dictionary) -> void:
	_highlight = int(f.get("id", 0))
	var n := (f.get("covers", []) as Array).size()
	rt.ui.open_facility_card({
		"title": "Sprinkler", "lead": "Waters %d plot%s" % [n, "" if n == 1 else "s"],
		"icon": P0Logic.icon("facility_sprinkler"), "button": "Move"},
		func(): begin_move(int(f.get("id", 0))))
