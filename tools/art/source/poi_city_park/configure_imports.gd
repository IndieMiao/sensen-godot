extends SceneTree
## Keep generated import UIDs stable when staging new art into the offline project.
func _initialize():
	var root=OS.get_cmdline_user_args()[0]
	var kit="res://assets/rooms/poi_city_park/"
	var layout=JSON.parse_string(FileAccess.get_file_as_string(kit+"layout.json"))
	for asset in layout.assets:
		var path=(kit+asset.file).simplify_path()
		var config=ConfigFile.new()
		assert(config.load(path+".import")==OK)
		if not str(config.get_value("remap","uid","")).begins_with("uid://"):
			var uid=ResourceLoader.get_resource_uid(path)
			if uid==ResourceUID.INVALID_ID:uid=ResourceUID.create_id()
			config.set_value("remap","uid",ResourceUID.id_to_text(uid))
			assert(config.save(path+".import")==OK)
		assert(DirAccess.copy_absolute(ProjectSettings.globalize_path(path+".import"),root+"/"+path.trim_prefix("res://")+".import")==OK)
	print("N5_IMPORT_UIDS ",layout.assets.size())
	quit()
