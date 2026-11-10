class_name GlesAlbedo
extends Node
## SGODOT-458 (周瑜's spec 2c, the global hook): on Compatibility (GLES3) a StandardMaterial3D drawing a linear vertex
## colour (vertex_color_use_as_albedo, not vertex_color_is_srgb) reads it as sRGB, a second decode: every such piece —
## the farm's art, the market, the soup, Alcatraz, the mine's monsters — darker and more saturated than on Mobile. Here,
## on GLES only, each one on a node in the tree is swapped for a vcol_matte ShaderMaterial with its parameters: as a
## node comes into the tree (and the whole tree once, as the hook connects), a frame later too for code that sets the
## material after add_child. Only the instance's own slots change (material_override, a surface's override); the shared
## Mesh resources keep theirs. A material some code reads back as a BaseMaterial3D to change it (a flash, a fade) is
## marked KEEP and left as it is. The RD renderers never get here.

const SHADER := preload("res://modules/render/vcol_matte.gdshader")
static var _both: Shader   # vcol_matte with both faces drawn, for a material with CULL_DISABLED (the pond's bank flowers)
## Meta on a material (or a node) that code reads back as a BaseMaterial3D: never swapped.
const KEEP := &"gles_albedo_keep"

## The rendering method the swap is for: "" = the running one; tests inject theirs ("gl_compatibility", "mobile").
static var method := ""
static var _cache := {}   # parameters → the ShaderMaterial made for them (one per look, shared like the originals)

static func on() -> bool:
	return (method if method != "" else RenderingServer.get_current_rendering_method()) == "gl_compatibility"

## A material this swaps: a BaseMaterial3D drawing a linear vertex colour as its albedo and nothing else a vcol_matte
## does not — opaque, per-pixel, back faces culled or none, no texture and no other feature.
static func swaps(m: Material) -> bool:
	if not m is BaseMaterial3D or m.has_meta(KEEP): return false
	var b := m as BaseMaterial3D
	if not b.vertex_color_use_as_albedo or b.vertex_color_is_srgb: return false
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL: return false
	if not b.cull_mode in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_DISABLED] or b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: return false
	if b.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY or b.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX: return false
	if b.albedo_texture != null or b.next_pass != null: return false
	for f in BaseMaterial3D.FEATURE_MAX:
		if b.get_feature(f): return false
	return true

## The vcol_matte for a swapped material, made once for its parameters.
static func matte(b: BaseMaterial3D) -> ShaderMaterial:
	var key := [b.albedo_color, b.roughness, b.metallic_specular, b.metallic, b.render_priority, b.cull_mode]
	var made: ShaderMaterial = _cache.get(key)
	if made == null:
		made = ShaderMaterial.new()
		made.shader = SHADER if b.cull_mode == BaseMaterial3D.CULL_BACK else both_faces()
		made.set_shader_parameter("albedo", b.albedo_color)
		made.set_shader_parameter("roughness", b.roughness)
		made.set_shader_parameter("metallic_specular", b.metallic_specular)
		made.set_shader_parameter("metallic", b.metallic)
		made.render_priority = b.render_priority
		_cache[key] = made
	return made

## vcol_matte drawing both faces: its own code, cull_disabled for cull_back.
static func both_faces() -> Shader:
	if _both == null:
		_both = Shader.new()
		_both.code = SHADER.code.replace("cull_back", "cull_disabled")
	return _both

## One node's slots: its override, else each surface's (its own override, else the mesh's material — set as the
## instance's override, the Mesh untouched). A MultiMesh has only the override: its single surface's material goes there.
static func fix(node: Node) -> void:
	if not node is GeometryInstance3D or node.has_meta(KEEP): return
	var g := node as GeometryInstance3D
	if g.material_override != null:
		if swaps(g.material_override): g.material_override = matte(g.material_override)
		return
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		if mi.mesh == null: return
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m == null: m = mi.mesh.surface_get_material(i)
			if swaps(m): mi.set_surface_override_material(i, matte(m))
	elif g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm and mm.mesh and mm.mesh.get_surface_count() == 1 and swaps(mm.mesh.surface_get_material(0)):
			g.material_override = matte(mm.mesh.surface_get_material(0))

## What under `root` still draws a linear vertex colour through a BaseMaterial3D, swapped or not (a check, for shots):
## "node path [slot]: why it stays" — kept, or what it has a vcol_matte does not draw.
static func left(root: Node) -> Array[String]:
	var out: Array[String] = []
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		var slots := {"override": g.material_override}
		if g is MeshInstance3D and (g as MeshInstance3D).mesh and g.material_override == null:
			for i in (g as MeshInstance3D).mesh.get_surface_count():
				var m := (g as MeshInstance3D).get_surface_override_material(i)
				slots["surface %d" % i] = m if m else (g as MeshInstance3D).mesh.surface_get_material(i)
		elif g is MultiMeshInstance3D and g.material_override == null and (g as MultiMeshInstance3D).multimesh and (g as MultiMeshInstance3D).multimesh.mesh:
			var mesh := (g as MultiMeshInstance3D).multimesh.mesh
			for i in mesh.get_surface_count(): slots["surface %d" % i] = mesh.surface_get_material(i)
		for slot in slots:
			var b = slots[slot]
			if b is BaseMaterial3D and b.vertex_color_use_as_albedo and not b.vertex_color_is_srgb:
				out.append("%s [%s]: %s" % [str(g.get_path()), slot, _why(b, g)])
	return out

static func _why(b: BaseMaterial3D, g: Node) -> String:
	if b.has_meta(KEEP) or g.has_meta(KEEP): return "kept"
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return "transparent"
	if b.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL: return "unshaded"
	if b.albedo_texture != null: return "textured"
	if b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: return "billboard"
	return "not swapped" if swaps(b) else "other"

## A node and all under it.
static func sweep(root: Node) -> void:
	fix(root)
	for n in root.find_children("*", "GeometryInstance3D", true, false): fix(n)

# ---------------------------------------------------------------- the hook (autoload, GLES only)
func _ready() -> void:
	if not on(): return
	get_tree().node_added.connect(_added)
	sweep(get_tree().root)

func _added(node: Node) -> void:
	if not node is GeometryInstance3D: return
	fix(node)
	_again.call_deferred(node)   # code that sets the mesh or the material after add_child

func _again(node: Node) -> void:
	if is_instance_valid(node) and node.is_inside_tree(): fix(node)
