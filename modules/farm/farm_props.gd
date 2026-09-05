extends RefCounted
## Fixed scenery stays one merged mesh per anchor, with no new gameplay or collision nodes.

const WALL := Color(0.91, 0.92, 0.82)
const ROOF := Color(0.24, 0.49, 0.38)
const TRIM := Color(0.17, 0.35, 0.29)
const WOOD := Color(0.65, 0.45, 0.27)
const WOOD_LIGHT := Color(0.76, 0.57, 0.35)
const STONE := Color(0.62, 0.67, 0.60)
const WATER := Color(0.34, 0.67, 0.73)

static func build(kind: String, position: Vector3, scale: float = 1.0) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"house": _house(surface)
		"storage": _storage(surface)
		"well": _well(surface)
	surface.index()
	var instance := MeshInstance3D.new()
	instance.name = kind.capitalize()
	instance.mesh = surface.commit()
	instance.position = position
	instance.scale = Vector3.ONE * scale
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	instance.material_override = material
	return instance

static func _house(surface: SurfaceTool) -> void:
	_box(surface, Vector3(1.72, 0.11, 1.72), Vector3(0, 0.055, 0), STONE)
	_box(surface, Vector3(1.58, 0.86, 1.58), Vector3(0, 0.54, 0), WALL)
	for front in [-1.0, 1.0]:
		var z: float = front * 0.79
		_triangle(surface, Vector3(-0.79, 0.97, z), Vector3(0, 1.38, z), Vector3(0.79, 0.97, z), WALL, front > 0)
		for side in [-1.0, 1.0]:
			_box(surface, Vector3(0.07, 0.85, 0.07), Vector3(side * 0.755, 0.54, z), Color(0.76, 0.83, 0.69))
	for side in [-1.0, 1.0]:
		var basis := Basis(Vector3.BACK, -side * 0.41)
		var center := Vector3(side * 0.465, 1.17, 0)
		_box(surface, Vector3(1.04, 0.09, 1.90), center, ROOF, basis)
		for seam in 5:
			_box(surface, Vector3(1.04, 0.014, 0.016), center + Vector3(0, 0.044, -0.64 + seam * 0.32),
				ROOF.lightened(0.10), basis)
		for front in [-1.0, 1.0]:
			_box(surface, Vector3(1.06, 0.085, 0.055), center + Vector3(0, 0, front * 0.955), TRIM, basis)
	_box(surface, Vector3(0.11, 0.07, 1.96), Vector3(0, 1.395, 0), ROOF.lightened(0.08))
	_box(surface, Vector3(0.19, 0.37, 0.20), Vector3(-0.49, 1.24, -0.30), STONE.darkened(0.06))
	_box(surface, Vector3(0.24, 0.05, 0.25), Vector3(-0.49, 1.45, -0.30), TRIM)
	_box(surface, Vector3(0.47, 0.68, 0.045), Vector3(-0.26, 0.40, 0.80), TRIM)
	_box(surface, Vector3(0.36, 0.59, 0.035), Vector3(-0.26, 0.365, 0.83), WOOD)
	for plank in [-0.09, 0.0, 0.09]:
		_box(surface, Vector3(0.008, 0.55, 0.01), Vector3(-0.26 + plank, 0.36, 0.853), WOOD.darkened(0.18))
	_box(surface, Vector3(0.045, 0.055, 0.035), Vector3(-0.13, 0.35, 0.865), Color(0.80, 0.65, 0.30))
	_box(surface, Vector3(0.54, 0.075, 0.20), Vector3(-0.26, 0.0375, 0.85), STONE.lightened(0.09))
	_window(surface, Vector3(0.39, 0.57, 0.80), Basis.IDENTITY)
	_window(surface, Vector3(0.80, 0.57, 0.10), Basis(Vector3.UP, PI * 0.5))

