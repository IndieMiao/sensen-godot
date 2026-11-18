extends RefCounted
## Mesh assembly from frozen masks; missing cells and holes are never filled.
const CHUNK := 32
const GROUND_SHADER = preload("res://modules/farm/shaders/meadow_woods.gdshader")
const MEADOW = preload("res://assets/farm/art/meadow.png")

static func build(data: Dictionary, walk: RefCounted, recipe: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "DynamicGround"
	var tops := {}
	var grids := {}
	var shaded := {}
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := {}
	var half: float = data.cell_m * 0.5
	for cell: Dictionary in data.cells:
		var at := Vector2i(cell.x, cell.y)
		var chunk := Vector2i(at.x / CHUNK, at.y / CHUNK)
		var key := "%d:%d:%d" % [chunk.x,chunk.y,cell.surface_id]
		if not tops.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tops[key] = {"tool":st,"chunk":chunk,"surface":cell.surface_id}
		var top: SurfaceTool = tops[key].tool
		var center: Vector3 = walk.point(at)
		var corners := [center + Vector3(-half,0,half), center + Vector3(half,0,half),
			center + Vector3(half,0,-half), center + Vector3(-half,0,-half)]
		_quad(top, corners[0],corners[3],corners[2],corners[1],Vector3.UP,data.palette[cell.kind])
		var directions := [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT]
		for edge in 4:
			var a: Vector3 = corners[edge]
			var b: Vector3 = corners[(edge+1)%4]
			if not data.by_cell.has(at + directions[edge]):
				var normal := Vector3(directions[edge].x, 0, -directions[edge].y)
				_quad(rim,a,b,b-Vector3.UP*0.7,a-Vector3.UP*0.7,normal,Color("958665"))
			if cell.zone == "core":
				if not grids.has(chunk):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					grids[chunk] = st
				var grid: SurfaceTool = grids[chunk]
				var other: Vector2i = at + directions[edge]
				var edge_key := "%d,%d:%d,%d" % [at.x,at.y,other.x,other.y] if at < other else "%d,%d:%d,%d" % [other.x,other.y,at.x,at.y]
				if not edges.has(edge_key):
					edges[edge_key] = true
					var perpendicular := (b-a).cross(Vector3.UP).normalized() * 0.005
					a.y = 0.008
					b.y = 0.008
					_quad(grid,a-perpendicular,b-perpendicular,b+perpendicular,a+perpendicular,Vector3.UP,Color("bda677"))
	for key: String in tops:
		var part: Dictionary = tops[key]
		var mesh := _add(root,part.tool,"Surface_" + key.replace(":","_"),false)
		mesh.material_override = _ground_material(part.surface, data, recipe)
		if not shaded.has(part.chunk): shaded[part.chunk] = []
		shaded[part.chunk].append(mesh)
	for chunk: Vector2i in grids:
		var mesh := _add(root,grids[chunk],"CoreGrid_%d_%d" % [chunk.x,chunk.y],false)
		mesh.material_override = _ground_material(3, data, recipe)
		shaded[chunk].append(mesh)
	_add(root,rim,"EarthEdge",true)
	var chunks: Array = []
	for chunk: Vector2i in shaded:
		var low: Vector2 = Vector2(chunk * CHUNK) - walk.center_grid
		var high: Vector2 = Vector2((chunk + Vector2i.ONE) * CHUNK).min(Vector2(data.grid_size)) - walk.center_grid
		var rect := Rect2(Vector2(low.x,-high.y)*data.cell_m, (high-low)*data.cell_m)
		chunks.append({"rect":rect,"meshes":shaded[chunk]})
	root.set_meta("shade_chunks",chunks)
	root.set_meta("cell_count",data.cells.size())
	root.set_meta("core_count",data.counts.core)
	return root

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	# Fix winding from the supplied normal instead of depending on an outline's orientation.
	var points: Array[Vector3] = [a,b,c,a,c,d]
	if (b-a).cross(c-a).dot(normal) > 0:
		points = [a,c,b,a,d,c]
	for p in points:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(p)

static func _add(parent: Node3D, st: SurfaceTool, node_name: String, shadows: bool) -> MeshInstance3D:
	st.index()
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.12
	mesh.material_override = material
	if not shadows:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

	return mesh

static func _ground_material(surface: int, data: Dictionary, recipe: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("meadow_texture",MEADOW)
	var grass := surface == 1
	var color := Color(recipe.surface.grass_srgb if grass else recipe.surface.core_warm_surface_srgb)
	if surface == 3: color = Color("bda677")
	material.set_shader_parameter("clearing_color",color)
	material.set_shader_parameter("mottle_warm",color)
	material.set_shader_parameter("mottle_cool",Color(recipe.surface.grass_far_srgb) if grass else color)
	material.set_shader_parameter("mottle",0.35 if grass else 1.0)
	material.set_shader_parameter("wander",0.06 if grass else 0.0)
	material.set_shader_parameter("strokes",0.07 if grass else 0.0)
	material.set_shader_parameter("woodland_start",100000.0)
	material.set_shader_parameter("floor_tint",Vector3.ONE)
	var extent: Vector2 = Vector2(data.grid_size) * data.cell_m * 0.5
	material.set_shader_parameter("yard",Vector4(-extent.x,-extent.y,extent.x,extent.y))
	return material
