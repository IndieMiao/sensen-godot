extends SceneTree
func _initialize():
	var root=OS.get_cmdline_user_args()[0];var id=ProjectSettings.get_setting("monster_review/identity")
	var relative="assets/monsters/"+id+"/"+id+".glb.import"
	var config=ConfigFile.new();assert(config.load("res://"+relative)==OK)
	assert(str(config.get_value("remap","uid","")).begins_with("uid://"))
	assert(config.save(root+"/"+relative)==OK)
	var uid=FileAccess.get_file_as_string("res://assets/monsters/material_import.gd.uid")
	var file=FileAccess.open(root+"/assets/monsters/material_import.gd.uid",FileAccess.WRITE);file.store_string(uid);file.close()
	print("MONSTER_IMPORT_UID ",config.get_value("remap","uid"));quit()
