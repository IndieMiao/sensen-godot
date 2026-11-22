extends RefCounted
## Upright primitive in metres. Shape dimensions and pose are shared by the XZ
## walker and the debug renderer. Dynamic scenery uses uniform scale and yaw.
var shape: Shape3D
var pose: Transform3D
var solid: bool

func _init(profile: Dictionary, model: Transform3D, fit: float) -> void:
	fit = clampf(fit, 0.8, 1.0)
	var scale_m := model.basis.x.length()
	var height := float(profile.height_m)
	var center := Vector3(profile.center_xz_m[0], height * 0.5, profile.center_xz_m[1])
	var yaw := deg_to_rad(float(profile.get("yaw_degrees", 0)))
	pose = Transform3D(model.basis.orthonormalized() * Basis(Vector3.UP, yaw), model * center)
	solid = profile.solid
	if profile.has("radius_m"):
		var cylinder := CylinderShape3D.new()
		cylinder.radius = float(profile.radius_m) * fit * scale_m
		cylinder.height = height * scale_m
		shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(profile.size_xz_m[0] * fit, height, profile.size_xz_m[1] * fit) * scale_m
		shape = box

func touches(p: Vector3, body_radius: float) -> bool:
	var delta := p - pose.origin
	if shape is CylinderShape3D:
		var r := (shape as CylinderShape3D).radius + body_radius
		return delta.x * delta.x + delta.z * delta.z < r * r
	var half := (shape as BoxShape3D).size * 0.5
	var dx := maxf(0.0, absf(delta.dot(pose.basis.x)) - half.x)
	var dz := maxf(0.0, absf(delta.dot(pose.basis.z)) - half.z)
	return dx * dx + dz * dz < body_radius * body_radius

func bounds() -> AABB:
	var size: Vector3
	if shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		size = Vector3(2*c.radius, c.height, 2*c.radius)
		return AABB(pose.origin - size*0.5, size)
	size = (shape as BoxShape3D).size
	return pose * AABB(-size*0.5, size)

func debug_wire() -> ArrayMesh:
	# get_debug_mesh() can also contain a filled triangle surface. Keep the art
	# visible through the X-ray lines, including when the shape is inside a trunk.
	var wire := ArrayMesh.new()
	var debug := shape.get_debug_mesh()
	for i in debug.get_surface_count():
		if debug.surface_get_primitive_type(i) == Mesh.PRIMITIVE_LINES:
			wire.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, debug.surface_get_arrays(i))
	return wire
