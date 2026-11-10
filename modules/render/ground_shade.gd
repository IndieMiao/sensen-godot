extends Node
## The ground's tree shadows under the Compatibility renderer (SGODOT-457, 盘古; 上官婉儿's spec 11-09): there no sun casts
## a shadow (SGODOT-456, GlesSunShadows), so the wild's and the farm's ground lost their trees' shade. This draws it once
## into a mask instead: every piece that would cast a shadow on Metal (cast_shadow on) as a soft ellipse where the sun
## throws its crown on the ground — an ellipsoid round the upper part of a tall piece, the whole of a low one — into an
## R8 image over `rect` at PX_M, edges soft over BLUR_M. The ground's light() takes the mask as its shadow there
## (#if CURRENT_RENDERER == RENDERER_COMPATIBILITY: att = min(ATTENUATION, 1 − shade)), so a shade is coloured as a Metal
## shadow is (grass blue-green, sand a cool beige). On the ground only: pieces don't shade one another. Other renderers:
## nothing is drawn, the shaders don't read it.
## Drawn after the pieces stand (the frame after this node enters the tree); `ground` takes the mask on whichever
## material it has then, and a material it gets later keeps it (PondWildGroundBake.LIVE_KEYS).

const PX_M := 16.0     # 6 cm a pixel: the soft edge is 0.4 m
const BLUR_M := 0.4
## Only the trees (2 m and up): a bush's, a stone's, a log's shade on Metal falls mostly on itself, and drawn on the
## ground they made it darker than Metal round them (11-10, Fern / Willow / Clover against Metal). Env: tuning shots.
static var MIN_H := float(OS.get_environment("P0_SHADE_MINH")) if OS.get_environment("P0_SHADE_MINH") != "" else 2.0
const TALL := 1.5      # taller: a tree — its crown is the upper part (from CROWN_LOW of its height up)
const CROWN_LOW := 0.3
const MAX_R := 4.0
const ROOF_K := 0.85   # a building's roof thrown from this much of its height: a gable's ends stand lower than its ridge
static var r_k := float(OS.get_environment("P0_SHADE_RK")) if OS.get_environment("P0_SHADE_RK") != "" else 0.7   # a cone's shade, not its box
static var deep := float(OS.get_environment("P0_SHADE_MAX")) if OS.get_environment("P0_SHADE_MAX") != "" else 1.0     # no single piece is wider: a wider one is ground (the painted ground's terraces stand 0.6 m)

static var enabled := (RenderingServer.get_current_rendering_method() == "gl_compatibility" or OS.get_environment("P0_GLES_SHADE") == "1") \
	and OS.get_environment("P0_NO_SHADE") == ""   # dev: the before shots

var ground: GeometryInstance3D
var casters_root: Node3D
var more_roots: Array[Node] = []   # other roots of standing pieces (the pond's gathering points); redrawn as they gain one
var skip_roots: Array[Node] = []   # what moves (the insects): never a shade
var box_roots: Array[Node] = []    # buildings (the farmhouse, its porch and wing): each piece a box, its whole footprint thrown
var clear_spots: Array = []         # [Vector2 xz, radius m]: kept unshaded (the farm's exit ring, 上官婉儿 on 457)
var rect := Rect2()
var mask: ImageTexture
var opacity := 1.0   # the sun's shadow_opacity: the mask says where, this how deep (overlapping crowns no deeper, as on Metal)
var shades := 0   # ellipses drawn (shots, tests)
var _vp: SubViewport
var _t0 := 0
var _queued := false
var _again := false   # asked again while a drawing was out: drawn once more when it is read

## One piece as a caster: Vector4(x, z, height above the ground, radius), from its box in the world.
static func caster_of(box: AABB) -> Vector4:
	return Vector4(box.get_center().x, box.get_center().z, box.end.y, maxf(box.size.x, box.size.z) * 0.5)

