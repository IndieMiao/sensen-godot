class_name P0FarmFacilities
extends Node
## P1 facilities on the homestead (q(59) §1.4–1.5, SGODOT-241): sprinklers standing on plots, Build and Move through
## the shared placement mode (P0Ui.begin_placement), the sprinkler's status card and the Coverage Overlay.
## One child node of the farm, like P0FarmMaterials: p0_farm.gd keeps one-line hooks. Facts come from the server view
## (plots[].covered / facility, facilities[].covers); the preview judges a spot with the same rules the place command
## checks (an empty plot of the homestead's, ring8 cover), so a Build the bar allows is one the server accepts.
## Placeholder art (a post and a head of simple meshes) until the modelled sprinkler (q(59) §4: 美术总监).
## A greenhouse (q(118) ②; 不知火舞 on 241) is a glass roof over a 4×4 block of plots, placed by its anchor (the block's
## lowest col and row): four corner posts and a gable roof ~25% opaque, ~10% while the player stands under it; its 16
## plots wear a faint glass outline. Placeholder until 上官婉儿's model.

const TAP_PX := 40.0            # a tap this close to a sprinkler's head opens its card
const HEAD := Vector3(0, 0.55, 0)
const SNAP_PX := 70.0           # a finger this close to a bed's centre on screen points at that bed
const COVER_TINT := Color(0.55, 0.78, 0.95, 0.55)   # Coverage: light blue (q(59) §1.5; water, 284 v2 §2)
const OK_TINT := Color(UiTokens.COLOR_PRIMARY, 0.30)  # the spot underfoot when it may stand there (284 v2 §2)
const BAD_TINT := Color(UiTokens.COLOR_DANGER, 0.35)  # … when it may not
const GLASS := Color(0.80, 0.94, 0.98)            # the greenhouse's glass and its plots' outline
const ROOF_ALPHA := 0.25
const ROOF_INSIDE := 0.10
const ROOF_H := 1.45
const GREENHOUSE_TAP_PX := 90.0

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
var _roofs := {}                # greenhouse id → its roof material (the fade under it)
var _glass: Array = []          # greenhouse plots' outlines, reused

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
	_draw_greenhouses(v)

func _sync_art(list: Array) -> void:
	var keep := {}
	for f in list:
		var id := int(f.get("id", 0))
		var kind := str(f.get("kind", "sprinkler"))
		keep[id] = true
		var node: Node3D = _art.get(id)
		if node != null and str(node.get_meta("plot", -1)) != str(f.get("plot", 0)) and is_block(kind):
			node.queue_free()   # a moved greenhouse is rebuilt over its new block
			node = null
		if node == null:
			node = _greenhouse_art(f.get("covers", [])) if is_block(kind) else _sprinkler_art()
			node.set_meta("plot", int(f.get("plot", 0)))
			farm.add_child(node)
			_art[id] = node
			if is_block(kind): _roofs[id] = node.get_meta("roof")
		if not is_block(kind): node.position = _bed_top(int(f.get("plot", 0)))
	for id in _art.keys():
		if not keep.has(id):
			(_art[id] as Node3D).queue_free()
			_art.erase(id)
			_roofs.erase(id)

