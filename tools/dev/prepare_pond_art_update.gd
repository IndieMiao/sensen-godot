extends SceneTree
## Run against the isolated integrated source, with an explicit artifact folder.
# Farm pond retirement also requires the domain-28 backend migration.
const VERSION := "0.16.40"
const VERSION_CODE := 2026092503

func _initialize() -> void:
	assert(FileAccess.file_exists("res://modules/net/voice_match_link.gd"), "Build from the integrated source so the installed Voice Profile is retained.")
	assert(FileAccess.file_exists("res://android/build/src/main/java/com/sensen/webview/GodotWebViewPlugin.kt"), "Prepare the native WebView plugin before exporting.")
	var destination := ""
	var inspect := "--inspect" in OS.get_cmdline_user_args()
	var mine_max_view := "--mine-max-view" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--destination="): destination = arg.trim_prefix("--destination=")
	assert(destination.is_absolute_path())
	var folder := destination.path_join("inspection-project" if inspect else "project")
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	# Preserve the currently installed app's name, native WebView entry, splash,
	# autoloads and user directory. Only add logging for installation readback.
	config.set_value("debug", "file_logging/enable_file_logging", true)
	config.set_value("sensen", "network/base_url", "https://farm.sensenjoy.cn/preview/journey/v1")
	config.set_value("sensen", "network/mobile_base_url", "https://farm.sensenjoy.cn/preview/journey/v1")
	if config.has_section_key("sensen", "network/online_qa"): config.erase_section_key("sensen", "network/online_qa")
	config.set_value("editor_plugins", "enabled", PackedStringArray())
	if inspect:
		config.set_value("autoload", "PondDeviceObserver", "*res://pond_device_observer.gd")
		assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tools/dev/pond_device_observer.gd"), folder.path_join("pond_device_observer.gd")) == OK)
	assert(config.save(folder.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "android", "mapbox_token.txt", "icon.svg", "icon.svg.import"]:
		if not DirAccess.open(folder).is_link(name):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), folder.path_join(name)) == OK)
	DirAccess.make_dir_recursive_absolute(folder.path_join(".godot"))
	if not DirAccess.dir_exists_absolute(folder.path_join(".godot/imported")):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"),folder.path_join(".godot/imported")) == OK)
	assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://.godot/global_script_class_cache.cfg"),folder.path_join(".godot/global_script_class_cache.cfg")) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section,key,original.get_value(section,key))
	preset.set_value("preset.0", "name", "Android Mine Camera Update" if mine_max_view else "Android Pond Art Update")
	preset.set_value("preset.0", "custom_features", "")
	preset.set_value("preset.0", "include_filter", "mapbox_token.txt,assets/ponds/*.json,assets/map/*.json,assets/map/cities/*.json,assets/localization/*.json,assets/landmarks/griffith_observatory/layout.json,assets/farm/data/*.json,assets/farm/art/styles.json,assets/farm/presets/*.json,assets/blueprints/**/*.json,assets/avatar/**/*.json,assets/ui/icons/game/LICENSE.txt,assets/ui/icons/lucide/LICENSE,assets/ui/fonts/LICENSE-NotoSansSC.txt,assets/ui/fonts/Nunito-OFL.txt")
	preset.set_value("preset.0", "exclude_filter", "addons/*,tests/*,assets/avatar/source/*.fbx,tools/*,docs/*,reports/*,artifacts/*,build/*,output/*,server/*,packages/*,tmp/*,native/*,*probe*,*qa_account*,gallery_*.json,.playwright-mcp/*" + ("" if inspect else ",*observer*"))
	preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeypreview")
	preset.set_value("preset.0.options", "package/name", "Sensen Journey Preview")
	preset.set_value("preset.0.options", "package/signed", true)
	preset.set_value("preset.0.options", "command_line/extra_args", "")
	preset.set_value("preset.0.options", "version/code", 2026092504 if mine_max_view else VERSION_CODE)
	preset.set_value("preset.0.options", "version/name", "0.16.41" if mine_max_view else VERSION)
	assert(preset.save(folder.path_join("export_presets.cfg")) == OK)
	print("POND_UPDATE_PROJECT ",folder)
	quit()
