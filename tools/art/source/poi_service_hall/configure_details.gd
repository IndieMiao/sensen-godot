extends SceneTree

func _initialize():
	var root=OS.get_cmdline_user_args()[0]
	var directory="assets/rooms/poi_service_hall/"
	for name in DirAccess.get_files_at("res://"+directory):
		if not name.ends_with(".import"):continue
		var path="res://"+directory+name
		var config=ConfigFile.new()
		assert(config.load(path)==OK)
		if name.ends_with(".glb.import"):
			config.set_value("params","gltf/texture_map_mode",1)
			if not config.has_section_key("remap","uid"):
				config.set_value("remap","uid",ResourceUID.id_to_text(ResourceUID.create_id()))
		assert(config.save(path)==OK)
		assert(config.save(root+"/"+directory+name)==OK)
	quit()
