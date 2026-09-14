extends RefCounted
## Cached Blender meshes share opaque vertex paint; terrain has two shared shaders.

const ROOT := "res://assets/farm/art/"
const STYLES := ["cottage", "mushroom", "thatch", "dome", "east_asian", "barn", "windmill"]
static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D
static var _ground_materials: Dictionary = {}
static var _styles: Dictionary = {}

static func style_for(region_id: String, layout_id := "", override := "") -> String:
	if override in STYLES: return override
	if _styles.is_empty():
		_styles = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "styles.json"))
	var style := str(_styles.layouts.get(layout_id, _styles.regions.get(region_id, _styles.default)))
	return style if style in STYLES else "cottage"

static func preview_for(layout_id: String, region_id := "") -> Texture2D:
	var path := ROOT + "previews/" + style_for(region_id, layout_id) + ".png"
	return load(path) if ResourceLoader.exists(path) else null

static func mesh_for(asset: String) -> Mesh:
	if _meshes.has(asset): return _meshes[asset]
	var scene := load(ROOT + asset + ".glb") as PackedScene
	if scene == null: return null
	var root := scene.instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: found.push_front(root)
	if found.size() == 1:
		_meshes[asset] = (found[0] as MeshInstance3D).mesh
	else:
		push_error("Farm art export must contain one merged mesh: " + asset)
	root.free()
	return _meshes.get(asset)

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		# glTF stores linear vertex colors, unlike the procedural sRGB crop meshes.
		_material.vertex_color_is_srgb = false
		_material.roughness = 0.9
		_material.metallic_specular = 0.18
	return _material

static func ground_material(asset: String) -> ShaderMaterial:
	if not _ground_materials.has(asset):
		var surface := ShaderMaterial.new()
		surface.shader = preload("res://modules/farm/shaders/garden_path.gdshader") if asset == "path_tile" else preload("res://modules/farm/shaders/garden_soil.gdshader")
		surface.set_shader_parameter("meadow_texture", preload("res://assets/farm/art/meadow.png"))
		_ground_materials[asset] = surface
	return _ground_materials[asset]

static func instance(asset: String, position := Vector3.ZERO, scale := 1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = asset.to_pascal_case()
	node.mesh = mesh_for(asset)
	node.material_override = ground_material(asset) if asset in ["plot", "path_tile"] else material()
	node.position = position
	node.scale = Vector3.ONE * scale
	return node

static func batch(asset: String, transforms: Array, shadows := true, tints := PackedColorArray()) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = asset.to_pascal_case()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_colors = not tints.is_empty()
	node.multimesh.mesh = mesh_for(asset)
	node.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		node.multimesh.set_instance_transform(i, transforms[i])
		if i < tints.size(): node.multimesh.set_instance_color(i, tints[i])
	node.material_override = ground_material(asset) if asset in ["plot", "path_tile"] else material()
	if not shadows: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
