extends SceneTree
## Prepare a temporary Android QA preset, then restore the original bytes after export.

const PRESETS := "res://export_presets.cfg"
const BACKUP := "res://output/g3-week/device-backup/export_presets.cfg"
const DRIVER_FILES := ["res://tools/dev/g3_week_ui.gd", "res://tools/dev/g3_week_ui.tscn", "res://tools/dev/g3_week_ui.gd.uid"]
var _week_args := {"path": "tool", "style": "life", "base": "http://10.0.2.2:3103/v1", "out": "user://g3-week-device", "touch": "false", "run": "", "resume": ""}
var _apk := "build/sensen-g3-week-qa.apk"

func _init() -> void:
	var mode := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--g3-device-export="): mode = arg.trim_prefix("--g3-device-export=")
		if arg.begins_with("--g3-device-apk="): _apk = arg.trim_prefix("--g3-device-apk=")
		for key in _week_args:
			var prefix := "--week-%s=" % key
			if arg.begins_with(prefix): _week_args[key] = arg.trim_prefix(prefix)
	match mode:
		"prepare": _prepare()
		"restore": _restore()
		_:
			push_error("Specify --g3-device-export=prepare or --g3-device-export=restore")
			quit(2)

func _prepare() -> void:
	if not _valid_args(): return
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
	config.set_value(section, "export_path", _apk)
	var features := str(config.get_value(section, "custom_features", ""))
	config.set_value(section, "custom_features", features + ("," if not features.is_empty() else "") + "g3_device_qa")
	var exclusions := str(config.get_value(section, "exclude_filter", "")).split(",", false)
	if exclusions.has("tools/*"): exclusions.remove_at(exclusions.find("tools/*"))
	for path in _tool_exclusions("res://tools"):
		exclusions.append(path.trim_prefix("res://"))
	config.set_value(section, "exclude_filter", ",".join(exclusions))
	var args := ["++", "--qa-scene=week"]
	for key in _week_args:
		if not str(_week_args[key]).is_empty(): args.append("--week-%s=%s" % [key, _week_args[key]])
	config.set_value(section + ".options", "command_line/extra_args", " ".join(args))
	if config.save(PRESETS) != OK:
		_fail("Could not save temporary QA preset; restore from the backup")
		return
	print("G3_DEVICE_EXPORT_PREPARED ", JSON.stringify({"preset": "Android G3 QA", "apk": _apk, "args": _week_args}))
	quit(0)

func _valid_args() -> bool:
	if _week_args.path not in ["tool", "field"] or _week_args.style not in ["life", "sell"] or _week_args.touch not in ["true", "false"]:
		_fail("Use --week-path=tool|field, --week-style=life|sell and --week-touch=true|false")
		return false
	var allowed := RegEx.new()
	allowed.compile("^[A-Za-z0-9_./:=+-]+$")
	for value in _week_args.values() + [_apk]:
		if not str(value).is_empty() and allowed.search(str(value)) == null:
			_fail("Export arguments must not contain whitespace or command-line quotes")
			return false
	if not str(_week_args.base).begins_with("http://") or not str(_week_args.base).ends_with("/v1") or not _apk.ends_with(".apk"):
		_fail("Use an explicit HTTP QA /v1 endpoint and an .apk output path")
		return false
	if _week_args.touch == "true" and str(_week_args.run).is_empty():
		_fail("Touch exports require --week-run matching the host worker")
		return false
	if not str(_week_args.resume).is_empty() and (_week_args.resume not in ["g3_vivo_tool_life_03", "g3_vivo_tool_life_04"]
		or _week_args.touch != "true" or _week_args.path != "tool" or _week_args.style != "life"
		or _week_args.run in ["g3_vivo_tool_life_03", "g3_vivo_tool_life_04"] or _week_args.base != "http://127.0.0.1:3103/v1"
		or str(_week_args.out).simplify_path().trim_suffix("/") in ["user://g3-vivo-tool-life-03", "user://g3-vivo-tool-life-04"]):
		_fail("Resume is restricted to the known tool/life 03/04 failures, with a new run and output")
		return false
	return true

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
