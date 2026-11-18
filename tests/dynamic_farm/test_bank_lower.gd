extends SceneTree
const Ground=preload("res://modules/dynamic_farm/farm_mesh.gd")
const Walk=preload("res://modules/dynamic_farm/farm_walk.gd")
const Guard=preload("res://modules/dynamic_farm/farm_bank_guard.gd")
const Data=preload("res://modules/dynamic_farm/farm_data.gd")
var checks:=0
var failures:=0
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func _above(points: Array[Vector3], height: float) -> Array[Vector3]:
	var result:Array[Vector3]=[]
	for i in points.size():
		var a:=points[i]
		var b:=points[(i+1)%points.size()]
		if a.y>=height:result.append(a)
		if (a.y<height)!=(b.y<height):result.append(a.lerp(b,(height-a.y)/(b.y-a.y)))
	return result

func _convex_enclosure(points: Array[Vector3], cells: Array, walk: RefCounted, limit: float) -> bool:
	if points.is_empty():return true
	# Distance to one closed square is convex. If all clipped polygon vertices fit
	# one square's round dilation, the ENTIRE triangle/polygon fits, not just a sample.
	for cell:Vector2i in cells:
		var fits:=true
		for v:Vector3 in points:
			var p:Vector2=Vector2(v.x,-v.z)/0.8+walk.center_grid
			var nearest:=Vector2(clampf(p.x,cell.x,cell.x+1),clampf(p.y,cell.y,cell.y+1))
			if p.distance_to(nearest)>limit+0.00001:
				fits=false
				break
		if fits:return true
	return false

func _run() -> void:
	var recipe=JSON.parse_string(FileAccess.get_file_as_string("res://assets/dynamic_farm/499-art-recipe.json"))
	var cases: Array=[
		[Vector2i(0,0)],
		[Vector2i(0,0),Vector2i(1,0),Vector2i(0,1)],
		[Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(0,1),Vector2i(2,1),Vector2i(0,2),Vector2i(2,2)],
		[Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(0,1),Vector2i(2,1),Vector2i(0,2),Vector2i(1,2),Vector2i(2,2)],
		[Vector2i(0,0),Vector2i(1,1)]]
	var widened:=0
	for cells:Array in cases:
		var data:Dictionary={"cell_m":0.8,"grid_size":Vector2i(3,3),"origin":Vector2i.ZERO,"spawn":cells[0],"by_cell":{},"cells":[],"counts":{"core":cells.size()},"palette":{"soil":Color("dcc79a")}}
		for cell:Vector2i in cells:
			var row:Dictionary={"x":cell.x,"y":cell.y,"kind":"soil","surface_id":0,"zone":"core"}
			data.by_cell[cell]=row
			data.cells.append(row)
		var original:=data.duplicate(true)
		var walk:=Walk.new(data)
		var mesh:=Ground.build(data,walk,recipe,true,true)
		var metrics:Dictionary=mesh.get_meta("bank_metrics")
		widened+=metrics.expanded_pieces
		var upper_ok:=true
		var lower_ok:=true
		var normals_ok:=true
		var tested:=0
		for node in mesh.find_children("*","MeshInstance3D",true,false):
			if str(node.name).begins_with("CoreGrid_"):continue
			var arrays:Array=node.mesh.surface_get_arrays(0)
			var vv:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var ii:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var nn:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			for i in range(0,ii.size(),3):
				var tri:Array[Vector3]=[vv[ii[i]],vv[ii[i+1]],vv[ii[i+2]]]
				upper_ok=upper_ok and _convex_enclosure(_above(tri,-0.08),cells,walk,0.25)
				lower_ok=lower_ok and _convex_enclosure(tri,cells,walk,0.75)
				var n:=nn[ii[i]]+nn[ii[i+1]]+nn[ii[i+2]]
				normals_ok=normals_ok and n.is_finite() and (tri[1]-tri[0]).cross(tri[2]-tri[0]).dot(n)<=0.000001
				tested+=1
		_check(tested>0 and upper_ok,"whole triangles clipped above -0.08 stay in original quarter-cell enclosure")
		_check(lower_ok,"whole triangles stay in cumulative lower 0.75-cell enclosure")
		_check(normals_ok,"wide mesh normals and winding")
		_check(data==original,"authority masks unchanged")
		mesh.free()
	_check(widened>0,"guard permits safe widening rather than silently disabling every candidate")
	var ta:=PackedVector2Array([Vector2(0,0),Vector2(2,0),Vector2(1,2)])
	var tb:=PackedVector2Array([Vector2(-0.5,1),Vector2(2.5,1),Vector2(1,-1)])
	_check(Guard.overlap(ta,tb),"continuous crossing rejected without relying on vertex-only containment")
	var a:=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(0,1)])
	var b:=PackedVector2Array([Vector2(0,-0.05),Vector2(1,-0.05),Vector2(0,-1)])
	_check(is_equal_approx(Guard.distance(a,b),0.05),"separation measures positive gap independently of floating epsilon")
	for path:String in OS.get_cmdline_user_args():
		if not path.ends_with(".json"):continue
		var data:Dictionary=Data.decode(JSON.parse_string(FileAccess.get_file_as_string(path)))
		_check(data.ok,"real sample decodes")
		if not data.ok:continue
		var ground:=Ground.build(data,Walk.new(data),recipe,true,true)
		var metrics:Dictionary=ground.get_meta("bank_metrics")
		_check(metrics.expanded_pieces>0 and not metrics.guard_fallback,"real sample must retain safe expanded segments: "+data.block_id)
		print("REAL_LOWER_BANK ",data.block_id," ",JSON.stringify(metrics))
		ground.free()
	print("DYNAMIC_LOWER_BANK_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
