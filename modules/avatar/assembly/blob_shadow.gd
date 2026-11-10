class_name BlobShadow
extends RefCounted
## 脚下假影：角色 cast_shadow 全关（性能口径），用一张径向渐变面片提供接地感。
## spec §5.3 的"低成本假影"实现；材质全角色共享一份。

const NODE_NAME := "blob_shadow"

static var _shared_material: StandardMaterial3D

static func attach(rig: Node3D, radius := 0.45) -> void:
	if rig.get_node_or_null(NODE_NAME) != null:
		return
	var mi := MeshInstance3D.new()
	mi.name = NODE_NAME
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = plane
	mi.material_override = _material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.02, 0.0)
	rig.add_child(mi)

## The shadow's darkness from its middle (0.4 black) to its rim (none). GLES blends in sRGB where the RD renderers blend
## in linear, so the same alpha darkens more there (周瑜 on 458: the ground under the feet 132 on GLES, 173 on Mobile):
## for a black overlay linear (1 − a) on the ground matches sRGB (1 − a′) with a′ = 1 − (1 − a)^(1/2.2) — on GLES the
## ramp is laid down as GLES_STOPS points of that, between which it is near enough straight (SGODOT-458).
const CENTRE_ALPHA := 0.4
const GLES_STOPS := 8
static func gradient(gles: bool) -> Gradient:
	var g := Gradient.new()
	if not gles:
		g.set_color(0, Color(0, 0, 0, CENTRE_ALPHA))
		g.set_color(1, Color(0, 0, 0, 0.0))
		return g
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in GLES_STOPS:
		var t := float(i) / float(GLES_STOPS - 1)
		offsets.append(t)
		colors.append(Color(0, 0, 0, gles_alpha(CENTRE_ALPHA * (1.0 - t))))
	g.offsets = offsets
	g.colors = colors
	return g

static func gles_alpha(a: float) -> float: return 1.0 - pow(1.0 - a, 1.0 / 2.2)

static func _material() -> StandardMaterial3D:
	if _shared_material:
		return _shared_material
	var tex := GradientTexture2D.new()
	tex.gradient = gradient(GlesAlbedo.on())
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	_shared_material = mat
	return mat
