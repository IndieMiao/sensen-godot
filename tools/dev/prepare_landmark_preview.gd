extends SceneTree
## Isolated art preview: no production identity directory and no network boot.
func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://output/griffith-rebuild-2026-09-23/project")
	DirAccess.make_dir_recursive_absolute(folder)
	var cfg := ConfigFile.new()
	assert(cfg.load("res://project.godot") == OK)
	cfg.set_value("application", "config/name", "Griffith Art Review")
	cfg.set_value("application", "config/use_custom_user_dir", true)
	cfg.set_value("application", "config/custom_user_dir_name", "sensen-griffith-art-review")
	cfg.set_value("application", "run/main_scene", "res://tools/dev/landmark_preview.tscn")
	cfg.set_value("sensen", "network/online_qa", true)
	cfg.set_value("sensen", "network/base_url", "http://127.0.0.1:9/v1")
	cfg.set_value("sensen", "network/mobile_base_url", "http://127.0.0.1:9/v1")
	cfg.set_value("editor_plugins", "enabled", PackedStringArray())
	assert(cfg.save(folder.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "docs", "android", "mapbox_token.txt", "icon.svg", "icon.svg.import"]:
		if not DirAccess.open(folder).is_link(name):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), folder.path_join(name)) == OK)
	if DirAccess.open(folder).is_link("tools"):
		assert(DirAccess.remove_absolute(folder.path_join("tools")) == OK)
	DirAccess.make_dir_recursive_absolute(folder.path_join("tools/dev"))
	for name in ["landmark_preview.gd", "landmark_preview.gd.uid", "landmark_preview.tscn"]:
		var dest := folder.path_join("tools/dev").path_join(name)
		if not FileAccess.file_exists(dest):
			assert(source.create_link(ProjectSettings.globalize_path("res://tools/dev/" + name),dest) == OK)
	DirAccess.make_dir_recursive_absolute(folder.path_join(".godot"))
	if not DirAccess.open(folder.path_join(".godot")).is_link("imported"):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), folder.path_join(".godot/imported")) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section,key,original.get_value(section,key))
	preset.set_value("preset.0", "name", "Griffith QA")
	preset.set_value("preset.0", "custom_features", "journey_device_qa")
	preset.set_value("preset.0", "include_filter", "assets/**/*.json,assets/farm/art/styles.json,assets/ui/fonts/*.txt,mapbox_token.txt")
	preset.set_value("preset.0", "exclude_filter", "addons/*,tests/*,docs/*,reports/*,artifacts/*,build/*,output/*,assets/avatar/source/*.fbx,tools/art/*")
	preset.set_value("preset.0", "export_path", "../griffith-art-qa.apk")
	preset.set_value("preset.0.options", "package/unique_name", "com.sensen.griffithqa")
	preset.set_value("preset.0.options", "package/name", "Griffith Art Review")
	preset.set_value("preset.0.options", "version/code", 2026092312)
	preset.set_value("preset.0.options", "version/name", "0.1-art-review")
	assert(preset.save(folder.path_join("export_presets.cfg")) == OK)
	print("OFFLINE_LANDMARK_PROJECT ",folder)
	quit()
