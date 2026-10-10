class_name P0FarmDecor
extends Node
## Decorate in the yard (P1, SGODOT-284; plan §9.11.6, q(24) / q(111) / q(113) / q(120); 不知火舞 on 284 ee15926a,
## 49b11f91; Figma row 62 DECOR-PLACE / -TAKEN / -CARD). The pieces the yard holds (view.decor.placed) stand as
## placeholder art (simple meshes, no new asset: 3D waits for 上官婉儿) and are solid, as the facilities are. Decorate is
## the shared placement mode (P0Ui.begin_placement, 刘邦's SGODOT-241):
##   place   a piece from Farm Storage (its Place, the stall toast's Place now): `Cancel · Rotate · Place`, Rotate only
##           for a piece that isn't square; a multi-piece one goes on piece by piece, `Stone Path · 3 left`.
##   move    a placed piece's card Move: the same bar with `Move`.
##   idle    Decorate from HOME-1, nothing picked: one `Done`, `Tap decor to move or store it`; a tap on a piece opens its
##           card (Move / Store), a tap on a sprinkler its own card; after a Move or Store the mode stays (the next).
## Outside the mode a piece isn't tappable (49b11f91 ②). Spots are judged with P0Decor (the server's rules), so a Place
## the bar allows is one the server accepts. One child node of the farm, like P0FarmFacilities.

const TAP_SLOP := 12.0
const OK_TINT := Color(0.55, 0.78, 0.95, 0.6)   # DECOR-PLACE: the cells light blue (family/water)
const BAD_TINT := Color(0.86, 0.36, 0.30, 0.7)  # DECOR-PLACE-TAKEN: red
const IDLE_CAPTION := "Tap decor to move or store it"   # 李白 q(120)
## Placeholder looks: colour, height (m) and what stands on the footprint, per piece.
const LOOKS := {
	"deco_planter": [Color(0.62, 0.42, 0.26), 0.28, "pot"], "deco_lantern": [Color(0.96, 0.82, 0.38), 0.9, "post"],
	"deco_path": [Color(0.72, 0.72, 0.68), 0.04, "slab"], "deco_bench": [Color(0.66, 0.46, 0.28), 0.42, "box"],
	"deco_scarecrow": [Color(0.86, 0.72, 0.42), 1.2, "post"], "deco_fence": [Color(0.78, 0.62, 0.42), 0.5, "box"],
	"deco_birdbath": [Color(0.78, 0.82, 0.86), 0.55, "pot"], "deco_windmill": [Color(0.92, 0.9, 0.84), 1.8, "box"],
	"deco_fountain": [Color(0.6, 0.76, 0.86), 0.5, "pot"], "deco_pergola": [Color(0.7, 0.5, 0.32), 1.9, "frame"],
	"recipe_stand": [Color(0.86, 0.66, 0.46), 0.8, "box"],
}

var farm: Node3D                # p0_farm.gd: bp, cam, actor, grid
var rt: P0Runtime
## {mode: "idle" | "place" | "move", id, uid, rot, at (top-left cell), ok, stay (back to idle when done)}; {} = not placing.
var placing := {}
var _art := {}                  # uid → Node3D
var _looks := {}                # uid → "id:rot" the art was built for
var _solid := {}                # "x,y" → cell this file made solid
var _sig := ""
var _preview: Node3D
var _cells: Array = []
var _finger := Vector2.INF
var _press := Vector2.INF
var _pending: Array = []        # pieces sent and not yet in the view (a multi-piece's next spot avoids them)

func setup(farm_node: Node3D) -> P0FarmDecor:
	farm = farm_node
	name = "FarmDecor"
	return self

func _ready() -> void:
	rt = P0Runtime.ensure()
	rt.ui.placement_point.connect(_on_point)
	rt.ui.placement_done.connect(_on_done)
	rt.ui.placement_pan.connect(_on_pan)
	rt.ui.placement_secondary.connect(_on_rotate)

