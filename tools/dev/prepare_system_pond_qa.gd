extends SceneTree

func _initialize() -> void:
	var water_pass := "--water-clarity" in OS.get_cmdline_user_args()
	var output_root := "res://output/pond-water-2026-09-24" if water_pass else "res://output/system-ponds-2026-09-24"
	var directory := ProjectSettings.globalize_path(output_root.path_join("qa-project"))
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/name", "Journey Pond QA")
	config.set_value("application", "config/use_custom_user_dir", true)
	config.set_value("application", "config/custom_user_dir_name", "sensen-system-pond-qa-20260924")
	config.set_value("application", "run/main_scene", "res://tools/dev/system_pond_qa.tscn")
	config.set_value("sensen", "network/online_qa", true)
	config.set_value("sensen", "network/base_url", "http://127.0.0.1:3201/v1")
	config.set_value("sensen", "network/mobile_base_url", "http://10.0.2.2:3201/v1")
	config.set_value("editor_plugins", "enabled", PackedStringArray())
	assert(config.save(directory.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", "android", "mapbox_token.txt", "icon.svg", "icon.svg.import"]:
		var dest := directory.path_join(name)
		if not DirAccess.open(directory).is_link(name) and not FileAccess.file_exists(dest) and not DirAccess.dir_exists_absolute(dest):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), dest) == OK)
	DirAccess.make_dir_recursive_absolute(directory.path_join("tools/dev"))
	for name in ["system_pond_qa.gd", "system_pond_qa.tscn", "pond_gallery.gd", "pond_gallery.tscn", "pond_water_gallery.gd", "pond_water_gallery.tscn"]:
		assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tools/dev/" + name), directory.path_join("tools/dev/" + name)) == OK)
	assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://output/system-ponds-2026-09-24/private/qa-account.json"), directory.path_join("pond_qa_account.json")) == OK)
	DirAccess.make_dir_recursive_absolute(directory.path_join(".godot"))
	if not DirAccess.dir_exists_absolute(directory.path_join(".godot/imported")):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), directory.path_join(".godot/imported")) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section, key, original.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Pond QA")
	preset.set_value("preset.0", "custom_features", "journey_device_qa")
	preset.set_value("preset.0", "include_filter", str(preset.get_value("preset.0", "include_filter")) + ",pond_qa_account.json,assets/ponds/*.json")
	preset.set_value("preset.0", "exclude_filter", "addons/*,tests/*,assets/avatar/source/*.fbx,docs/*,reports/*,artifacts/*,build/*,output/*,server/*,tmp/*,native/*")
	preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeypondqa")
	preset.set_value("preset.0.options", "package/name", "Journey Pond QA")
	preset.set_value("preset.0.options", "version/code", 2026092403 if water_pass else 2026092402)
	preset.set_value("preset.0.options", "version/name", "0.16.35-waterqa" if water_pass else "0.16.34-pondqa")
	assert(preset.save(directory.path_join("export_presets.cfg")) == OK)
	print("POND_QA_PROJECT ", directory)
	quit()
