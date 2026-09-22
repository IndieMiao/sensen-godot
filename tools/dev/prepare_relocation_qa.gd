extends SceneTree

func _initialize() -> void:
	var physical := false
	var directory := ProjectSettings.globalize_path("res://output/farm-relocation-2026-09-21/qa/project")
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/name", "农场迁居测试")
	config.set_value("application", "config/use_custom_user_dir", true)
	config.set_value("application", "config/custom_user_dir_name", "sensen-relocation-qa-20260921")
	config.set_value("application", "run/main_scene", "res://tools/dev/relocation_probe.tscn")
	config.set_value("sensen", "network/online_qa", true)
	if physical: config.set_value("sensen", "network/private_farm_qa_host", "127.0.0.1")
	assert(config.save(directory.path_join("project.godot")) == OK)
	var root := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", "android", "mapbox_token.txt", "icon.svg", "icon.svg.import"]:
		var link := directory.path_join(name)
		if not DirAccess.open(directory).is_link(name) and not FileAccess.file_exists(link) and not DirAccess.dir_exists_absolute(link):
			assert(root.create_link(ProjectSettings.globalize_path("res://" + name), link) == OK)
	DirAccess.make_dir_recursive_absolute(directory.path_join(".godot"))
	if not DirAccess.dir_exists_absolute(directory.path_join(".godot/imported")):
		assert(root.create_link(ProjectSettings.globalize_path("res://.godot/imported"), directory.path_join(".godot/imported")) == OK)
	DirAccess.make_dir_recursive_absolute(directory.path_join("tools/dev"))
	for file in ["relocation_probe.gd", "relocation_probe.tscn"]:
		assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tools/dev/" + file), directory.path_join("tools/dev/" + file)) == OK)
	assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://output/farm-relocation-2026-09-21/qa/private/account.json"), directory.path_join("relocation_account.json")) == OK)
	var source := ConfigFile.new()
	assert(source.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in source.get_section_keys(section): preset.set_value(section, key, source.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Relocation QA")
	preset.set_value("preset.0", "custom_features", "journey_device_qa")
	var exclusions := str(preset.get_value("preset.0", "exclude_filter")).split(",")
	if "tools/*" in exclusions: exclusions.remove_at(exclusions.find("tools/*"))
	preset.set_value("preset.0", "exclude_filter", ",".join(exclusions))
	preset.set_value("preset.0", "include_filter", "relocation_account.json,mapbox_token.txt,assets/localization/*.json,assets/farm/data/*.json,assets/farm/art/styles.json")
	preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeyrelocationqa")
	preset.set_value("preset.0.options", "package/name", "农场迁居测试")
	preset.set_value("preset.0.options", "version/code", 2026092102)
	preset.set_value("preset.0.options", "version/name", "0.16.6-relocation-qa")
	preset.set_value("preset.0.options", "architectures/x86_64", not physical)
	assert(preset.save(directory.path_join("export_presets.cfg")) == OK)
	print("PRIVATE_FARM_QA_PROJECT ", directory)
	quit()
