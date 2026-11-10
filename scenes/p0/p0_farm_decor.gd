class_name P0FarmDecor
extends Node
## Decorate in the yard (P1, SGODOT-284; plan §9.11.6, q(24) / q(111) / q(113) / q(120); 不知火舞 on 284 ee15926a,
## 49b11f91; Figma row 62 DECOR-PLACE / -TAKEN / -CARD). The pieces the yard holds (view.decor.placed) stand as
## their own models (SGODOT-290, 刘备's kit; one draw per kind) and are solid, as the facilities are. Decorate is
## the shared placement mode (P0Ui.begin_placement, 刘邦's SGODOT-241):
##   place   a piece from Farm Storage (its Place, the stall toast's Place now): `Cancel · Rotate · Place`, Rotate only
##           for a piece that isn't square; a multi-piece one goes on piece by piece, `Stone Path · 3 left`.
##   move    a placed piece's card Move: the same bar with `Move`.
##   idle    Decorate from HOME-1, nothing picked: one `Done`, `Tap decor to move or store it`; a tap on a piece opens its
##           card (Move / Store), a tap on a sprinkler its own card; after a Move or Store the mode stays (the next).
## Outside the mode a piece isn't tappable (49b11f91 ②). Spots are judged with P0Decor (the server's rules), so a Place
## the bar allows is one the server accepts. One child node of the farm, like P0FarmFacilities.
## The ground (不知火舞's spec v2, 284 6a751a9a, for the top-down view the placement shell turns to — 刘邦's, 058639c7):
## nothing picked, the yard's edge in a faint dashed line and the paths in faint sand; a piece picked, grid lines round
## it fading out over HALO_R cells, its cells filled green (primary 30 %) or red (danger 35 %) with a 2 px edge, paths
## in reach still sand.

const FarmArt = preload("res://modules/farm/farm_art.gd")
const TAP_SLOP := 12.0
const OK_FILL := Color(UiTokens.COLOR_PRIMARY, 0.30)   # spec v2: the piece's cells, may stand
const BAD_FILL := Color(UiTokens.COLOR_DANGER, 0.35)   # … may not
const HALO_R := 3                                      # grid lines this many cells round the piece, 50 % → 0
const HALO_A := 0.5
const SAND := Color(0.86, 0.74, 0.50, 0.30)            # a path cell (Keep the path clear), faint
const EDGE := Color(1, 1, 1, 0.55)                     # the yard's dashed edge
const DASH_M := 0.3
const GAP_M := 0.2
const TAP_MIN_PX := 44.0                               # a piece taps as at least 44 × 44 at any zoom (spec v2)
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
## The decor's own models (SGODOT-290; 刘备's kit, docs/design/decor-290-2026-10-10): assets/farm/art/deco_<id>.glb,
## one mesh each in the farm's vertex paint, its floor pivot at the footprint's middle, +Z forward, one cell 0.65 m. The
## Windmill's sails are their own file on its `rotor` socket (manifest sockets), turning about their axle. A piece with
## no model yet keeps its LOOKS shape (the Recipe Stand).
const SAILS := "deco_windmill_sails"
## The Fountain's bubbling (q(131): `Bubbles away`; the model has flat water only): per basin [its water's height, its
## radius, the ring sources' distance from the middle, how many, how far a ring grows], in the model's metres — measured
## on deco_fountain.glb's water: the upper basin at 0.725 m, 0.26 across the middle; the lower at 0.255 m, 0.51.
const RIPPLES := {"deco_fountain": [[0.725, 0.26, 0.0, 1, 0.22], [0.255, 0.51, 0.38, 3, 0.12]]}
const RippleShader := preload("res://scenes/p0/p0_fountain_ripples.gdshader")
static var _ripple_mats := {}   # "id:i" → its basin's material, shared by every Fountain
const SAIL_TURN_S := 9.0                                   # one turn of the sails
static var _sockets := {}                                  # "id:name" → position, from the farm art manifest

var farm: Node3D                # p0_farm.gd: bp, cam, actor, grid
var rt: P0Runtime
## {mode: "idle" | "place" | "move", id, uid, rot, at (top-left cell), ok, stay (back to idle when done)}; {} = not placing.
var placing := {}
var _list: Array = []           # the view's placed pieces, as last drawn
var _hidden := P0Decor.NO_PIECE # the piece a Move has lifted: out of its kind's draw until the view moves it
var _batches := {}              # id → MultiMeshInstance3D: every placed piece of a kind in one draw (上官婉儿 on #276)
var _singles := {}              # "uid:id:x:y:rot" → Node3D: what does not batch — a Windmill's turning sails, a shape
var _solid := {}                # "x,y" → cell this file made solid
var _sig := 0
var _preview: Node3D
var _cells: Array = []          # the piece's cells: fill
var _edges: Array = []          # … and their 2 px edge
var _halo: Array = []           # grid lines round it
var _sand: Array = []           # path cells
var _dashes: Array = []         # the yard's dashed edge
var _sel: Array = []            # the piece whose card is open: a 2 px white edge …
var _glow: Array = []           # … and a faint glow round it, so it reads at the whole-yard zoom
const GLOW := Color(1, 1, 1, 0.22)
static var _outline: ImageTexture
var _finger := Vector2.INF
var _press := Vector2.INF
## Pieces sent and not yet in the view, {uid (< 0), id, x, y, rot, sent (ms)}: a multi-piece's next spot and its `N left`
## count them. Each goes when the view shows it, when its command is refused or fails, or after PENDING_MS (周瑜 on #265).
var _pending: Array = []
var _pending_uid := 0           # counts down: each sent piece its own uid, never one still on its way (周瑜 on #265)
const PENDING_MS := 10000

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
	rt.session.refused.connect(_on_refused)
	rt.session.connection_failed.connect(_on_failed)

