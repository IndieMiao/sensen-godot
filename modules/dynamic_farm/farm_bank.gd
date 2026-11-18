extends RefCounted
## Render-only rolled turf outside the unchanged walking surface. No new shader or permissions.
const SEGMENTS := 2
const Guard = preload("res://modules/dynamic_farm/farm_bank_guard.gd")
const LOWER_CELLS := 0.75
const LOWER_START_Y := -0.08

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

static func lower_profile(anchor: Vector3, outside: Vector3, seed_phase: float, weight: float, cell_m: float) -> Array[Vector3]:
	var old := profile(anchor,outside,seed_phase)
	var offset:=outside-anchor
	if offset.length_squared()<0.00000001:
		return [old[0],old[1],old[2],old[3],old[3],old[4]]
	var direction:=offset.normalized()
	var wave:=0.5+0.3*sin(anchor.x*0.83+anchor.z*0.47+seed_phase)+0.2*sin(anchor.x*0.31-anchor.z*0.62-seed_phase)
	var lip_radius:float=Vector2(old[2].x-anchor.x,old[2].z-anchor.z).length()
	var radius:=lerpf(lip_radius,cell_m*LOWER_CELLS*(0.65+0.35*wave),weight)
	# Art review 620ec024: one outward/downward profile family, including narrow
	# rollback sections. Do not reuse the previous inward-hooked pipe cross-section.
	var variation:float=(wave-0.5)*0.06*clampf(offset.length()/(cell_m*0.175),0.0,1.0)
	return [anchor,
		anchor+direction*(lip_radius*0.30)-Vector3.UP*0.025,
		anchor+direction*(lip_radius*0.70)-Vector3.UP*0.10,
		anchor+direction*lerpf(lip_radius,radius,0.50)-Vector3.UP*(0.22+variation),
		anchor+direction*radius-Vector3.UP*(0.34+variation),
		anchor+direction*radius-Vector3.UP*(0.38+variation)]

static func _key(a: Vector3, b: Vector3) -> Vector4:
	return Vector4(snappedf(a.x,0.00001),snappedf(a.z,0.00001),snappedf(b.x,0.00001),snappedf(b.z,0.00001))

static func _guard_profile(anchor: Vector3, outside: Vector3, seed_phase: float, weight: float, cell_m: float) -> Array[Vector3]:
	# Freeze Q58's exact solver input so A cannot gain extra width by changing its
	# cross-section. The final A triangles are independently checked below.
	var old:=profile(anchor,outside,seed_phase)
	var result:Array[Vector3]=[old[0],old[1],old[2],old[3],old[3],old[4]]
	var offset:=outside-anchor
	if weight<=0.0 or offset.length_squared()<0.00000001:return result
	var direction:=offset.normalized()
	var wave:=0.5+0.3*sin(anchor.x*0.83+anchor.z*0.47+seed_phase)+0.2*sin(anchor.x*0.31-anchor.z*0.62-seed_phase)
	var lip_radius:float=Vector2(old[2].x-anchor.x,old[2].z-anchor.z).length()
	var radius:=lerpf(lip_radius,cell_m*LOWER_CELLS*(0.65+0.35*wave),weight)
	result[2].y=minf(result[2].y,LOWER_START_Y-0.04*wave)
	result[3]=anchor+direction*lerpf(lip_radius,radius,0.60)-Vector3.UP*(0.21+0.10*wave)
	result[4]=anchor+direction*radius-Vector3.UP*(0.34+0.14*wave)
	result[5]=anchor+direction*radius-Vector3.UP*(0.38+0.14*wave)
	return result

