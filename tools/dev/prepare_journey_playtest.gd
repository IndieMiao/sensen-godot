extends SceneTree

func _initialize() -> void:
	var directory := ProjectSettings.globalize_path("res://output/journey-playtest/project")
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	if config.load("res://project.godot") != OK:
		quit(1)
		return
	config.set_value("application", "config/name", "Sensen Journey Playtest")
	config.set_value("application", "config/use_custom_user_dir", true)
	config.set_value("application", "config/custom_user_dir_name", "sensen-journey-playtest-v7")
	config.set_value("application", "config/icon", "res://assets/ui/icons/lucide/sprout.svg")
	config.set_value("application", "run/main_scene", "res://tools/dev/journey_playtest.tscn")
	if "--journey-smoke" in OS.get_cmdline_user_args():
		config.set_value("application", "config/custom_user_dir_name", "sensen-journey-smoke-v7")
	config.save(directory.path_join("project.godot"))
	var source := DirAccess.open("res://")
	for name in ["assets", "modules", "scenes", "shaders", "addons", "tools", ".godot"]:
		if source.dir_exists(name) and not DirAccess.dir_exists_absolute(directory.path_join(name)):
			if source.create_link(ProjectSettings.globalize_path("res://" + name), directory.path_join(name)) != OK:
				push_error("Cannot link " + name)
				quit(1)
				return
	print("JOURNEY_PROJECT ", directory)
	quit()