func _exit_tree() -> void:
	if rt == null: return
	for s in [[rt.ui.placement_point, _on_point], [rt.ui.placement_done, _on_done], [rt.ui.placement_pan, _on_pan],
			[rt.ui.placement_secondary, _on_rotate], [rt.session.refused, _on_refused], [rt.session.connection_failed, _on_failed]]:
		if (s[0] as Signal).is_connected(s[1]): (s[0] as Signal).disconnect(s[1])
	if not placing.is_empty(): rt.ui.end_placement()

# ---------------------------------------------------------------- the view → art and solid cells
## The yard grew (yard v2, P0Farm._sync_yard): pieces on cells just opened to walking are made solid at the next frame.
func walk_changed() -> void: _sig = 0

func frame(v: Dictionary, dt := 0.0) -> void:
	var list := P0Decor.placed(v)
	var sig := list.hash()
	if sig != _sig:
		_sig = sig
		_pending = settle_pending(_pending, list, Time.get_ticks_msec())
		_sync(list)
	elif not _pending.is_empty():   # one lost on the way goes after PENDING_MS even when the view stays still
		var left := settle_pending(_pending, list, Time.get_ticks_msec())
		if left.size() != _pending.size():
			_pending = left
			if not placing.is_empty() and str(placing.mode) != "idle": _show()
	if not placing.is_empty() and str(placing.mode) != "idle" and farm.placement_edge(_finger, dt): _snap(_finger)
	if _held_on: _paint_held()

func _sync(list: Array) -> void:
	_list = list
	_draw_pieces()
	var cells := {}
	for p in list:   # the Pergola's middle line stays open (q(131) ②)
		for c in P0Decor.solid_cells(str(p.get("id", "")), Vector2i(int(p.get("x", 0)), int(p.get("y", 0))), int(p.get("rot", 0))):
			cells["%d,%d" % [c.x, c.y]] = c
	# Solid like a facility (49b11f91 ③): only cells the yard's mask lets one walk on are switched, and back.
	for k in _solid.keys():
		if not cells.has(k):
			farm.grid.set_solid(_solid[k], false)
			_solid.erase(k)
	for k in cells:
		if _solid.has(k) or not farm.bp.is_walkable(cells[k]): continue
		farm.grid.set_solid(cells[k], true)
		_solid[k] = cells[k]

## The placed pieces drawn: one MultiMesh per kind with a model (the lifted one left out), and one node each for the
## Windmills' sails, the Fountains' ripples and the pieces still shapes. Rebuilt when the view's pieces or the lifted
## one change.
func _draw_pieces() -> void:
	for n in _batches.values(): (n as Node3D).queue_free()
	_batches.clear()
	var groups := batch_transforms(_list, _hidden, farm.bp.cell_m, centre)
	for id in groups:
		_batches[id] = FarmArt.batch(id, groups[id])
		(_batches[id] as Node3D).name = "Decor_" + str(id)
		farm.add_child(_batches[id])
	var keep := {}
	for p in _list:
		var uid := int(p.get("uid", 0))
		var id := str(p.get("id", ""))
		if uid == _hidden or (has_model(id) and not _has_extra(id)): continue
		var at := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
		var rot := int(p.get("rot", 0))
		var key := "%d:%s:%d:%d:%d" % [uid, id, at.x, at.y, rot]
		keep[key] = true
		if _singles.has(key): continue   # the sails keep turning through a rebuild of the batches
		var node := _extra_on(id, rot, farm.bp.cell_m) if has_model(id) else art(id, rot, farm.bp.cell_m)
		node.position = centre(id, at, rot)
		farm.add_child(node)
		_singles[key] = node
	for key in _singles.keys():
		if not keep.has(key):
			(_singles[key] as Node3D).queue_free()
			_singles.erase(key)

