extends SceneTree
## Temporary read-only observation project. The final package uses its own clean
## project and never includes this observer, test transport or account data.
func _initialize() -> void:
	var release := ProjectSettings.globalize_path("res://output/ui-redesign-2026-09-21/release/project")
	var folder := ProjectSettings.globalize_path("res://output/ui-redesign-2026-09-21/device/project")
	DirAccess.make_dir_recursive_absolute(folder)
	var config := ConfigFile.new()
	assert(config.load(release.path_join("project.godot")) == OK)
	config.set_value("autoload", "UiObservation", "*res://game_ui_observer.gd")
	assert(config.save(folder.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "android", "mapbox_token.txt", "icon.svg", "icon.svg.import"]:
		var dest := folder.path_join(name)
		if not DirAccess.open(folder).is_link(name) and not FileAccess.file_exists(dest) and not DirAccess.dir_exists_absolute(dest):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), dest) == OK)
	DirAccess.make_dir_recursive_absolute(folder.path_join(".godot"))
	if not DirAccess.dir_exists_absolute(folder.path_join(".godot/imported")):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), folder.path_join(".godot/imported")) == OK)
	assert(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tools/dev/game_ui_observer.gd"), folder.path_join("game_ui_observer.gd")) == OK)
	var preset := ConfigFile.new()
	assert(preset.load(release.path_join("export_presets.cfg")) == OK)
	preset.set_value("preset.0", "name", "Android Game UI Observation")
	preset.set_value("preset.0", "export_path", "../instrumented.apk")
	preset.set_value("preset.0", "exclude_filter", str(preset.get_value("preset.0", "exclude_filter")).replace(",*observer*", ""))
	assert(preset.save(folder.path_join("export_presets.cfg")) == OK)
	quit()
