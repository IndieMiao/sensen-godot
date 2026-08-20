class_name LocalOutfitStore
extends RefCounted

var base_dir: String = "user://avatar"

func save_outfit(user_id: String, config: AvatarConfig) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(base_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var f := FileAccess.open(_path_for(user_id), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(config.to_json_text())
	f.close()
	return OK

func load_outfit(user_id: String) -> AvatarConfig:
	var path := _path_for(user_id)
	if not FileAccess.file_exists(path):
		return null
	var cfg := AvatarConfig.from_json_text(FileAccess.get_file_as_string(path))
	if cfg == null:
		push_warning("OutfitStore: 存档损坏，备份并回退默认: %s" % path)
		var dir := DirAccess.open(base_dir)
		if dir:
			var rename_err := dir.rename(path.get_file(), path.get_file() + ".corrupt")
			if rename_err != OK:
				push_error("OutfitStore: 损坏存档备份失败 err=%d path=%s" % [rename_err, path])
		else:
			push_error("OutfitStore: 无法打开目录备份损坏存档: %s" % base_dir)
	return cfg

func _path_for(user_id: String) -> String:
	var safe := user_id.replace("/", "_").replace("\\", "_").replace(":", "_")
	return base_dir.path_join("outfit_%s.json" % safe)