## Every placed piece with a model as its kind's instance transforms: its footprint's middle, turned a quarter per rot
## (as art()), the lifted one left out.
static func batch_transforms(list: Array, hidden: int, cell: float, centre_of: Callable) -> Dictionary:
	var out := {}
	for p in list:
		var id := str(p.get("id", ""))
		if int(p.get("uid", 0)) == hidden or not has_model(id): continue
		var at := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
		var rot := int(p.get("rot", 0))
		var basis := Basis(Vector3.UP, -rot * PI / 2.0).scaled(Vector3.ONE * cell / 0.65)
		(out.get_or_add(id, []) as Array).append(Transform3D(basis, centre_of.call(id, at, rot)))
	return out

## The cells the yard's pieces stand solid on (the sent ones too; a Pergola's middle line is open, q(131) ②): the shell
## brings the player back off them when Decorate ends,
## on the nearest free cell by walking (刘邦's P0Farm.free_cell_near, #261; 不知火舞 on 284).
func taken_cells() -> Array:
	var out: Array = []
	for p in P0Decor.placed(_view()): out.append_array(P0Decor.solid_cells(str(p.id), Vector2i(int(p.x), int(p.y)), int(p.get("rot", 0))))
	return out

## The middle of a piece's cells on the ground.
func centre(id: String, at: Vector2i, rot: int) -> Vector3:
	var cs := P0Decor.cells(id, at, rot)
	var sum := Vector3.ZERO
	for c in cs: sum += farm.bp.cell_to_world(c)
	return sum / maxf(1.0, float(cs.size()))

## A piece's art, facing +z at rot 0: its model (has_model) turned a quarter per rot, else a shape of its colour
## sized to its footprint (LOOKS; turned pieces swap w and h).
static func art(id: String, rot := 0, cell := 0.65) -> Node3D:
	if has_model(id): return _model(id, rot, cell)
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

static func has_model(id: String) -> bool:
	return id.begins_with("deco_") and ResourceLoader.exists(FarmArt.ROOT + id + ".glb")

