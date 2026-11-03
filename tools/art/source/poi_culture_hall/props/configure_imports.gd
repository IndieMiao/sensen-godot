extends SceneTree
func _initialize():
	var root=OS.get_cmdline_user_args()[0];var directory="assets/rooms/poi_culture_hall/props/"
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://"+directory+"prop_manifest.json"))
	for asset in manifest.assets:
		var name=asset.file+".import"
		var config=ConfigFile.new();assert(config.load("res://"+directory+name)==OK)
		config.set_value("params","gltf/texture_map_mode",1)
		config.set_value("params","import_script/path","res://"+directory+"material_import.gd")
		if not config.has_section_key("remap","uid"):config.set_value("remap","uid",ResourceUID.id_to_text(ResourceUID.create_id()))
		assert(config.save("res://"+directory+name)==OK);assert(config.save(root+"/"+directory+name)==OK)
	quit()
