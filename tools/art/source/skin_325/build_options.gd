extends SceneTree
## Offline authoring only. Export static switch resources; never rewrite source GLBs.
var evidence = {"niches": {}, "signs": {}, "checks": []}

func _initialize():
	build.call_deferred()

func check(ok, label):
	evidence.checks.append({"check": label, "passed": bool(ok)})
	assert(ok, label)

func save_scene(node, path):
	for child in node.find_children("*", "", true, false):
		child.owner = node
	var packed = PackedScene.new()
	check(packed.pack(node) == OK, "Pack " + path)
	check(ResourceSaver.save(packed, path) == OK, "Save " + path)

func material(color):
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.roughness = .9
	mat.metallic_specular = .15
	return mat

func bottle(parent, name, position, height, radius, color):
	var node = MeshInstance3D.new()
	node.name = name
	node.position = position
	parent.add_child(node)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Rounded shoulder, short neck and a closed green cap, matching the approved mock.
	var profile = [[0., radius * .8], [.02, radius], [height * .67, radius],
		[height * .8, radius * .56], [height * .86, radius * .53],
		[height * .86, radius * .58], [height, radius * .58]]
	for j in range(profile.size() - 1):
		var ring_color = Color(color) if j < 4 else Color("3E9E6A")
		var before = profile[maxi(0, j - 1)]
		var after = profile[mini(profile.size() - 1, j + 1)]
		for i in 16:
			var a = i * TAU / 16
			var b = (i + 1) * TAU / 16
			var p = [Vector3(cos(a)*profile[j][1], profile[j][0], sin(a)*profile[j][1]),
				Vector3(cos(b)*profile[j][1], profile[j][0], sin(b)*profile[j][1]),
				Vector3(cos(a)*profile[j+1][1], profile[j+1][0], sin(a)*profile[j+1][1]),
				Vector3(cos(b)*profile[j+1][1], profile[j+1][0], sin(b)*profile[j+1][1])]
			for idx in [0, 1, 2, 1, 3, 2]:
				st.set_color(ring_color.srgb_to_linear())
				var angle = a if idx % 2 == 0 else b
				st.set_normal(Vector3(cos(angle)*(after[0]-before[0]), before[1]-after[1], sin(angle)*(after[0]-before[0])).normalized())
				st.add_vertex(p[idx])
	for top in [false, true]:
		var y = height if top else 0.
		var r = radius * (.58 if top else .8)
		for i in 16:
			var a = i * TAU / 16
			var b = (i + 1) * TAU / 16
			var p = [Vector3(0,y,0), Vector3(cos(a)*r,y,sin(a)*r), Vector3(cos(b)*r,y,sin(b)*r)]
			for idx in ([0,1,2] if top else [0,2,1]):
				st.set_color(Color("3E9E6A" if top else color).srgb_to_linear())
				st.set_normal(Vector3.UP if top else Vector3.DOWN)
				st.add_vertex(p[idx])
	st.index()
	var mesh = st.commit()
	mesh.resource_name = name + "_mobile"
	var mat = material("FFFFFF")
	mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mat)
	node.mesh = mesh