func _exit_tree() -> void:
	if rt == null: return
	for s in [[rt.ui.placement_point, _on_point], [rt.ui.placement_done, _on_done], [rt.ui.placement_pan, _on_pan],
			[rt.ui.placement_secondary, _on_rotate]]:
		if (s[0] as Signal).is_connected(s[1]): (s[0] as Signal).disconnect(s[1])
	if not placing.is_empty(): rt.ui.end_placement()

# ---------------------------------------------------------------- the view → art and solid cells
func frame(v: Dictionary, dt := 0.0) -> void:
	var list := P0Decor.placed(v)
	var sig := str(list)
	if sig != _sig:
		_sig = sig
		_pending.clear()
		_sync(list)
	if not placing.is_empty() and str(placing.mode) != "idle" and farm.placement_edge(_finger, dt): _snap(_finger)

func _sync(list: Array) -> void:
	var keep := {}
	var cells := {}
	for p in list:
		var uid := int(p.get("uid", 0))
		var id := str(p.get("id", ""))
		var at := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
		var rot := int(p.get("rot", 0))
		keep[uid] = true
		var look := "%s:%d" % [id, rot]
		if _looks.get(uid, "") != look:
			if _art.has(uid): (_art[uid] as Node3D).queue_free()
			_art[uid] = art(id, rot, farm.bp.cell_m)
			farm.add_child(_art[uid])
			_looks[uid] = look
		(_art[uid] as Node3D).position = centre(id, at, rot)
		(_art[uid] as Node3D).visible = not (str(placing.get("mode", "")) == "move" and int(placing.get("uid", -1)) == uid)
		for c in P0Decor.cells(id, at, rot): cells["%d,%d" % [c.x, c.y]] = c
	for uid in _art.keys():
		if not keep.has(uid):
			(_art[uid] as Node3D).queue_free()
			_art.erase(uid)
			_looks.erase(uid)
	# Solid like a facility (49b11f91 ③): only cells the yard's mask lets one walk on are switched, and back.
	for k in _solid.keys():
		if not cells.has(k):
			farm.grid.set_solid(_solid[k], false)
			_solid.erase(k)
	for k in cells:
		if _solid.has(k) or not farm.bp.is_walkable(cells[k]): continue
		farm.grid.set_solid(cells[k], true)
		_solid[k] = cells[k]
	_step_off()

## A piece put down where the player stands: they step to the nearest free cell rather than stand inside it.
func _step_off() -> void:
	var here: Vector2i = farm.bp.world_to_cell(farm.actor.position)
	if not _solid.has("%d,%d" % [here.x, here.y]): return
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := here + Vector2i(dx, dy)
			if not farm.bp.in_bounds(c) or farm.grid.astar.is_point_solid(c) or not farm.bp.is_walkable(c): continue
			var d := Vector2(dx, dy).length_squared()
			if d < best_d:
				best_d = d
				best = c
	if best.x >= 0: farm.actor.teleport(farm.bp.cell_to_world(best))

## The middle of a piece's cells on the ground.
func centre(id: String, at: Vector2i, rot: int) -> Vector3:
	var cs := P0Decor.cells(id, at, rot)
	var sum := Vector3.ZERO
	for c in cs: sum += farm.bp.cell_to_world(c)
	return sum / maxf(1.0, float(cs.size()))

