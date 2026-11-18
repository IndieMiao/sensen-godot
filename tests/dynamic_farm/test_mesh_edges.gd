extends SceneTree
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + label)

func _key(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x,a.y,b.x,b.y) if a < b else Vector4i(b.x,b.y,a.x,a.y)

func _point(v: Vector3, walk: RefCounted) -> Vector2:
	return Vector2(v.x,-v.z)/walk.cell_m+walk.center_grid

func _arrays(mesh: Mesh) -> Array:
	return mesh.surface_get_arrays(0)

func _run() -> void:
	var legacy := OS.get_cmdline_user_args().has("--legacy")
	var script = load("res://old_farm_mesh.gd" if legacy else "res://modules/dynamic_farm/farm_mesh.gd")
	var recipe = JSON.parse_string(FileAccess.get_file_as_string("res://assets/dynamic_farm/499-art-recipe.json"))
	var cases := [
		{"name":"horizontal2x1","cells":[Vector2i(0,0),Vector2i(1,0)],"size":Vector2i(2,1),"rim":6,"grid":7},
		{"name":"vertical1x2","cells":[Vector2i(0,0),Vector2i(0,1)],"size":Vector2i(1,2),"rim":6,"grid":7},
		{"name":"L","cells":[Vector2i(0,0),Vector2i(1,0),Vector2i(0,1)],"size":Vector2i(2,2),"rim":8,"grid":10},
		{"name":"hole","cells":[Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(0,1),Vector2i(2,1),Vector2i(0,2),Vector2i(1,2),Vector2i(2,2)],"size":Vector2i(3,3),"rim":16,"grid":24}]
	for fixture in cases:
		var data := {"cell_m":1.0,"grid_size":fixture.size,"origin":Vector2i.ZERO,"spawn":fixture.cells[0],
			"by_cell":{},"cells":[],"counts":{"core":fixture.cells.size()},"palette":{"soil":Color("dcc79a")}}
		# Reference boundary: cancel shared geometric square segments, without consulting a neighbor direction table.
		var multiplicity := {}
		var expected_normals := {}
		for at: Vector2i in fixture.cells:
			var row := {"x":at.x,"y":at.y,"kind":"soil","surface_id":0,"zone":"core"}
			data.cells.append(row)
			data.by_cell[at]=row
			var vertices := [at,at+Vector2i(1,0),at+Vector2i(1,1),at+Vector2i(0,1)]
			for i in 4:
				var key := _key(vertices[i],vertices[(i+1)%4])
				multiplicity[key]=multiplicity.get(key,0)+1
				var outward := (Vector2(vertices[i])+Vector2(vertices[(i+1)%4]))*0.5-Vector2(at)-Vector2.ONE*0.5
				expected_normals[key]=Vector3(outward.x,0,-outward.y).normalized()
		var expected := {}
		for key: Vector4i in multiplicity:
			if multiplicity[key]==1: expected[key]=true
		_check(expected.size()==fixture.rim and multiplicity.size()==fixture.grid,fixture.name+" golden reference counts")
		var walk := Walk.new(data)
		var root = script.build(data,walk,recipe) if legacy else script.build(data,walk,recipe,false)
		var arrays := _arrays(root.get_node("EarthEdge").mesh)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var actual := {}
		var normals_ok := true
		var winding_ok := true
		for index in range(0,indices.size(),6):
			var tops: Array[Vector2i] = []
			for j in 6:
				var v := vertices[indices[index+j]]
				if absf(v.y) < 0.00001:
					var p := _point(v,walk)
					var q := Vector2i(roundi(p.x),roundi(p.y))
					if q not in tops: tops.append(q)
			if tops.size()!=2:
				normals_ok=false
				continue
			var key := _key(tops[0],tops[1])
			actual[key]=true
			if not expected.has(key) or normals[indices[index]].dot(expected_normals[key]) < 0.9999: normals_ok=false
			var a := vertices[indices[index]]
			var b := vertices[indices[index+1]]
			var c := vertices[indices[index+2]]
			if (b-a).cross(c-a).dot(normals[indices[index]]) >= 0: winding_ok=false
		_check(actual==expected,fixture.name+" exact exterior walls, no interior walls")
		_check(normals_ok and winding_ok,fixture.name+" outward normals and clockwise winding")
		var actual_grid := {}
		var grid_count := 0
		for node in root.find_children("CoreGrid_*","MeshInstance3D",true,false):
			var g := _arrays(node.mesh)
			var gv: PackedVector3Array=g[Mesh.ARRAY_VERTEX]
			var gi: PackedInt32Array=g[Mesh.ARRAY_INDEX]
			for index in range(0,gi.size(),6):
				var low := Vector2(INF,INF)
				var high := Vector2(-INF,-INF)
				for j in 6:
					var p := _point(gv[gi[index+j]],walk)
					low=low.min(p)
					high=high.max(p)
				var a: Vector2i
				var b: Vector2i
				if high.x-low.x > high.y-low.y:
					a=Vector2i(roundi(low.x),roundi((low.y+high.y)*0.5))
					b=Vector2i(roundi(high.x),a.y)
				else:
					a=Vector2i(roundi((low.x+high.x)*0.5),roundi(low.y))
					b=Vector2i(a.x,roundi(high.y))
				actual_grid[_key(a,b)]=true
				grid_count+=1
		_check(actual_grid.size()==multiplicity.size() and grid_count==actual_grid.size() and actual_grid.keys().all(func(k):return multiplicity.has(k)),fixture.name+" unique complete grid segments")
		root.free()
		if not legacy:
			var soft = script.build(data,walk,recipe,true)
			var top_vertices: Array[Vector2] = []
			var triangles: Array = []
			for node in soft.find_children("Surface_*","MeshInstance3D",true,false):
				var mesh_arrays := _arrays(node.mesh)
				var vv: PackedVector3Array=mesh_arrays[Mesh.ARRAY_VERTEX]
				var ii: PackedInt32Array=mesh_arrays[Mesh.ARRAY_INDEX]
				for v in vv: top_vertices.append(_point(v,walk))
				for i in range(0,ii.size(),3): triangles.append([_point(vv[ii[i]],walk),_point(vv[ii[i+1]],walk),_point(vv[ii[i+2]],walk)])
			var within_tolerance := true
			for p: Vector2 in top_vertices:
				var nearest := INF
				for at: Vector2i in fixture.cells:
					var q := Vector2(clampf(p.x,at.x,at.x+1),clampf(p.y,at.y,at.y+1))
					nearest=minf(nearest,p.distance_to(q))
				if nearest>0.250001: within_tolerance=false
			_check(within_tolerance,fixture.name+" visual apron within quarter-cell tolerance")
			var occupancy_ok := true
			for y in fixture.size.y:
				for x in fixture.size.x:
					var at := Vector2i(x,y)
					var p := Vector2(at)+Vector2.ONE*0.5
					var covered := triangles.any(func(t):return _in_triangle(p,t))
					if covered != data.by_cell.has(at): occupancy_ok=false
			_check(occupancy_ok,fixture.name+" keep all supported cell centres and holes")
			soft.free()
	print("DYNAMIC_EDGE_TESTS legacy=%s checks=%d failures=%d" % [legacy,checks,failures])
	quit(1 if failures else 0)

func _in_triangle(p: Vector2,t: Array) -> bool:
	if absf((t[1]-t[0]).cross(t[2]-t[0])) < 0.00000001: return false
	var a: float=(t[1]-t[0]).cross(p-t[0])
	var b: float=(t[2]-t[1]).cross(p-t[1])
	var c: float=(t[0]-t[2]).cross(p-t[2])
	return (minf(a,minf(b,c))>=-0.000001) or (maxf(a,maxf(b,c))<=0.000001)
