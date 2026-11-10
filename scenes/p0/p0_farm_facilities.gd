class_name P0FarmFacilities
extends Node
## P1 facilities on the homestead (q(59) §1.4–1.5, SGODOT-241): sprinklers standing on plots, Build and Move through
## the shared placement mode (P0Ui.begin_placement), the sprinkler's status card and the Coverage Overlay.
## One child node of the farm, like P0FarmMaterials: p0_farm.gd keeps one-line hooks. Facts come from the server view
## (plots[].covered / facility, facilities[].covers); the preview judges a spot with the same rules the place command
## checks (an empty plot of the homestead's, ring8 cover), so a Build the bar allows is one the server accepts.
## SGODOT-244's modelled sprinkler keeps its authored head pivot and only turns on watering / tap.
## A greenhouse (q(118) ②; 不知火舞 on 241) is a glass roof over a 4×4 block of plots, placed by its anchor (the block's
## lowest col and row): four corner posts and a gable roof ~25% opaque, ~10% while the player stands under it; its 16
## plots wear a faint glass outline. Placeholder until 上官婉儿's model.

const TAP_PX := 40.0            # a tap this close to a sprinkler's head opens its card
const HEAD := Vector3(0, 0.42, 0)
const SNAP_PX := 70.0           # a finger this close to a bed's centre on screen points at that bed
const COVER_TINT := Color(0.55, 0.78, 0.95, 0.55)   # Coverage: light blue (q(59) §1.5; water, 284 v2 §2)
const OK_TINT := Color(UiTokens.COLOR_PRIMARY, 0.30)  # the spot underfoot when it may stand there (284 v2 §2)
const BAD_TINT := Color(UiTokens.COLOR_DANGER, 0.35)  # … when it may not
const GLASS := Color(0.80, 0.94, 0.98)            # the greenhouse plots' outline
const FarmArt = preload("res://modules/farm/farm_art.gd")
const SprinklerArt = preload("res://scenes/p0/p0_sprinkler_art.gd")
## SGODOT-294's greenhouse (assets/farm/art/greenhouse_{base,roof,glass}.glb, their manifest entries): three parts on one
## ground-centred origin, +Z to the camera, unit scale, standing on the ground (its posts are in the walkways).
const GLASS_ALPHA := 0.25         # the glass panes' opacity (manifest runtime_opacity_normal) …
const GLASS_INSIDE := 0.10        # … and while the player stands inside (runtime_opacity_inside)
const GH_POST := 2.60             # post centres ±2.60 m on x and z (post_centres_xz): the walkway crossings at the corners
const GH_EAVE := 1.92             # eave top (eave_height): the strip sits above the back-left post
const GH_ROOF_CENTER := Vector3(0, 2.63, 0)   # sockets.roof_center: what a tap on the greenhouse aims at
const GREENHOUSE_TAP_PX := 90.0
const ElasticZoom = preload("res://modules/p0/p0_elastic_zoom.gd")   # ground_at: the yard cell under a finger

var farm: Node3D                # p0_farm.gd: bp, cam, actor
var rt: P0Runtime
var _art := {}                  # facility id → Node3D
var _sig := ""
## Placement in progress: {recipe, facility (Move), plot (the spot shown), ok}; empty when not placing.
var placing := {}
## Called once the placement ends, however it ends (Decorate on the Kitchen Wing's held cells again after the Compost
## Bin's Move from there, q(303) ④); cleared as it is called.
var after_end := Callable()
var _preview: Node3D
var _cells: Array = []          # preview / highlight squares, reused
var _overlay: Array = []        # Coverage Overlay outlines, reused
var _highlight := -1            # a tapped sprinkler: its covered plots show until the card closes
var _finger := Vector2.INF      # placement: where the finger holds (the farm's edge pan), INF when lifted
var _roofs := {}                # greenhouse id → its glass material (the fade under it)
var _glass: Array = []          # greenhouse plots' outlines, reused
var _solid := {}                # "x,y" → cell: yard cells a facility (the Compost Bin) made solid, switched back as it moves
var _water_view := {}           # previous authoritative reply, never a frame's projected countdown
var _water_player := ""

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
	_water_view = rt.session.view
	_water_player = rt.session.player_id
	rt.session.state_changed.connect(_water_changed)

