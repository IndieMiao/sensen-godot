extends SceneTree
func _initialize():
	var destination=OS.get_cmdline_user_args()[0]
	var folder="assets/farm/art/"
	var config=ConfigFile.new();assert(config.load("res://"+folder+"flax_patch.glb.import")==OK)
	assert(str(config.get_value("remap","uid","")).begins_with("uid://"))
	assert(config.get_value("params","gltf/texture_map_mode")==1)
	assert(config.get_value("params","meshes/light_baking")==1)
	assert(config.save(destination+"/"+folder+"flax_patch.glb.import")==OK)
	print("FLAX_IMPORT_UID_READY");quit()
