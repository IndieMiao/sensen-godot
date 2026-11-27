extends RefCounted
## Mesh assembly from frozen masks; missing cells and holes are never filled.
const CHUNK := 32
const Edges = preload("res://modules/dynamic_farm/farm_edges.gd")
const Spill = preload("res://modules/dynamic_farm/core_grass_edge.gd")
const Bank = preload("res://modules/dynamic_farm/farm_bank.gd")
const GROUND_SHADER = preload("res://modules/dynamic_farm/parcel_ground.gdshader")
const PIGMENTS = preload("res://assets/dynamic_farm/fieldkit/field_pigments.png")
const EARTH := Color("a8845c") # inner hole walls, warm like the island cliff

static func build(data: Dictionary, walk: RefCounted, recipe: Dictionary, soften := true, widen := false, slope_gain := 0.65) -> Node3D:
	var root := Node3D.new()
	root.name = "DynamicGround"
	var tops := {}
	var slopes := {}
	var grids := {}
	var shaded := {}
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := {}
	var half: float = data.cell_m * 0.5
	var exterior := Bank.exterior(data) if soften else {}
	var seed_phase := Bank.phase(data)
	var soil_colour := Color(recipe.surface.core_warm_surface_srgb).lerp(Color(recipe.surface.grass_far_srgb),0.35).darkened(0.12)
	var noise := Spill.noise_for(data.get("seed_hex", "00000000"))
	var masks := {}
	for at: Vector2i in data.by_cell:
		var sides := Spill.mask(data.by_cell, at)
		if sides: masks[at] = sides
	var bank_spans: Array=[]
	for cell: Dictionary in data.cells:
		var at := Vector2i(cell.x, cell.y)
		var chunk := Vector2i(at.x / CHUNK, at.y / CHUNK)
		var key := "%d:%d:%d" % [chunk.x,chunk.y,cell.surface_id]
		var top := _top_tool(tops, key, chunk, cell.surface_id)
		var center: Vector3 = walk.point(at)
		var corners := [center + Vector3(-half,0,half), center + Vector3(half,0,half),
			center + Vector3(half,0,-half), center + Vector3(-half,0,-half)]
		if masks.has(at):
			var soil_key := "%d:%d:%d" % [chunk.x, chunk.y, Spill.SOIL]
			var soil := _top_tool(tops, soil_key, chunk, Spill.SOIL)
			soil.set_color(data.palette.soil)
			top.set_color(data.palette[cell.kind])
			Spill.emit(soil, top, corners, at, masks, noise)
		else:
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
					var slope_top:=_slope_tool(slopes,key,chunk,cell.surface_id,top,slope_gain)
					bank_spans.append({"top":slope_top,"soil":rim,"a":a,"b":b,"oa":outside_a,"ob":outside_b,
						"normal":normal,"phase":seed_phase,"colour":soil_colour,"segments":Bank.SEGMENTS})
				else:
					_quad(rim,outside_a,outside_b,outside_b-Vector3.UP*0.7,outside_a-Vector3.UP*0.7,normal,EARTH)
				if soften and Edges.convex(data,at,edge):
					var pad: float = data.cell_m * Edges.PAD_CELLS
					var previous := Edges.normal((edge+3)%4)
					var last: Vector3 = a+previous*pad
					for step in range(1,5):
						var next: Vector3 = a+(Edges.normal(edge) if step==4 else previous.rotated(Vector3.UP,float(step)*PI/8.0))*pad
						if rolled:
							var slope_top:=_slope_tool(slopes,key,chunk,cell.surface_id,top,slope_gain)
							bank_spans.append({"top":slope_top,"soil":rim,"a":a,"b":a,"oa":last,"ob":next,
								"normal":(next-last).cross(Vector3.UP).normalized(),"phase":seed_phase,"colour":soil_colour,"segments":1})
						else:
							_triangle(top,a,last,next,Vector3.UP,data.palette[cell.kind])
							_quad(rim,last,next,next-Vector3.UP*0.7,last-Vector3.UP*0.7,(next-last).cross(Vector3.UP).normalized(),EARTH)
						last=next
			# The soil outline replaces the rule along a spilled core edge.
			if cell.zone == "core" and not (int(masks.get(at + directions[edge], 0)) & (1 << ((edge + 2) % 4))):
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
	var bank_metrics:=Bank.emit(bank_spans,data,walk.center_grid,widen)
	var padding:float=Bank.LOWER_CELLS if bank_metrics.expanded_pieces>0 else Edges.PAD_CELLS
	root.set_meta("bank_metrics",bank_metrics)
	root.set_meta("shade_padding_cells",padding)
	for key: String in tops:
		var part: Dictionary = tops[key]
		var mesh := _add(root,part.tool,"Surface_" + key.replace(":","_"),false)
		mesh.material_override = _ground_material(part.surface, data, recipe)
		if not shaded.has(part.chunk): shaded[part.chunk] = []
		shaded[part.chunk].append(mesh)
	for key:String in slopes:
		var part:Dictionary=slopes[key]
		var mesh:=_add(root,part.tool,"Slope_"+key.replace(":","_"),false)
		var material:=_ground_material(part.surface,data,recipe)
		var base:Color=material.get_shader_parameter("clearing_color")
		material.set_meta("original_clearing_color",base)
		material.set_meta("clearing_linear_gain",slope_gain)
		var linear:=base.srgb_to_linear()
		linear.r*=slope_gain
		linear.g*=slope_gain
		linear.b*=slope_gain
		linear.a=1.0
		material.set_shader_parameter("clearing_color",linear.linear_to_srgb())
		mesh.material_override=material
		shaded[part.chunk].append(mesh)
	for chunk: Vector2i in grids:
		var mesh := _add(root,grids[chunk],"CoreGrid_%d_%d" % [chunk.x,chunk.y],false)
		mesh.material_override = _ground_material(3, data, recipe)
		mesh.hide()
		shaded[chunk].append(mesh)
	_add(root,rim,"EarthEdge",true)
	var chunks: Array = []
	for chunk: Vector2i in shaded:
		var low: Vector2 = Vector2(chunk * CHUNK) - walk.center_grid
		var high: Vector2 = Vector2((chunk + Vector2i.ONE) * CHUNK).min(Vector2(data.grid_size)) - walk.center_grid
		var rect := Rect2(Vector2(low.x,-high.y)*data.cell_m, (high-low)*data.cell_m)
		chunks.append({"key":chunk,"rect":rect.grow(data.cell_m*padding) if soften else rect,"meshes":shaded[chunk]})
	root.set_meta("shade_chunks",chunks)
	root.set_meta("cell_count",data.cells.size())
	root.set_meta("core_count",data.counts.core)
	root.set_meta("visual_pad_cells",Edges.PAD_CELLS if soften else 0.0)
	root.set_meta("maximum_corner_offset_cells",sqrt(2.0)*Edges.PAD_CELLS if soften else 0.0)
	root.set_meta("slope_material_linear_gain",slope_gain)
	root.set_meta("slope_batches",slopes.size())
	return root

static func _top_tool(tops: Dictionary, key: String, chunk: Vector2i, surface: int) -> SurfaceTool:
	if not tops.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tops[key] = {"tool":st, "chunk":chunk, "surface":surface}
	return tops[key].tool

static func _slope_tool(slopes: Dictionary, key: String, chunk: Vector2i, surface: int, original: SurfaceTool, gain: float) -> SurfaceTool:
	if is_equal_approx(gain,1.0):return original
	if not slopes.has(key):
		var tool:=SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		slopes[key]={"tool":tool,"chunk":chunk,"surface":surface}
	return slopes[key].tool

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
	material.set_shader_parameter("pigments", PIGMENTS)
	material.set_shader_parameter("parcel_metres", Vector2(data.grid_size) * data.cell_m)
	material.set_shader_parameter("grid_overlay", surface == 3)
	material.set_shader_parameter("clearing_color", Color(recipe.surface.core_grid_srgb) if surface == 3 else Color.WHITE)
	return material
