extends SceneTree
## Worktree-local, offline art viewer. Never shares Android build outputs or saves.
func _initialize() -> void:
	# Captures and archived scripts are not source: do not let their class_name
	# declarations replace runtime classes in the parent project's import cache.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	if not FileAccess.file_exists("res://output/.gdignore"):
		FileAccess.open("res://output/.gdignore", FileAccess.WRITE).close()
	var directory := ProjectSettings.globalize_path("res://output/pond-reference-2026-09-29/project")
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/name", "Gensen Pond Art")
	config.set_value("application", "config/features", PackedStringArray(["4.7", "Mobile"]))
	config.set_value("application", "config/use_custom_user_dir", true)
	config.set_value("application", "config/custom_user_dir_name", "sensen-pond-art-" + str(ProjectSettings.globalize_path("res://").hash()))
	config.set_value("application", "run/main_scene", "res://tools/dev/pond_pitch.tscn")
	config.set_value("sensen", "network/online_qa", true)
	config.set_value("sensen", "network/base_url", "http://127.0.0.1:9/v1")
	config.set_value("sensen", "network/mobile_base_url", "http://127.0.0.1:9/v1")
	config.set_value("editor_plugins", "enabled", PackedStringArray())
	config.set_value("display", "window/size/window_width_override", 1280)
	config.set_value("display", "window/size/window_height_override", 800)
	config.set_value("display", "window/handheld/orientation", 0)
	assert(config.save(directory.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "addons", "icon.svg"]:
		if not DirAccess.open(directory).is_link(name):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), directory.path_join(name)) == OK)
	# Export only this viewer, not unrelated historical QA scripts.
	if DirAccess.open(directory).is_link("tools"):
		assert(DirAccess.remove_absolute(directory.path_join("tools")) == OK)
	DirAccess.make_dir_recursive_absolute(directory.path_join("tools/dev"))
	for name in ["pond_pitch.gd", "pond_pitch.gd.uid", "pond_pitch.tscn"]:
		assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tools/dev/" + name), directory.path_join("tools/dev/" + name)) == OK)
	DirAccess.make_dir_recursive_absolute(directory.path_join(".godot"))
	# Only this worktree's cache. The other branch has a different .godot directory.
	if not DirAccess.dir_exists_absolute(directory.path_join(".godot/imported")):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), directory.path_join(".godot/imported")) == OK)
	assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://.godot/global_script_class_cache.cfg"), directory.path_join(".godot/global_script_class_cache.cfg")) == OK)
	var original := ConfigFile.new()
	assert(original.load("res://export_presets.cfg") == OK)
	var preset := ConfigFile.new()
	for section in ["preset.0", "preset.0.options"]:
		for key in original.get_section_keys(section): preset.set_value(section, key, original.get_value(section, key))
	preset.set_value("preset.0", "name", "Android Pond Art")
	preset.set_value("preset.0", "include_filter", "assets/ponds/*.json,assets/farm/data/*.json,assets/localization/*.json,assets/avatar/*.json")
	preset.set_value("preset.0", "export_filter", "all_resources")
	preset.set_value("preset.0", "exclude_filter", "addons/gdUnit4/*,tests/*,docs/*,reports/*,build/*,output/*,server/*,native/*,assets/avatar/source/*.fbx")
	# The scene uses core Godot rendering: no Gradle/Mapbox/voice build is needed.
	preset.set_value("preset.0.options", "gradle_build/use_gradle_build", false)
	preset.set_value("preset.0.options", "package/unique_name", "com.sensen.pondart.calmcloud")
	preset.set_value("preset.0.options", "package/name", "Gensen Pond Art")
	preset.set_value("preset.0.options", "version/code", 2026092901)
	preset.set_value("preset.0.options", "version/name", "pond-reference-2026-09-29")
	assert(preset.save(directory.path_join("export_presets.cfg")) == OK)
	print("POND_ART_PROJECT ", directory)
	quit()
