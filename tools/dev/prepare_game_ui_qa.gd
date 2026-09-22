extends SceneTree
## Separate development project and identity for UI screenshots and HTTP actions.
func _initialize() -> void:
	var gallery := "--gallery" in OS.get_cmdline_user_args()
	var folder := ProjectSettings.globalize_path("res://output/ui-redesign-2026-09-21/" + ("gallery-project" if gallery else "qa-project"))
	DirAccess.make_dir_recursive_absolute(folder)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/name", "Journey UI QA")
	config.set_value("application", "config/use_custom_user_dir", true)
	config.set_value("application", "config/custom_user_dir_name", "sensen-game-ui-gallery-20260921" if gallery else "sensen-game-ui-http-20260921")
	config.set_value("application", "run/main_scene", "res://tools/dev/game_ui_gallery.tscn" if gallery else "res://tools/dev/game_ui_probe.tscn")
	config.set_value("sensen", "network/online_qa", true)
	config.set_value("editor_plugins", "enabled", PackedStringArray())
	if gallery:
		config.set_value("display", "window/size/window_width_override", 360)
		config.set_value("display", "window/size/window_height_override", 780)
		config.set_value("gallery", "output", ProjectSettings.globalize_path("res://output/ui-redesign-2026-09-21/gallery"))
	assert(config.save(folder.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", "android", "mapbox_token.txt", "icon.svg", "icon.svg.import"]:
		var dest := folder.path_join(name)
		if not DirAccess.open(folder).is_link(name) and not FileAccess.file_exists(dest) and not DirAccess.dir_exists_absolute(dest):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), dest) == OK)
	if gallery:
		if not DirAccess.open(folder).is_link("tools"):
			assert(source.create_link(ProjectSettings.globalize_path("res://tools"), folder.path_join("tools")) == OK)
	else:
		if DirAccess.open(folder).is_link("tools"):
			assert(DirAccess.remove_absolute(folder.path_join("tools")) == OK)
		DirAccess.make_dir_recursive_absolute(folder.path_join("tools/dev"))
		for name in ["game_ui_probe.gd", "game_ui_probe.tscn", "game_ui_observer.gd"]:
			assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tools/dev/" + name), folder.path_join("tools/dev/" + name)) == OK)
	DirAccess.make_dir_recursive_absolute(folder.path_join(".godot"))
	if not DirAccess.dir_exists_absolute(folder.path_join(".godot/imported")):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), folder.path_join(".godot/imported")) == OK)
	var dto: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://output/ui-redesign-2026-09-21/private/source-farm.json"))
	dto.farm_id = "gallery-current-contract"
	FileAccess.open(folder.path_join("gallery_farm.json"), FileAccess.WRITE).store_string(JSON.stringify(dto))
	assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://output/ui-redesign-2026-09-21/device/private/baseline/avatar/outfit_local.json"), folder.path_join("gallery_outfit.json")) == OK)
	if not gallery:
		assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://output/ui-redesign-2026-09-21/private/qa-account.json"), folder.path_join("ui_qa_account.json")) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section, key, original.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Game UI QA")
	preset.set_value("preset.0", "custom_features", "journey_device_qa")
	preset.set_value("preset.0", "include_filter", "gallery_farm.json,gallery_outfit.json,ui_qa_account.json,mapbox_token.txt,assets/localization/*.json,assets/farm/data/*.json,assets/farm/art/styles.json,assets/farm/presets/*.json,assets/blueprints/**/*.json,assets/avatar/**/*.json")
	preset.set_value("preset.0", "exclude_filter", "addons/*,tests/*,assets/avatar/source/*.fbx,docs/*,reports/*,artifacts/*,build/*,output/*,server/*,tmp/*,native/*")
	preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeyuiqa")
	preset.set_value("preset.0.options", "package/name", "Journey UI QA")
	preset.set_value("preset.0.options", "version/code", 2026092106)
	preset.set_value("preset.0.options", "version/name", "0.16.10-qa")
	assert(preset.save(folder.path_join("export_presets.cfg")) == OK)
	print("GAME_UI_PROJECT ", folder)
	quit()
