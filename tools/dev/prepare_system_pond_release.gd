extends SceneTree
## Final Journey project only. Development observers have a separate QA project.
const RELEASE_ROOT := "res://output/system-ponds-2026-09-24/release"
const VERSION := "0.16.34"
const VERSION_CODE := 2026092402

func _initialize() -> void:
	var water_pass := "--water-clarity" in OS.get_cmdline_user_args()
	var release_root := "res://output/pond-water-2026-09-24/release" if water_pass else RELEASE_ROOT
	var version := "0.16.35" if water_pass else VERSION
	var version_code := 2026092403 if water_pass else VERSION_CODE
	var integrated := "--integrated" in OS.get_cmdline_user_args()
	var motion_fix := "--motion-fix" in OS.get_cmdline_user_args()
	var voice_match := "--voice-match" in OS.get_cmdline_user_args()
	if integrated:
		release_root = "res://output/integrated-release-20260924/release"
		version = "0.16.36"
		version_code = 2026092404
	if motion_fix:
		release_root = "res://output/avatar-motion-20260924/release"
		version = "0.16.37"
		version_code = 2026092405
	if voice_match:
		release_root = "res://output/voice-match-20260925/release"
		version = "0.16.38"
		version_code = 2026092501
	var folder := ProjectSettings.globalize_path(release_root.path_join("project"))
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/name", "Sensen Journey Preview")
	config.set_value("application", "config/icon", "res://assets/ui/icons/lucide/sprout.svg")
	config.set_value("application", "run/main_scene", "res://scenes/city_select/city_select.tscn")
	for key in ["config/use_custom_user_dir", "config/custom_user_dir_name"]:
		if config.has_section_key("application", key): config.erase_section_key("application", key)
	config.set_value("debug", "file_logging/enable_file_logging", true)
	config.set_value("sensen", "network/base_url", "https://farm.sensenjoy.cn/preview/journey/v1")
	if config.has_section_key("sensen", "network/online_qa"):
		config.erase_section_key("sensen", "network/online_qa")
	config.set_value("editor_plugins", "enabled", PackedStringArray())
	for autoload in config.get_section_keys("autoload"):
		if autoload not in ["Localization", "Avatar", "AppRouter", "Net", "Voice"]:
			config.erase_section_key("autoload", autoload)
	assert(config.save(folder.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "android", "mapbox_token.txt", "icon.svg", "icon.svg.import"]:
		var dest := folder.path_join(name)
		if not DirAccess.open(folder).is_link(name) and not FileAccess.file_exists(dest) and not DirAccess.dir_exists_absolute(dest):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), dest) == OK)
	assert(not FileAccess.file_exists(folder.path_join("physical_observer.gd")))
	assert(not FileAccess.file_exists(folder.path_join("game_ui_observer.gd")))
	DirAccess.make_dir_recursive_absolute(folder.path_join(".godot"))
	if not DirAccess.dir_exists_absolute(folder.path_join(".godot/imported")):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), folder.path_join(".godot/imported")) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section, key, original.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Pond Update")
	if integrated:
		preset.set_value("preset.0", "name", "Android Integrated Update")
	if motion_fix:
		preset.set_value("preset.0", "name", "Android Motion Update")
	if voice_match:
		preset.set_value("preset.0", "name", "Android Voice Match Update")
	preset.set_value("preset.0", "custom_features", "")
	preset.set_value("preset.0", "include_filter", "mapbox_token.txt,assets/ponds/*.json,assets/map/*.json,assets/map/cities/*.json,assets/localization/*.json,assets/landmarks/griffith_observatory/layout.json,assets/farm/data/*.json,assets/farm/art/styles.json,assets/farm/presets/*.json,assets/blueprints/**/*.json,assets/avatar/**/*.json,assets/ui/icons/game/LICENSE.txt,assets/ui/icons/lucide/LICENSE,assets/ui/fonts/LICENSE-NotoSansSC.txt,assets/ui/fonts/Nunito-OFL.txt")
	preset.set_value("preset.0", "exclude_filter", "addons/*,tests/*,assets/avatar/source/*.fbx,tools/*,docs/*,reports/*,artifacts/*,build/*,output/*,server/*,tmp/*,native/*,*observer*,*probe*,*qa_account*,gallery_*.json,.playwright-mcp/*")
	preset.set_value("preset.0", "export_path", "../sensen-journey-ponds-" + version + ".apk")
	if integrated:
		preset.set_value("preset.0", "export_path", "../sensen-journey-integrated-" + version + ".apk")
	if motion_fix:
		preset.set_value("preset.0", "export_path", "../sensen-journey-motion-" + version + ".apk")
	if voice_match:
		preset.set_value("preset.0", "export_path", "../sensen-journey-voicematch-" + version + ".apk")
	preset.set_value("preset.0.options", "package/unique_name", "com.sensen.journeypreview")
	preset.set_value("preset.0.options", "package/name", "Sensen Journey Preview")
	preset.set_value("preset.0.options", "package/signed", true)
	preset.set_value("preset.0.options", "command_line/extra_args", "")
	preset.set_value("preset.0.options", "version/code", version_code)
	preset.set_value("preset.0.options", "version/name", version)
	assert(preset.save(folder.path_join("export_presets.cfg")) == OK)
	var provenance := {
		"package": "com.sensen.journeypreview", "version": version, "versionCode": version_code,
		"project": folder, "client_only": motion_fix or voice_match, "required_backend_feature": "system_ponds_v1", "backend_deployed": motion_fix or voice_match,
		"observer_included": false, "qa_feature_enabled": false,
		"source_files_are_symlinks": true, "original_signing_configuration_retained": true,
		"source_project_sha256": FileAccess.get_sha256("res://project.godot"),
		"prepared_project_sha256": FileAccess.get_sha256(folder.path_join("project.godot")),
		"prepare_script_sha256": FileAccess.get_sha256("res://tools/dev/prepare_system_pond_release.gd"),
		"prepared_at": Time.get_datetime_string_from_system(true),
	}
	var file := FileAccess.open(release_root.path_join("project-prepared.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(provenance, "  ") + "\n")
	file.close()
	print("FINAL_JOURNEY_PROJECT ", folder)
	quit()
