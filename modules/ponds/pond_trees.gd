extends RefCounted
## Pond-only cloud crowns and flared roots; two shared draws for all six trees.
static var _crown: ArrayMesh
static var _wood: ArrayMesh

static func build(transforms: Array) -> Node3D:
	if _crown == null: _build_meshes()
	var root := Node3D.new()
	root.name = "PondTrees"
	for kind in ["Crown", "Trunk"]:
		var node := MultiMeshInstance3D.new()
		node.name = kind
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.mesh = _crown if kind == "Crown" else _wood
		node.multimesh.instance_count = transforms.size()
		for i in transforms.size(): node.multimesh.set_instance_transform(i, transforms[i])
		var material := ShaderMaterial.new()
		material.shader = preload("res://modules/ponds/pond_tree.gdshader")
		material.set_shader_parameter("foliage", kind == "Crown")
		node.material_override = material
		root.add_child(node)
	return root

static func _ellipsoid(surface: SurfaceTool, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 28
	mesh.rings = 16
	PlaceScenery._append(surface, mesh, Transform3D(Basis.from_scale(size), at), color.srgb_to_linear())

static func _build_meshes() -> void:
	var crown := SurfaceTool.new()
	var wood := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	wood.set_normal(Vector3.UP)
	# Distinct overlapping lobes, not the old three elongated canopy masses.
	_ellipsoid(crown, Vector3(0,1.83,0), Vector3(1.25,1.12,1.18), Color("819d3d"))
	for i in 7:
		var a := TAU * i / 7.0
		var at := Vector3(cos(a)*.53, 1.62 + sin(a*2.0)*.15, sin(a)*.49)
		var color := Color("8da942").lerp(Color("a0b84c"), float(i%3)*.35)
		_ellipsoid(crown, at, Vector3(.85,.96,.87), color)
	for i in 4:
		var a := TAU * i / 4.0 + .38
		_ellipsoid(crown, Vector3(cos(a)*.36,2.16+sin(a)*.10,sin(a)*.33), Vector3(.94,.93,.91), Color("9ab347").lerp(Color("a9bd54"),float(i%2)*.35))
	_ellipsoid(crown, Vector3(-.07,2.41,.02), Vector3(.86,.70,.84), Color("a4bb4d"))
	# A fluted trunk grows into five buttress roots; the base is visibly wood.
	var heights := [0.0,.045,.11,.21,.38,.65,1.03,1.48]
	var radii := [.235,.23,.205,.172,.148,.13,.11,.082]
	for ring in heights.size()-1:
		for segment in 32:
			var points: Array[Vector3] = []
			for corner in [Vector2(segment,ring),Vector2(segment+1,ring),Vector2(segment+1,ring+1),Vector2(segment,ring+1)]:
				var band := int(corner.y)
				var a: float = corner.x / 32.0 * TAU
				var radius: float = radii[band] * (1.0 + cos(a*5.0)*(.14 if band < 3 else .065))
				points.append(Vector3(cos(a)*radius + sin(heights[band]*1.8)*.045,heights[band],sin(a)*radius))
			for index in [0,1,2,0,2,3]:
				wood.set_color(Color("987043").srgb_to_linear())
				wood.add_vertex(points[index])
	for i in 5:
		var a := i * TAU/5.0
		_ellipsoid(wood, Vector3(cos(a)*.19,.035,sin(a)*.19), Vector3(.19,.12,.18), Color("987043"))
		var start := Vector3(0,.92,0)
		var end := Vector3(cos(a)*.39,1.53,sin(a)*.39)
		var limb := CylinderMesh.new()
		limb.bottom_radius = .085
		limb.top_radius = .036
		limb.height = start.distance_to(end)
		limb.radial_segments = 12
		PlaceScenery._append(wood,limb,Transform3D(Basis(Quaternion(Vector3.UP,(end-start).normalized())),(start+end)*.5),Color("987043").srgb_to_linear())
	wood.generate_normals()
	wood.index()
	crown.index()
	_wood = wood.commit()
	_crown = crown.commit()