static func _window(surface: SurfaceTool, center: Vector3, basis: Basis) -> void:
	_box(surface, Vector3(0.41, 0.36, 0.055), center, TRIM, basis)
	_box(surface, Vector3(0.31, 0.27, 0.035), center + basis * Vector3(0, 0, 0.042), WATER.lightened(0.22), basis)
	_box(surface, Vector3(0.025, 0.28, 0.024), center + basis * Vector3(0, 0, 0.067), WALL, basis)
	_box(surface, Vector3(0.32, 0.025, 0.024), center + basis * Vector3(0, 0, 0.067), WALL, basis)
	_box(surface, Vector3(0.46, 0.045, 0.12), center + basis * Vector3(0, -0.195, 0.035), TRIM, basis)

static func _storage(surface: SurfaceTool) -> void:
	_box(surface, Vector3(0.58, 0.38, 0.52), Vector3(0, 0.20, 0), WOOD_LIGHT)
	for front in [-1.0, 1.0]:
		for plank in 3:
			_box(surface, Vector3(0.56, 0.013, 0.018), Vector3(0, 0.11 + plank * 0.10, front * 0.265), WOOD)
	_box(surface, Vector3(0.64, 0.075, 0.58), Vector3(0, 0.4275, 0), WOOD_LIGHT.lightened(0.08))
	for plank in 5:
		_box(surface, Vector3(0.009, 0.009, 0.55), Vector3(-0.21 + plank * 0.105, 0.469, 0), WOOD)
	for side in [-1.0, 1.0]:
		_box(surface, Vector3(0.048, 0.40, 0.55), Vector3(side * 0.21, 0.20, 0), TRIM)
		_box(surface, Vector3(0.048, 0.04, 0.59), Vector3(side * 0.21, 0.48, 0), TRIM)
	_box(surface, Vector3(0.075, 0.13, 0.04), Vector3(0, 0.38, 0.295), Color(0.75, 0.60, 0.28))

static func _well(surface: SurfaceTool) -> void:
	_cylinder(surface, 0.31, 0.09, Vector3(0, 0.045, 0), STONE.darkened(0.14))
	_cylinder(surface, 0.215, 0.02, Vector3(0, 0.255, 0), WATER)
	for i in 12:
		var angle := TAU * float(i) / 12.0
		var center := Vector3(sin(angle) * 0.25, 0.20, cos(angle) * 0.25)
		var basis := Basis(Vector3.UP, angle)
		_box(surface, Vector3(0.125, 0.25, 0.12), center, STONE.lightened(0.035 * float(i % 3)), basis)
		_box(surface, Vector3(0.15, 0.075, 0.15), center + Vector3(0, 0.165, 0), STONE.lightened(0.14), basis)
	for side in [-1.0, 1.0]:
		_box(surface, Vector3(0.065, 0.55, 0.065), Vector3(side * 0.255, 0.425, -0.04), WOOD)
	_box(surface, Vector3(0.65, 0.07, 0.075), Vector3(0, 0.715, -0.04), TRIM)
	_cylinder(surface, 0.012, 0.25, Vector3(0, 0.565, -0.04), WOOD_LIGHT)
	var bucket := CylinderMesh.new()
	bucket.bottom_radius = 0.055
	bucket.top_radius = 0.075
	bucket.height = 0.12
	bucket.radial_segments = 10
	_append(surface, bucket, Transform3D(Basis.IDENTITY, Vector3(0, 0.38, -0.04)), WOOD_LIGHT)
	_cylinder(surface, 0.079, 0.024, Vector3(0, 0.44, -0.04), TRIM)
	_cylinder(surface, 0.059, 0.009, Vector3(0, 0.455, -0.04), WATER.darkened(0.22))

static func _box(surface: SurfaceTool, size: Vector3, center: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(surface, mesh, Transform3D(basis, center), color)

static func _cylinder(surface: SurfaceTool, radius: float, height: float, center: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	_append(surface, mesh, Transform3D(Basis.IDENTITY, center), color)

static func _append(surface: SurfaceTool, mesh: PrimitiveMesh, transform: Transform3D, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		surface.set_color(color)
		surface.set_normal((transform.basis * normals[index]).normalized())
		surface.add_vertex(transform * vertices[index])

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, front: bool) -> void:
	var vertices := [a, b, c] if front else [c, b, a]
	for vertex in vertices:
		surface.set_color(color)
		surface.set_normal(Vector3.BACK if front else Vector3.FORWARD)
		surface.add_vertex(vertex)
