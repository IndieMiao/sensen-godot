extends RefCounted
## Primitive in metres, upright except for capsules, which lie along the local X
## axis. Shape dimensions and pose are shared by the XZ walker and the debug
## renderer. Dynamic scenery uses uniform scale and yaw.
var shape: Shape3D
var pose: Transform3D
var solid: bool
# Footprint = flat core (half extents along local X/Z) rounded by a radius:
# cylinder = point + r, capsule = segment + r, box = rectangle + 0.
var _core := Vector2.ZERO
var _round := 0.0

func _init(profile: Dictionary, model: Transform3D, fit: float) -> void:
	fit = clampf(fit, 0.8, 1.0)
	var scale_m := model.basis.x.length()
	# A lying capsule is centred on the ground: its visible half covers the base it blocks.
	var height := float(profile.get("height_m", 0.0))
	var center := Vector3(profile.center_xz_m[0], height * 0.5, profile.center_xz_m[1])
	var yaw := deg_to_rad(float(profile.get("yaw_degrees", 0)))
	pose = Transform3D(model.basis.orthonormalized() * Basis(Vector3.UP, yaw), model * center)
	solid = profile.solid
	var k := fit * scale_m
	match String(profile.shape):
		"cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(profile.radius_m) * k
			cylinder.height = height * scale_m
			_round = cylinder.radius
			shape = cylinder
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = float(profile.radius_m) * k
			capsule.height = float(profile.length_m) * k
			_round = capsule.radius
			_core = Vector2(capsule.height * 0.5 - capsule.radius, 0)
			shape = capsule
		"box":
			var box := BoxShape3D.new()
			box.size = Vector3(profile.size_xz_m[0] * k, height * scale_m, profile.size_xz_m[1] * k)
			_core = Vector2(box.size.x, box.size.z) * 0.5
			shape = box
		_:
			push_error("Unknown collision proxy shape")

func _closest(p: Vector3) -> Array:
	var local := pose.affine_inverse() * p
	var q := Vector2(local.x, local.z)
	return [q, q.clamp(-_core, _core)]

## Horizontal distance from p to the footprint edge; negative inside.
func gap(p: Vector3) -> float:
	var pair := _closest(p)
	return (pair[0] as Vector2).distance_to(pair[1]) - _round

func touches(p: Vector3, body_radius: float) -> bool:
	return gap(p) < body_radius

## Outward horizontal unit normal of the footprint nearest to p (ZERO on the core).
func away(p: Vector3) -> Vector3:
	var pair := _closest(p)
	var d: Vector2 = (pair[0] as Vector2) - (pair[1] as Vector2)
	if d.length_squared() < 1e-12: return Vector3.ZERO
	return (pose.basis * Vector3(d.x, 0, d.y)).normalized()

## Footprint extent from the centre along a horizontal unit direction.
func reach(direction: Vector3) -> float:
	return _core.x * absf(direction.dot(pose.basis.x)) + _core.y * absf(direction.dot(pose.basis.z)) + _round

func bounds() -> AABB:
	var size := Vector3(2 * (_core.x + _round), 0, 2 * (_core.y + _round))
	return pose * AABB(-size * 0.5, size)

func debug_wire() -> ArrayMesh:
	# get_debug_mesh() can also contain a filled triangle surface. Keep the art
	# visible through the X-ray lines, including when the shape is inside a trunk.
	var wire := ArrayMesh.new()
	var debug := shape.get_debug_mesh()
	var lying := Basis(Vector3.BACK, PI * 0.5) if shape is CapsuleShape3D else Basis.IDENTITY
	for i in debug.get_surface_count():
		if debug.surface_get_primitive_type(i) == Mesh.PRIMITIVE_LINES:
			var arrays := debug.surface_get_arrays(i)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for j in vertices.size(): vertices[j] = lying * vertices[j]
			arrays[Mesh.ARRAY_VERTEX] = vertices
			wire.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return wire
