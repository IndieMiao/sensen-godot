extends SceneTree
func _initialize() -> void:
	var stats: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://ruin_details_stats.json"))
	for name in stats.assets:
		var path:="res://assets/landmarks/alcatraz_island/"+str(name)+".glb.import"
		var config:=ConfigFile.new();assert(config.load(path)==OK)
		assert(str(config.get_value("remap","uid","")).begins_with("uid://"))
		config.set_value("params","gltf/texture_map_mode",1)
		config.set_value("params","meshes/light_baking",1)
		config.set_value("params","meshes/ensure_tangents",false)
		config.set_value("params","meshes/generate_lods",false)
		config.set_value("params","meshes/create_shadow_meshes",false)
		config.set_value("params","animation/import",false)
		assert(config.save(path)==OK)
	print("RUIN_IMPORTS ",stats.assets.size()," Godot UIDs generated")
	quit()