func _exit_tree() -> void:
	if rt == null: return
	if rt.session.state_changed.is_connected(_water_changed): rt.session.state_changed.disconnect(_water_changed)
	for s in [[rt.ui.placement_point, _on_point], [rt.ui.placement_done, _on_done], [rt.ui.placement_requested, begin_build],
			[rt.ui.placement_pan, _on_pan]]:
		if (s[0] as Signal).is_connected(s[1]): (s[0] as Signal).disconnect(s[1])
	if not placing.is_empty(): rt.ui.end_placement()

# ---------------------------------------------------------------- the view → art
## The yard grew (yard v2, P0Farm._sync_yard): a yard facility on a cell just opened to walking is made solid at the
## next frame.
func walk_changed() -> void: _sig = ""

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
			node = _greenhouse_art(f.get("covers", [])) if is_block(kind) else (_bin_art() if is_yard(kind) else _sprinkler_art())
			node.set_meta("plot", int(f.get("plot", 0)))
			farm.add_child(node)
			_art[id] = node
			if is_block(kind): _roofs[id] = node.get_meta("glass")
		if is_yard(kind): node.position = _cell_ground(cell_of(f))
		elif not is_block(kind): node.position = _bed_top(int(f.get("plot", 0)))
	for id in _art.keys():
		if not keep.has(id):
			(_art[id] as Node3D).queue_free()
			_art.erase(id)
			_roofs.erase(id)
	_sync_solid(list)

## A yard facility is solid like a decor piece (49b11f91 ③), and so are a greenhouse's four posts (the walkway crossings at
## its corners; its beds stay walkable, 不知火舞 on 294 c92e7e18): only cells the yard lets one walk on are switched, and back.
func _sync_solid(list: Array) -> void:
	var now := {}
	for f in list:
		if f.get("cell", null) is Array: now["%d,%d" % [int(f.cell[0]), int(f.cell[1])]] = cell_of(f)
		elif is_block(str(f.get("kind", ""))):
			for c in post_cells(farm.bp, f.get("covers", [])): now["%d,%d" % [c.x, c.y]] = c
	for k in _solid.keys():
		if not now.has(k):
			farm.grid.set_solid(_solid[k], false)
			_solid.erase(k)
	for k in now:
		if _solid.has(k) or not farm.bp.is_walkable(now[k]): continue
		farm.grid.set_solid(now[k], true)
		_solid[k] = now[k]

## A greenhouse's four post cells: the walkway crossings ±GH_POST from its block's middle.
static func post_cells(bp: FarmBlueprint, plots: Array) -> Array:
	var c := block_middle(bp, plots)
	var out: Array = []
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		out.append(bp.world_to_cell(Vector3(c.x + d.x * GH_POST, 0.0, c.y + d.y * GH_POST)))
	return out

## The middle (x, z) of a block of plots: its beds' centres' middle.
static func block_middle(bp: FarmBlueprint, plots: Array) -> Vector2:
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for id in plots:
		var w := bp.cell_to_world(P0Garden.cell_of(int(id)))
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	return (lo + hi) * 0.5

## A yard facility's cell (the view's `cell`: [x, y]); P0Decor.NONE for one on the field.
static func cell_of(f: Dictionary) -> Vector2i:
	var c = f.get("cell", null)
	return Vector2i(int(c[0]), int(c[1])) if c is Array and (c as Array).size() == 2 else P0Decor.NONE

func _cell_ground(cell: Vector2i) -> Vector3:
	return (farm.bp as FarmBlueprint).cell_to_world(cell)

## Placeholder Compost Bin (FARM-5: a compost bin with an open lid): a slatted wooden crate, dark compost inside, its lid
## propped open behind it; 0.55 m across, within its one yard cell.
static func _bin_art() -> Node3D:
	var root := Node3D.new()
	root.name = "CompostBin"
	var wood := _mat(Color(0.55, 0.38, 0.22))
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.42, 0.55)
	box.mesh = bm
	box.position = Vector3(0, 0.21, 0)
	box.material_override = wood
	root.add_child(box)
	for y in [0.12, 0.28]:   # two darker slats round the crate
		var slat := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.57, 0.04, 0.57)
		slat.mesh = sm
		slat.position = Vector3(0, y, 0)
		slat.material_override = _mat(Color(0.42, 0.28, 0.16))
		root.add_child(slat)
	var soil := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.48, 0.48)
	soil.mesh = pm
	soil.position = Vector3(0, 0.425, 0)
	soil.material_override = _mat(Color(0.24, 0.17, 0.10))
	root.add_child(soil)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.58, 0.04, 0.5)
	lid.mesh = lm
	lid.position = Vector3(0, 0.55, -0.36)
	lid.rotation = Vector3(deg_to_rad(-62.0), 0, 0)
	lid.material_override = wood
	root.add_child(lid)
	return root

