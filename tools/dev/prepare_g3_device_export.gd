extends SceneTree
## Prepare a temporary Android QA preset, then restore the original bytes after export.

const PRESETS := "res://export_presets.cfg"
const BACKUP := "res://output/g3-week/device-backup/export_presets.cfg"
const DRIVER_FILES := ["res://tools/dev/g3_week_ui.gd", "res://tools/dev/g3_week_ui.tscn", "res://tools/dev/g3_week_ui.gd.uid"]

func _init() -> void:
	var mode := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--g3-device-export="): mode = arg.trim_prefix("--g3-device-export=")
	match mode:
		"prepare": _prepare()
		"restore": _restore()
		_:
			push_error("Specify --g3-device-export=prepare or --g3-device-export=restore")
			quit(2)

func _prepare() -> void:
	var config := ConfigFile.new()
	if config.load(PRESETS) != OK:
		_fail("Could not read export_presets.cfg")
		return
	var source := -1
	var target := 0
	while config.has_section("preset.%d" % target):
		var name := str(config.get_value("preset.%d" % target, "name", ""))
		if name == "Android G3 QA":
			_fail("QA preset already present; restore the original before preparing again")
			return
		if name == "Android": source = target
		target += 1
	if source < 0:
		_fail("Android export preset was not found")
		return
	var original := FileAccess.get_file_as_bytes(PRESETS)
	if FileAccess.file_exists(BACKUP) and FileAccess.get_file_as_bytes(BACKUP) != original:
		_fail("Existing preset backup differs; kept it unchanged")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BACKUP.get_base_dir()))
	if not FileAccess.file_exists(BACKUP):
		var backup := FileAccess.open(BACKUP, FileAccess.WRITE)
		if backup == null:
			_fail("Could not back up export presets")
			return
		backup.store_buffer(original)
		backup.close()
	if FileAccess.get_file_as_bytes(BACKUP) != original:
		_fail("Export preset backup failed byte comparison")
		return
	for suffix in ["", ".options"]:
		var old_section := "preset.%d%s" % [source, suffix]
		var new_section := "preset.%d%s" % [target, suffix]
		for key in config.get_section_keys(old_section):
			config.set_value(new_section, key, config.get_value(old_section, key))
	var section := "preset.%d" % target
	config.set_value(section, "name", "Android G3 QA")
	config.set_value(section, "runnable", false)
	config.set_value(section, "export_path", "build/sensen-g3-week-qa.apk")
	var features := str(config.get_value(section, "custom_features", ""))
	config.set_value(section, "custom_features", features + ("," if not features.is_empty() else "") + "g3_device_qa")
	var exclusions := str(config.get_value(section, "exclude_filter", "")).split(",", false)
	if exclusions.has("tools/*"): exclusions.remove_at(exclusions.find("tools/*"))
	for path in _tool_exclusions("res://tools"):
		exclusions.append(path.trim_prefix("res://"))
	config.set_value(section, "exclude_filter", ",".join(exclusions))
	config.set_value(section + ".options", "command_line/extra_args",
		"++ --qa-scene=week --week-path=tool --week-style=life --week-base=http://10.0.2.2:3103/v1 --week-out=user://g3-week-device")
	if config.save(PRESETS) != OK:
		_fail("Could not save temporary QA preset; restore from the backup")
		return
	print("G3_DEVICE_EXPORT_PREPARED Android G3 QA -> build/sensen-g3-week-qa.apk")
	quit(0)

func _restore() -> void:
	if not FileAccess.file_exists(BACKUP):
		_fail("No original export preset backup exists")
		return
	var original := FileAccess.get_file_as_bytes(BACKUP)
	var file := FileAccess.open(PRESETS, FileAccess.WRITE)
	if file == null:
		_fail("Could not restore export presets")
		return
	file.store_buffer(original)
	file.close()
	if FileAccess.get_file_as_bytes(PRESETS) != original:
		_fail("Restored export presets differ from the backup")
		return
	print("G3_DEVICE_EXPORT_RESTORED byte_equal=true")
	quit(0)

func _tool_exclusions(path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null: return result
	for child in dir.get_files():
		var file := path.path_join(child)
		if not DRIVER_FILES.has(file): result.append(file)
	for child in dir.get_directories():
		var nested := path.path_join(child)
		var contains_driver := false
		for driver in DRIVER_FILES:
			if str(driver).begins_with(nested + "/"): contains_driver = true
		if contains_driver: result.append_array(_tool_exclusions(nested))
		else: result.append(nested + "/*")
	return result

func _fail(message: String) -> void:
	push_error(message)
	quit(2)