## Placeholder piece: a shape of its colour sized to its footprint (LOOKS), facing +z; turned pieces swap w and h.
static func art(id: String, rot := 0, cell := 0.65) -> Node3D:
	var look: Array = LOOKS.get(id, [Color(0.7, 0.7, 0.7), 0.4, "box"])
	var size := P0Decor.size_of(id, rot)
	var w := size.x * cell * 0.8
	var d := size.y * cell * 0.8
	var h := float(look[1])
	var root := Node3D.new()
	root.name = "Decor_" + id
	var add := func(mesh: Mesh, at: Vector3, tint: Color) -> void:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.position = at
		m.material_override = _mat(tint)
		root.add_child(m)
	match str(look[2]):
		"pot":
			var c := CylinderMesh.new()
			c.top_radius = minf(w, d) * 0.45
			c.bottom_radius = minf(w, d) * 0.35
			c.height = h
			add.call(c, Vector3(0, h * 0.5, 0), look[0])
			var top := SphereMesh.new()
			top.radius = minf(w, d) * 0.38
			top.height = minf(w, d) * 0.4
			add.call(top, Vector3(0, h, 0), Color(0.92, 0.55, 0.62) if id == "deco_planter" else Color(0.5, 0.72, 0.9))
		"post":
			var p := BoxMesh.new()
			p.size = Vector3(0.08, h, 0.08)
			add.call(p, Vector3(0, h * 0.5, 0), Color(0.45, 0.33, 0.22))
			var head := SphereMesh.new()
			head.radius = 0.12
			head.height = 0.2
			add.call(head, Vector3(0, h, 0), look[0])
		"slab":
			var s := BoxMesh.new()
			s.size = Vector3(w * 1.15, h, d * 1.15)
			add.call(s, Vector3(0, h * 0.5, 0), look[0])
		"frame":
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					var post := BoxMesh.new()
					post.size = Vector3(0.1, h, 0.1)
					add.call(post, Vector3(sx * w * 0.45, h * 0.5, sz * d * 0.45), look[0])
			var roof := BoxMesh.new()
			roof.size = Vector3(w, 0.08, d)
			add.call(roof, Vector3(0, h, 0), Color(0.48, 0.66, 0.4))
		_:
			var b := BoxMesh.new()
			b.size = Vector3(w, h, d)
			add.call(b, Vector3(0, h * 0.5, 0), look[0])
	return root

static func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

# ---------------------------------------------------------------- entering Decorate
## Farm Storage's Place / the stall toast's Place now: the piece picked, the preview on the nearest free spot. The cap
## reached stops it here (q(113) ①: `Decor 24/24 · Homestead Lv3 adds 4`); nothing in storage, nothing happens.
func begin_place(id: String, stay := false) -> bool:
	var v := _view()
	if P0Decor.full(v):
		rt.ui.toast(P0Decor.cap_line(v))
		return false
	if P0Decor.stored(v, id) - _pending_of(id) < 1: return false
	var rot := 0
	placing = {mode = "place", id = id, uid = -1, rot = rot, stay = stay,
		at = P0Decor.nearest_spot(v, id, rot, farm.bp.world_to_cell(farm.actor.position))}
	_start()
	return true

## A placed piece's card Move (in Decorate): the piece lifts, the preview where it stood.
func begin_move(uid: int, stay := true) -> void:
	var p := _piece(uid)
	if p.is_empty(): return
	placing = {mode = "move", id = str(p.id), uid = uid, rot = int(p.get("rot", 0)), stay = stay,
		at = Vector2i(int(p.x), int(p.y))}
	if _art.has(uid): (_art[uid] as Node3D).visible = false
	_start()

## HOME-1's Decorate ›: the mode with nothing picked.
func begin_decorate() -> void:
	placing = {mode = "idle"}
	_start()

func _start() -> void:
	var first := not rt.ui.placing()
	var spec := _bar()
	if first: rt.ui.begin_placement(spec)
	else: rt.ui.set_placement(spec)
	if first:
		var at: Vector3 = centre(str(placing.id), placing.at, int(placing.rot)) if str(placing.mode) != "idle" and placing.at != P0Decor.NONE else farm.actor.position
		farm.placement_camera_begin(at)
	_show()

