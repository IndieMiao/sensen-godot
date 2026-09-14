extends SceneTree
## Package the accepted farm art for Workshop, the default app, or isolated QA.

const DRIVER_FILES := ["journey_playtest.gd", "journey_playtest.tscn", "journey_device_observer.gd"]

func _initialize() -> void:
	var qa := "--farm-app-qa" in OS.get_cmdline_user_args()
	var investor := "--farm-app-investor" in OS.get_cmdline_user_args()
	var default_app := "--farm-app-default" in OS.get_cmdline_user_args()
	var usb := "--farm-app-usb" in OS.get_cmdline_user_args()
	var partner := "--farm-app-partner" in OS.get_cmdline_user_args()
	var public_workshop := "--farm-app-public-workshop" in OS.get_cmdline_user_args()
	var public_app := partner or public_workshop
	assert(not (partner and public_workshop))
	assert(not (public_app and (qa or default_app or usb)))
	assert(not (qa and default_app))
	assert(not (usb and (qa or default_app)))
	var staging_name := "default-project" if default_app else ("qa-project" if qa else "project")
	if usb: staging_name = "usb-project"
	if public_app: staging_name = "partner-project" if partner else "public-workshop-project"
	var release_date := "2026-09-13" if investor else "2026-09-10"
	var directory := ProjectSettings.globalize_path("res://output/farm-app-" + release_date + "/" + staging_name)
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	if not default_app and not public_app:
		config.set_value("application", "config/name", "Sensen Farm Art QA" if qa else "Sensen Workshop09-09")
		config.set_value("application", "config/icon", "res://assets/ui/icons/lucide/sprout.svg")
		config.set_value("application", "run/main_scene", "res://tools/dev/journey_playtest.tscn")
		config.set_value("application", "config/use_custom_user_dir", true)
		config.set_value("application", "config/custom_user_dir_name", "sensen-farm-art-app-qa-20260910" if qa else "sensen-workshop-preview-20260909")
		config.set_value("debug", "file_logging/enable_file_logging", true)
	if public_app:
		config.set_value("application", "config/name", "Sensen Journey Preview" if partner else "Sensen Workshop09-09")
		config.set_value("application", "config/icon", "res://assets/ui/icons/lucide/sprout.svg")
		config.set_value("sensen", "network/base_url", "https://farm.sensenjoy.cn/preview/journey/v1")
		if public_workshop:
			config.set_value("application", "config/use_custom_user_dir", true)
			config.set_value("application", "config/custom_user_dir_name", "sensen-workshop-preview-20260909")
	assert(config.save(directory.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", "android", "mapbox_token.txt", "icon.svg", "icon.svg.import"]:
		var link := directory.path_join(name)
		if (source.dir_exists(name) or source.file_exists(name)) and not (DirAccess.dir_exists_absolute(link) or FileAccess.file_exists(link)):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), link) == OK)
	var staging := DirAccess.open(directory)
	if staging.is_link(".godot"):
		assert(staging.read_link(".godot") == ProjectSettings.globalize_path("res://.godot"))
		assert(staging.remove(".godot") == OK)
	# Share imported meshes/textures, but keep script discovery and editor state local.
	DirAccess.make_dir_recursive_absolute(directory.path_join(".godot"))
	if not DirAccess.dir_exists_absolute(directory.path_join(".godot/imported")):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), directory.path_join(".godot/imported")) == OK)
	# Copy only the full-game bootstrap and observer; no art preview or Blender source.
	if not default_app and not public_app:
		DirAccess.make_dir_recursive_absolute(directory.path_join("tools/dev"))
		for filename in DRIVER_FILES:
			assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tools/dev/" + filename), directory.path_join("tools/dev/" + filename)) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section, key, original.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Farm App")
	preset.set_value("preset.0", "custom_features", "journey_device_qa" if not default_app and not public_app else "")
	var exclusions := str(preset.get_value("preset.0", "exclude_filter")).split(",")
	if not default_app and not public_app and "tools/*" in exclusions: exclusions.remove_at(exclusions.find("tools/*"))
	exclusions.append("server/*")
	preset.set_value("preset.0", "exclude_filter", ",".join(exclusions))
	var apk_name := "sensen-android-farm-art-2026-09-10.apk" if default_app else ("sensen-farm-art-qa.apk" if qa else "sensen-workshop-farm-art-2026-09-10.apk")
	if usb: apk_name = "sensen-workshop-farm-art-usb-2026-09-10.apk"
	if public_app: apk_name = "sensen-journey-farm-2026-09-10.apk" if partner else "sensen-workshop-online-2026-09-10.apk"
	if investor: apk_name = apk_name.replace("2026-09-10", release_date + "-r4")
	preset.set_value("preset.0", "export_path", "../" + apk_name)
	if not default_app:
		preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeyfarmartqa" if qa else "com.sensen.workshoppreview0909")
		preset.set_value("preset.0.options", "package/name", "Sensen Farm Art QA" if qa else "Sensen Workshop09-09")
	if partner:
		preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeypreview")
		preset.set_value("preset.0.options", "package/name", "Sensen Journey Preview")
	preset.set_value("preset.0.options", "version/code", 2026091002 if public_app else 2026091001)
	preset.set_value("preset.0.options", "version/name", "0.2.0-farm-online.20260910" if public_app else "0.2.0-farm-art.20260910")
	if investor:
		preset.set_value("preset.0.options", "version/code", 2026091304)
		preset.set_value("preset.0.options", "version/name", "0.3.3-investor.20260913")
		preset.set_value("preset.0", "include_filter", str(preset.get_value("preset.0", "include_filter")) + ",assets/farm/art/styles.json,assets/farm/presets/*.json")
		if qa: preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeyinvestorqa")
	if public_app: preset.set_value("preset.0.options", "command_line/extra_args", "")
	if not default_app and not public_app:
		var host := "127.0.0.1" if usb else "10.0.2.2"
		preset.set_value("preset.0.options", "command_line/extra_args", "++ --journey-base=http://" + host + ":3134/v1")
		if investor: preset.set_value("preset.0.options", "command_line/extra_args", "++ --journey-base=http://" + host + ":3137/v1")
		if investor and qa: preset.set_value("preset.0.options", "command_line/extra_args", "++ --journey-base=http://127.0.0.1:3138/v1 --journey-city-select")
	assert(preset.save(directory.path_join("export_presets.cfg")) == OK)
	print("FARM_APP_PROJECT ", directory)
	quit()
