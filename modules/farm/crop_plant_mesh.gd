extends RefCounted
## Each plant is one colored mesh shared by an entire MultiMesh layer.

const LEAF := Color(0.34, 0.65, 0.22)
const LEAF_LIGHT := Color(0.53, 0.76, 0.31)
const STEM := Color(0.32, 0.53, 0.18)

static func build(kind: String, body_color: Color) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"R": _radish(surface)
		"R_detail": _radish_root(surface, body_color)
		"L": _lettuce(surface)
		"C": _carrot(surface)
		"C_detail": _carrot_root(surface, body_color)
		"H": _chamomile(surface)
		"H_detail": _chamomile_flowers(surface)
		"weed": _weeds(surface, body_color)
		"soil": _soil(surface, body_color)
	surface.index()
	return surface.commit()

static func _radish(surface: SurfaceTool) -> void:
	_stem(surface, Vector3(0, -0.49, 0), Vector3(0, 0.19, 0), 0.033)
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var radial := Vector3(sin(angle), 0, cos(angle))
		var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, 0.65)
		_oval(surface, Vector3(0.24, 0.43, 0.08), radial * 0.18 + Vector3(0, 0.24, 0),
			LEAF_LIGHT if i % 2 == 0 else LEAF, basis)

static func _radish_root(surface: SurfaceTool, body_color: Color) -> void:
	_oval(surface, Vector3(0.48, 0.51, 0.48), Vector3(0, -0.20, 0), body_color)
	_cone(surface, Vector3(0, -0.49, 0), Vector3(0, -0.24, 0), 0.015, 0.16, body_color.darkened(0.06))

static func _lettuce(surface: SurfaceTool) -> void:
	_oval(surface, Vector3(0.68, 0.64, 0.68), Vector3(0, -0.18, 0), LEAF)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var radial := Vector3(sin(angle), 0, cos(angle))
		var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, 0.58)
		_oval(surface, Vector3(0.39, 0.63, 0.18), radial * 0.26 + Vector3(0, 0.03, 0),
			LEAF_LIGHT if i % 2 == 0 else LEAF.lightened(0.05), basis)
	_oval(surface, Vector3(0.40, 0.53, 0.40), Vector3(0, 0.18, 0), Color(0.65, 0.81, 0.36))
	_oval(surface, Vector3(0.23, 0.31, 0.28), Vector3(0.04, 0.31, 0.02), LEAF_LIGHT)

static func _carrot(surface: SurfaceTool) -> void:
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var radial := Vector3(sin(angle), 0, cos(angle))
		var tip := radial * 0.25 + Vector3(0, 0.43, 0)
		_stem(surface, Vector3(0, -0.49, 0), tip, 0.018)
		var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, 0.5)
		for j in 3:
			var t := 0.38 + float(j) * 0.23
			_oval(surface, Vector3(0.24 - float(j) * 0.04, 0.13, 0.10), tip * t,
				LEAF_LIGHT if j == 2 else LEAF, basis)

static func _carrot_root(surface: SurfaceTool, body_color: Color) -> void:
	_cone(surface, Vector3(0, -0.49, 0), Vector3(0, -0.02, 0), 0.025, 0.19, body_color)
	_oval(surface, Vector3(0.38, 0.21, 0.38), Vector3(0, -0.02, 0), body_color.lightened(0.06))

static func _chamomile(surface: SurfaceTool) -> void:
	var heads := [Vector3(0, 0.40, 0), Vector3(-0.25, 0.18, 0.16), Vector3(0.23, 0.10, -0.19)]
	for i in heads.size():
		var head: Vector3 = heads[i]
		_stem(surface, Vector3(0, -0.49, 0), head, 0.024)
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var radial := Vector3(sin(angle), 0, cos(angle))
		_oval(surface, Vector3(0.12, 0.36, 0.075), radial * 0.13 + Vector3(0, -0.22, 0),
			LEAF, Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, 0.8))