static func _model(id: String, rot: int, cell: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Decor_" + id
	var body := Node3D.new()
	body.rotation.y = -rot * PI / 2.0
	body.scale = Vector3.ONE * cell / 0.65
	root.add_child(body)
	body.add_child(FarmArt.instance(id))
	if id == "deco_windmill": body.add_child(_sails(socket(id, "rotor")))
	return root

## A placed piece's own part beside its kind's batch: a Windmill's sails, a Fountain's ripples.
static func _has_extra(id: String) -> bool: return id == "deco_windmill" or RIPPLES.has(id)

static func _extra_on(id: String, rot: int, cell: float) -> Node3D:
	return _sails_on(id, rot, cell) if id == "deco_windmill" else _ripples_on(id, rot, cell)

## A Fountain's ripples alone, one quad on each basin's water, turned and scaled as its body in the batch.
static func _ripples_on(id: String, rot: int, cell: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Ripples_" + id
	var body := Node3D.new()
	body.rotation.y = -rot * PI / 2.0
	body.scale = Vector3.ONE * cell / 0.65
	root.add_child(body)
	var basins: Array = RIPPLES.get(id, [])
	for i in basins.size(): body.add_child(_ripple(id, i, basins[i]))
	return root

## One basin's rings: a quad a hair over its water, the ripple shader on it (its material shared by every Fountain).
static func _ripple(id: String, i: int, b: Array) -> MeshInstance3D:
	var key := "%s:%d" % [id, i]
	if not _ripple_mats.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = RippleShader
		mat.set_shader_parameter("basin", float(b[1]))
		mat.set_shader_parameter("source_r", float(b[2]))
		mat.set_shader_parameter("sources", int(b[3]))
		mat.set_shader_parameter("reach", float(b[4]))
		_ripple_mats[key] = mat
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * float(b[1]) * 2.0
	var m := MeshInstance3D.new()
	m.name = "Ripple%d" % i
	m.mesh = quad
	m.position.y = float(b[0]) + 0.004
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.material_override = _ripple_mats[key]
	return m

## A Windmill's sails alone, where a placed one's body is drawn in its kind's batch.
static func _sails_on(id: String, rot: int, cell: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Sails_" + id
	var body := Node3D.new()
	body.rotation.y = -rot * PI / 2.0
	body.scale = Vector3.ONE * cell / 0.65
	root.add_child(body)
	body.add_child(_sails(socket(id, "rotor")))
	return root

## The sails on the rotor socket, turning about their axle (local +Z) once a SAIL_TURN_S; one tween however often they
## re-enter the tree (周瑜 on #276).
static func _sails(at: Vector3) -> Node3D:
	var sails := FarmArt.instance(SAILS, at)
	sails.name = "Sails"
	sails.tree_entered.connect(func() -> void:
		if sails.has_meta("turning"): return
		sails.set_meta("turning", true)
		sails.create_tween().set_loops().tween_property(sails, "rotation:z", -TAU, SAIL_TURN_S).from(0.0))
	return sails

## A model's socket (the farm art manifest's `sockets`: the Windmill's rotor, the Bench's seats, the Lantern's glow).
static func socket(id: String, name: String) -> Vector3:
	if _sockets.is_empty():
		var m = JSON.parse_string(FileAccess.get_file_as_string(FarmArt.ROOT + "manifest.json"))
		for a in (m.get("assets", {}) as Dictionary if m is Dictionary else {}):
			var s = m.assets[a].get("sockets", {})
			for k in (s as Dictionary if s is Dictionary else {}):
				var v: Array = s[k].get("position", [0, 0, 0])
				_sockets["%s:%s" % [a, k]] = Vector3(float(v[0]), float(v[1]), float(v[2]))
	return _sockets.get("%s:%s" % [id, name], Vector3.ZERO)

## The placement preview: see-through, so the cells' green / red under it reads. Its own copies of the shared
## materials (the placed pieces keep theirs: the farm's one vertex-paint material).
static func ghost(node: Node3D) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		mat = mat.duplicate() if mat != null else _mat(Color.WHITE)
		mat.albedo_color.a = 0.6
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat

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
	placing = {mode = "place", id = id, uid = P0Decor.NO_PIECE, rot = rot, stay = stay,
		at = P0Decor.nearest_spot(v, id, rot, farm.bp.world_to_cell(farm.actor.position))}
	_start()
	return true

## A placed piece's card Move (in Decorate): the piece lifts, the preview where it stood.
func begin_move(uid: int, stay := true) -> void:
	var p := _piece(uid)
	if p.is_empty(): return
	placing = {mode = "move", id = str(p.id), uid = uid, rot = int(p.get("rot", 0)), stay = stay,
		at = Vector2i(int(p.x), int(p.y))}
	_hidden = uid
	_draw_pieces()
	_start()

## HOME-1's Decorate ›: the mode with nothing picked.
func begin_decorate() -> void:
	placing = {mode = "idle"}
	_start()

## The top-down camera (刘邦's shell, #261; spec v2 §1): Decorate opens on the whole yard (YARD_PX a cell) with nothing
## picked, on the piece (PICK_PX) with one; picking one up from the yard view comes in to it in 0.3 s; the next piece
## of a multi-piece one is followed without changing the zoom; putting one down or cancelling keeps the zoom.
const YARD_PX := 17.0
const PICK_PX := 36.0
var _held := false   # the camera came in to a piece (PICK_PX) this session

func _start() -> void:
	var first := not rt.ui.placing()
	var spec := _bar()
	if first: rt.ui.begin_placement(spec)
	else: rt.ui.set_placement(spec)
	var idle := str(placing.mode) == "idle"
	var at: Vector3 = yard_centre() if idle or placing.at == P0Decor.NONE else centre(str(placing.id), placing.at, int(placing.rot))
	var held_in := idle and bool(placing.get("held", false))   # q(303) ④: in close over the held cells
	if held_in: at = held_centre(held(_view()))
	if first:
		farm.placement_camera_begin(at, HELD_PX if held_in else YARD_PX if idle else PICK_PX)
		_held = not idle or held_in
	elif held_in: farm.placement_camera_focus(at, HELD_PX)
	elif not idle:
		farm.placement_camera_focus(at, 0.0 if _held else PICK_PX)   # into the piece once; then follow it at this zoom
		_held = true
	_show()

## The middle of the yard (the walk rect), where Decorate with nothing picked looks from.
func yard_centre() -> Vector3:
	var r := P0Decor.walk_of(_view())
	var w: Array = [r.position.x, r.position.y, r.size.x, r.size.y]
	var a: Vector3 = farm.bp.cell_to_world(Vector2i(int(w[0]), int(w[1])))
	var b: Vector3 = farm.bp.cell_to_world(Vector2i(int(w[0]) + int(w[2]) - 1, int(w[1]) + int(w[3]) - 1))
	return (a + b) * 0.5

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
			_pending_uid -= 1
			_pending.append({"uid": _pending_uid, "id": str(p.id), "x": p.at.x, "y": p.at.y, "rot": int(p.rot),
				"sent": Time.get_ticks_msec()})
			# a multi-piece one goes on: the next piece on the nearest free spot (49b11f91 ④)
			if int(P0Decor.item(str(p.id)).get("pieces", 1)) > 1 and begin_place(str(p.id), bool(p.stay)): return
	if str(p.mode) == "move" and _hidden != P0Decor.NO_PIECE:   # back in its kind's draw; the view moves it
		_hidden = P0Decor.NO_PIECE
		_draw_pieces()
	if bool(p.get("stay", false)): begin_decorate()
	else: _end()

func _end() -> void:
	placing = {}
	_held = false
	_finger = Vector2.INF
	_press = Vector2.INF
	farm.placement_camera_end(taken_cells())   # the player fades back in off any piece (#261)
	if is_instance_valid(_preview): _preview.queue_free()
	_preview = null
	_paint([], false)
	_paint_idle(false)
	_select({})
	_held_off()
	rt.ui.end_placement()

## In idle Decorate: a tap on a piece opens its card (DECOR-CARD: name, `1×1 · Classic lamp`, Move, Store); on the
## Compost Bin's cell its card (Move only, 刘邦); on a sprinkler its own card (Move, no Store: facilities stay, q(22)).
func tap(screen: Vector2) -> bool:
	var v := _view()
	var hits: Array = []
	for p in P0Decor.placed(v): hits.append([p, _screen_rect(str(p.id), Vector2i(int(p.x), int(p.y)), int(p.get("rot", 0)))])
	var i := pick_near(hits.map(func(h): return h[1]), screen)
	if i >= 0:
		open_card(hits[i][0])
		return true
	if farm._facilities != null:
		for f in v.get("facilities", []):   # a yard facility (the Compost Bin) by its cell, like a 1×1 piece
			var cell := P0FarmFacilities.cell_of(f)
			if cell != P0Decor.NONE and pick_near([_cell_rect(cell)], screen) == 0:
				open_bin_card(f)
				return true
		for f in v.get("facilities", []):
			if P0FarmFacilities.cell_of(f) != P0Decor.NONE: continue   # the yard's, above
			if farm.cam.unproject_position(farm._facilities._bed_top(int(f.get("plot", 0))) + P0FarmFacilities.HEAD).distance_to(screen) > P0FarmFacilities.TAP_PX: continue
			_end()   # the sprinkler's Move is its own placement
			farm._facilities.open_card(f)
			return true
	return false

## The piece whose screen box — grown to TAP_MIN_PX where it is smaller (the whole yard is 17 px a cell) — holds the
## point, the nearest centre first; -1 for none.
static func pick_near(boxes: Array, at: Vector2, min_px := TAP_MIN_PX) -> int:
	var best := -1
	var best_d := INF
	for i in boxes.size():
		var r: Rect2 = boxes[i]
		var grown := r.grow_individual(maxf(0.0, (min_px - r.size.x) * 0.5), maxf(0.0, (min_px - r.size.y) * 0.5),
			maxf(0.0, (min_px - r.size.x) * 0.5), maxf(0.0, (min_px - r.size.y) * 0.5))
		if not grown.has_point(at): continue
		var d := r.get_center().distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best

## A piece's cells on screen: the box round its footprint's corners.
func _screen_rect(id: String, at: Vector2i, rot: int) -> Rect2:
	var half: float = farm.bp.cell_m * 0.5
	var box := Rect2()
	var first := true
	for c in P0Decor.cells(id, at, rot):
		for corner in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(-half, 0, half), Vector3(half, 0, half)]:
			var sp: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(c) + corner)
			box = Rect2(sp, Vector2.ZERO) if first else box.expand(sp)
			first = false
	return box

## One yard cell on screen: the box round its corners.
func _cell_rect(cell: Vector2i) -> Rect2:
	var half: float = farm.bp.cell_m * 0.5
	var box := Rect2()
	var first := true
	for corner in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(-half, 0, half), Vector3(half, 0, half)]:
		var sp: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(cell) + corner)
		box = Rect2(sp, Vector2.ZERO) if first else box.expand(sp)
		first = false
	return box

