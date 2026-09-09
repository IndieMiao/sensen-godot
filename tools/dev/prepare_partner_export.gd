extends SceneTree

func _initialize() -> void:
	var base := OS.get_environment("SENSEN_PARTNER_BASE").strip_edges().trim_suffix("/")
	if not base.begins_with("https://") or not base.ends_with("/v1"):
		push_error("Set SENSEN_PARTNER_BASE to the HTTPS /v1 endpoint for the preview service")
		quit(1)
		return
	var directory := ProjectSettings.globalize_path("res://output/partner-apk-2026-09-08/project")
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/name", "Sensen Journey Preview")
	config.set_value("application", "config/icon", "res://assets/ui/icons/lucide/sprout.svg")
	config.set_value("sensen", "network/base_url", base)
	assert(config.save(directory.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", ".godot", "android", "mapbox_token.txt"]:
		var link := directory.path_join(name)
		if (source.dir_exists(name) or source.file_exists(name)) and not (DirAccess.dir_exists_absolute(link) or FileAccess.file_exists(link)):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), link) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section):
			preset.set_value(section, key, original.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Partner Preview")
	preset.set_value("preset.0", "custom_features", "")
	preset.set_value("preset.0", "export_path", "../sensen-journey-preview-2026-09-08.apk")
	preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeypreview")
	preset.set_value("preset.0.options", "package/name", "Sensen Journey Preview")
	preset.set_value("preset.0.options", "version/code", 2026090801)
	preset.set_value("preset.0.options", "version/name", "0.2.0-preview.20260908")
	preset.set_value("preset.0.options", "command_line/extra_args", "")
	assert(preset.save(directory.path_join("export_presets.cfg")) == OK)
	print("PARTNER_EXPORT_PREPARED ", JSON.stringify({"project": directory, "base": base}))
	quit()
