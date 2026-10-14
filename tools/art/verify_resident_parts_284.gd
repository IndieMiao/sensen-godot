extends SceneTree
## Actual importer and extracted-part audit, separate from the generator.
var report={"checks":[],"parts":{}}
func _initialize():run.call_deferred()
func check(ok,label):
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func frames(root):
	var out={}
	for n in root.find_children("*","",true,false):
		var key=str(root.get_path_to(n))
		if n is Node3D:out[key]=str(n.transform)
		if n is Skeleton3D:
			for i in n.get_bone_count():out[key+"/bone/"+n.get_bone_name(i)]=str(n.get_bone_rest(i))
	return out
func tris(root):
	var count=0
	for m in root.find_children("*","MeshInstance3D",true,false):count+=m.mesh.get_faces().size()/3
	return count
func part_info(id):
	var part=load("res://assets/avatar/parts/"+id+".res")
	var root=part.scene.instantiate();var info={"triangles":tris(root),"meshes":[],"offset_pos":str(part.offset_pos),"offset_rot_deg":str(part.offset_rot_deg),"offset_scale":str(part.offset_scale)}
	for m in root.find_children("*","MeshInstance3D",true,false):
		var mat=m.mesh.surface_get_material(0)
		info.meshes.append({"name":m.name,"transform":str(m.transform),"bounds":str(m.transform*m.mesh.get_aabb()),"surfaces":m.mesh.get_surface_count(),"albedo":mat.get_shader_parameter("albedo_tex").resource_path,"emission_strength":mat.get_shader_parameter("emission_strength")})
	root.free();return info
func run():
	var avatar=root.get_node("Avatar")
	var pairs=[["hairhat80_npc_ama","hairhat80_npc_granny_wu","SM_hairHat80.fbx"],["hairhat51","hairhat_npc_ivo","SM_hairHat51.fbx"],["mask16_npc_kai","mask16_npc_ivo","SM_mask16.fbx"]]
	for pair in pairs:
		var before=load("res://assets/avatar/source/"+pair[0]+"/"+pair[2]).instantiate()
		var after=load("res://assets/avatar/source/"+pair[1]+"/"+pair[2]).instantiate()
		check(frames(before)==frames(after),pair[1]+": imported node paths, types of frames and bone rest transforms match base")
		check(before.name==after.name,pair[1]+": original FBX root name retained")
		var info=part_info(pair[1]);report.parts[pair[1]]=info
		check(info.meshes.size()==1 and info.meshes[0].surfaces==1,pair[1]+": one extracted static mesh and one surface")
		check(info.triangles==tris(after),pair[1]+": extracted triangles match actual FBX import")
		var texture=load(info.meshes[0].albedo)
		info.texture_size=[texture.get_width(),texture.get_height()]
		var original=part_info(pair[0]);var original_tex=load(original.meshes[0].albedo)
		check(texture.get_size()==original_tex.get_size(),pair[1]+": texture resolution equals base")
		check(info.meshes[0].transform==original.meshes[0].transform,pair[1]+": extracted mesh transform exactly matches base")
		check(info.offset_pos==str(Vector3.ZERO) and info.offset_rot_deg==str(Vector3.ZERO) and info.offset_scale==str(Vector3.ONE),pair[1]+": no compensating recipe offset or scale")
		check(avatar.catalog.part(pair[1])!=null,pair[1]+": actual NPC catalog lookup succeeds")
		before.free();after.free()
	check(report.parts.hairhat_npc_ivo.meshes[0].emission_strength==0.0,"Ivo lamp/hat material has zero emission")
	var maximum=0;var existing={}
	for meta in avatar.catalog.parts_for_slot(&"hairHat",true):
		if meta.id in ["hairhat_npc_ivo","hairhat80_npc_granny_wu"]:continue
		var info=part_info(meta.id);existing[meta.id]=info.triangles;maximum=maxi(maximum,info.triangles)
	report.existing_hairhat_triangles=existing;report.hairhat_budget=maximum
	check(report.parts.hairhat_npc_ivo.triangles<=maximum,"Ivo hat within largest existing runtime hairHat budget")
	report.failures=report.checks.filter(func(x):return not x.passed)
	DirAccess.make_dir_recursive_absolute("output/resident-parts-284")
	FileAccess.open("output/resident-parts-284/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("RESIDENT_IMPORT_QA ",report.checks.size()," checks; ",report.failures.size()," failures")
	quit(0 if report.failures.is_empty() else 1)