## The Compost Bin in Decorate (不知火舞 on 241): its card is `Compost Bin` / `1×1` with Move only — no Store, a
## facility stays (q(22)). Move hands it to the facility's own placement on the same top-down shell (刘邦's
## P0FarmFacilities), as a sprinkler's does: Decorate ends and the bin's placement begins in one frame, so neither
## the camera nor the hidden player moves between them.
func open_bin_card(f: Dictionary) -> void:
	var cell := P0FarmFacilities.cell_of(f)
	var fid := int(f.get("id", 0))
	var kind := str(f.get("kind", "compost_bin"))
	_squares(_glow, [[cell, GLOW]], false, 0.034, 1.25)
	_squares(_sel, [[cell, Color.WHITE]], true, 0.036)
	var name := str(P0Logic.content().get("facilities", {}).get("kinds", {}).get(kind, {}).get("name", "Compost Bin"))
	var card := rt.ui.open_facility_card({"title": name, "lead": "1×1", "icon": P0Logic.icon("facility_" + kind),
		"button": "Move", "kind": &"primary", "close": true},
		func():
			var back := _held_on   # q(303): the bin moved off the wing's cells, Decorate on them again
			_end()
			farm._facilities.begin_move(fid)
			if back: farm._facilities.after_end = begin_held)
	card.tree_exited.connect(func(): if is_inside_tree(): _select({}))

func open_card(p: Dictionary) -> void:
	var uid := int(p.get("uid", 0))
	var id := str(p.get("id", ""))
	_select(p)
	var card := rt.ui.open_facility_card({"title": P0Decor.name_of(id), "lead": P0Decor.line(id), "icon": P0Logic.icon(id),
		"button": "Move", "kind": &"primary", "second": "Store", "close": true},
		func(): begin_move(uid, true),
		func(): rt.session.send({"type": "store_decor", "uid": uid, "space": "home"}))
	card.tree_exited.connect(func(): if is_inside_tree(): _select({}))

