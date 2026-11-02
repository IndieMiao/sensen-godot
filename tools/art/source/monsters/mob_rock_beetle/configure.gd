extends SceneTree
const KIT := "res://assets/monsters/mob_rock_beetle/"
const MODEL := KIT + "mob_rock_beetle.glb"
func _initialize() -> void:
	var previous := ConfigFile.new()
	assert(previous.load(MODEL + ".import") == OK)
	var config := ConfigFile.new()
	assert(config.load("res://assets/monsters/mob_cave_bat/mob_cave_bat.glb.import") == OK)
	for entry in [["remap","uid"],["remap","path"],["deps","source_file"],["deps","dest_files"]]:
		config.set_value(entry[0],entry[1],previous.get_value(entry[0],entry[1]))
	config.set_value("params","animation/remove_immutable_tracks",false)
	config.set_value("params","nodes/use_name_suffixes",true)
	config.set_value("params","meshes/ensure_tangents",false)
	config.set_value("params","meshes/create_shadow_meshes",false)
	config.set_value("params","_subresources",{})
	config.save(MODEL + ".import")
	print("BEETLE_UID ",config.get_value("remap","uid",""))
	quit()