## Every piece under `root` but `skip` (the ground) that casts a shadow, stands MIN_H or more and is no wider than MAX_R:
## its world box as a caster.
static func casters_under(root: Node, skip: Node = null, skip_roots: Array[Node] = []) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if g == skip or g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not g.is_visible_in_tree(): continue
		if skip_roots.any(func(r: Node): return is_instance_valid(r) and (r == g or r.is_ancestor_of(g))): continue
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null: continue
			var local := mm.mesh.get_aabb()
			var n := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for i in n:
				var box := (g.global_transform * mm.get_instance_transform(i)) * local
				if box.end.y >= MIN_H and caster_of(box).w <= MAX_R: out.append(caster_of(box))
		elif g is MeshInstance3D and (g as MeshInstance3D).mesh:
			var box := g.global_transform * (g as MeshInstance3D).mesh.get_aabb()
			if box.end.y >= MIN_H and caster_of(box).w <= MAX_R: out.append(caster_of(box))
	return out

## Where a caster's shade falls, given the way to the sun (unit, pointing at it): [centre xz, half-length along the throw,
## half-width, angle of the throw in the ground's x–z plane].
static func shade_of(c: Vector4, to_sun: Vector3) -> Array:
	var h := c.z
	var low := h * CROWN_LOW if h >= TALL else 0.0
	var mid := (low + h) * 0.5   # the crown's middle height
	var half_up := (h - low) * 0.5
	var throw := Vector2(-to_sun.x, -to_sun.z) / maxf(to_sun.y, 0.2)   # ground metres a metre of height moves the shade
	var centre := Vector2(c.x, c.y) + throw * mid
	var r := c.w * r_k
	var along := sqrt(r * r + pow(half_up * throw.length(), 2.0))
	return [centre, along, r, throw.angle()]

## A building's shade: its footprint and its roof (ROOF_K of its height) thrown along the sun, the hull of both (x–z).
static func box_shade(box: AABB, to_sun: Vector3) -> PackedVector2Array:
	var throw := Vector2(-to_sun.x, -to_sun.z) / maxf(to_sun.y, 0.2) * (box.end.y * ROOF_K)
	var a := Vector2(box.position.x, box.position.z)
	var b := Vector2(box.end.x, box.end.z)
	var foot := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
	var pts := PackedVector2Array(foot)
	for p: Vector2 in foot: pts.append(p + throw)
	return Geometry2D.convex_hull(pts)