## The greenhouse over its plots (SGODOT-294): base (posts, plinths, eaves, braces, vine, can), roof frame and glass, one
## origin at the block's middle on the ground. The glass wears its own copy of the farm material, alpha-blended at
## GLASS_ALPHA, both faces drawn (single-sided panes seen from inside too), no shadow; the shared material stays opaque.
## `roof` false: the base alone (the placement preview: seen from straight above, the roof and glass would wash out the
## green / red squares under it; the eaves stay at the perimeter).
func _greenhouse_art(plots: Array, roof := true) -> Node3D:
	return greenhouse_art(farm.bp, plots, roof)

static func greenhouse_art(bp: FarmBlueprint, plots: Array, roof := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Greenhouse"
	var c := block_middle(bp, plots)
	root.position = Vector3(c.x, 0.0, c.y)
	root.add_child(FarmArt.instance("greenhouse_base"))
	if not roof: return root
	root.add_child(FarmArt.instance("greenhouse_roof"))
	var glass := FarmArt.instance("greenhouse_glass")
	var mat := FarmArt.material().duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color.a = GLASS_ALPHA
	glass.material_override = mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	root.set_meta("glass", mat)
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

## Greenhouses each frame: the glass fades while the player stands inside; their plots wear the glass outline.
func _draw_greenhouses(v: Dictionary) -> void:
	var ids: Array = []
	for f in v.get("facilities", []):
		if not is_block(str(f.get("kind", ""))): continue
		ids.append_array(f.get("covers", []))
		var mat: StandardMaterial3D = _roofs.get(int(f.get("id", 0)))
		if mat != null:
			var p: Vector3 = (farm.actor as Node3D).position
			var c := _block_rect(f.get("covers", [])).get_center()
			var inside := absf(p.x - c.x) < GH_POST and absf(p.z - c.y) < GH_POST   # between the posts
			mat.albedo_color.a = GLASS_INSIDE if inside else GLASS_ALPHA
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

## A whole scene, not FarmArt.mesh_for(): base, rotating head and the spray socket must stay separate.
static func _sprinkler_art() -> Node3D:
	return SprinklerArt.new()

## Covered annuals start growing in the sow/place/move reply; there is no separate sprinkler-water event.
## Ignore the first snapshot, unchanged growing crops, manual watering outside coverage and greenhouse-only cover.
static func watered_sprinklers(before: Dictionary, after: Dictionary) -> Array:
	if before.is_empty(): return []
	var old := {}
	for p in before.get("plots", []): old[int(p.get("id", -1))] = p
	var watered := []
	for p in after.get("plots", []):
		var id := int(p.get("id", -1))
		if str(p.get("state", "")) != "growing" or not old.has(id) or bool(p.get("tree", false)): continue
		if not str(old[id].get("state", "")) in ["tilled", "sown"]: continue
		watered.append(id)
	var ids := []
	for f in after.get("facilities", []):
		if str(f.get("kind", "")) != "sprinkler": continue
		if (f.get("covers", []) as Array).any(func(id): return watered.has(int(id))): ids.append(int(f.id))
	return ids

func _water_changed(v: Dictionary, _events: Array) -> void:
	var before := _water_view
	_water_view = v
	var same_player := _water_player == rt.session.player_id
	_water_player = rt.session.player_id
	if not same_player or rt.world != farm: return
	var ids := watered_sprinklers(before, v)
	if ids.is_empty(): return
	_sync_art(v.get("facilities", []))   # a newly placed sprinkler can water immediately
	for id in ids: _play_sprinkler(id)

func _play_sprinkler(id: int) -> void:
	var node = _art.get(id)
	if is_instance_valid(node) and node is SprinklerArt: node.play()

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

## A yard facility (cover yard: the Compost Bin, q(118) ③) stands on a yard cell, never a plot.
static func is_yard(kind: String) -> bool:
	return str(P0Logic.content().get("facilities", {}).get("kinds", {}).get(kind, {}).get("cover", "")) == "yard"

## "" when a yard facility may stand on `cell`, else the bar's reason: the decor yard's rules and words (P0Decor,
## the server's yardBlock); the one being moved leaves its own cell.
static func yard_reason(view: Dictionary, cell: Vector2i, moving := -1) -> String:
	if cell == P0Decor.NONE: return P0Decor.REASONS.decor_outside
	var t := P0Decor.taken(view)
	for f in view.get("facilities", []):
		if int(f.get("id", 0)) == moving and cell_of(f) != P0Decor.NONE: t.erase("%d,%d" % [cell_of(f).x, cell_of(f).y])
	return P0Decor.reason_cells(view, [cell], t)

## The legal yard cell nearest `from` (the preview starts there: beside the workbench, q(118) ③); NONE when none is.
## `span`: cells either side of `from` that count as its footprint (the workbench's three: 1). Beside it comes first,
## then in front; behind it last, where the 43° view would hide a low box behind the bench.
static func nearest_yard_cell(view: Dictionary, from: Vector2i, moving := -1, span := 0) -> Vector2i:
	var r := P0Decor.walk_of(view)
	var walk := [r.position.x, r.position.y, r.size.x, r.size.y]
	var best := P0Decor.NONE
	var best_d := INF
	for y in range(int(walk[1]), int(walk[1]) + int(walk[3])):
		for x in range(int(walk[0]), int(walk[0]) + int(walk[2])):
			var dx := maxi(0, absi(x - from.x) - span)
			var dy := y - from.y
			var d := float(dx * dx + dy * dy) + (0.25 if dy != 0 else 0.0) + (0.5 if dy > 0 else 0.0)
			if d >= best_d or yard_reason(view, Vector2i(x, y), moving) != "": continue
			best_d = d
			best = Vector2i(x, y)
	return best

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

## Whether the beds open now hold one whole w × h block anywhere (trees and crops in it or not).
static func has_open_block(view: Dictionary, kind := "greenhouse") -> bool:
	var size := block_size(kind)
	for id in P0Garden.plot_count(view):
		if cover_of(view, id, kind).size() == size.x * size.y: return true
	return false

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
	if is_yard(kind):   # `Compost Bin · 1×1` (不知火舞 on 241)
		return "%s · 1×1" % str(P0Logic.content().get("facilities", {}).get("kinds", {}).get(kind, {}).get("name", kind))
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
	if is_yard(str(p.kind)):
		_begin_yard(v)
		return
	placing.plot = nearest_spot(v, farm.actor.position, int(p.facility), str(p.kind))
	_preview = _greenhouse_art(cover_of(v, maxi(0, int(placing.plot)), str(p.kind)), false) if is_block(str(p.kind)) else _sprinkler_art()
	_preview.name = "PlacementPreview"
	farm.add_child(_preview)
	rt.ui.begin_placement({"confirm": p.confirm})
	# no spot to take: the camera frames the open beds, not the grass where the player stands (不知火舞 on #624)
	farm.placement_camera_begin(_spot_center(v, int(placing.plot)) if int(placing.plot) >= 0 else beds_center(v))
	_show_spot(v, int(placing.plot))
	# no whole block open on the grid yet (不知火舞 on the grid, SGODOT-355 b1): an Info toast on entering, over the caption;
	# the cells in the way still go red as q(130) ④ has it
	if is_block(str(p.kind)) and not has_open_block(v, str(p.kind)): rt.ui.toast("More plots open as your Home grows")

## A yard facility: the preview starts on the free cell nearest the workbench (a moved one: nearest where it stands).
## No free cell in the yard: Info `Store one to place this` (不知火舞 450 v1.2 ⑩) — a piece stored makes room.
const STORE_ONE := "Store one to place this"
func _begin_yard(v: Dictionary) -> void:
	var from := P0Decor.NONE
	var span := 0
	for f in v.get("facilities", []): if int(f.get("id", 0)) == int(placing.facility): from = cell_of(f)
	if from == P0Decor.NONE:   # a new one: beside the workbench, whose anchor is the middle of its three cells
		for c in farm._materials.card_candidates(): if str(c[0]) == "workbench": from = farm.bp.world_to_cell(c[1])
		span = 1
	placing.plot = -1
	placing.cell = nearest_yard_cell(v, from, int(placing.facility), span)
	if placing.cell == P0Decor.NONE: rt.ui.toast(STORE_ONE)   # a full yard: nowhere it may go (q(303) ⑩)
	_preview = _bin_art()
	_preview.name = "PlacementPreview"
	farm.add_child(_preview)
	rt.ui.begin_placement({"confirm": placing.confirm})
	farm.placement_camera_begin(_cell_ground(placing.cell) if placing.cell != P0Decor.NONE else farm.actor.position)
	_show_yard(v, placing.cell)

func _show_yard(v: Dictionary, cell: Vector2i) -> void:
	var reason := yard_reason(v, cell, int(placing.facility))
	placing.ok = reason == ""
	_preview.visible = cell != P0Decor.NONE
	var at := _cell_ground(cell) if cell != P0Decor.NONE else Vector3.INF
	if cell != P0Decor.NONE: _preview.position = at
	farm.placement_grid(at)
	_paint_tints([[at, BAD_TINT if reason != "" else OK_TINT]] if cell != P0Decor.NONE else [])
	rt.ui.set_placement({"caption": caption(v, -1, str(placing.kind)), "reason": reason})   # two keys: the reason on Done

## The middle of the open beds, at their tops (the placement camera when there is no spot to take).
func beds_center(v: Dictionary) -> Vector3:
	var n := P0Garden.plot_count(v)
	if n <= 0: return farm.actor.position
	var sum := Vector3.ZERO
	for id in n: sum += _bed_top(id)
	return sum / float(n)

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
	if is_yard(str(placing.kind)):   # the yard cell under the finger
		var g = ElasticZoom.ground_at(farm.cam, screen, 0.0)
		var cell: Vector2i = farm.bp.world_to_cell(g) if g is Vector3 else P0Decor.NONE
		if cell == placing.get("cell", P0Decor.NONE): return
		placing.cell = cell
		_show_yard(v, cell)
		return
	var id := plot_at_screen(v, screen)
	if is_block(str(placing.kind)) and id >= 0: id = anchor_for(v, id, str(placing.kind))
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
## block's middle), kept on the open beds' cols and rows (the grid starts at col −1, row −2 since SGODOT-355 b1); -1 when
## no plot stands there.
static func anchor_for(v: Dictionary, finger_plot: int, kind: String) -> int:
	var size := block_size(kind)
	var g := P0Garden.grid_of(finger_plot) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	var lo := P0Garden.grid_of(0)
	var hi := lo
	for id in P0Garden.plot_count(v):
		var at := P0Garden.grid_of(id)
		lo = Vector2i(mini(lo.x, at.x), mini(lo.y, at.y))
		hi = Vector2i(maxi(hi.x, at.x), maxi(hi.y, at.y))
	g = Vector2i(clampi(g.x, lo.x, maxi(lo.x, hi.x - size.x + 1)), clampi(g.y, lo.y, maxi(lo.y, hi.y - size.y + 1)))
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
		if id >= 0: _preview.position = Vector3(c.x, 0.0, c.y)   # the model stands on the ground
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
	if is_yard(str(p.kind)):   # a solid Compost Bin: the player comes back off its cell
		_end([p.cell] if go else [])
		if not go: return
		var at: Vector2i = p.cell
		if int(p.facility) >= 0: rt.session.send({"type": "move_facility", "facility": int(p.facility), "x": at.x, "y": at.y, "space": "home"})
		else: rt.session.send({"type": "place", "recipe": str(p.recipe), "x": at.x, "y": at.y, "space": "home"})
		return
	# the player steps off the bed a sprinkler takes; a greenhouse is walked into, so they come back where they stood,
	# unless that is where one of its posts goes
	var taken: Array = []
	if go: taken = post_cells(farm.bp, cover_of(rt.session.view, int(p.plot), str(p.kind))) if is_block(str(p.kind)) else [P0Garden.cell_of(int(p.plot))]
	_end(taken)
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
	if after_end.is_valid():
		var then := after_end
		after_end = Callable()
		then.call_deferred()

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
	for i in pairs.size():
		if pairs[i][0] is Vector3: _place_square_at(_cells[i], pairs[i][0], pairs[i][1], float(farm.bp.cell_m) * 0.94)   # a yard cell
		else: _place_square(_cells[i], int(pairs[i][0]), pairs[i][1])
	for k in range(pairs.size(), _cells.size()): (_cells[k] as MeshInstance3D).visible = false

## A square on a bed: `tint` filled; the spot underfoot also wears a 2 px edge of its own colour, green or red
## (不知火舞 on #261, 284 v2 §2: the fill alone read only as a darker bed); coverage squares have none.
func _place_square(q: MeshInstance3D, id: int, tint: Color) -> void:
	_place_square_at(q, _bed_top(id), tint, 0.9)

## The same square at a ground point, `size` metres across (a bed's 0.9, a yard cell's own size).
func _place_square_at(q: MeshInstance3D, at: Vector3, tint: Color, size: float) -> void:
	q.visible = true
	q.position = at + Vector3(0, 0.014, 0)
	(q.mesh as PlaneMesh).size = Vector2(size, size)
	var m := q.material_override as ShaderMaterial
	m.set_shader_parameter("size_m", size)
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
		if is_yard(str(f.get("kind", ""))):   # the Compost Bin: a tap on it opens its drawer
			if farm.cam.unproject_position(_cell_ground(cell_of(f)) + BIN_HIT).distance_to(screen) > TAP_PX: continue
			open_bin(f)
			return true
		if is_block(str(f.get("kind", ""))):   # a greenhouse: a tap near its roof's middle
			var c := _block_rect(f.get("covers", [])).get_center()
			if farm.cam.unproject_position(Vector3(c.x, 0.0, c.y) + GH_ROOF_CENTER).distance_to(screen) > GREENHOUSE_TAP_PX: continue
		elif farm.cam.unproject_position(_bed_top(int(f.get("plot", 0))) + HEAD).distance_to(screen) > TAP_PX: continue
		open_card(f)
		return true
	return false

# ---------------------------------------------------------------- the greenhouse's name strip
## Its own name strip (不知火舞 on 241, 4e7d1119): `Greenhouse · −25%` on the strip Fish Trap uses, over the block's
## back-left post; shown by the farm's rules (its icon button within range, the strip when it is the nearest facility in
## reach, LOCK-07 v2). A tap on the button, the strip or the greenhouse opens its card.
const STRIP_MARK := Vector3(0, GH_EAVE + 0.3, 0)
## The Compost Bin's strip `Compost Bin · 2/5` (today's / the day's, 不知火舞 on 241) over its lid; the same rules.
const BIN_MARK := Vector3(0, 0.95, 0)
const BIN_HIT := Vector3(0, 0.35, 0)
const BIN_REACH := 1.6

## [id, position, reach m] for the farm's one-strip pick: the block's middle, reach half its diagonal and a step.
func card_candidates() -> Array:
	var out: Array = []
	for f in rt.session.view.get("facilities", []):
		if is_yard(str(f.get("kind", ""))):
			out.append(["bin_%d" % int(f.get("id", 0)), _cell_ground(cell_of(f)), BIN_REACH])
			continue
		if not is_block(str(f.get("kind", ""))): continue
		var r := _block_rect(f.get("covers", []))
		out.append(["gh_%d" % int(f.get("id", 0)), Vector3(r.get_center().x, 0, r.get_center().y), r.size.length() * 0.5 + 0.8])
	return out

## Each frame on the farm: every greenhouse's button or strip, through the farm's world_prompt.
func prompts(v: Dictionary) -> void:
	for f in v.get("facilities", []):
		if is_yard(str(f.get("kind", ""))):
			farm.world_prompt("bin_%d" % int(f.get("id", 0)), bin_prompt(v, f), _cell_ground(cell_of(f)), BIN_MARK, BIN_HIT, true,
				UiWorldNameBar.Dir.RIGHT)
			continue
		if not is_block(str(f.get("kind", ""))): continue
		var c := _block_rect(f.get("covers", [])).get_center()
		var corner := Vector3(c.x - GH_POST, 0.0, c.y - GH_POST)   # the back-left post
		var middle := Vector3(c.x, 0.0, c.y) + GH_ROOF_CENTER
		farm.world_prompt("gh_%d" % int(f.get("id", 0)), greenhouse_prompt(f), corner, STRIP_MARK, middle - corner, true,
			UiWorldNameBar.Dir.RIGHT)

static func greenhouse_prompt(f: Dictionary) -> Dictionary:
	var cut := cut_percent(str(f.get("kind", "")))
	return {icon = P0Logic.icon("facility_greenhouse"), text = "Greenhouse", fact = "−%d%%" % cut, status = -1, dimmed = false,
		button = true, count = ""}

## `Compost Bin · 2/5`: today's crops in, of the day's (`5/5` at the cap).
static func bin_prompt(view: Dictionary, f: Dictionary) -> Dictionary:
	var q = view.get("compost", null)
	var name := str(P0Logic.content().get("facilities", {}).get("kinds", {}).get(str(f.get("kind", "")), {}).get("name", "Compost Bin"))
	var fact := "%d/%d" % [int(q.get("used", 0)), int(q.get("cap", 5))] if q is Dictionary else ""
	return {icon = P0Logic.icon("facility_" + str(f.get("kind", "compost_bin"))), text = name, fact = fact, status = -1,
		dimmed = false, button = true, count = ""}

## A greenhouse's or the Compost Bin's button or strip tapped (the farm's _tap_card by id): its card, or the bin's drawer.
func tap_card(id: String) -> bool:
	if not (id.begins_with("gh_") or id.begins_with("bin_")): return false
	if rt.ui.has_modal(): return true
	for f in rt.session.view.get("facilities", []):
		if "gh_%d" % int(f.get("id", 0)) == id: open_card(f)
		elif "bin_%d" % int(f.get("id", 0)) == id: open_bin(f)
	return true

## The Compost Bin's drawer (COMPOST-BIN): the player turns to it; Move is Decorate's (不知火舞 on 241).
func open_bin(f: Dictionary) -> void:
	farm.actor.face(_cell_ground(cell_of(f)))
	rt.ui.open_compost_bin()

## A greenhouse's status card (李白): `Greenhouse` / `16 plots · −25%` / `Move`, the green primary key while it can move;
## crops under it grey Move with `Move · Harvest first` (q(139): a facility card's one action is the primary key when it
## works, the grey key with its reason when it does not). The view's ids are JSON numbers (floats): compared as ints.
static func greenhouse_card(view: Dictionary, f: Dictionary) -> Dictionary:
	var under := (f.get("covers", []) as Array).map(func(x): return int(x))
	var growing := false
	for p in view.get("plots", []):
		if under.has(int(p.get("id", -1))) and (p.get("crop", null) != null or str(p.get("state", "")) in ["sown", "growing", "ready"]):
			growing = true
	var cut := cut_percent(str(f.get("kind", "")))
	return {"title": "Greenhouse", "lead": "%d plots · −%d%%" % [under.size(), cut], "icon": P0Logic.icon("facility_greenhouse"),
		"button": "Move", "kind": &"primary", "reason": "Move · Harvest first" if growing else ""}

## A sprinkler's status card (q(136), FAC-STATUS 2116:32993): `Sprinkler` / `Waters 8 plots · −15%` — the greenhouse's
## `16 plots · −25%` form — and `Move`, the card's one action, as the green primary key.
static func sprinkler_card(f: Dictionary) -> Dictionary:
	var n := (f.get("covers", []) as Array).size()
	return {"title": "Sprinkler", "lead": "Waters %d plot%s · −%d%%" % [n, "" if n == 1 else "s", cut_percent(str(f.get("kind", "")))],
		"icon": P0Logic.icon("facility_sprinkler"), "button": "Move", "kind": &"primary"}

## A facility kind's grow time cut as a whole percent (content facilities.kinds[kind].grow_cut: sprinkler 15, greenhouse 25).
static func cut_percent(kind: String) -> int:
	return int(round(float(P0Logic.content().get("facilities", {}).get("kinds", {}).get(kind, {}).get("grow_cut", 0.0)) * 100.0))

func open_card(f: Dictionary) -> void:
	if is_yard(str(f.get("kind", ""))):   # the Compost Bin has a drawer, not a card
		open_bin(f)
		return
	_highlight = int(f.get("id", 0))
	if is_block(str(f.get("kind", ""))):
		rt.ui.open_facility_card(greenhouse_card(rt.session.view, f), func(): begin_move(int(f.get("id", 0))))
		return
	_play_sprinkler(int(f.get("id", 0)))
	rt.ui.open_facility_card(sprinkler_card(f), func(): begin_move(int(f.get("id", 0))))
