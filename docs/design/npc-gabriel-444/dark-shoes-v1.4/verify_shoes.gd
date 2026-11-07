extends SceneTree
var report = {"checks":[]}
func _initialize():
	run.call_deferred()
func check(ok, label):
	report.checks.append({"check":label,"passed":ok})
	if not ok: push_error(label)
func binds(skin):
	var result = []
	for i in skin.get_bind_count():
		result.append([skin.get_bind_bone(i),str(skin.get_bind_name(i)),str(skin.get_bind_pose(i))])
	return result
func run():
	var avatar = root.get_node("Avatar")
	var donor = load("res://assets/avatar/parts/shoes3.res")
	var part = load("res://assets/avatar/parts/shoes3_npc_gabriel.res")
	check(part.id == "shoes3_npc_gabriel" and part.slot == &"shoes" and part.attach == donor.attach and part.tier == donor.tier,"ID, slot, attachment and tier")
	check(part.mesh.get_surface_count() == donor.mesh.get_surface_count(),"Surface count unchanged")
	for i in donor.mesh.get_surface_count():
		check(var_to_bytes(part.mesh.surface_get_arrays(i)) == var_to_bytes(donor.mesh.surface_get_arrays(i)),"Vertices, normals, UVs, indices, bones and weights identical")
	check(part.mesh.get_aabb() == donor.mesh.get_aabb(),"Bounds identical")
	check(binds(part.skin) == binds(donor.skin),"All skin bind names, bones and poses identical")
	var mat = part.mesh.surface_get_material(0)
	var original = donor.mesh.surface_get_material(0)
	check(mat.shader == original.shader,"Shader unchanged")
	for key in ["rim_strength","ao_strength","diffuse_strength","emission_strength","smoothness"]:
		check(mat.get_shader_parameter(key) == original.get_shader_parameter(key),"Material float unchanged: " + key)
	check(mat.get_shader_parameter("ao_tex") == original.get_shader_parameter("ao_tex"),"AO texture unchanged")
	var tex = mat.get_shader_parameter("albedo_tex")
	check(tex.resource_path == "res://assets/avatar/source/shoes3_npc_gabriel/T_skin03_shoes_D.png","New texture bound to runtime shoe")
	check(tex.get_size() == Vector2(512,512) and tex.get_image().is_compressed() and tex.get_image().has_mipmaps(),"512² compressed texture with mipmaps")
	check(avatar.catalog.part("shoes3_npc_gabriel") != null,"New shoe in NPC catalog")
	check(avatar.catalog.parts_for_slot(&"shoes",false).all(func(p):return p.id != "shoes3_npc_gabriel"),"New shoe excluded from player wardrobe")
	check(avatar.catalog.parts_for_slot(&"shoes",false).any(func(p):return p.id == "shoes3"),"Original shoes3 still available to players")
	report.geometry = {"triangles":part.mesh.get_faces().size()/3,"surfaces":part.mesh.get_surface_count(),"skin_binds":part.skin.get_bind_count(),"bounds":str(part.mesh.get_aabb())}
	report.failures = report.checks.filter(func(c):return not c.passed)
	DirAccess.make_dir_recursive_absolute("res://output/gabriel-dark-shoes-444")
	FileAccess.open("res://output/gabriel-dark-shoes-444/structure-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("GABRIEL_SHOES_QA ",report.checks.size()," checks; ",report.failures.size()," failures")
	quit(0 if report.failures.is_empty() else 1)
