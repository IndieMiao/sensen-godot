extends SceneTree

func _initialize():
	ProjectSettings.set_setting("application/config/custom_user_dir_name","SensenTea216QA")
	ProjectSettings.set_setting("display/window/vsync/vsync_mode",0)
	ProjectSettings.set_setting("application/run/max_fps",60)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size",4096)
	assert(ProjectSettings.save()==OK)
	var destination=OS.get_cmdline_user_args()[0]
	var directory="assets/rooms/tea_house/"
	for name in DirAccess.get_files_at("res://"+directory):
		if not name.ends_with(".import"):continue
		var path="res://"+directory+name;var config=ConfigFile.new();assert(config.load(path)==OK)
		if name.ends_with(".glb.import"):
			config.set_value("params","gltf/texture_map_mode",1)
			if not config.has_section_key("remap","uid"):config.set_value("remap","uid",ResourceUID.id_to_text(ResourceUID.create_id()))
		assert(config.save(path)==OK);assert(config.save(destination+"/"+directory+name)==OK)
	for name in DirAccess.get_files_at("res://scenes/tea_house"):
		if name.ends_with(".gd.uid"):
			DirAccess.copy_absolute(ProjectSettings.globalize_path("res://scenes/tea_house/"+name),destination+"/scenes/tea_house/"+name)
	quit()
