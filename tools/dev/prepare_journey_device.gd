extends SceneTree

const DRIVER_FILES := ["res://tools/dev/journey_playtest.gd", "res://tools/dev/journey_playtest.tscn", "res://tools/dev/journey_device_observer.gd"]

func _initialize() -> void:
	var directory := ProjectSettings.globalize_path("res://output/journey-device/project")
	var package := "com.sensen.journeyqa"
	var title := "Sensen Journey QA"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--journey-output="):
			directory = ProjectSettings.globalize_path(arg.trim_prefix("--journey-output="))
		elif arg.begins_with("--journey-package="):
			package = arg.trim_prefix("--journey-package=")
		elif arg.begins_with("--journey-title="):
			title = arg.trim_prefix("--journey-title=")
	var package_pattern := RegEx.create_from_string("^com\\.sensen\\.journey[a-z0-9_]*qa$")
	assert(package_pattern.search(package) != null)
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/name", title)
	config.set_value("application", "config/icon", "res://assets/ui/icons/lucide/sprout.svg")
	config.set_value("application", "run/main_scene", "res://tools/dev/journey_playtest.tscn")
	config.set_value("debug", "file_logging/enable_file_logging", true)
	assert(config.save(directory.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", "tools", ".godot", "android", "mapbox_token.txt"]:
		var link := directory.path_join(name)
		if (source.dir_exists(name) or source.file_exists(name)) and not (DirAccess.dir_exists_absolute(link) or FileAccess.file_exists(link)):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), link) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section, key, original.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Journey QA")
	preset.set_value("preset.0", "custom_features", "journey_device_qa")
	var exclusions := str(preset.get_value("preset.0", "exclude_filter")).split(",")
	exclusions.remove_at(exclusions.find("tools/*"))
	exclusions.append_array(_tool_exclusions("res://tools"))
	preset.set_value("preset.0", "exclude_filter", ",".join(exclusions))
	preset.set_value("preset.0.options", "package/unique_name", package)
	preset.set_value("preset.0.options", "package/name", title)
	var host := "10.0.2.2" if "--journey-emulator" in OS.get_cmdline_user_args() else "127.0.0.1"
	var port := OS.get_environment("JOURNEY_PORT").to_int() if not OS.get_environment("JOURNEY_PORT").is_empty() else 3117
	assert(port > 0 and port < 65536)
	preset.set_value("preset.0.options", "command_line/extra_args", "++ --journey-base=http://%s:%d/v1" % [host, port])
	assert(preset.save(directory.path_join("export_presets.cfg")) == OK)
	print("JOURNEY_DEVICE_PROJECT ", directory)
	quit()

func _tool_exclusions(path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(path)
	for child in dir.get_files():
		var file := path.path_join(child)
		if not DRIVER_FILES.has(file): result.append(file)
	for child in dir.get_directories(): result.append_array(_tool_exclusions(path.path_join(child)))
	return result
