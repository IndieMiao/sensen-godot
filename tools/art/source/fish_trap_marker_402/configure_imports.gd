extends SceneTree
func _initialize():
	var destination=OS.get_cmdline_user_args()[0]
	var folder="assets/props/fish_trap_marker/"
	var config=ConfigFile.new();assert(config.load("res://"+folder+"fish_trap_marker.glb.import")==OK)
	assert(str(config.get_value("remap","uid","")).begins_with("uid://"))
	assert(config.get_value("params","gltf/texture_map_mode")==1)
	assert(config.save(destination+"/"+folder+"fish_trap_marker.glb.import")==OK)
	var uid=FileAccess.get_file_as_string("res://"+folder+"material_import.gd.uid")
	assert(uid.begins_with("uid://"))
	FileAccess.open(destination+"/"+folder+"material_import.gd.uid",FileAccess.WRITE).store_string(uid)
	print("FISH_TRAP_IMPORT_UIDS_READY");quit()