static func emit(spans: Array, data: Dictionary, center: Vector2, widen: bool) -> Dictionary:
	var vertices: Dictionary={}
	var pieces: Array=[]
	for span: Dictionary in spans:
		for segment in span.segments:
			var t0:float=float(segment)/span.segments
			var t1:float=float(segment+1)/span.segments
			var a:Vector3=span.a.lerp(span.b,t0)
			var b:Vector3=span.a.lerp(span.b,t1)
			var oa:Vector3=span.oa.lerp(span.ob,t0)
			var ob:Vector3=span.oa.lerp(span.ob,t1)
			var ka:=_key(a,oa)
			var kb:=_key(b,ob)
			if not vertices.has(ka):vertices[ka]={"a":a,"o":oa,"weight":1.0 if widen and a.distance_squared_to(oa)>0.00000001 else 0.0}
			if not vertices.has(kb):vertices[kb]={"a":b,"o":ob,"weight":1.0 if widen and b.distance_squared_to(ob)>0.00000001 else 0.0}
			pieces.append({"ka":ka,"kb":kb,"span":span})
	var budget_fallback:=pieces.size()>Guard.MAX_PIECES
	if budget_fallback:
		for vertex: Dictionary in vertices.values():vertex.weight=0.0
	var rejected:=0
	var passes:=0
	var rollback_centres:Dictionary={}
	var iterations:Array=[]
	var guard_fallback:=false
	for attempt in 8:
		passes=attempt+1
		# Reject a local neighborhood, not just the endpoints of one triangle.
		# Otherwise a sharp fallback edge transfers the same conflict to its next
		# segment on every pass, eventually forcing a needless whole-farm fallback.
		for vertex:Dictionary in vertices.values():
			for rejected_at:Vector3 in rollback_centres:
				var distance:float=Vector2(vertex.a.x-rejected_at.x,vertex.a.z-rejected_at.z).length()/data.cell_m
				var ramp:=clampf((distance-1.6)/1.5,0.0,1.0)
				vertex.weight=minf(vertex.weight,ramp*ramp*(3.0-2.0*ramp))
		# Conservative ramp back to old narrow geometry; shared endpoints have one weight.
		for smoothing in 4:
			for piece: Dictionary in pieces:
				var wa:float=vertices[piece.ka].weight
				var wb:float=vertices[piece.kb].weight
				vertices[piece.ka].weight=minf(wa,wb+0.25)
				vertices[piece.kb].weight=minf(wb,wa+0.25)
		_profiles(pieces,vertices,data.cell_m)
		if not widen or budget_fallback:break
		var bad:=Guard.unsafe(pieces,data,center,data.cell_m)
		var candidates:=0
		for piece:Dictionary in pieces:
			if piece.expanded:candidates+=1
		iterations.append({"expanded":candidates,"unsafe":bad.size()})
		if bad.is_empty():break
		rejected+=bad.size()
		for i: int in bad:
			rollback_centres[vertices[pieces[i].ka].a]=true
			rollback_centres[vertices[pieces[i].kb].a]=true
			vertices[pieces[i].ka].weight=0.0
			vertices[pieces[i].kb].weight=0.0
		if attempt==7:
			guard_fallback=true
			# Fail closed within this scene without changing its layout or any authority mask.
			for vertex:Dictionary in vertices.values():vertex.weight=0.0
			_profiles(pieces,vertices,data.cell_m)
	_profiles(pieces,vertices,data.cell_m,true)
	var final_unsafe:=Guard.unsafe(pieces,data,center,data.cell_m) if widen and not budget_fallback else {}
	var final_rejected:=0
	for final_attempt in 4:
		if final_unsafe.is_empty():break
		final_rejected+=final_unsafe.size()
		# New profile may occupy more of the already-approved NARROW envelope.
		# Only shrink original Q58 weights near that conflict, never enlarge them.
		var centres:Array[Vector3]=[]
		for i:int in final_unsafe:
			centres.append(vertices[pieces[i].ka].a)
			centres.append(vertices[pieces[i].kb].a)
		for vertex:Dictionary in vertices.values():
			for at:Vector3 in centres:
				var distance:float=Vector2(vertex.a.x-at.x,vertex.a.z-at.z).length()/data.cell_m
				var ramp:=clampf((distance-1.6)/1.5,0.0,1.0)
				vertex.weight=minf(vertex.weight,ramp*ramp*(3.0-2.0*ramp))
		_profiles(pieces,vertices,data.cell_m,true)
		final_unsafe=Guard.unsafe(pieces,data,center,data.cell_m)
	if not final_unsafe.is_empty():
		guard_fallback=true
		for vertex:Dictionary in vertices.values():vertex.weight=0.0
		_profiles(pieces,vertices,data.cell_m,true)
	var expanded:=0
	for piece:Dictionary in pieces:
		var span:Dictionary=piece.span
		if piece.expanded:expanded+=1
		_emit_profile(span.top,span.soil,piece.pa,piece.pb,
			span.normal,span.colour)
	return {"pieces":pieces.size(),"expanded_pieces":expanded,"rejected_pieces":rejected,
		"guard_passes":passes,"rollback_centres":rollback_centres.size(),"guard_fallback":guard_fallback,
		"iterations":iterations,"final_profile_rejected":final_rejected,"final_profile_unsafe":final_unsafe.size(),"budget_fallback":budget_fallback,"gap_m":Guard.GAP_CELLS*data.cell_m,
		"upper_limit_cells":0.25,"lower_limit_cells":LOWER_CELLS,"lower_start_y":LOWER_START_Y}

