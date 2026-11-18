extends RefCounted
## Render-only rolled turf outside the unchanged walking surface. No new shader or permissions.
const SEGMENTS := 2

static func exterior(data: Dictionary) -> Dictionary:
	# Compact flood over void cells, including a one-cell border. Holes are never exterior.
	var stride: int = data.grid_size.x + 2
	var height: int = data.grid_size.y + 2
	var flags := PackedByteArray()
	flags.resize(stride * height)
	for cell: Vector2i in data.by_cell:
		flags[(cell.y+1)*stride+cell.x+1] = 1
	var queue := PackedInt32Array([0])
	flags[0] = 2
	var index := 0
	while index < queue.size():
		var at: int = queue[index]
		index += 1
		for step in [-stride,1,stride,-1]:
			var next: int = at + step
			if next < 0 or next >= flags.size(): continue
			if abs(step)==1 and at/stride != next/stride: continue
			if flags[next] != 0: continue
			flags[next] = 2
			queue.append(next)
	return {"flags":flags,"stride":stride}

static func is_exterior(field: Dictionary, cell: Vector2i) -> bool:
	return field.flags[(cell.y+1)*field.stride+cell.x+1] == 2

static func phase(data: Dictionary) -> float:
	return float(str(data.get("seed_hex","00000000")).substr(0,8).hex_to_int() % 4096) / 4096.0 * TAU

static func profile(anchor: Vector3, outside: Vector3, seed_phase: float) -> Array[Vector3]:
	var offset := outside-anchor
	if offset.length_squared() < 0.00000001:
		# Keep the old vertical point-contact junction; neither widen nor join it.
		return [anchor,anchor,anchor,anchor,anchor-Vector3.UP*0.7]
	# Broad, continuous variation shared by neighboring vertices; never per-cell random heights.
	var wave := 0.5 + 0.3*sin(anchor.x*0.83+anchor.z*0.47+seed_phase) + 0.2*sin(anchor.x*0.31-anchor.z*0.62-seed_phase)
	var width := 0.65 + 0.35*wave
	return [anchor,
		anchor+offset*(width*0.55)-Vector3.UP*(0.015+0.01*wave),
		anchor+offset*width-Vector3.UP*(0.06+0.04*wave),
		anchor+offset*(width*0.32)-Vector3.UP*(0.17+0.12*wave),
		anchor+offset*(width*0.15)-Vector3.UP*(0.22+0.14*wave)]

static func _normals(points: Array[Vector3], outward: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = [Vector3.UP]
	for i in range(1,points.size()):
		var delta: Vector3 = points[mini(i+1,points.size()-1)]-points[i-1]
		var n := outward*(-delta.y)+Vector3.UP*delta.dot(outward)
		result.append(n.normalized() if n.length_squared()>0.00000001 else outward)
	return result

static func append(top: SurfaceTool, soil: SurfaceTool, a: Vector3, b: Vector3,
		outside_a: Vector3, outside_b: Vector3, outward: Vector3, seed_phase: float, colour: Color, segments := SEGMENTS) -> void:
	for segment in segments:
		var t0 := float(segment)/segments
		var t1 := float(segment+1)/segments
		var start := a.lerp(b,t0)
		var end := a.lerp(b,t1)
		var lip_a := outside_a.lerp(outside_b,t0)
		var lip_b := outside_a.lerp(outside_b,t1)
		var pa := profile(start,lip_a,seed_phase)
		var pb := profile(end,lip_b,seed_phase)
		var na := _normals(pa,(lip_a-start).normalized() if lip_a.distance_squared_to(start)>0.00000001 else outward)
		var nb := _normals(pb,(lip_b-end).normalized() if lip_b.distance_squared_to(end)>0.00000001 else outward)
		for band in 4:
			var tool := soil if band==3 else top
			var upper := colour if band==3 else Color.WHITE
			var lower := colour.darkened(0.12) if band==3 else Color.WHITE
			_triangle(tool,[pa[band],pb[band],pb[band+1]],[na[band],nb[band],nb[band+1]],[upper,upper,lower])
			_triangle(tool,[pa[band],pb[band+1],pa[band+1]],[na[band],nb[band+1],na[band+1]],[upper,lower,lower])

static func _triangle(tool: SurfaceTool, points: Array, normals: Array, colours: Array) -> void:
	var cross: Vector3 = (points[1]-points[0]).cross(points[2]-points[0])
	if cross.length_squared()<0.000000000001: return
	var order := [0,1,2]
	if cross.dot(normals[0]+normals[1]+normals[2])>0: order=[0,2,1]
	for i in order:
		tool.set_normal(normals[i])
		tool.set_color(colours[i])
		tool.add_vertex(points[i])
