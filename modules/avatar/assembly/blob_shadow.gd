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

static func _material() -> StandardMaterial3D:
	if _shared_material:
		return _shared_material
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.4))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
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
