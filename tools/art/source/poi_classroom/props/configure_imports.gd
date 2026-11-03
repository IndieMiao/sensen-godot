extends SceneTree
func _initialize():
	var root=OS.get_cmdline_user_args()[0]
	var directory="assets/rooms/poi_classroom/props/"
	for name in DirAccess.get_files_at("res://"+directory):
		if not name.ends_with(".glb.import"):continue
		var config=ConfigFile.new()
		assert(config.load("res://"+directory+name)==OK)
		config.set_value("params","gltf/texture_map_mode",1)
		config.set_value("params","import_script/path","res://assets/rooms/poi_classroom/props/material_import.gd")
		if not config.has_section_key("remap","uid"):
			config.set_value("remap","uid",ResourceUID.id_to_text(ResourceUID.create_id()))
		assert(config.save("res://"+directory+name)==OK)
		assert(config.save(root+"/"+directory+name)==OK)
	quit()
