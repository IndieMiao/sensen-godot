extends SceneTree
func _initialize():
	var destination=OS.get_cmdline_user_args()[0];var seen={};var rx=RegEx.new();rx.compile("^uid://[a-y0-8]+$")
	var report={"generated_by":"Godot scene importer, missing uid before initial import","uids":{}}
	for name in ["grove","rock_pile","reed_bank","clay_pit","herb_patch","hardwood_grove","flax_patch"]:
		var relative="assets/farm/art/"+name+"_gathered.glb.import"
		var cfg=ConfigFile.new();assert(cfg.load("res://"+relative)==OK)
		var uid=str(cfg.get_value("remap","uid",""));assert(rx.search(uid)!=null and not seen.has(uid));seen[uid]=true
		assert(cfg.get_value("params","meshes/light_baking")==1)
		assert(cfg.get_value("params","meshes/ensure_tangents")==true and cfg.get_value("params","meshes/generate_lods")==true)
		assert(cfg.save(destination+"/"+relative)==OK);report.uids[name]=uid
	FileAccess.open("res://../uid-generation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("GODOT_GENERATED_GATHERED_UIDS ",JSON.stringify(report));quit()
