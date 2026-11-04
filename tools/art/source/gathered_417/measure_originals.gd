extends SceneTree
const Art=preload("res://modules/farm/farm_art.gd")
const Old=preload("res://old_art.gd")
func _initialize():run.call_deferred()
func xyz(p):return [p.x,p.y,p.z]
func run():
	var report={}
	for name in ["grove","rock_pile","reed_bank","clay_pit","herb_patch","hardwood_grove","flax_patch"]:
		var node=Old.build("spot_"+name,Vector3.ZERO) if name in ["grove","rock_pile","herb_patch"] else Art.instance(name)
		root.add_child(node);var found=node.find_children("*","MeshInstance3D",true,false)
		if node is MeshInstance3D:found.push_front(node)
		var lo=Vector3.INF;var hi=-Vector3.INF;var triangles=0;var surfaces=0
		for mesh in found:
			for surface in mesh.mesh.get_surface_count():
				surfaces+=1;var a=mesh.mesh.surface_get_arrays(surface)
				triangles+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3
				for v in a[Mesh.ARRAY_VERTEX]:
					var p=node.global_transform.affine_inverse()*mesh.global_transform*v;lo=lo.min(p);hi=hi.max(p)
		report[name]={"bounds":[xyz(lo),xyz(hi)],"dimensions_xyz":xyz(hi-lo),"triangles":triangles,"surfaces":surfaces,
			"source":"original attachment factory spot_"+name if name in ["grove","rock_pile","herb_patch"] else "assets/farm/art/"+name+".glb"}
		node.free()
	var path=OS.get_cmdline_user_args()[0]
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("ORIGINAL_VERTEX_MEASUREMENTS ",JSON.stringify(report));quit()
