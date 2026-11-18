extends SceneTree
const Bank = preload("res://modules/dynamic_farm/farm_bank.gd")
const Ground = preload("res://modules/dynamic_farm/farm_mesh.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	var recipe = JSON.parse_string(FileAccess.get_file_as_string("res://assets/dynamic_farm/499-art-recipe.json"))
	var fixtures := [
		[Vector2i(0,0)],
		[Vector2i(0,0),Vector2i(1,0)],
		[Vector2i(0,0),Vector2i(1,1)],
		[Vector2i(0,0),Vector2i(1,0),Vector2i(0,1)],
		[Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(0,1),Vector2i(2,1),Vector2i(0,2),Vector2i(1,2),Vector2i(2,2)]]
	for cells in fixtures:
		var data := {"cell_m":0.8,"grid_size":Vector2i(3,3),"origin":Vector2i.ZERO,"spawn":cells[0],
			"by_cell":{},"cells":[],"counts":{"core":cells.size()},"palette":{"soil":Color("dcc79a")}}
		for cell: Vector2i in cells:
			var row := {"x":cell.x,"y":cell.y,"kind":"soil","surface_id":0,"zone":"core"}
			data.by_cell[cell]=row
			data.cells.append(row)
		var field := Bank.exterior(data)
		_check(Bank.is_exterior(field,Vector2i(-1,-1)),"outside border reachable")
		_check(not Bank.is_exterior(field,cells[0]),"walk cells never classified exterior")
		if cells.size()==8: _check(not Bank.is_exterior(field,Vector2i(1,1)),"enclosed hole excluded from rolling")
		var original := data.duplicate(true)
		var walk := Walk.new(data)
		var root := Ground.build(data,walk,recipe)
		var top_triangles: Array = []
		var inside_tolerance := true
		var normals_ok := true
		for node in root.find_children("*","MeshInstance3D",true,false):
			if str(node.name).begins_with("CoreGrid_"): continue
			var arrays: Array = node.mesh.surface_get_arrays(0)
			var vv: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var ii: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			for v in vv:
				var point := Vector2(v.x,-v.z)/0.8+walk.center_grid
				var distance := INF
				for cell: Vector2i in cells:
					distance=minf(distance,point.distance_to(Vector2(clampf(point.x,cell.x,cell.x+1),clampf(point.y,cell.y,cell.y+1))))
				if distance>0.250001:inside_tolerance=false
			for i in range(0,ii.size(),3):
				var a:=vv[ii[i]]
				var b:=vv[ii[i+1]]
				var c:=vv[ii[i+2]]
				var normal: Vector3=nn[ii[i]]+nn[ii[i+1]]+nn[ii[i+2]]
				if not normal.is_finite() or (b-a).cross(c-a).dot(normal)>0.000001:normals_ok=false
				if is_zero_approx(a.y) and is_zero_approx(b.y) and is_zero_approx(c.y):
					top_triangles.append([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
		var supported := true
		for cell: Vector2i in cells:
			var center := walk.point(cell)
			for offset in [Vector2.ZERO,Vector2(-0.39,-0.39),Vector2(0.39,-0.39),Vector2(-0.39,0.39),Vector2(0.39,0.39)]:
				var point: Vector2 = Vector2(center.x,center.z)+offset
				if not top_triangles.any(func(t):return Geometry2D.is_point_in_polygon(point,PackedVector2Array(t))): supported=false
		_check(supported,"complete original walk top, including near each corner")
		_check(inside_tolerance,"all final XZ vertices inside cumulative quarter-cell envelope")
		_check(normals_ok,"finite outward vertex normals and clockwise winding")
		_check(data==original,"rendering does not mutate masks or input")
		root.free()
	var anchor := Vector3(1,0,2)
	var pinned := Bank.profile(anchor,anchor,0.0)
	_check(pinned.slice(0,4).all(func(p):return p==anchor) and pinned[-1]==anchor-Vector3.UP*0.7,"point junction preserves old vertical seam")
	var heights := {}
	for i in 24:
		var p:=Vector3(i*0.4,0,0)
		var profile := Bank.profile(p,p+Vector3(0,0,0.14),0.0)
		heights[snappedf(profile[-1].y,0.01)]=true
		_check(profile[0]==p and profile==Bank.profile(p,p+Vector3(0,0,0.14),0.0),"shared anchor deterministic with unchanged walk edge")
	_check(heights.size()>5,"bank depth varies continuously across multiple cells")
	print("DYNAMIC_BANK_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