## The bar for the mode: Cancel · (Rotate) · Place / Move, or one Done with its caption.
func _bar() -> Dictionary:
	if str(placing.mode) == "idle":
		return {"confirm": "Done", "cancel": "", "secondary": "", "caption": IDLE_CAPTION, "reason": ""}
	var id := str(placing.id)
	var left := P0Decor.stored(_view(), id) - _pending_of(id)
	var multi := int(P0Decor.item(id).get("pieces", 1)) > 1 and str(placing.mode) == "place"
	return {"confirm": "Move" if str(placing.mode) == "move" else "Place", "cancel": "Cancel",
		"secondary": "Rotate" if P0Decor.turns(id) else "",
		"caption": "%s · %d left" % [P0Decor.name_of(id), left] if multi else ""}

# ---------------------------------------------------------------- the finger, the keys
func _on_point(screen: Vector2, phase: String) -> void:
	if placing.is_empty(): return
	_finger = Vector2.INF if phase == "release" else screen
	if rt.ui.placement_bar_rect().has_point(screen): return
	if str(placing.mode) == "idle":
		if phase == "press": _press = screen
		elif phase == "release" and _press != Vector2.INF and _press.distance_to(screen) < TAP_SLOP: tap(screen)
		if phase == "release": _press = Vector2.INF
		return
	_snap(screen)

func _snap(screen: Vector2) -> void:
	var cell := cell_at_screen(screen)
	if cell == P0Decor.NONE: return
	var s := P0Decor.size_of(str(placing.id), int(placing.rot))
	var at := cell - Vector2i((s.x - 1) / 2, (s.y - 1) / 2)   # the finger holds the piece by its middle
	if at == placing.at: return
	placing.at = at
	_show()

## The ground cell under a screen point; NONE off the grid.
func cell_at_screen(screen: Vector2) -> Vector2i:
	var cam: Camera3D = farm.cam
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 0.001: return P0Decor.NONE
	var c: Vector2i = farm.bp.world_to_cell(o + d * (-o.y / d.y))
	return c if farm.bp.in_bounds(c) else P0Decor.NONE

func _on_pan(px: Vector2, at: Vector2) -> void:
	if not placing.is_empty(): farm.placement_drag(px, at)

func _on_rotate() -> void:
	if placing.is_empty() or str(placing.mode) == "idle": return
	placing.rot = 1 - int(placing.rot)
	_show()

func _on_done(ok: bool) -> void:
	if placing.is_empty(): return
	var p := placing
	if str(p.mode) == "idle":
		_end()
		return
	if ok and bool(p.get("ok", false)):
		if str(p.mode) == "move":
			rt.session.send({"type": "move_decor", "uid": int(p.uid), "x": p.at.x, "y": p.at.y, "rot": int(p.rot), "space": "home"})
		else:
			rt.session.send({"type": "place_decor", "item": str(p.id), "x": p.at.x, "y": p.at.y, "rot": int(p.rot), "space": "home"})
			_pending.append({"uid": -1 - _pending.size(), "id": str(p.id), "x": p.at.x, "y": p.at.y, "rot": int(p.rot)})
			# a multi-piece one goes on: the next piece on the nearest free spot (49b11f91 ④)
			if int(P0Decor.item(str(p.id)).get("pieces", 1)) > 1 and begin_place(str(p.id), bool(p.stay)): return
	if str(p.mode) == "move" and _art.has(int(p.uid)): (_art[int(p.uid)] as Node3D).visible = true   # the view moves it
	if bool(p.get("stay", false)): begin_decorate()
	else: _end()

func _end() -> void:
	placing = {}
	_finger = Vector2.INF
	_press = Vector2.INF
	farm.placement_camera_end()
	if is_instance_valid(_preview): _preview.queue_free()
	_preview = null
	_paint([], false)
	rt.ui.end_placement()

