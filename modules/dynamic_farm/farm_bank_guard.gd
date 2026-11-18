extends RefCounted
## Continuous XZ projection guard for the approved, unreachable lower skirt only.
## Separation is not a floating-point epsilon. Existing narrow holes are not enlarged.
const GAP_CELLS := 0.10
const AREA_EPS := 0.0000001
const DIST_EPS := 0.000001
const MAX_PIECES := 8192

static func triangles(a: Array[Vector3], b: Array[Vector3]) -> Array:
	var pa := Vector2(a[2].x,a[2].z)
	var pb := Vector2(b[2].x,b[2].z)
	var qa := Vector2(a[4].x,a[4].z)
	var qb := Vector2(b[4].x,b[4].z)
	return [PackedVector2Array([pa,pb,qb]),PackedVector2Array([pa,qb,qa])]

static func extra_triangles(a: Array[Vector3], b: Array[Vector3], cell_m: float) -> Array:
	var aa:=Vector2(a[0].x,a[0].z)
	var ba:=Vector2(b[0].x,b[0].z)
	var qa:=Vector2(a[4].x,a[4].z)
	var qb:=Vector2(b[4].x,b[4].z)
	var pa:=aa+ (qa-aa).limit_length(cell_m*0.25)
	var pb:=ba+ (qb-ba).limit_length(cell_m*0.25)
	return [PackedVector2Array([pa,pb,qb]),PackedVector2Array([pa,qb,qa])]

static func _adjacent(a: Dictionary, b: Dictionary) -> bool:
	# Subdivisions of the same original edge/corner are one continuous local surface,
	# not nonadjacent geometry. Positive-area overlap is still forbidden there.
	for pa:Vector3 in [a.span.a,a.span.b]:
		for pb:Vector3 in [b.span.a,b.span.b]:
			if pa.distance_squared_to(pb)<DIST_EPS*DIST_EPS:return true
	return false

static func _area(points: PackedVector2Array) -> float:
	var sum := 0.0
	for i in points.size(): sum+=points[i].cross(points[(i+1)%points.size()])
	return absf(sum)*0.5

static func overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if _area(a)<=AREA_EPS or _area(b)<=AREA_EPS: return false
	for polygon in Geometry2D.intersect_polygons(a,b):
		if _area(polygon)>AREA_EPS: return true
	return false

static func distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var result := INF
	for i in a.size():
		for j in b.size():
			var a0:=a[i]
			var a1:=a[(i+1)%a.size()]
			var b0:=b[j]
			var b1:=b[(j+1)%b.size()]
			if Geometry2D.segment_intersects_segment(a0,a1,b0,b1)!=null: return 0.0
			result=minf(result,a0.distance_to(Geometry2D.get_closest_point_to_segment(a0,b0,b1)))
			result=minf(result,b0.distance_to(Geometry2D.get_closest_point_to_segment(b0,a0,a1)))
	return result

static func _bounds(polygons: Array) -> Rect2:
	var rect := Rect2(polygons[0][0],Vector2.ZERO)
	for polygon: PackedVector2Array in polygons:
		for point in polygon:rect=rect.expand(point)
	return rect

static func unsafe(pieces: Array, data: Dictionary, center: Vector2, cell_m: float) -> Dictionary:
	var bad := {}
	var buckets := {}
	var gap := GAP_CELLS*cell_m
	for i in pieces.size():
		var piece: Dictionary = pieces[i]
		piece.bounds=_bounds(piece.triangles)
		var box: Rect2=piece.bounds.grow(gap)
		var low:=Vector2i(floori(box.position.x/cell_m),floori(box.position.y/cell_m))
		var high:=Vector2i(floori(box.end.x/cell_m),floori(box.end.y/cell_m))
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var key:=Vector2i(x,y)
				if not buckets.has(key):buckets[key]=[]
				buckets[key].append(i)
		if not piece.expanded:continue
		if overlap(piece.triangles[0],piece.triangles[1]):bad[i]=true
		# Test actual triangle projections against occupied squares, not just control points.
		var grid_low:=Vector2i(floori(box.position.x/cell_m+center.x),floori(-box.end.y/cell_m+center.y))
		var grid_high:=Vector2i(ceili(box.end.x/cell_m+center.x),ceili(-box.position.y/cell_m+center.y))
		for y in range(grid_low.y,grid_high.y+1):
			for x in range(grid_low.x,grid_high.x+1):
				if not data.by_cell.has(Vector2i(x,y)):continue
				var x0:float=(x-center.x)*cell_m
				var z0:float=-(y-center.y)*cell_m
				var square:=PackedVector2Array([Vector2(x0,z0),Vector2(x0+cell_m,z0),Vector2(x0+cell_m,z0-cell_m),Vector2(x0,z0-cell_m)])
				for triangle: PackedVector2Array in piece.triangles:
					if overlap(triangle,square):bad[i]=true
	var checked := {}
	for indices: Array in buckets.values():
		for i: int in indices:
			for j: int in indices:
				if j<=i:continue
				var pair:=Vector2i(i,j)
				if checked.has(pair):continue
				checked[pair]=true
				var a:Dictionary=pieces[i]
				var b:Dictionary=pieces[j]
				if not a.expanded and not b.expanded:continue
				if not a.bounds.grow(gap).intersects(b.bounds,true):continue
				var adjacent:=_adjacent(a,b)
				var passes: Array=[]
				if a.expanded:passes.append([a.extra,b.triangles])
				if b.expanded:passes.append([b.extra,a.triangles])
				for projection: Array in passes:
					for ta:PackedVector2Array in projection[0]:
						if _area(ta)<=AREA_EPS:continue
						for tb:PackedVector2Array in projection[1]:
							if _area(tb)<=AREA_EPS:continue
							if overlap(ta,tb) or (not adjacent and distance(ta,tb)<gap-DIST_EPS):
								if a.expanded:bad[i]=true
								if b.expanded:bad[j]=true
	return bad