## Every visible piece casting a shadow at or under `root`: its world box.
static func boxes_under(root: Node, skip_roots: Array[Node] = []) -> Array[AABB]:
	var out: Array[AABB] = []
	var all: Array[Node] = [root]
	all.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	for g in all:
		if not (g is MeshInstance3D) or (g as MeshInstance3D).mesh == null: continue
		if (g as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not (g as Node3D).is_visible_in_tree(): continue
		if skip_roots.any(func(r: Node): return is_instance_valid(r) and (r == g or r.is_ancestor_of(g))): continue
		out.append((g as Node3D).global_transform * (g as MeshInstance3D).mesh.get_aabb())
	return out

## Drawn as it enters the tree; off where the owner draws it itself once its pieces stand (the farm, on its first view:
## each drawing is a GPU read-back, about 15.5 ms — 周瑜 on #967).
var draw_on_ready := true

func _ready() -> void:
	if not enabled or DisplayServer.get_name() == "headless" or not draw_on_ready: return
	_draw_mask.call_deferred()

## Another root of standing pieces: its pieces cast too, and a piece added there draws the mask again (once a frame).
func watch(root: Node) -> void:
	more_roots.append(root)
	root.child_entered_tree.connect(func(_n: Node): redraw(), CONNECT_DEFERRED)
	# a root whose pieces turn in place (the pond's gathering points: gathered looks, C67) says so: drawn again once
	if root.has_signal("looks_changed"): root.connect("looks_changed", redraw, CONNECT_DEFERRED)
	redraw()

func redraw() -> void:
	if not enabled or DisplayServer.get_name() == "headless" or _queued: return
	if _vp != null:
		_again = true
		return
	_queued = true
	_draw_mask.call_deferred()

## The sun lighting the ground: a directional light in the ground's own world (not a UI preview's), the strongest.
func _sun() -> DirectionalLight3D:
	var best: DirectionalLight3D = null
	for l: DirectionalLight3D in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		if not l.is_visible_in_tree() or l.get_world_3d() != ground.get_world_3d(): continue
		if best == null or l.light_energy > best.light_energy: best = l
	return best

func _draw_mask() -> void:
	_queued = false
	if not is_inside_tree() or not is_instance_valid(ground): return   # an old scenery, already replaced
	if _vp != null: return   # one drawing at a time; the next asks again
	_t0 = Time.get_ticks_usec()
	var sun := _sun()
	if sun == null or not is_instance_valid(casters_root): return
	var to_sun := sun.global_transform.basis.z.normalized()
	opacity = sun.shadow_opacity
	var list: Array = []
	var not_trees: Array[Node] = []
	not_trees.append_array(skip_roots)
	not_trees.append_array(box_roots)
	var cs := casters_under(casters_root, ground, not_trees)
	for r in more_roots:
		if is_instance_valid(r): cs.append_array(casters_under(r, ground, not_trees))
	for c in cs: list.append(shade_of(c, to_sun))
	var polys: Array = []
	for r in box_roots:
		if is_instance_valid(r):
			for b in boxes_under(r, skip_roots): polys.append(box_shade(b, to_sun))
	shades = list.size() + polys.size()
	_vp = SubViewport.new()
	_vp.size = Vector2i(roundi(rect.size.x * PX_M), roundi(rect.size.y * PX_M))
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(_vp.size)
	_vp.add_child(bg)
	var pen := _Pen.new()
	pen.shades = list
	pen.polys = polys
	pen.rect = rect
	pen.deep = deep
	pen.clear_spots = clear_spots
	_vp.add_child(pen)
	add_child(_vp)
	RenderingServer.frame_post_draw.connect(_read, CONNECT_ONE_SHOT)

func _read() -> void:
	if not is_inside_tree() or _vp == null: return
	var t_read := Time.get_ticks_usec()
	var img := _vp.get_texture().get_image()
	_vp.queue_free()
	_vp = null
	if _again:
		_again = false
		redraw()
	if img == null or img.is_empty(): return
	img.convert(Image.FORMAT_R8)
	if OS.get_environment("P0_SHADE_DUMP") != "": img.save_png(OS.get_environment("P0_SHADE_DUMP"))
	mask = ImageTexture.create_from_image(img)
	apply()
	if OS.get_environment("P0_SHADE_LOG") != "": print("P0_SHADE_MS ", (Time.get_ticks_usec() - _t0) / 1000.0, " cpu_read ", (Time.get_ticks_usec() - t_read) / 1000.0)

## The mask on the ground's material now (and on a later one: the bake's swap copies these keys).
func apply() -> void:
	if mask == null or not is_instance_valid(ground) or not (ground.material_override is ShaderMaterial): return
	var m := ground.material_override as ShaderMaterial
	m.set_shader_parameter("shade_mask", mask)
	m.set_shader_parameter("shade_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	m.set_shader_parameter("shade_opacity", opacity)

## The ellipses, white on black, soft at the edge (a radial gradient: whole to 1 − BLUR_M / size, nothing at 1).
class _Pen extends Node2D:
	var shades: Array
	var polys: Array   # buildings' shades (box_shade): hard hulls, softened by drawing them grown to shrunk in layers
	var rect: Rect2
	var deep := 1.0
	var clear_spots: Array
	var _dot: GradientTexture2D
	func _ready() -> void:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, deep))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.6, Color(1, 1, 1, deep))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
		queue_redraw()
	func _draw() -> void:
		for s in shades:
			var c: Vector2 = s[0]
			var at := (c - rect.position) * PX_M
			var a := (float(s[1]) + 0.5 * BLUR_M) * PX_M
			var b := (float(s[2]) + 0.5 * BLUR_M) * PX_M
			draw_set_transform(at, float(s[3]), Vector2(a, b))
			draw_texture_rect(_dot, Rect2(-1, -1, 2, 2), false)
		draw_set_transform(Vector2.ZERO)
		# BLUR_M wide edge: SOFT layers from half of it out to half in, each over the last so the inside sums to whole
		for poly: PackedVector2Array in polys:
			var px := PackedVector2Array()
			for p in poly: px.append((p - rect.position) * PX_M)
			for i in SOFT:
				var grow := BLUR_M * (0.5 - (float(i) + 0.5) / SOFT) * PX_M
				for g: PackedVector2Array in Geometry2D.offset_polygon(px, grow, Geometry2D.JOIN_ROUND):
					draw_colored_polygon(g, Color(1, 1, 1, 1.0 / float(SOFT - i)))
		for spot in clear_spots:
			draw_circle((Vector2(spot[0]) - rect.position) * PX_M, float(spot[1]) * PX_M, Color.BLACK)
	const SOFT := 5