## The piece whose card is open, marked on the ground (不知火舞 on 284: a 2 px white edge and a faint glow); {} clears.
func _select(p: Dictionary) -> void:
	var cs: Array = [] if p.is_empty() else P0Decor.cells(str(p.id), Vector2i(int(p.x), int(p.y)), int(p.get("rot", 0)))
	_squares(_glow, cs.map(func(c): return [c, GLOW]), false, 0.034, 1.25)
	_squares(_sel, cs.map(func(c): return [c, Color.WHITE]), true, 0.036)

# ---------------------------------------------------------------- the Kitchen Wing's held cells (q(303), SGODOT-450)
## Decorate on what holds the Kitchen Wing's cells (不知火舞 450 v1.2 ④, frame B2): in close over them (HELD_PX), the
## wing's cells red as a spot that may not take a piece (BAD_FILL with its edge) and grid lines round them fading out
## over HALO_R cells as round a piece picked, each piece or facility on them in a red edge
## 1.25 × its cells (the white selection's texture, no fill), the first of them picked — a piece before a facility
## (后裔). Moved off, its edge goes; all clear, the red cells fade out in HELD_FADE_S. The view says what holds them
## (homestead.next.blocked, or wing_blocked past Lv8); a homestead_blocked refusal's detail stands in until the view moves.
const HELD_PX := 52.0
const HELD_FADE_S := 0.25
var _held_on := false           # Decorate came in on the held cells: they stay marked while it lasts
var _held_detail := {}          # a refusal's {cells, pieces, facilities}, until the view changes
var _held_detail_sig := 0
var _held_sig := ""
var _held_fills: Array = []
var _held_edges: Array = []
var _held_frames: Array = []
var _held_halo: Array = []
var _held_fade: Tween

## What holds the wing's cells now: the view's, or a refusal's while the view has not caught up; {} when nothing does.
func held(v: Dictionary) -> Dictionary:
	var b := P0Decor.next_blocked(v)
	if b.is_empty(): b = P0Decor.wing_blocked(v)
	if b.is_empty() and not _held_detail.is_empty() and _held_detail_sig == _sig: b = _held_detail
	return b

## Into Decorate on the held cells: `Space taken · clear it first`'s Decorate ›, Today's Show, homestead_blocked.
## detail: the refusal's. Nothing held (already cleared): Decorate as HOME-1 opens it.
func begin_held(detail := {}) -> void:
	if not detail.is_empty():
		_held_detail = detail
		_held_detail_sig = _sig
	var b := held(_view())
	if b.is_empty():
		begin_decorate()
		return
	if not placing.is_empty() and str(placing.mode) != "idle": _end()
	_held_on = true
	_held_sig = ""
	placing = {mode = "idle", held = true}
	_start()
	_paint_held()
	for p in b.get("pieces", []):
		var piece := _piece(int(p.get("uid", 0)))
		if not piece.is_empty():
			open_card(piece)
			return
	for f in b.get("facilities", []):
		for g in _view().get("facilities", []):
			if int(g.get("id", 0)) == int(f.get("id", -1)):
				open_bin_card(g)
				return

## The middle of the wing's cells on the ground (all of them: the red block the frame centres on).
func held_centre(b: Dictionary) -> Vector3:
	var cs := P0Decor.wing_cells() if not b.is_empty() else []
	if cs.is_empty(): return yard_centre()
	var sum := Vector3.ZERO
	for c in cs: sum += farm.bp.cell_to_world(c)
	return sum / cs.size()

## The held cells red and what stands on them edged red, as the view has them; cheap while nothing changes.
func _paint_held() -> void:
	var b := held(_view())
	var sig := JSON.stringify(b) + str(_hidden)
	if sig == _held_sig: return
	var had := _held_sig != "" and not _held_fills.is_empty() and (_held_fills[0] as MeshInstance3D).visible
	_held_sig = sig
	var frames: Array = []
	for p in b.get("pieces", []):
		if int(p.get("uid", 0)) == _hidden: continue   # lifted by its Move: its edge goes with it
		for c in P0Decor.cells(str(p.get("item", "")), Vector2i(int(p.get("x", 0)), int(p.get("y", 0))), int(p.get("rot", 0))):
			frames.append([c, UiTokens.COLOR_DANGER])
	for f in b.get("facilities", []): frames.append([Vector2i(int(f.get("x", 0)), int(f.get("y", 0))), UiTokens.COLOR_DANGER])
	_squares(_held_frames, frames, true, 0.038, 1.25)
	if b.is_empty():
		if had: _fade_held()
		else: _held_cells([])
		return
	if _held_fade and _held_fade.is_valid(): _held_fade.kill()
	_held_cells(P0Decor.wing_cells())

