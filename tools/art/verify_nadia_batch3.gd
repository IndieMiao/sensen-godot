extends "verify_npc_batch3.gd"
func run():
	var avatar = root.get_node("Avatar")
	var lou = OS.get_cmdline_user_args().has("--lou")
	var pairs = [["hairhat41_npc_auburn", "hairhat41_npc_nadia_baker", "SM_hairHat41.fbx", 1296],
		["cloth1_1", "cloth1_1_npc_nadia", "SK_dt_skin01.fbx", 1869]]
	if lou: pairs = [["cloth1", "cloth1_npc_lou", "SK_dt_skin01.fbx", 2811]]
	for pair in pairs:
		var id = pair[1]
		var before = load("res://assets/avatar/source/" + pair[0] + "/" + pair[2]).instantiate()
		var after = load("res://assets/avatar/source/" + id + "/" + pair[2]).instantiate()
		check(before.name == after.name and frames(before) == frames(after), id + ": original imported nodes/hierarchy/transforms/bone rests")
		var old = load("res://assets/avatar/parts/" + pair[0] + ".res")
		var part = load("res://assets/avatar/parts/" + id + ".res")
		check(part.attach == old.attach and part.slot == old.slot, id + ": original attachment and slot")
		check(part.offset_pos == old.offset_pos and part.offset_rot_deg == old.offset_rot_deg and part.offset_scale == old.offset_scale, id + ": no compensating offsets")
		var mesh: Mesh = part.mesh; var old_mesh: Mesh = old.mesh
		var scene: Node; var old_scene: Node
		if part.attach == "socket":
			scene = part.scene.instantiate(); old_scene = old.scene.instantiate()
			check(frames(scene) == frames(old_scene), id + ": original extracted transforms")
			var meshes = scene.find_children("*", "MeshInstance3D", true, false)
			check(meshes.size() == 1, id + ": one mesh")
			mesh = meshes[0].mesh; old_mesh = old_scene.find_children("*", "MeshInstance3D", true, false)[0].mesh
		else:
			check(part.skin.get_bind_count() == old.skin.get_bind_count(), id + ": original skin bind count")
			for i in part.skin.get_bind_count():
				check(part.skin.get_bind_bone(i) == old.skin.get_bind_bone(i) and part.skin.get_bind_name(i) == old.skin.get_bind_name(i) and part.skin.get_bind_pose(i) == old.skin.get_bind_pose(i), id + ": original bind " + str(i))
			var arrays = mesh.surface_get_arrays(0)
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var stride = weights.size() / arrays[Mesh.ARRAY_VERTEX].size()
			var valid = true
			print("NPC_WEIGHT_STRIDE ", stride, " original ", old_mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS].size() / old_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
			for i in range(0, weights.size(), stride):
				var total = 0.0
				for j in stride: total += weights[i+j]
				valid = valid and absf(total - 1.0) < .002
			check(valid, id + ": all original/new vertex skin weights normalized")
		check(mesh.get_surface_count() == 1, id + ": one surface")
		check(mesh.get_faces().size()/3 == pair[3], id + ": authored triangle count")
		var mat = mesh.surface_get_material(0); var old_mat = old_mesh.surface_get_material(0)
		check(mat.shader == old_mat.shader, id + ": original shared shader")
		for key in ["emission_strength", "smoothness", "ao_strength", "diffuse_strength", "rim_strength"]:
			check(mat.get_shader_parameter(key) == old_mat.get_shader_parameter(key), id + ": original material " + key)
		var texture = mat.get_shader_parameter("albedo_tex")
		check(texture.resource_path.contains("/" + id + "/"), id + ": own new atlas bound")
		check(texture.get_size() == Vector2(512,512), id + ": 512px runtime texture")
		check(avatar.catalog.part(id) != null and avatar.catalog.parts_for_slot(part.slot, false).all(func(p): return p.id != id), id + ": NPC only")
		report.parts[id] = {"base": pair[0], "triangles": mesh.get_faces().size()/3, "delta": (mesh.get_faces().size()-old_mesh.get_faces().size())/3,
			"surface_count": mesh.get_surface_count(), "runtime_texture_size": [texture.get_width(),texture.get_height()]}
		before.free(); after.free()
		if scene: scene.free(); old_scene.free()
	report.failures = report.checks.filter(func(c): return not c.passed)
	var output = "res://output/npc-batch3/lou-validation.json" if lou else "res://output/npc-batch3/nadia-validation.json"
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("LOU_BATCH3_QA " if lou else "NADIA_BATCH3_QA ", report.checks.size(), " checks / ", report.failures.size(), " failures")
	quit(0 if report.failures.is_empty() else 1)