func niche(id, prefix):
	var source = load(prefix + id + ".glb").instantiate()
	root.add_child(source)
	var nodes = source.find_children("*", "MeshInstance3D", true, false)
	check(nodes.size() == 1, id + " has one merged mesh")
	var old_node = nodes[0]
	var arrays = old_node.mesh.surface_get_arrays(0)
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	var uv = arrays[Mesh.ARRAY_TEX_UV]
	var old = arrays[Mesh.ARRAY_INDEX]
	var keep = PackedInt32Array()
	var removed = 0
	for k in range(0, old.size(), 3):
		var inside = true
		for idx in [old[k], old[k+1], old[k+2]]:
			var p = vertices[idx]
			var slot = Vector2i(floori(uv[idx].x*8), floori(uv[idx].y*8))
			inside = inside and absf(p.x)<.36 and p.y>=.749 and p.y<1.31 and p.z>.144
			inside = inside and slot in [Vector2i(2,5),Vector2i(1,6),Vector2i(6,4),Vector2i(7,7)]
		if inside: removed += 1
		else: keep.append_array([old[k], old[k+1], old[k+2]])
	check(removed == (620 if id.ends_with("1") else 452), id + " removes only approved mock exhibits")
	arrays[Mesh.ARRAY_INDEX] = keep
	var mesh = ArrayMesh.new()
	mesh.resource_name = id + "_b_frame_mobile"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat = old_node.get_active_material(0).duplicate()
	mat.albedo_texture = load(prefix + "room_albedo_ao_b.png")
	mesh.surface_set_material(0, mat)
	var new_arrays = mesh.surface_get_arrays(0)
	for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
		check(var_to_bytes(arrays[key]) == var_to_bytes(new_arrays[key]), id + " frame array retained " + str(key))
	var normal_error = 0.
	for i in arrays[Mesh.ARRAY_NORMAL].size():
		normal_error = maxf(normal_error, arrays[Mesh.ARRAY_NORMAL][i].distance_to(new_arrays[Mesh.ARRAY_NORMAL][i]))
	check(normal_error < .0002, id + " normal encoding tolerance")
	var out = prefix + "variants/b/" + id + ".tscn"
	var option = Node3D.new()
	option.name = id + "_B"
	var frame = MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = mesh
	frame.transform = old_node.global_transform
	option.add_child(frame)
	if id.ends_with("1"):
		bottle(option, "MedicineBottleTall", Vector3(-.19,.75,.24),.37,.085,"E1ECE3")
		bottle(option, "MedicineBottleShort", Vector3(.18,.75,.25),.28,.071,"ABCAB6")
	else:
		bottle(option, "MedicineBottleRound", Vector3(0,.75,.24),.40,.09,"D9E8DD")
	save_scene(option, out)
	var mesh_path = id + "/" + str(source.name) + "/" + str(source.get_path_to(old_node))
	evidence.niches[id] = {"source_sha256": FileAccess.get_sha256(prefix + id + ".glb"),
		"hidden_mesh": mesh_path, "removed_triangles": removed, "retained_triangles": keep.size()/3,
		"normal_max_error": normal_error, "scene": out.trim_prefix(prefix)}
	option.free()
	source.free()
	return {"parent":id,"hide_meshes":[mesh_path],"scene":out.trim_prefix(prefix)}

func build_sign(room, prefix, anchor):
	var n1 = room == "poi_hotel_lobby"
	var size = Vector2(1.6,.22) if n1 else Vector2(.88,.23)
	var option = Node3D.new()
	option.name = "SignPatchB"
	option.position = Vector3(anchor.position[0],anchor.position[1],anchor.position[2]+.008)
	var node = MeshInstance3D.new()
	node.name = "BlankSign" if n1 else "GreenCrossSign"
	var mesh = QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat = material("FFFFFF")
	mat.albedo_texture = load(prefix + "sign_b.png")
	node.material_override = mat
	option.add_child(node)
	save_scene(option, prefix + "variants/b/sign_patch.tscn")
	evidence.signs[room] = {"patch_size_m":[size.x,size.y], "writing_size_m":anchor.size if n1 else [.66,.23],
		"writing_anchor":"sign_name", "writing_offset_m":[0 if n1 else .10,0,.009], "baked_text":false}
	option.free()
	return {"parent":".","hide_meshes":[],"scene":"variants/b/sign_patch.tscn"}

func write_json(path, value):
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t") + "\n")

func build():
	for room in ["poi_hotel_lobby","poi_service_hall"]:
		var prefix = "res://assets/rooms/" + room + "/"
		DirAccess.make_dir_recursive_absolute(prefix + "variants/b")
		var layout = JSON.parse_string(FileAccess.get_file_as_string(prefix + "layout.json"))
		var anchor = layout.anchors.filter(func(a):return a.name == "sign_name")[0]
		var options = {"sign_b":build_sign(room,prefix,anchor)}
		var enabled = ["sign_b"]
		if room == "poi_service_hall":
			for id in ["display_niche_1","display_niche_2"]:
				options[id + "_medicine"] = niche(id,prefix)
				enabled.append(id + "_medicine")
		var a_atlas = "room_albedo_ao.png" if room == "poi_hotel_lobby" else "hall_albedo_ao_n2.png"
		var manifest = {"schema_version":1,"room_id":room,"default_variant":"A","layout":"layout.json",
			"material_source_atlas":a_atlas,"options":options,
			"variants":{"A":{"atlas":a_atlas,"enabled_options":[],"sign":{"anchor":"sign_name","size_m":anchor.size,"offset_m":[0,0,0]}},
			"B":{"atlas":"room_albedo_ao_b.png","enabled_options":enabled,
				"sign":{"anchor":"sign_name","size_m":anchor.size if room=="poi_hotel_lobby" else [.66,.23],
					"offset_m":[0 if room=="poi_hotel_lobby" else .10,0,.009],"baked_text":false}}}}
		write_json(prefix + "variants.json",manifest)
	evidence.passed = evidence.checks.all(func(c):return c.passed)
	write_json("res://../options-validation.json", evidence)
	print("B_OPTIONS_BUILT ", evidence.passed)
	quit(0 if evidence.passed else 1)