func _held_cells(cells: Array) -> void:
	_squares(_held_fills, cells.map(func(c): return [c, BAD_FILL]), false, 0.029)
	_squares(_held_edges, cells.map(func(c): return [c, Color(BAD_FILL, 1.0)]), true, 0.031)
	var lines: Array = []
	for h in halo_cells(_view(), cells): lines.append([h[0], Color(1, 1, 1, HALO_A * (1.0 - float(int(h[1]) - 1) / float(HALO_R)))])
	_squares(_held_halo, lines, true, 0.027)

## All clear: the red cells fade out (HELD_FADE_S), then hide.
func _fade_held() -> void:
	if _held_fade and _held_fade.is_valid(): _held_fade.kill()
	_held_fade = create_tween().set_parallel()
	for q in _held_fills + _held_edges + _held_halo:
		if not (q as MeshInstance3D).visible: continue
		var m := (q as MeshInstance3D).material_override as StandardMaterial3D
		_held_fade.tween_property(m, "albedo_color:a", 0.0, HELD_FADE_S)
	_held_fade.chain().tween_callback(func(): _held_cells([]))

func _held_off() -> void:
	_held_on = false
	_held_detail = {}
	_held_sig = ""
	if _held_fade and _held_fade.is_valid(): _held_fade.kill()
	_held_cells([])
	_squares(_held_frames, [], true, 0.038, 1.25)

# ---------------------------------------------------------------- the preview
func _show() -> void:
	if str(placing.mode) == "idle":
		if is_instance_valid(_preview): _preview.queue_free()
		_preview = null
		_paint([], false)
		_paint_idle(true)
		rt.ui.set_placement(_bar())
		return
	_paint_idle(false)
	var id := str(placing.id)
	var at: Vector2i = placing.at
	var reason := "Outside your yard" if at == P0Decor.NONE else P0Decor.reason(_view(), id, at, int(placing.rot), int(placing.uid))
	placing.ok = reason == ""
	if is_instance_valid(_preview) and str(_preview.get_meta("look", "")) != "%s:%d" % [id, int(placing.rot)]:
		_preview.queue_free()
		_preview = null
	if _preview == null:
		_preview = art(id, int(placing.rot), farm.bp.cell_m)
		ghost(_preview)
		_preview.name = "DecorPreview"
		_preview.set_meta("look", "%s:%d" % [id, int(placing.rot)])
		farm.add_child(_preview)
	_preview.visible = at != P0Decor.NONE
	if at != P0Decor.NONE: _preview.position = centre(id, at, int(placing.rot))
	_paint(P0Decor.cells(id, at, int(placing.rot)) if at != P0Decor.NONE else [], reason != "")
	var spec := _bar()
	spec.reason = reason
	rt.ui.set_placement(spec)

## A piece picked: its cells filled green or red with their edge, grid lines round it fading out, paths in reach sand.
func _paint(cells: Array, bad: bool) -> void:
	var fills: Array = cells.map(func(c): return [c, BAD_FILL if bad else OK_FILL])
	var lines: Array = []
	var sand: Array = []
	for h in halo_cells(_view(), cells):
		lines.append([h[0], Color(1, 1, 1, HALO_A * (1.0 - float(int(h[1]) - 1) / float(HALO_R)))])
		if bool(h[2]): sand.append([h[0], SAND])
	_squares(_cells, fills, false, 0.030)
	_squares(_edges, fills.map(func(f): return [f[0], Color(f[1], 1.0)]), true, 0.032)
	_squares(_halo, lines, true, 0.026)
	_squares(_sand, sand, false, 0.024)

## The yard's cells within HALO_R of the piece's, [cell, distance, on a path]: only where a piece could stand and the
## paths — never the field, the house, facilities or spots (不知火舞 on 284: the grid is the yard's).
static func halo_cells(view: Dictionary, cells: Array, r := HALO_R) -> Array:
	var near := {}
	for c in cells:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n: Vector2i = c + Vector2i(dx, dy)
				var d := maxi(absi(dx), absi(dy))
				var k := "%d,%d" % [n.x, n.y]
				if cells.has(n) or (near.has(k) and int(near[k][1]) <= d): continue
				near[k] = [n, d]
	var out: Array = []
	for k in near:
		var why := P0Decor.reason(view, "deco_planter", near[k][0])
		if why == "" or why == P0Decor.REASONS.decor_path: out.append([near[k][0], near[k][1], why != ""])
	return out

## Nothing picked: the paths in faint sand and the yard's edge dashed (spec v2); `on` false clears them.
func _paint_idle(on: bool) -> void:
	var sand: Array = []
	var y := P0Decor.yard()
	if on:
		for r in y.get("paths", []) + y.get("paths2", []):   # yard v2's three too (v4q(12) ②)
			for dy in int(r[3]):
				for dx in int(r[2]): sand.append([Vector2i(int(r[0]) + dx, int(r[1]) + dy), SAND])
	if on or not placing.is_empty(): _squares(_sand, sand, false, 0.024)
	var walk := P0Decor.walk_of(_view())
	var segs: Array = yard_dashes(farm.bp, [walk.position.x, walk.position.y, walk.size.x, walk.size.y]) if on else []
	while _dashes.size() < segs.size():
		var q := _quad(Vector2.ONE)
		farm.add_child(q)
		_dashes.append(q)
	for i in _dashes.size():
		var q: MeshInstance3D = _dashes[i]
		q.visible = i < segs.size()
		if not q.visible: continue
		q.position = segs[i][0]
		(q.mesh as PlaneMesh).size = segs[i][1]
		(q.material_override as StandardMaterial3D).albedo_color = EDGE

