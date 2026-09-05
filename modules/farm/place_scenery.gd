class_name PlaceScenery
extends RefCounted
## Static, collision-free place scenery. The caller owns navigation, lighting and residents.

const FarmProps = preload("res://modules/farm/farm_props.gd")
const CropPlantMesh = preload("res://modules/farm/crop_plant_mesh.gd")

const GRASS := Color("b8d8a0")
const LEAF := Color("709f65")
const PAPER := Color("fcfefa")
const GREEN := Color("287c59")
const CORAL := Color("ce705c")
const BLUE := Color("43869f")
const WOOD := Color("b99773")
const STONE := Color("d4ded5")
const SOIL := Color("7b6957")

static func build(place_id: String, state: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "PlaceScenery"
	root.set_meta("place_id", place_id)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ground(surface)
	match place_id:
		"nursery":
			var nursery: Dictionary = state.get("nursery", {})
			var stage := str(nursery.get("stage", "derelict"))
			var appearance := str(nursery.get("appearance", "a"))
			root.set_meta("nursery_stage", stage)
			root.set_meta("nursery_appearance", appearance)
			_nursery(surface, stage, appearance)
			root.add_child(FarmProps.build("storage", Vector3(-3.2, 0, -1.75), 1.25))
			root.add_child(FarmProps.build("well", Vector3(3.15, 0, -1.1), 1.5))
		"bistro":
			_bistro(surface)
			root.add_child(FarmProps.build("house", Vector3(-1.2, 0, -2.15), 1.65))
		"courtyard":
			_courtyard(surface)
			root.add_child(FarmProps.build("well", Vector3(0, 0.10, -1.3), 1.55))
	surface.index()
	var scenery := MeshInstance3D.new()
	scenery.name = "ArchitectureAndGarden"
	scenery.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	scenery.material_override = material
	root.add_child(scenery)
	return root

static func _ground(s: SurfaceTool) -> void:
	_cylinder(s, 1.0, 0.14, Vector3(0, -0.07, 0), GRASS, Vector3(5, 1, 4), 40)
	_box(s, Vector3(1.35, 0.025, 5.8), Vector3(0, 0.0125, 0.9), STONE)
	for index in 9:
		_box(s, Vector3(1.28, 0.008, 0.017), Vector3(0, 0.029, -1.6 + index * 0.64), STONE.darkened(0.08))
	for side in [-1.0, 1.0]:
		_tree(s, Vector3(side * 3.25, 0, -2.45), 0.9 if side < 0 else 1.1)
		_planter(s, Vector3(side * 3.1, 0, 1.65), Vector2(1.2, 0.68), BLUE if side < 0 else CORAL)
		_plants(s, "H", [Vector3(side * 3.1 - 0.28, 0.53, 1.65), Vector3(side * 3.1 + 0.28, 0.53, 1.65)], 0.55)
	for x in [-2.5, -1.5, -0.5, 0.5, 1.5, 2.5]:
		_box(s, Vector3(0.10, 0.68, 0.10), Vector3(x, 0.34, -3.25), PAPER.darkened(0.08))
	for y in [0.25, 0.52]:
		_box(s, Vector3(5.1, 0.08, 0.08), Vector3(0, y, -3.25), PAPER.darkened(0.04))

static func _nursery(s: SurfaceTool, stage: String, appearance: String) -> void:
	var center := Vector3(0, 0, -1.85)
	_box(s, Vector3(4.4, 0.12, 2.6), center + Vector3(0, 0.06, 0), STONE)
	_box(s, Vector3(4.1, 0.025, 2.3), center + Vector3(0, 0.1325, 0), STONE.lightened(0.13))
	if stage == "derelict":
		for side in [-1.0, 1.0]:
			_beam(s, center + Vector3(side * 1.9, 0.1, -0.9), center + Vector3(side * 2.0, 1.25, -0.9), 0.13, WOOD.darkened(0.18))
			_box(s, Vector3(1.55, 0.10, 0.16), center + Vector3(side * 0.65, 0.23, 0.65), WOOD.darkened(0.12), Basis(Vector3.UP, side * 0.38))
			_planter(s, center + Vector3(side * 1.25, 0.13, -0.3), Vector2(0.85, 1.2), STONE.darkened(0.18))
		_plants(s, "weed", [center + Vector3(-1.35, 0.55, -0.3), center + Vector3(1.2, 0.55, -0.45),
			center + Vector3(-0.45, 0.4, 0.25), center + Vector3(0.6, 0.45, 0.75), center + Vector3(1.65, 0.42, 0.55)], 0.75)
		for i in 5:
			_oval(s, Vector3(0.22 + i * 0.025, 0.15, 0.20), center + Vector3(-0.85 + i * 0.42, 0.2, -0.95 + (i % 2) * 0.2), STONE.darkened(0.25))
		return
	var accent := CORAL if appearance == "b" else GREEN
	for side in [-1.0, 1.0]:
		_planter(s, center + Vector3(side * 1.28, 0.14, 0), Vector2(0.92, 1.65), accent if stage == "built" else WOOD)
		for z in [-0.78, 0.88]:
			_box(s, Vector3(0.13, 1.8 if stage == "built" else 0.72, 0.13),
				center + Vector3(side * 1.95, 1.04 if stage == "built" else 0.50, z), WOOD)
	if stage != "built":
		for index in 3:
			_box(s, Vector3(1.25, 0.075, 0.15), center + Vector3(-0.15, 0.2 + index * 0.077, -0.76), WOOD)
		for x in [-0.38, 0.06, 0.5]:
			_pot(s, center + Vector3(x, 0.14, 0.5), 0.17, CORAL)
		return
	for side in [-1.0, 1.0]:
		var points: Array[Vector3] = []
		for z in [-0.5, 0.05, 0.6]: points.append(center + Vector3(side * 1.28, 0.68, z))
		_plants(s, "H" if appearance == "b" else "L", points, 0.68)
		_box(s, Vector3(0.14, 0.13, 2.08), center + Vector3(side * 1.95, 1.95, 0.04), accent)
	for z in [-0.94, 1.02]:
		for side in [-1.0, 1.0]:
			_beam(s, center + Vector3(side * 2.05, 1.96, z), center + Vector3(0, 2.65, z), 0.12, accent)
	_box(s, Vector3(0.14, 0.12, 2.12), center + Vector3(0, 2.65, 0.04), accent)
	for index in 9:
		var x := -1.8 + index * 0.45
		var y := 2.65 - absf(x) * 0.337
		_box(s, Vector3(0.25 if appearance == "a" else 0.44, 0.035, 2.08), center + Vector3(x, y, 0.04),
			PAPER if index % 2 == 0 else accent.lightened(0.42), Basis(Vector3.BACK, -signf(x) * 0.325))
	_box(s, Vector3(0.72, 0.24, 0.07), center + Vector3(0, 2.31, 1.09), PAPER)
	_oval(s, Vector3(0.12, 0.15, 0.055), center + Vector3(-0.045, 2.32, 1.14), GREEN, Basis(Vector3.BACK, 0.4))
	_oval(s, Vector3(0.12, 0.15, 0.055), center + Vector3(0.045, 2.32, 1.14), GREEN, Basis(Vector3.BACK, -0.4))

static func _bistro(s: SurfaceTool) -> void:
	_box(s, Vector3(6.4, 0.09, 2.6), Vector3(0.25, 0.045, -0.6), STONE.lightened(0.06))
	for index in 11:
		_box(s, Vector3(0.025, 0.006, 2.52), Vector3(-2.7 + index * 0.59, 0.094, -0.6), STONE.darkened(0.13))
	for side in [-1.0, 1.0]:
		_box(s, Vector3(0.09, 1.92, 0.09), Vector3(-1.2 + side * 1.32, 0.96, -0.25), WOOD)
	for index in 9:
		var x := -2.4 + index * 0.3
		_box(s, Vector3(0.3, 0.05, 1.18), Vector3(x, 1.96, -0.76), CORAL if index % 2 == 0 else PAPER, Basis(Vector3.RIGHT, -0.12))
		_box(s, Vector3(0.3, 0.19, 0.06), Vector3(x, 1.81, -0.17), CORAL if index % 2 == 0 else PAPER)
	_box(s, Vector3(1.65, 0.7, 0.52), Vector3(-1.1, 0.44, -0.7), GREEN)
	_box(s, Vector3(1.83, 0.09, 0.66), Vector3(-1.1, 0.835, -0.7), WOOD)
	for x in [-1.62, -1.12, -0.62]:
		_cylinder(s, 0.15, 0.025, Vector3(x, 0.9, -0.7), PAPER)
		_oval(s, Vector3(0.19, 0.13, 0.15), Vector3(x, 0.96, -0.7), CORAL.lightened(0.27))
	for z in [-1.65, 0.30]:
		_table(s, Vector3(2.0, 0.095, z))
		for side in [-1.0, 1.0]: _chair(s, Vector3(2.0 + side * 0.81, 0.095, z), side)
	_planter(s, Vector3(-2.7, 0.1, 0.8), Vector2(0.55, 0.55), BLUE)
	_plants(s, "H", [Vector3(-2.7, 0.63, 0.8)], 0.65)

static func _courtyard(s: SurfaceTool) -> void:
	_cylinder(s, 1.35, 0.07, Vector3(0, 0.035, -1.3), STONE, Vector3.ONE, 32)
	_cylinder(s, 0.85, 0.04, Vector3(0, 0.09, -1.3), BLUE.lightened(0.48), Vector3.ONE, 24)
	for side in [-1.0, 1.0]:
		_planter(s, Vector3(side * 2.1, 0, -2.1), Vector2(1.5, 1.3), PAPER.darkened(0.08))
		_plants(s, "H", [Vector3(side * 2.1 - 0.35, 0.55, -2.3), Vector3(side * 2.1 + 0.3, 0.55, -1.95)], 0.8)
		_box(s, Vector3(0.10, 2.05, 0.10), Vector3(side * 1.35, 1.025, -2.7), GREEN)
	_box(s, Vector3(2.95, 0.14, 0.25), Vector3(0, 2.03, -2.7), GREEN)
	for index in 7:
		_box(s, Vector3(0.10, 0.12, 0.65), Vector3(-1.32 + index * 0.44, 2.15, -2.7), WOOD)
	for side in [-1.0, 1.0]:
		_oval(s, Vector3(0.9, 0.36, 0.58), Vector3(side * 0.98, 2.3, -2.7), LEAF)
		_bench(s, Vector3(side * 2.25, 0, 0.25), CORAL if side > 0 else BLUE)
	_blueprint_table(s, Vector3(-1.9, 0, -0.8))

static func _blueprint_table(s: SurfaceTool, center: Vector3) -> void:
	for side in [-1.0, 1.0]:
		_box(s, Vector3(0.11, 0.8, 0.58), center + Vector3(side * 0.54, 0.4, 0), WOOD)
	_box(s, Vector3(1.5, 0.08, 1.0), center + Vector3(0, 0.84, 0), WOOD)
	_box(s, Vector3(1.34, 0.016, 0.85), center + Vector3(0, 0.89, 0), BLUE)
	for index in 7:
		_box(s, Vector3(0.008, 0.003, 0.81), center + Vector3(-0.6 + index * 0.2, 0.901, 0), BLUE.lightened(0.35))
	for index in 5:
		_box(s, Vector3(1.28, 0.003, 0.008), center + Vector3(0, 0.901, -0.38 + index * 0.19), BLUE.lightened(0.35))
	for side in [-1.0, 1.0]:
		_box(s, Vector3(0.28, 0.09, 0.48), center + Vector3(side * 0.35, 0.95, 0), PAPER)
		for front in [-1.0, 1.0]:
			_box(s, Vector3(0.025, 0.29, 0.025), center + Vector3(side * 0.53, 1.05, front * 0.31), PAPER)
		_beam(s, center + Vector3(side * 0.56, 1.2, -0.32), center + Vector3(0, 1.4, -0.32), 0.025, PAPER)
		_beam(s, center + Vector3(side * 0.56, 1.2, 0.32), center + Vector3(0, 1.4, 0.32), 0.025, PAPER)
	_box(s, Vector3(0.025, 0.025, 0.7), center + Vector3(0, 1.4, 0), PAPER)

static func _planter(s: SurfaceTool, center: Vector3, size: Vector2, color: Color) -> void:
	_box(s, Vector3(size.x, 0.31, size.y), center + Vector3(0, 0.155, 0), color)
	_box(s, Vector3(size.x - 0.11, 0.012, size.y - 0.11), center + Vector3(0, 0.316, 0), SOIL)
	for side in [-1.0, 1.0]:
		_box(s, Vector3(size.x + 0.04, 0.045, 0.065), center + Vector3(0, 0.33, side * (size.y * 0.5 - 0.025)), color.lightened(0.13))
		_box(s, Vector3(0.065, 0.045, size.y + 0.04), center + Vector3(side * (size.x * 0.5 - 0.025), 0.33, 0), color.lightened(0.13))

static func _pot(s: SurfaceTool, center: Vector3, radius: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius * 0.72
	mesh.top_radius = radius
	mesh.height = radius * 1.55
	mesh.radial_segments = 10
	_append(s, mesh, Transform3D(Basis.IDENTITY, center + Vector3(0, radius * 0.775, 0)), color)
	_cylinder(s, radius * 1.06, 0.055, center + Vector3(0, radius * 1.48, 0), color.lightened(0.1))
	_cylinder(s, radius * 0.79, 0.008, center + Vector3(0, radius * 1.65, 0), SOIL)

static func _table(s: SurfaceTool, center: Vector3) -> void:
	_cylinder(s, 0.29, 0.07, center + Vector3(0, 0.035, 0), GREEN)
	_cylinder(s, 0.065, 0.72, center + Vector3(0, 0.4, 0), GREEN)
	_cylinder(s, 0.6, 0.09, center + Vector3(0, 0.78, 0), WOOD.lightened(0.18), Vector3.ONE, 24)
	for side in [-1.0, 1.0]:
		_cylinder(s, 0.15, 0.018, center + Vector3(side * 0.3, 0.835, 0), PAPER)
		_cylinder(s, 0.062, 0.11, center + Vector3(side * 0.3, 0.892, 0), CORAL)
	_pot(s, center + Vector3(0, 0.83, 0), 0.075, BLUE)
	_plants(s, "H", [center + Vector3(0, 1.03, 0)], 0.2)

static func _chair(s: SurfaceTool, center: Vector3, side: float) -> void:
	for x in [-0.17, 0.17]:
		for z in [-0.17, 0.17]:
			_box(s, Vector3(0.055, 0.41, 0.055), center + Vector3(x, 0.205, z), WOOD)
	_box(s, Vector3(0.46, 0.075, 0.46), center + Vector3(0, 0.435, 0), CORAL)
	for z in [-0.17, 0.17]:
		_box(s, Vector3(0.05, 0.73, 0.05), center + Vector3(side * 0.20, 0.365, z), WOOD)
	_box(s, Vector3(0.07, 0.21, 0.46), center + Vector3(side * 0.20, 0.69, 0), CORAL)

static func _bench(s: SurfaceTool, center: Vector3, color: Color) -> void:
	for x in [-0.52, 0.52]:
		_box(s, Vector3(0.12, 0.4, 0.48), center + Vector3(x, 0.2, 0), STONE.darkened(0.25))
		_box(s, Vector3(0.07, 0.82, 0.07), center + Vector3(x, 0.41, -0.22), WOOD)
	for z in [-0.16, 0.0, 0.16]:
		_box(s, Vector3(1.5, 0.075, 0.13), center + Vector3(0, 0.44, z), WOOD)
	for y in [0.61, 0.77]:
		_box(s, Vector3(1.5, 0.12, 0.07), center + Vector3(0, y, -0.22), color)

static func _tree(s: SurfaceTool, center: Vector3, scale: float) -> void:
	_beam(s, center, center + Vector3(0, 1.9, 0) * scale, 0.18 * scale, WOOD.darkened(0.16))
	for side in [-1.0, 1.0]:
		_beam(s, center + Vector3(0, 1.1, 0) * scale, center + Vector3(side * 0.4, 1.85, 0) * scale, 0.09 * scale, WOOD.darkened(0.16))
	_oval(s, Vector3(1.65, 1.3, 1.45) * scale, center + Vector3(0, 2.08, 0) * scale, LEAF)
	_oval(s, Vector3(1.0, 0.9, 1.0) * scale, center + Vector3(-0.3, 2.5, 0.12) * scale, LEAF.lightened(0.12))

static func _plants(s: SurfaceTool, kind: String, points: Array[Vector3], scale: float) -> void:
	var mesh := CropPlantMesh.build(kind, LEAF)
	var detail := CropPlantMesh.build("H_detail", PAPER) if kind == "H" else null
	for point in points:
		var transform := Transform3D(Basis.from_scale(Vector3.ONE * scale), point)
		_append(s, mesh, transform, Color.WHITE, true)
		if detail != null: _append(s, detail, transform, Color.WHITE, true)

static func _box(s: SurfaceTool, size: Vector3, center: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(s, mesh, Transform3D(basis, center), color)

static func _cylinder(s: SurfaceTool, radius: float, height: float, center: Vector3, color: Color, scale := Vector3.ONE, segments := 12) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	_append(s, mesh, Transform3D(Basis.from_scale(scale), center), color)

static func _oval(s: SurfaceTool, size: Vector3, center: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 4
	_append(s, mesh, Transform3D(basis * Basis.from_scale(size), center), color)

static func _beam(s: SurfaceTool, start: Vector3, end: Vector3, width: float, color: Color) -> void:
	_box(s, Vector3(width, start.distance_to(end), width), (start + end) * 0.5, color,
		Basis(Quaternion(Vector3.UP, (end - start).normalized())))

static func _append(s: SurfaceTool, mesh: Mesh, transform: Transform3D, color: Color, preserve_colors := false) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if preserve_colors else PackedColorArray()
	var normal_basis := transform.basis.inverse().transposed()
	for index in indices:
		s.set_color(colors[index] if preserve_colors else color)
		s.set_normal((normal_basis * normals[index]).normalized())
		s.add_vertex(transform * vertices[index])
