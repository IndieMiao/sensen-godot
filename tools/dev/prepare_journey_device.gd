extends SceneTree

const DRIVER_FILES := ["res://tools/dev/journey_playtest.gd", "res://tools/dev/journey_playtest.tscn", "res://tools/dev/journey_device_observer.gd"]

func _initialize() -> void:
	var mining := "--journey-mining" in OS.get_cmdline_user_args()
	var inventory := "--journey-inventory" in OS.get_cmdline_user_args()
	var character := "--journey-character" in OS.get_cmdline_user_args()
	var requests := "--journey-requests" in OS.get_cmdline_user_args()
	var combat := "--journey-combat" in OS.get_cmdline_user_args()
	var isolated := mining or inventory or character or requests or combat
	var directory := ProjectSettings.globalize_path("res://output/mining-device-2026-09-14/project" if mining else "res://output/journey-device/project")
	var package := "com.sensen.journeyminingqa" if mining else "com.sensen.journeyqa"
	var title := "Sensen Mining QA" if mining else "Sensen Journey QA"
	if inventory:
		directory = ProjectSettings.globalize_path("res://output/inventory-emulator-2026-09-14/project")
		package = "com.sensen.journeyinventoryqa"
		title = "Sensen Inventory QA"
	if character:
		directory = ProjectSettings.globalize_path("res://output/character-emulator-2026-09-14/project")
		package = "com.sensen.journeycharacterqa"
		title = "Sensen Character QA"
	if requests:
		directory = ProjectSettings.globalize_path("res://output/requests-emulator-2026-09-14/project")
		package = "com.sensen.journeyrequestsqa"
		title = "Sensen Requests QA"
	if combat:
		directory = ProjectSettings.globalize_path("res://output/combat-emulator-2026-09-15/project")
		package = "com.sensen.journeycombatqa"
		title = "街角四季·战斗测试"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--journey-output="):
			directory = ProjectSettings.globalize_path(arg.trim_prefix("--journey-output="))
		elif arg.begins_with("--journey-package="):
			package = arg.trim_prefix("--journey-package=")
		elif arg.begins_with("--journey-title="):
			title = arg.trim_prefix("--journey-title=")
	var package_pattern := RegEx.create_from_string("^com\\.sensen\\.journey[a-z0-9_]*qa$")
	assert(package_pattern.search(package) != null)
	var host := "10.0.2.2" if "--journey-emulator" in OS.get_cmdline_user_args() else "127.0.0.1"
	var port := OS.get_environment("JOURNEY_PORT").to_int() if not OS.get_environment("JOURNEY_PORT").is_empty() else (3155 if combat else (3153 if requests else (3151 if character else (3149 if inventory else (3147 if mining else 3117)))))
	assert(port > 0 and port < 65536)
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/name", title)
	config.set_value("application", "config/icon", "res://assets/ui/icons/lucide/sprout.svg")
	config.set_value("application", "run/main_scene", "res://tools/dev/journey_playtest.tscn")
	config.set_value("debug", "file_logging/enable_file_logging", true)
	if isolated:
		config.set_value("application", "config/use_custom_user_dir", true)
		config.set_value("application", "config/custom_user_dir_name", "sensen-inventory-local-qa-20260914" if inventory else "sensen-mining-local-qa-20260914")
		config.set_value("sensen", "network/base_url", "http://%s:%d/v1" % [host, port])
	if character: config.set_value("application", "config/custom_user_dir_name", "sensen-character-local-qa-20260914")
	if requests: config.set_value("application", "config/custom_user_dir_name", "sensen-requests-local-qa-20260914")
	if combat: config.set_value("application", "config/custom_user_dir_name", "sensen-combat-local-qa-20260915")
	assert(config.save(directory.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", "tools", ".godot", "android", "mapbox_token.txt"]:
		if isolated and name in ["tools", ".godot"]: continue
		var link := directory.path_join(name)
		if (source.dir_exists(name) or source.file_exists(name)) and not (DirAccess.dir_exists_absolute(link) or FileAccess.file_exists(link)):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), link) == OK)
	if isolated:
		DirAccess.make_dir_recursive_absolute(directory.path_join(".godot"))
		if not DirAccess.dir_exists_absolute(directory.path_join(".godot/imported")):
			assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), directory.path_join(".godot/imported")) == OK)
		DirAccess.make_dir_recursive_absolute(directory.path_join("tools/dev"))
		for file in DRIVER_FILES:
			assert(DirAccess.copy_absolute(ProjectSettings.globalize_path(file), directory.path_join(file.trim_prefix("res://"))) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section, key, original.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Journey QA")
	preset.set_value("preset.0", "custom_features", "journey_device_qa")
	var exclusions := str(preset.get_value("preset.0", "exclude_filter")).split(",")
	exclusions.remove_at(exclusions.find("tools/*"))
	if not isolated: exclusions.append_array(_tool_exclusions("res://tools"))
	exclusions.append("server/*")
	preset.set_value("preset.0", "exclude_filter", ",".join(exclusions))
	preset.set_value("preset.0.options", "package/unique_name", package)
	preset.set_value("preset.0.options", "package/name", title)
	if isolated:
		preset.set_value("preset.0", "include_filter", str(preset.get_value("preset.0", "include_filter")) + ",assets/farm/data/*.json,assets/farm/art/styles.json,assets/farm/presets/*.json")
		preset.set_value("preset.0", "export_path", "../sensen-mining-local-qa-2026-09-14.apk")
		preset.set_value("preset.0.options", "version/code", 2026091405)
		preset.set_value("preset.0.options", "version/name", "0.4.0-mining-local.20260914.r5")
	if inventory:
		preset.set_value("preset.0", "export_path", "../sensen-inventory-local-qa-2026-09-14.apk")
		preset.set_value("preset.0.options", "version/code", 2026091406)
		preset.set_value("preset.0.options", "version/name", "0.5.0-inventory-local.20260914.r1")
	if character:
		preset.set_value("preset.0", "export_path", "../sensen-character-local-qa-2026-09-14.apk")
		preset.set_value("preset.0.options", "version/code", 2026091407)
		preset.set_value("preset.0.options", "version/name", "0.6.0-character-local.20260914.r1")
	if requests:
		preset.set_value("preset.0", "export_path", "../sensen-requests-local-qa-2026-09-14.apk")
		preset.set_value("preset.0.options", "version/code", 2026091409)
		preset.set_value("preset.0.options", "version/name", "0.7.0-requests-local.20260914.r2")
	preset.set_value("preset.0.options", "command_line/extra_args", "++ --journey-base=http://%s:%d/v1" % [host, port])
	if combat:
		preset.set_value("preset.0", "export_path", "../sensen-combat-local-qa-2026-09-15.apk")
		preset.set_value("preset.0.options", "version/code", 2026091507)
		preset.set_value("preset.0.options", "version/name", "0.9.0-combat-local.20260915.r5")
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