## The yard's edge as dashes on the ground: [centre, size] per dash, round the walk rect's outer cell edges.
static func yard_dashes(bp: FarmBlueprint, walk: Array) -> Array:
	var half := bp.cell_m * 0.5
	var a: Vector3 = bp.cell_to_world(Vector2i(int(walk[0]), int(walk[1]))) + Vector3(-half, 0.028, half)
	var b: Vector3 = bp.cell_to_world(Vector2i(int(walk[0]) + int(walk[2]) - 1, int(walk[1]) + int(walk[3]) - 1)) + Vector3(half, 0.028, -half)
	var out: Array = []
	var width := 0.05
	for side in [[a, Vector3(b.x, a.y, a.z)], [Vector3(a.x, a.y, b.z), b], [a, Vector3(a.x, a.y, b.z)], [Vector3(b.x, a.y, a.z), b]]:
		var from: Vector3 = side[0]
		var to: Vector3 = side[1]
		var length := from.distance_to(to)
		var dir := (to - from) / maxf(length, 0.001)
		var t := 0.0
		while t < length:
			var l := minf(DASH_M, length - t)
			var c := from + dir * (t + l * 0.5)
			out.append([c, Vector2(l, width) if absf(dir.x) > 0.5 else Vector2(width, l)])
			t += DASH_M + GAP_M
	return out

## Squares on cells, pooled: a plain fill, or (outline) the cell's edge.
func _squares(pool: Array, list: Array, outline: bool, lift: float, grow := 1.0) -> void:
	while pool.size() < list.size():
		var q := _quad(Vector2(farm.bp.cell_m, farm.bp.cell_m) * (1.0 if outline else 0.96) * grow)
		if outline: (q.material_override as StandardMaterial3D).albedo_texture = outline_texture()
		farm.add_child(q)
		pool.append(q)
	for i in pool.size():
		var q: MeshInstance3D = pool[i]
		q.visible = i < list.size()
		if not q.visible: continue
		q.position = farm.bp.cell_to_world(list[i][0]) + Vector3(0, lift, 0)
		(q.material_override as StandardMaterial3D).albedo_color = list[i][1]

static func _quad(size: Vector2) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var m := PlaneMesh.new()
	m.size = size
	q.mesh = m
	q.material_override = _mat(Color.WHITE, true)
	(q.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q

## A cell's edge: white border, clear inside (tinted per use); about 2 px at 36 px a cell.
static func outline_texture() -> ImageTexture:
	if _outline != null: return _outline
	var n := 36
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for i in n:
		for w in 2:
			img.set_pixel(i, w, Color.WHITE)
			img.set_pixel(i, n - 1 - w, Color.WHITE)
			img.set_pixel(w, i, Color.WHITE)
			img.set_pixel(n - 1 - w, i, Color.WHITE)
	_outline = ImageTexture.create_from_image(img)
	return _outline

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

## The pending pieces still on their way: those the view now places are gone, and any older than PENDING_MS.
static func settle_pending(pending: Array, placed: Array, now_ms: int) -> Array:
	return pending.filter(func(q):
		if now_ms - int(q.get("sent", now_ms)) > PENDING_MS: return false
		for p in placed:
			if str(p.get("id", "")) == str(q.id) and int(p.get("x", 0)) == int(q.x) and int(p.get("y", 0)) == int(q.y) \
					and int(p.get("rot", 0)) == int(q.rot): return false
		return true)

## A place the server refused, or a send that failed: that piece is not on its way any more.
func _on_refused(_code: String, _detail: Dictionary, cmd: Dictionary) -> void: _drop_pending(cmd)
func _on_failed(_message: String, cmd: Dictionary) -> void: _drop_pending(cmd)

func _drop_pending(cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) != "place_decor": return
	var before := _pending.size()
	_pending = _pending.filter(func(q): return not (str(q.id) == str(cmd.get("item", "")) and int(q.x) == int(cmd.get("x", -1))
		and int(q.y) == int(cmd.get("y", -1)) and int(q.rot) == int(cmd.get("rot", 0))))
	if _pending.size() != before and not placing.is_empty() and str(placing.mode) != "idle": _show()

func _pending_of(id: String) -> int:
	return _pending.filter(func(p): return str(p.id) == id).size()

func _piece(uid: int) -> Dictionary:
	for p in P0Decor.placed(rt.session.view):
		if int(p.get("uid", 0)) == uid: return p
	return {}
