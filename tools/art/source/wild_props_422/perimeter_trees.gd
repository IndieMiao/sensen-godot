extends RefCounted
## Preview-only replacement of six PondTrees; production integration belongs to the client.
func bounds_on_screen(node: Node3D, camera: Camera3D) -> Rect2:
	var rect:=Rect2(camera.unproject_position(node.global_position),Vector2.ZERO)
	var meshes:=node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D:meshes.push_front(node)
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			for v in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:rect=rect.expand(camera.unproject_position(mesh.to_global(v)))
	return rect
func build(pond, scatter, resources: Array) -> Dictionary:
	var original:=pond.get_node("Scenery/PondTrees") as Node3D
	var instances:=original.get_node("Crown") as MultiMeshInstance3D
	assert(instances.multimesh.instance_count==6)
	var resource_rects: Array=[]
	for item in resources:resource_rects.append(bounds_on_screen(item,pond.cam))
	var result:={"original_count":6,"replacements":[],"all_clear":true,"original_hidden":false}
	for i in 6:
		var transform:=instances.multimesh.get_instance_transform(i)
		var at:=transform.origin
		var name: String="wild_tree_pine" if i%2==0 else "wild_tree_round"
		var scale_value:=transform.basis.get_scale().x
		var angle:=transform.basis.get_euler().y
		var outward:= -1.0 if at.x<6 else 1.0
		var chosen:=Vector3.INF
		for delta in [Vector3.ZERO,Vector3(outward*.8,0,0),Vector3(outward*1.4,0,0),Vector3(0,0,-.7),Vector3(outward*.8,0,-.7),Vector3(outward*1.4,0,.7)]:
			var candidate: Vector3=at+delta
			if FishingModel.dry_walkable(pond.grid,candidate):continue
			if not scatter.valid(name,candidate,scale_value,angle):continue
			var rectangle: Rect2=scatter.screen_box(name,candidate,scale_value,angle)
			var blocked:=false
			for resource in resource_rects:
				if resource.intersects(Rect2(0,0,360,800)) and rectangle.intersects(resource.grow(3)):blocked=true
			if blocked:continue
			chosen=candidate;break
		if chosen==Vector3.INF:
			result.all_clear=false;continue
		scatter.put(name,chosen,scale_value,angle)
		result.replacements.append({"asset":name,"original_position":[at.x,at.y,at.z],"position":[chosen.x,chosen.y,chosen.z],"scale":scale_value,"yaw_degrees":rad_to_deg(angle),"slot_gap_m":scatter.slot_gap(chosen,scatter.radius(name,scale_value)),"outside_walkable":true,"no_default_resource_overlap":true})
	if result.replacements.size()==6:original.visible=false;result.original_hidden=true
	return result
