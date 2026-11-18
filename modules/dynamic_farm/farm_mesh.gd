extends RefCounted
## Mesh assembly from frozen masks; missing cells and holes are never filled.
const CHUNK := 32
const Edges = preload("res://modules/dynamic_farm/farm_edges.gd")
const Bank = preload("res://modules/dynamic_farm/farm_bank.gd")
const GROUND_SHADER = preload("res://modules/farm/shaders/meadow_woods.gdshader")
const MEADOW = preload("res://assets/farm/art/meadow.png")

static func build(data: Dictionary, walk: RefCounted, recipe: Dictionary, soften := true) -> Node3D:
	var root := Node3D.new()
	root.name = "DynamicGround"
	var tops := {}
	var grids := {}
	var shaded := {}
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := {}
	var half: float = data.cell_m * 0.5
	var exterior := Bank.exterior(data) if soften else {}
	var seed_phase := Bank.phase(data)
	var soil_colour := Color(recipe.surface.core_warm_surface_srgb).lerp(Color(recipe.surface.grass_far_srgb),0.35).darkened(0.12)
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
		var directions: Array = Edges.NEIGHBORS
		for edge in 4:
			var a: Vector3 = corners[edge]
			var b: Vector3 = corners[(edge+1)%4]
			if not data.by_cell.has(at + directions[edge]):
				var rolled := soften and Bank.is_exterior(exterior,at+directions[edge])
				var outside_a := a
				var outside_b := b
				if soften:
					var pad: float = data.cell_m * Edges.PAD_CELLS
					outside_a = Edges.endpoint(data,at,edge,(edge+3)%4,a,pad)
					outside_b = Edges.endpoint(data,at,edge,(edge+1)%4,b,pad)
					if not rolled: _quad(top,a,b,outside_b,outside_a,Vector3.UP,data.palette[cell.kind])
				var normal := (outside_b-outside_a).cross(Vector3.UP).normalized()
				if rolled:
					Bank.append(top,rim,a,b,outside_a,outside_b,normal,seed_phase,soil_colour)
				else:
					_quad(rim,outside_a,outside_b,outside_b-Vector3.UP*0.7,outside_a-Vector3.UP*0.7,normal,Color("958665"))
				if soften and Edges.convex(data,at,edge):
					var pad: float = data.cell_m * Edges.PAD_CELLS
					var previous := Edges.normal((edge+3)%4)
					var last: Vector3 = a+previous*pad
					for step in range(1,5):
						var next: Vector3 = a+(Edges.normal(edge) if step==4 else previous.rotated(Vector3.UP,float(step)*PI/8.0))*pad
						if rolled:
							Bank.append(top,rim,a,a,last,next,(next-last).cross(Vector3.UP).normalized(),seed_phase,soil_colour,1)
						else:
							_triangle(top,a,last,next,Vector3.UP,data.palette[cell.kind])
							_quad(rim,last,next,next-Vector3.UP*0.7,last-Vector3.UP*0.7,(next-last).cross(Vector3.UP).normalized(),Color("958665"))
						last=next
			if cell.zone == "core":
				if not grids.has(chunk):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					grids[chunk] = st
				var grid: SurfaceTool = grids[chunk]
				var edge_key := Edges.vertex_key(at+Edges.CORNERS[edge],at+Edges.CORNERS[(edge+1)%4])
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
		chunks.append({"key":chunk,"rect":rect.grow(data.cell_m*Edges.PAD_CELLS) if soften else rect,"meshes":shaded[chunk]})
	root.set_meta("shade_chunks",chunks)
	root.set_meta("cell_count",data.cells.size())
	root.set_meta("core_count",data.counts.core)
	root.set_meta("visual_pad_cells",Edges.PAD_CELLS if soften else 0.0)
	root.set_meta("maximum_corner_offset_cells",sqrt(2.0)*Edges.PAD_CELLS if soften else 0.0)
	return root

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (b-a).cross(c-a).length_squared() < 0.000000000001: return
	var points: Array[Vector3] = [a,b,c]
	if (b-a).cross(c-a).dot(normal)>0: points=[a,c,b]
	for point in points:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(point)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	_triangle(st,a,b,c,normal,color)
	_triangle(st,a,c,d,normal,color)

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