static func _chamomile_flowers(surface: SurfaceTool) -> void:
	var heads := [Vector3(0, 0.40, 0), Vector3(-0.25, 0.18, 0.16), Vector3(0.23, 0.10, -0.19)]
	for i in heads.size():
		var head: Vector3 = heads[i]
		for petal in 6:
			var angle := TAU * float(petal) / 6.0
			var radial := Vector3(sin(angle), 0, cos(angle))
			_oval(surface, Vector3(0.10, 0.065, 0.21), head + radial * 0.115,
				Color(1.0, 0.98, 0.89), Basis(Vector3.UP, angle), 6, 2)
		_oval(surface, Vector3(0.15, 0.10, 0.15), head + Vector3(0, 0.028, 0), Color(1.0, 0.75, 0.12), Basis.IDENTITY, 6, 2)

static func _weeds(surface: SurfaceTool, body_color: Color) -> void:
	for i in 7:
		var angle := TAU * float(i) / 7.0
		var radial := Vector3(sin(angle), 0, cos(angle))
		var side := Vector3(cos(angle), 0, -sin(angle))
		var base := radial * 0.06 + Vector3(0, -0.5, 0)
		var middle := radial * 0.23 + Vector3(0, -0.08, 0)
		var tip := radial * 0.44 + Vector3(0, 0.49 - float(i % 3) * 0.14, 0)
		var ridge := middle + Vector3(0, 0.08, 0)
		var color := body_color.lightened(0.08) if i % 2 == 0 else body_color
		_triangle(surface, base, middle - side * 0.09, ridge, color)
		_triangle(surface, base, ridge, middle + side * 0.09, color.darkened(0.07))
		_triangle(surface, middle - side * 0.09, tip, ridge, color)
		_triangle(surface, ridge, tip, middle + side * 0.09, color.darkened(0.07))

static func _soil(surface: SurfaceTool, body_color: Color) -> void:
	var outline := PackedVector2Array([Vector2(-0.38, -0.49), Vector2(0.38, -0.49), Vector2(0.49, -0.38),
		Vector2(0.49, 0.38), Vector2(0.38, 0.49), Vector2(-0.38, 0.49), Vector2(-0.49, 0.38), Vector2(-0.49, -0.38)])
	for i in outline.size():
		var a := Vector3(outline[i].x, -0.26, outline[i].y)
		var b := Vector3(outline[(i + 1) % outline.size()].x, -0.26, outline[(i + 1) % outline.size()].y)
		_triangle(surface, Vector3(0, -0.26, 0), a, b, body_color)
		_triangle(surface, a, a - Vector3(0, 0.24, 0), b, body_color.darkened(0.10))
		_triangle(surface, b, a - Vector3(0, 0.24, 0), b - Vector3(0, 0.24, 0), body_color.darkened(0.10))
	for i in 5:
		_oval(surface, Vector3(0.15, 0.76, 0.87), Vector3(-0.34 + float(i) * 0.17, 0.12, 0),
			body_color.lightened(0.09 if i % 2 == 0 else 0.04))

static func _oval(surface: SurfaceTool, size: Vector3, center: Vector3, color: Color, basis := Basis.IDENTITY, radial := 10, rings := 4) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = radial
	mesh.rings = rings
	_append(surface, mesh, Transform3D(basis * Basis.from_scale(size), center), color)

static func _cone(surface: SurfaceTool, start: Vector3, end: Vector3, bottom: float, top: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 7
	mesh.rings = 1
	_append(surface, mesh, Transform3D(Basis(Quaternion(Vector3.UP, (end - start).normalized())), (start + end) * 0.5), color)

static func _stem(surface: SurfaceTool, start: Vector3, end: Vector3, radius: float) -> void:
	_cone(surface, start, end, radius, radius * 0.72, STEM)

static func _box(surface: SurfaceTool, size: Vector3, center: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(surface, mesh, Transform3D(Basis.IDENTITY, center), color)

static func _append(surface: SurfaceTool, mesh: PrimitiveMesh, transform: Transform3D, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := transform.basis.inverse().transposed()
	for index in indices:
		surface.set_color(color)
		surface.set_normal((normal_basis * normals[index]).normalized())
		surface.add_vertex(transform * vertices[index])

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for vertex in [a, b, c]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(vertex)