## In idle Decorate: a tap on a piece opens its card (DECOR-CARD: name, `1×1 · Glows at night`, Move, Store); on a
## sprinkler its own card (Move, no Store: facilities stay, q(22)).
func tap(screen: Vector2) -> bool:
	var v := _view()
	var cell := cell_at_screen(screen)
	var p := P0Decor.piece_at(v, cell) if cell != P0Decor.NONE else {}
	if not p.is_empty():
		open_card(p)
		return true
	if farm._facilities != null:
		for f in v.get("facilities", []):
			if farm.cam.unproject_position(farm._facilities._bed_top(int(f.get("plot", 0))) + P0FarmFacilities.HEAD).distance_to(screen) > P0FarmFacilities.TAP_PX: continue
			_end()   # the sprinkler's Move is its own placement
			farm._facilities.open_card(f)
			return true
	return false

func open_card(p: Dictionary) -> void:
	var uid := int(p.get("uid", 0))
	var id := str(p.get("id", ""))
	rt.ui.open_facility_card({"title": P0Decor.name_of(id), "lead": P0Decor.line(id), "icon": P0Logic.icon(id),
		"button": "Move", "kind": &"primary", "second": "Store"},
		func(): begin_move(uid, true),
		func(): rt.session.send({"type": "store_decor", "uid": uid, "space": "home"}))

# ---------------------------------------------------------------- the preview
func _show() -> void:
	if str(placing.mode) == "idle":
		if is_instance_valid(_preview): _preview.queue_free()
		_preview = null
		_paint([], false)
		rt.ui.set_placement(_bar())
		return
	var id := str(placing.id)
	var at: Vector2i = placing.at
	var reason := "Outside your yard" if at == P0Decor.NONE else P0Decor.reason(_view(), id, at, int(placing.rot), int(placing.uid))
	placing.ok = reason == ""
	if is_instance_valid(_preview) and str(_preview.get_meta("look", "")) != "%s:%d" % [id, int(placing.rot)]:
		_preview.queue_free()
		_preview = null
	if _preview == null:
		_preview = art(id, int(placing.rot), farm.bp.cell_m)
		_preview.name = "DecorPreview"
		_preview.set_meta("look", "%s:%d" % [id, int(placing.rot)])
		farm.add_child(_preview)
	_preview.visible = at != P0Decor.NONE
	if at != P0Decor.NONE: _preview.position = centre(id, at, int(placing.rot))
	_paint(P0Decor.cells(id, at, int(placing.rot)) if at != P0Decor.NONE else [], reason != "")
	var spec := _bar()
	spec.reason = reason
	rt.ui.set_placement(spec)

## The footprint's squares on the ground: light blue, red where the spot is refused.
func _paint(cells: Array, bad: bool) -> void:
	while _cells.size() < cells.size():
		var q := MeshInstance3D.new()
		var m := PlaneMesh.new()
		m.size = Vector2(farm.bp.cell_m * 0.92, farm.bp.cell_m * 0.92)
		q.mesh = m
		q.material_override = _mat(OK_TINT, true)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		farm.add_child(q)
		_cells.append(q)
	for i in _cells.size():
		var q: MeshInstance3D = _cells[i]
		q.visible = i < cells.size()
		if not q.visible: continue
		q.position = farm.bp.cell_to_world(cells[i]) + Vector3(0, 0.02, 0)
		(q.material_override as StandardMaterial3D).albedo_color = BAD_TINT if bad else OK_TINT

# ---------------------------------------------------------------- helpers
## The session's view with the pieces sent but not yet back (a multi-piece's next spot and count avoid them).
func _view() -> Dictionary:
	var v: Dictionary = rt.session.view
	if _pending.is_empty() or not v.get("decor", null) is Dictionary: return v
	var out := v.duplicate()
	var d: Dictionary = (v.decor as Dictionary).duplicate()
	d.placed = (d.get("placed", []) as Array) + _pending
	out.decor = d
	return out

func _pending_of(id: String) -> int:
	return _pending.filter(func(p): return str(p.id) == id).size()

func _piece(uid: int) -> Dictionary:
	for p in P0Decor.placed(rt.session.view):
		if int(p.get("uid", 0)) == uid: return p
	return {}
