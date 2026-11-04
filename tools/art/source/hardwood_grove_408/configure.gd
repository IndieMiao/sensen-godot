extends SceneTree
func _initialize() -> void:
	var path:="res://assets/farm/art/hardwood_grove.glb.import"
	var config:=ConfigFile.new();assert(config.load(path)==OK)
	config.set_value("params","gltf/texture_map_mode",1)
	config.set_value("params","meshes/ensure_tangents",false)
	config.set_value("params","meshes/generate_lods",false)
	config.set_value("params","meshes/light_baking",1)
	config.set_value("params","animation/import",false)
	config.set_value("params","import_script/path","res://assets/farm/art/hardwood_grove_import.gd")
	assert(str(config.get_value("remap","uid","")).begins_with("uid://"));assert(config.save(path)==OK)
	print("HARDWOOD_IMPORT ",config.get_value("remap","uid")," light_baking=1");quit()
