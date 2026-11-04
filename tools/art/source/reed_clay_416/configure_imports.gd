extends SceneTree
func _initialize():
	var destination=OS.get_cmdline_user_args()[0]
	for name in ["reed_bank","clay_pit"]:
		var relative="assets/farm/art/"+name+".glb.import"
		var config=ConfigFile.new();assert(config.load("res://"+relative)==OK)
		assert(str(config.get_value("remap","uid","")).begins_with("uid://"))
		assert(config.get_value("params","meshes/light_baking")==1)
		assert(config.save(destination+"/"+relative)==OK)
	print("REED_CLAY_UIDS_READY");quit()
