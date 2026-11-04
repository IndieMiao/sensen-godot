extends SceneTree
func _initialize() -> void:
	var path:="res://assets/farm/art/homestead_badge.glb.import"
	var config:=ConfigFile.new();assert(config.load(path)==OK)
	config.set_value("params","gltf/texture_map_mode",1)
	config.set_value("params","meshes/ensure_tangents",false)
	config.set_value("params","meshes/generate_lods",false)
	config.set_value("params","meshes/light_baking",1)
	config.set_value("params","animation/import",false)
	config.set_value("params","meshes/create_shadow_meshes",false)
	config.set_value("params","import_script/path","res://assets/farm/art/homestead_badge_import.gd")
	assert(str(config.get_value("remap","uid","")).begins_with("uid://"))
	assert(config.save(path)==OK)
	print("BADGE_IMPORT_UID ",config.get_value("remap","uid"));quit()
