extends SceneTree
## Read material/attachment values from the actual shipped runtime part resources.
const PAIRS = [
	["hairhat51", "hairhat51_npc_lena", "SM_hairHat51.fbx", "T_lena_hairHat51_D.png"],
	["hairhat36_npc_pip", "hairhat36_npc_rafa", "SM_hairHat36.fbx", "T_rafa_hairHat36_D.png"],
	["cloth1_1", "cloth1_1_npc_rafa", "SK_dt_skin01.fbx", "T_rafa_cloth01_D.png"],
]
func _initialize():
	run.call_deferred()
func xyz(v): return [v.x, v.y, v.z]
func run():
	var recipe = JSON.parse_string(FileAccess.get_file_as_string("res://assets/avatar/source/recipes_284b.json"))
	recipe.parts = []
	for row in PAIRS:
		var original = load("res://assets/avatar/parts/" + row[0] + ".res")
		var mesh: Mesh = original.mesh
		var instance: Node
		if original.attach == "socket":
			instance = original.scene.instantiate()
			mesh = instance.find_children("*", "MeshInstance3D", true, false)[0].mesh
		var material = mesh.surface_get_material(0)
		var floats = {}
		for key in ["emission_strength", "smoothness", "ao_strength", "diffuse_strength", "rim_strength"]:
			floats[key] = material.get_shader_parameter(key)
		var path = "res://assets/avatar/source/" + row[1] + "/"
		recipe.parts.append({"id": row[1], "slot": String(original.slot), "attach": original.attach,
			"tier": original.tier, "unity_guid": "", "fbx": path + row[2],
			"mesh_name": "cloth" if original.attach == "mesh" else null,
			"thumb_src": null, "src_files": [],
			"offset": {"pos": xyz(original.offset_pos), "rot": xyz(original.offset_rot_deg), "scale": xyz(original.offset_scale)},
			"materials": [{"albedo": path + row[3], "ao": null, "floats": floats}]})
		if instance: instance.free()
	FileAccess.open("res://assets/avatar/source/recipes_batch3.json", FileAccess.WRITE).store_string(JSON.stringify(recipe, "\t", false) + "\n")
	var npc_path = "res://assets/avatar/npc_only.json"
	var text = FileAccess.get_file_as_string(npc_path)
	var data = JSON.parse_string(text)
	var entries = []
	for row in PAIRS:
		if not data.npc_only.has(row[1]): entries.append(row[1])
	if not entries.is_empty():
		var end = text.find("\n\t]")
		assert(end >= 0)
		var addition = ""
		for id in entries: addition += ",\n\t\t" + JSON.stringify(id)
		FileAccess.open(npc_path, FileAccess.WRITE).store_string(text.substr(0, end) + addition + text.substr(end))
	print("BATCH3_RECIPES ", JSON.stringify(recipe.parts))
	quit()