static func _profiles(pieces: Array, vertices: Dictionary, cell_m: float, final_profile := false) -> void:
	for piece: Dictionary in pieces:
		var a:Dictionary=vertices[piece.ka]
		var b:Dictionary=vertices[piece.kb]
		piece.pa=lower_profile(a.a,a.o,piece.span.phase,a.weight,cell_m) if final_profile else _guard_profile(a.a,a.o,piece.span.phase,a.weight,cell_m)
		piece.pb=lower_profile(b.a,b.o,piece.span.phase,b.weight,cell_m) if final_profile else _guard_profile(b.a,b.o,piece.span.phase,b.weight,cell_m)
		piece.triangles=Guard.triangles(piece.pa,piece.pb)
		piece.extra=Guard.extra_triangles(piece.pa,piece.pb,cell_m)
		var pa:Vector3=piece.pa[4]-piece.pa[0]
		var pb:Vector3=piece.pb[4]-piece.pb[0]
		piece.expanded=Vector2(pa.x,pa.z).length()>cell_m*0.25+0.000001 or Vector2(pb.x,pb.z).length()>cell_m*0.25+0.000001

static func _emit_profile(top: SurfaceTool, soil: SurfaceTool, pa: Array[Vector3], pb: Array[Vector3], outward: Vector3, colour: Color) -> void:
	var da:=Vector3(pa[2].x-pa[0].x,0,pa[2].z-pa[0].z)
	var db:=Vector3(pb[2].x-pb[0].x,0,pb[2].z-pb[0].z)
	var na:=_normals(pa,da.normalized() if da.length_squared()>0.00000001 else outward)
	var nb:=_normals(pb,db.normalized() if db.length_squared()>0.00000001 else outward)
	# Turf shading stops before the vertical soil lip: don't average that separate
	# material's normal into the grass and create a continuous artificial bright line.
	var da4:Vector3=pa[4]-pa[3]
	var db4:Vector3=pb[4]-pb[3]
	var oa:=da.normalized() if da.length_squared()>0.00000001 else outward
	var ob:=db.normalized() if db.length_squared()>0.00000001 else outward
	na[4]=(oa*(-da4.y)+Vector3.UP*da4.dot(oa)).normalized() if da4.length_squared()>0.00000001 else oa
	nb[4]=(ob*(-db4.y)+Vector3.UP*db4.dot(ob)).normalized() if db4.length_squared()>0.00000001 else ob
	for band in 5:
		var tool:=soil if band==4 else top
		var upper:=colour if band==4 else Color.WHITE
		var lower:=colour.darkened(0.12) if band==4 else Color.WHITE
		var nna:=oa if band==4 else na[band]
		var nnb:=ob if band==4 else nb[band]
		var nna_next:=oa if band==4 else na[band+1]
		var nnb_next:=ob if band==4 else nb[band+1]
		_triangle(tool,[pa[band],pb[band],pb[band+1]],[nna,nnb,nnb_next],[upper,upper,lower])
		_triangle(tool,[pa[band],pb[band+1],pa[band+1]],[nna,nnb_next,nna_next],[upper,lower,lower])

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
