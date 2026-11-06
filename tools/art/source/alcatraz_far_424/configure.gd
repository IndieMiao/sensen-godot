extends SceneTree
func _initialize():
	var dir="assets/landmarks/alcatraz_island/"
	var root=OS.get_cmdline_user_args()[0]
	for name in DirAccess.get_files_at("res://"+dir):
		if name=="alc_far_material_import.gd.uid":DirAccess.copy_absolute(ProjectSettings.globalize_path("res://"+dir+name),root+"/"+dir+name)
		if not name.begins_with("alc_") or not name.ends_with(".glb.import"):continue
		var cfg=ConfigFile.new();assert(cfg.load("res://"+dir+name)==OK)
		assert(cfg.has_section_key("remap","uid"))
		assert(cfg.get_value("params","gltf/texture_map_mode",0)==1)
		assert(cfg.save(root+"/"+dir+name)==OK)
	quit()
