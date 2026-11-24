extends RefCounted
## Review-only, bounded addition. Never write the original plan, walk blockers, or authority masks.
const Scenery=preload("res://modules/dynamic_farm/farm_scenery.gd")
const Bank=preload("res://modules/dynamic_farm/farm_bank.gd")
const CONFIG="res://assets/dynamic_farm/499-edge-decor-v2.json"

static func _point(p: Vector2, walk: RefCounted, cell_m: float) -> Vector3:
	return Vector3((p.x-walk.center_grid.x)*cell_m,0,-(p.y-walk.center_grid.y)*cell_m)

static func _segments(data: Dictionary) -> Array:
	var segments:Array=[]
	for polygon:Dictionary in data.boundaries.outer:
		var ring:Array=polygon.outer
		var length:=0.0
		var part:Array=[]
		for i in range(ring.size()-1):
			var a:=Vector2(ring[i][0],ring[i][1])
			var b:=Vector2(ring[i+1][0],ring[i+1][1])
			if a.distance_to(b)<0.00001:continue
			part.append({"a":a,"b":b,"start":length,"length":a.distance_to(b)})
			length+=a.distance_to(b)
		segments.append({"segments":part,"length":length})
	return segments

static func _safe_neighborhood(cells: Array[Vector2i], data: Dictionary, outside: Dictionary) -> bool:
	# Reject hole banks, diagonal point contacts and narrow/opposing sides near the
	# entire footprint. Only the unbounded exterior can border the proposed cluster.
	var width:int=data.grid_size.x
	var height:int=data.grid_size.y
	for cell:Vector2i in cells:
		for dy in range(-2,3):
			for dx in range(-2,3):
				var near:=cell+Vector2i(dx,dy)
				if near.x<0 or near.y<0 or near.x>=width or near.y>=height:continue
				if not data.by_cell.has(near) and not Bank.is_exterior(outside,near):return false
		for axis in [Vector2i.RIGHT,Vector2i.DOWN]:
			if not data.by_cell.has(cell+axis*2) and not data.by_cell.has(cell-axis*2):return false
		for d in [Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
			if data.by_cell.has(cell+d) and not data.by_cell.has(cell+Vector2i(d.x,0)) and not data.by_cell.has(cell+Vector2i(0,d.y)):return false
	return true

static func _make(asset: Dictionary, at: Vector3, rng: RefCounted, walk: RefCounted, data: Dictionary, outside: Dictionary) -> Dictionary:
	var low:Array=asset.bounds_godot_m[0]
	var high:Array=asset.bounds_godot_m[1]
	var local:=AABB(Vector3(low[0],low[1],low[2]),Vector3(high[0]-low[0],high[1]-low[1],high[2]-low[2]))
	var scale_value:=lerpf(0.85,1.0,rng.unit())
	var transform:=Transform3D(Basis(Vector3.UP,rng.unit()*TAU).scaled(Vector3.ONE*scale_value),at)
	var box:AABB=transform*local
	var cells:Array[Vector2i]=walk.try_box(box,false)
	if cells.is_empty() or not _safe_neighborhood(cells,data,outside):return {}
	return {"asset":asset.id,"role":"edge_decor_v2","transform":transform,"box":box,
		"solid":false,"shadow":false,"cells":cells,"triangles":int(asset.triangles)}

static func _coverage(box: AABB, ring: Dictionary, center_s: float, walk: RefCounted, cell_m: float) -> Vector2:
	# Use ALL nearby ring segments, not only a centre projection. Inflate the real
	# footprint by one cell to conservatively reserve visible bare edge around it.
	var low:=Vector2(box.position.x/cell_m+walk.center_grid.x,-box.end.z/cell_m+walk.center_grid.y)-Vector2.ONE
	var high:=Vector2(box.end.x/cell_m+walk.center_grid.x,-box.position.z/cell_m+walk.center_grid.y)+Vector2.ONE
	var rect:=Rect2(low,high-low)
	var interval:=Vector2(INF,-INF)
	for segment:Dictionary in ring.segments:
		var a:Vector2=segment.a
		var b:Vector2=segment.b
		var clipped:=_clip_segment(a,b,rect)
		if clipped.x>clipped.y:continue
		var lo:float=segment.start+segment.length*clipped.x
		var hi:float=segment.start+segment.length*clipped.y
		var midpoint:float=(lo+hi)*0.5
		var shift:float=round((center_s-midpoint)/ring.length)*ring.length
		interval.x=minf(interval.x,lo+shift)
		interval.y=maxf(interval.y,hi+shift)
	return interval

static func _clip_segment(a: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var interval:=Vector2(0,1)
	var delta:=b-a
	for axis in 2:
		if absf(delta[axis])<0.000001:
			if a[axis]<rect.position[axis] or a[axis]>rect.end[axis]:return Vector2(1,0)
			continue
		var low:float=(rect.position[axis]-a[axis])/delta[axis]
		var high:float=(rect.end[axis]-a[axis])/delta[axis]
		interval.x=maxf(interval.x,minf(low,high))
		interval.y=minf(interval.y,maxf(low,high))
	return interval

static func plan(data: Dictionary, walk: RefCounted, original: Dictionary) -> Dictionary:
	var spec=JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var caps:Dictionary=spec.sample_caps.get(data.block_id,{})
	var result:Dictionary={"ok":true,"layout":[],"layer":"edge_decor_v2","clusters":[],"attempts":0,
		"rejected":0,"triangles":0,"batches":0,"covered_cells":0.0,"perimeter_cells":0.0}
	if caps.is_empty():
		result.layout_sha256="".sha256_text()
		return result
	var inventory=JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	var assets:Dictionary={}
	for asset:Dictionary in inventory.assets:assets[asset.id]=asset
	var rings:=_segments(data)
	var candidates:Array=[]
	for ring_index in rings.size():
		var ring:Dictionary=rings[ring_index]
		result.perimeter_cells+=ring.length
		for segment:Dictionary in ring.segments:
			var count:=maxi(1,ceili(segment.length))
			for i in count:
				var t:float=(i+0.5)/count
				candidates.append({"point":segment.a.lerp(segment.b,t),"tangent":(segment.b-segment.a).normalized(),
					"s":segment.start+t*segment.length,"ring":ring_index})
	var rng:=Scenery.FixedRandom.new((data.seed_hex+"|"+str(original.art_version)+"|edge_decor_v2").sha256_text())
	for i in range(candidates.size()-1,0,-1):
		var j:int=rng.next()%(i+1)
		var tmp:Dictionary=candidates[i]
		candidates[i]=candidates[j]
		candidates[j]=tmp
	# Favor reachable opening-area pockets, using semantic data anchors rather
	# than the review camera or parcel-specific coordinates. Seed breaks ties;
	# the unchanged footprint/protection gates still decide whether anything fits.
	for candidate:Dictionary in candidates:
		var p:Vector2=candidate.point
		candidate.priority=p.distance_to(Vector2(data.spawn)+Vector2.ONE*0.5)*0.65+p.distance_to(Vector2(data.entry)+Vector2.ONE*0.5)*0.35+rng.unit()*2.0
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return a.priority<b.priority)
	var outside:=Bank.exterior(data)
	# Budget batches exactly as Scenery.build splits them (model colour variant per chunk).
	var palette:Dictionary=original.recipe.get("prop_palette",{})
	var batches:Dictionary={}
	var used_boxes:Array=[]
	for candidate:Dictionary in candidates:
		if result.clusters.size()>=int(caps.clusters) or result.attempts>=512:break
		result.attempts+=1
		var tangent:Vector2=candidate.tangent
		var normal:=Vector2(-tangent.y,tangent.x)
		var at:Vector2=candidate.point+normal*1.15
		var cell:=Vector2i(floori(at.x),floori(at.y))
		if not data.by_cell.has(cell):at=candidate.point-normal*1.15
		var origin:=_point(at,walk,data.cell_m)
		var main:=_make(assets.wild_pz_grass_24,origin,rng,walk,data,outside)
		if main.is_empty():
			result.rejected+=1
			continue
		var cluster:Array=[main]
		var bounds:AABB=main.box
		for offset:Vector2 in [Vector2(0.65,0.2),Vector2(-0.35,0.60)]:
			var point:Vector3=origin+Vector3(tangent.x*offset.x+normal.x*offset.y,0,-tangent.y*offset.x-normal.y*offset.y)*data.cell_m
			var leaf:=_make(assets.wild_pz_foot_leafy,point,rng,walk,data,outside)
			if not leaf.is_empty():
				cluster.append(leaf)
				bounds=bounds.merge(leaf.box)
		var interval:=_coverage(bounds,rings[candidate.ring],candidate.s,walk,data.cell_m)
		var length:float=interval.y-interval.x
		var valid:bool=is_finite(length) and length>0 and length<=6.0 and result.covered_cells+length<=result.perimeter_cells*0.2
		for earlier:Dictionary in result.clusters:
			if earlier.ring!=candidate.ring:continue
			for shift:float in [-rings[candidate.ring].length,0.0,rings[candidate.ring].length]:
				if interval.x<earlier.interval.y+shift+6 and interval.y>earlier.interval.x+shift-6:valid=false
		for old_box:AABB in used_boxes:
			if bounds.intersects(old_box):valid=false
		var next_batches:=batches.duplicate()
		var added_triangles:=0
		for item:Dictionary in cluster:
			var p:Vector3=item.transform.origin
			next_batches[Scenery.batch_key(palette,item.asset,p,data.cell_m)]=true
			added_triangles+=item.triangles
		if next_batches.size()>4 or result.triangles+added_triangles>int(caps.triangles) or result.layout.size()+cluster.size()>int(caps.instances):valid=false
		if not valid:
			result.rejected+=1
			continue
		batches=next_batches
		used_boxes.append(bounds)
		result.layout.append_array(cluster)
		result.clusters.append({"ring":candidate.ring,"interval":interval,"bounds":bounds,"instances":cluster.size()})
		result.triangles+=added_triangles
		result.covered_cells+=length
	result.batches=batches.size()
	var signature:=PackedStringArray()
	for item:Dictionary in result.layout:signature.append(str(item.asset)+":"+str(item.transform))
	result.layout_sha256="\n".join(signature).sha256_text()
	return result
