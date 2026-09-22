extends SceneTree

func _initialize() -> void:
	var mining := "--journey-mining" in OS.get_cmdline_user_args()
	var inventory := "--journey-inventory" in OS.get_cmdline_user_args()
	var character := "--journey-character" in OS.get_cmdline_user_args()
	var requests := "--journey-requests" in OS.get_cmdline_user_args()
	var combat := "--journey-combat" in OS.get_cmdline_user_args()
	var directory := ProjectSettings.globalize_path("res://output/mining-playtest/project" if mining else "res://output/journey-playtest/project")
	if inventory: directory = ProjectSettings.globalize_path("res://output/inventory-playtest/project")
	if character: directory = ProjectSettings.globalize_path("res://output/character-playtest/project")
	if requests: directory = ProjectSettings.globalize_path("res://output/requests-playtest/project")
	if combat: directory = ProjectSettings.globalize_path("res://output/combat-playtest/project")
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	if config.load("res://project.godot") != OK:
		quit(1)
		return
	config.set_value("application", "config/name", "Sensen Starter Mine" if mining else "Sensen Journey Playtest")
	config.set_value("application", "config/use_custom_user_dir", true)
	config.set_value("application", "config/custom_user_dir_name", "sensen-mining-playtest-20260914" if mining else "sensen-journey-playtest-v7")
	if inventory:
		config.set_value("application", "config/name", "Sensen Inventory")
		config.set_value("application", "config/custom_user_dir_name", "sensen-inventory-playtest-20260914")
	if character:
		config.set_value("application", "config/name", "Sensen Character")
		config.set_value("application", "config/custom_user_dir_name", "sensen-character-playtest-20260914")
	if requests:
		config.set_value("application", "config/name", "Sensen Requests")
		config.set_value("application", "config/custom_user_dir_name", "sensen-requests-playtest-20260914")
	config.set_value("application", "config/icon", "res://assets/ui/icons/lucide/sprout.svg")
	if combat:
		config.set_value("application", "config/name", "Sensen Combat")
		config.set_value("application", "config/custom_user_dir_name", "sensen-combat-playtest-20260915")
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