## Placeholder greenhouse over its plots: four corner posts and a gable glass roof (no walls: walkable from any side).
## `roof` false: the posts alone (the placement preview: seen from straight above, the glass would wash out the green /
## red squares under it).
func _greenhouse_art(plots: Array, roof := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Greenhouse"
	var r := _block_rect(plots)
	var mid := Vector3(r.get_center().x, P0Garden.BED_H, r.get_center().y)
	root.position = mid
	var post_mat := _mat(Color(0.93, 0.93, 0.90))
	for corner in [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.04
		pm.bottom_radius = 0.05
		pm.height = ROOF_H
		post.mesh = pm
		post.material_override = post_mat
		post.position = Vector3(corner.x - mid.x, ROOF_H * 0.5, corner.y - mid.z)
		root.add_child(post)
	if not roof: return root
	var roof_mat := _mat(Color(GLASS, ROOF_ALPHA), true)
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:   # two panes meeting at a ridge along x
		var pane := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(r.size.x + 0.2, r.size.y * 0.55)
		pane.mesh = plane
		pane.material_override = roof_mat
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pane.position = Vector3(0, ROOF_H + 0.22, side * r.size.y * 0.25)
		pane.rotation = Vector3(side * deg_to_rad(-22.0), 0, 0)
		root.add_child(pane)
	root.set_meta("roof", roof_mat)
	return root

## The ground rect (x, z) a block of plots covers, bed edges included.
func _block_rect(plots: Array) -> Rect2:
	var r := Rect2()
	var half := float(farm.bp.cell_m) * 0.5
	for i in plots.size():
		var c: Vector3 = (farm.bp as FarmBlueprint).cell_to_world(P0Garden.cell_of(int(plots[i])))
		var bed := Rect2(c.x - half, c.z - half, half * 2.0, half * 2.0)
		r = bed if i == 0 else r.merge(bed)
	return r

## Greenhouses each frame: the roof fades while the player stands under it; their plots wear the glass outline.
func _draw_greenhouses(v: Dictionary) -> void:
	var ids: Array = []
	for f in v.get("facilities", []):
		if not is_block(str(f.get("kind", ""))): continue
		ids.append_array(f.get("covers", []))
		var mat: StandardMaterial3D = _roofs.get(int(f.get("id", 0)))
		if mat != null:
			var p: Vector3 = (farm.actor as Node3D).position
			var inside := _block_rect(f.get("covers", [])).has_point(Vector2(p.x, p.z))
			mat.albedo_color.a = ROOF_INSIDE if inside else ROOF_ALPHA
	while _glass.size() < ids.size():
		var o := _square()   # a faint glass outline: a light wash and a glass edge (the shell's placement square)
		var m := o.material_override as ShaderMaterial
		m.set_shader_parameter("fill", Color(GLASS, 0.15))
		m.set_shader_parameter("edge", Color(GLASS, 0.6))
		m.set_shader_parameter("size_m", 0.98)
		(o.mesh as PlaneMesh).size = Vector2(0.98, 0.98)
		farm.add_child(o)
		_glass.append(o)
	for k in _glass.size():
		var o: MeshInstance3D = _glass[k]
		o.visible = k < ids.size()
		if o.visible: o.position = _bed_top(int(ids[k])) + Vector3(0, 0.008, 0)

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
## The facility a field recipe builds (content workbench.recipes[].facility).
static func kind_of(recipe: String) -> String:
	for r in P0Logic.content().get("workbench", {}).get("recipes", []):
		if str(r.get("id", "")) == recipe: return str(r.get("facility", "sprinkler"))
	return "sprinkler"

static func is_block(kind: String) -> bool:
	return str(P0Logic.content().get("facilities", {}).get("kinds", {}).get(kind, {}).get("cover", "")) == "block"

static func block_size(kind: String) -> Vector2i:
	var size: Array = P0Logic.content().get("facilities", {}).get("kinds", {}).get(kind, {}).get("size", [4, 4])
	return Vector2i(int(size[0]), int(size[1]))

static func cover_of(view: Dictionary, plot: int, kind := "sprinkler") -> Array:
	var at := P0Garden.grid_of(plot)
	var out: Array = []
	if is_block(kind):   # the w × h plots from the anchor (the server's coverOf)
		var size := block_size(kind)
		for id in P0Garden.plot_count(view):
			var g := P0Garden.grid_of(id)
			if g.x >= at.x and g.x < at.x + size.x and g.y >= at.y and g.y < at.y + size.y: out.append(id)
		return out
	for id in P0Garden.plot_count(view):
		var g := P0Garden.grid_of(id)
		if id != plot and absi(g.x - at.x) <= 1 and absi(g.y - at.y) <= 1: out.append(id)
	return out

## The plots of a greenhouse's block that are in the way (a crop, a sprinkler, another greenhouse), for the red cells.
static func blocked_of(view: Dictionary, plot: int, kind: String, moving := -1) -> Array:
	var block := cover_of(view, plot, kind)
	var own: Array = []
	for f in view.get("facilities", []):   # the view's ids are JSON floats: as ints, or has() never matches
		if int(f.get("id", 0)) == moving: own = (f.get("covers", []) as Array).map(func(x): return int(x))
	var out: Array = []
	for p in view.get("plots", []):
		var id := int(p.get("id", -1))
		if not block.has(id): continue
		if p.get("facility", null) != null or (p.get("greenhouse", false) and not own.has(id)) or p.get("crop", null) != null \
				or str(p.get("state", "")) in ["sown", "growing", "ready"]: out.append(id)
	return out

## "" when a facility may stand on `plot` (the server's spot rules), else the bar's reason (q(59) §5); a greenhouse
## needs its whole 4×4 clear (李白: `Needs 4×4 clear plots`, one reason for all).
static func spot_reason(view: Dictionary, plot: int, moving := -1, kind := "sprinkler") -> String:
	if is_block(kind):
		var size := block_size(kind)
		if plot < 0 or cover_of(view, plot, kind).size() < size.x * size.y or not blocked_of(view, plot, kind, moving).is_empty():
			return "Needs %d×%d clear plots" % [size.x, size.y]
		return ""
	if plot < 0 or plot >= P0Garden.plot_count(view): return "Outside your fields"
	for p in view.get("plots", []):
		if int(p.get("id", -1)) != plot: continue
		var f = p.get("facility", null)
		if f != null and int(f) != moving: return "Plot occupied"
		if p.get("crop", null) != null or str(p.get("state", "")) in ["sown", "growing", "ready"]: return "Plot occupied"
		if p.get("greenhouse", false): return "Plot occupied"   # no sprinkler under the glass (q(118) ②)
		return ""
	return "Outside your fields"

static func caption(view: Dictionary, plot: int, kind := "sprinkler") -> String:
	if is_block(kind):
		var size := block_size(kind)
		return "%s · %d×%d" % [str(P0Logic.content().get("facilities", {}).get("kinds", {}).get(kind, {}).get("name", kind)), size.x, size.y]
	var n := cover_of(view, plot).size() if plot >= 0 and plot < P0Garden.plot_count(view) else 0
	return "Coverage preview · %d plot%s" % [n, "" if n == 1 else "s"]

# ---------------------------------------------------------------- placement
## A Facilities card's Build (P0Ui.placement_requested): placement mode on the nearest empty plot (block).
func begin_build(recipe: String) -> void:
	_begin({"recipe": recipe, "facility": -1, "confirm": "Build", "kind": kind_of(recipe)})

## The status card's Move: the same mode, the facility's own plots excluded from "occupied".
func begin_move(facility: int) -> void:
	var kind := "sprinkler"
	for f in rt.session.view.get("facilities", []): if int(f.get("id", 0)) == facility: kind = str(f.get("kind", kind))
	_begin({"recipe": "", "facility": facility, "confirm": "Move", "kind": kind})

func _begin(p: Dictionary) -> void:
	var v := rt.session.view
	placing = p
	placing.plot = nearest_spot(v, farm.actor.position, int(p.facility), str(p.kind))
	_preview = _greenhouse_art(cover_of(v, maxi(0, int(placing.plot)), str(p.kind)), false) if is_block(str(p.kind)) else _sprinkler_art()
	_preview.name = "PlacementPreview"
	farm.add_child(_preview)
	rt.ui.begin_placement({"confirm": p.confirm})
	if int(placing.plot) >= 0: farm.placement_camera_begin(_spot_center(v, int(placing.plot)))
	else: farm.placement_camera_begin(farm.actor.position)
	_show_spot(v, int(placing.plot))

## Where a spot's preview stands: the bed top, or the middle of a greenhouse's block.
func _spot_center(v: Dictionary, plot: int) -> Vector3:
	if not is_block(str(placing.get("kind", ""))): return _bed_top(plot)
	var c := _block_rect(cover_of(v, plot, str(placing.kind))).get_center()
	return Vector3(c.x, P0Garden.BED_H, c.y)

## The valid spot nearest the player (q(59) §4: the preview starts there); -1 when there is none.
func nearest_spot(v: Dictionary, at: Vector3, moving := -1, kind := "sprinkler") -> int:
	var best := -1
	var best_d := INF
	var size := block_size(kind) if is_block(kind) else Vector2i.ONE
	for id in P0Garden.plot_count(v):
		if spot_reason(v, id, moving, kind) != "": continue
		# a block's distance from its middle: its anchor plus half its size on the garden grid
		var anchor: Vector3 = (farm.bp as FarmBlueprint).cell_to_world(P0Garden.cell_of(id))
		var c: Vector3 = anchor + Vector3(float(size.x - 1), 0, float(size.y - 1)) * float(farm.bp.cell_m) if size != Vector2i.ONE else anchor
		var d: float = c.distance_to(at)
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
	if is_block(str(placing.kind)) and id >= 0: id = _anchor_for(v, id, str(placing.kind))
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

## A finger on a plot points at the block around it: the anchor one row and one col before it (the finger near the
## block's middle), kept on the grid; -1 when no plot stands there.
func _anchor_for(v: Dictionary, finger_plot: int, kind: String) -> int:
	var size := block_size(kind)
	var g := P0Garden.grid_of(finger_plot) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	var top := Vector2i.ZERO
	for id in P0Garden.plot_count(v): top = Vector2i(maxi(top.x, P0Garden.grid_of(id).x), maxi(top.y, P0Garden.grid_of(id).y))
	g = Vector2i(clampi(g.x, 0, maxi(0, top.x - size.x + 1)), clampi(g.y, 0, maxi(0, top.y - size.y + 1)))
	for id in P0Garden.plot_count(v): if P0Garden.grid_of(id) == g: return id
	return -1

## Two fingers moved the picture: the camera follows them, in the yard.
func _on_pan(px: Vector2, at: Vector2) -> void:
	if not placing.is_empty(): farm.placement_drag(px, at)

## A finger held at a screen edge pans the camera (the farm's placement_edge); the preview keeps snapping to the bed
## under the finger as the ground moves under it.
func _edge_pan(_v: Dictionary, dt: float) -> void:
	if placing.is_empty(): return
	if farm.placement_edge(_finger, dt): _snap(_finger)

func _show_spot(v: Dictionary, id: int) -> void:
	var kind := str(placing.get("kind", "sprinkler"))
	var reason := spot_reason(v, id, int(placing.facility), kind)
	placing.ok = reason == ""
	_preview.visible = id >= 0
	if is_block(kind):
		# the roof over the block; its 16 plots green underfoot, only the ones in the way red (284 v2 §2, 李白)
		var block := cover_of(v, id, kind) if id >= 0 else []
		var c := _block_rect(block).get_center() if not block.is_empty() else Vector2.ZERO
		if id >= 0: _preview.position = Vector3(c.x, P0Garden.BED_H, c.y)
		farm.placement_grid(Vector3(c.x, P0Garden.BED_H, c.y) if id >= 0 else Vector3.INF, 4)
		var bad := blocked_of(v, id, kind, int(placing.facility)) if id >= 0 else []
		_paint_tints(block.map(func(b): return [b, BAD_TINT if bad.has(b) else OK_TINT]))
		rt.ui.set_placement({"caption": caption(v, id, kind), "reason": reason})
		return
	farm.placement_grid(_bed_top(id) if id >= 0 else Vector3.INF)   # the shell's fading cell lines around it
	if id >= 0: _preview.position = _bed_top(id)
	_paint([id] if id >= 0 else [], cover_of(v, id) if reason == "" else [], reason != "")
	rt.ui.set_placement({"caption": caption(v, id) if reason == "" else "", "reason": reason})

func _on_done(ok: bool) -> void:
	if placing.is_empty(): return
	var p := placing
	var go := ok and bool(p.get("ok", false))
	# the player steps off the bed a sprinkler takes; a greenhouse is walked into, so they come back where they stood
	_end([P0Garden.cell_of(int(p.plot))] if go and not is_block(str(p.kind)) else [])
	if not go: return
	if int(p.facility) >= 0: rt.session.send({"type": "move_facility", "facility": int(p.facility), "plot": int(p.plot), "space": "home"})
	else: rt.session.send({"type": "place", "recipe": str(p.recipe), "plot": int(p.plot), "space": "home"})

func _end(taken: Array = []) -> void:
	placing = {}
	_finger = Vector2.INF
	farm.placement_camera_end(taken)
	if is_instance_valid(_preview): _preview.queue_free()
	_preview = null
	_paint([], [], false)
	rt.ui.end_placement()

# ---------------------------------------------------------------- squares on beds
## centre: the spot's bed (red when bad); cover: light blue beds round it.
func _paint(centre: Array, cover: Array, bad: bool) -> void:
	_paint_tints(centre.map(func(id): return [id, BAD_TINT if bad else OK_TINT]) + cover.map(func(id): return [id, COVER_TINT]))

## [plot, tint] squares on the beds; the rest hidden.
func _paint_tints(pairs: Array) -> void:
	while _cells.size() < pairs.size():
		var q := _square()
		farm.add_child(q)
		_cells.append(q)
	for i in pairs.size(): _place_square(_cells[i], int(pairs[i][0]), pairs[i][1])
	for k in range(pairs.size(), _cells.size()): (_cells[k] as MeshInstance3D).visible = false

## A square on a bed: `tint` filled; the spot underfoot also wears a 2 px edge of its own colour, green or red
## (不知火舞 on #261, 284 v2 §2: the fill alone read only as a darker bed); coverage squares have none.
func _place_square(q: MeshInstance3D, id: int, tint: Color) -> void:
	q.visible = true
	q.position = _bed_top(id) + Vector3(0, 0.014, 0)
	var m := q.material_override as ShaderMaterial
	m.set_shader_parameter("fill", tint)
	var edge := Color(0, 0, 0, 0)
	if tint == OK_TINT: edge = UiTokens.COLOR_PRIMARY
	elif tint == BAD_TINT: edge = UiTokens.COLOR_DANGER
	m.set_shader_parameter("edge", edge)

static func _square() -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var m := PlaneMesh.new()
	m.size = Vector2(0.9, 0.9)
	q.mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/p0/p0_place_cell.gdshader")
	mat.set_shader_parameter("fill", COVER_TINT)
	q.material_override = mat
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
		if is_block(str(f.get("kind", ""))):   # a greenhouse: a tap near its roof's middle
			var c := _block_rect(f.get("covers", [])).get_center()
			if farm.cam.unproject_position(Vector3(c.x, P0Garden.BED_H + ROOF_H, c.y)).distance_to(screen) > GREENHOUSE_TAP_PX: continue
		elif farm.cam.unproject_position(_bed_top(int(f.get("plot", 0))) + HEAD).distance_to(screen) > TAP_PX: continue
		open_card(f)
		return true
	return false

# ---------------------------------------------------------------- the greenhouse's name strip
## Its own name strip (不知火舞 on 241, 4e7d1119): `Greenhouse · −25%` on the strip Fish Trap uses, over the block's
## back-left post; shown by the farm's rules (its icon button within range, the strip when it is the nearest facility in
## reach, LOCK-07 v2). A tap on the button, the strip or the greenhouse opens its card.
const STRIP_MARK := Vector3(0, ROOF_H + 0.3, 0)

## [id, position, reach m] for the farm's one-strip pick: the block's middle, reach half its diagonal and a step.
func card_candidates() -> Array:
	var out: Array = []
	for f in rt.session.view.get("facilities", []):
		if not is_block(str(f.get("kind", ""))): continue
		var r := _block_rect(f.get("covers", []))
		out.append(["gh_%d" % int(f.get("id", 0)), Vector3(r.get_center().x, 0, r.get_center().y), r.size.length() * 0.5 + 0.8])
	return out

## Each frame on the farm: every greenhouse's button or strip, through the farm's world_prompt.
func prompts(v: Dictionary) -> void:
	for f in v.get("facilities", []):
		if not is_block(str(f.get("kind", ""))): continue
		var r := _block_rect(f.get("covers", []))
		var corner := Vector3(r.position.x, P0Garden.BED_H, r.position.y)
		var middle := Vector3(r.get_center().x, P0Garden.BED_H + ROOF_H, r.get_center().y)
		farm.world_prompt("gh_%d" % int(f.get("id", 0)), greenhouse_prompt(f), corner, STRIP_MARK, middle - corner)

static func greenhouse_prompt(f: Dictionary) -> Dictionary:
	var cut := int(round(float(P0Logic.content().get("facilities", {}).get("kinds", {}).get(str(f.get("kind", "")), {}).get("grow_cut", 0.25)) * 100.0))
	return {icon = P0Logic.icon("facility_greenhouse"), text = "Greenhouse", fact = "−%d%%" % cut, status = -1, dimmed = false,
		button = true, count = ""}

## A greenhouse's button or strip tapped (the farm's _tap_card by id): its card.
func tap_card(id: String) -> bool:
	if not id.begins_with("gh_"): return false
	if rt.ui.has_modal(): return true
	for f in rt.session.view.get("facilities", []):
		if "gh_%d" % int(f.get("id", 0)) == id: open_card(f)
	return true

## A greenhouse's status card (李白): `Greenhouse` / `16 plots · −25%` / `Move`; crops under it grey Move with
## `Move · Harvest first`. The view's ids are JSON numbers (floats): compared as ints.
static func greenhouse_card(view: Dictionary, f: Dictionary) -> Dictionary:
	var under := (f.get("covers", []) as Array).map(func(x): return int(x))
	var growing := false
	for p in view.get("plots", []):
		if under.has(int(p.get("id", -1))) and (p.get("crop", null) != null or str(p.get("state", "")) in ["sown", "growing", "ready"]):
			growing = true
	var cut := int(round(float(P0Logic.content().get("facilities", {}).get("kinds", {}).get(str(f.get("kind", "")), {}).get("grow_cut", 0.25)) * 100.0))
	return {"title": "Greenhouse", "lead": "%d plots · −%d%%" % [under.size(), cut], "icon": P0Logic.icon("facility_greenhouse"),
		"button": "Move", "reason": "Move · Harvest first" if growing else ""}

func open_card(f: Dictionary) -> void:
	_highlight = int(f.get("id", 0))
	var n := (f.get("covers", []) as Array).size()
	if is_block(str(f.get("kind", ""))):
		rt.ui.open_facility_card(greenhouse_card(rt.session.view, f), func(): begin_move(int(f.get("id", 0))))
		return
	rt.ui.open_facility_card({
		"title": "Sprinkler", "lead": "Waters %d plot%s" % [n, "" if n == 1 else "s"],
		"icon": P0Logic.icon("facility_sprinkler"), "button": "Move"},
		func(): begin_move(int(f.get("id", 0))))
