extends SceneTree

func _initialize() -> void:
	var run_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-run="): run_id = arg.trim_prefix("--qa-run=")
	if not run_id.is_empty() and not run_id.is_valid_filename():
		push_error("QA run ID must be a valid directory name")
		quit(2)
		return
	var output_name := "localization-qa" + ("-" + run_id if not run_id.is_empty() else "")
	var directory := ProjectSettings.globalize_path("res://output/" + output_name + "/project")
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var config := ConfigFile.new()
	assert(config.load("res://project.godot") == OK)
	config.set_value("application", "config/use_custom_user_dir", true)
	config.set_value("application", "config/custom_user_dir_name", "sensen-localization-qa-" + (run_id if not run_id.is_empty() else "20260910"))
	config.set_value("sensen", "network/base_url", "https://localization.invalid/v1")
	assert(config.save(directory.path_join("project.godot")) == OK)
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", "tests", "tools", "icon.svg", "icon.svg.import", "export_presets.cfg"]:
		if not source.file_exists(name) and not source.dir_exists(name): continue
		var target := directory.path_join(name)
		if not FileAccess.file_exists(target) and not DirAccess.dir_exists_absolute(target):
			assert(source.create_link(ProjectSettings.globalize_path("res://" + name), target) == OK)
	assert(DirAccess.make_dir_recursive_absolute(directory.path_join(".godot")) == OK)
	var imported := directory.path_join(".godot/imported")
	if not DirAccess.dir_exists_absolute(imported):
		assert(source.create_link(ProjectSettings.globalize_path("res://.godot/imported"), imported) == OK)
	print("LOCALIZATION_QA_PROJECT ", directory)
	quit()
