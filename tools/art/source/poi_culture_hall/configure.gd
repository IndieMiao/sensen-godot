extends SceneTree
const KIT:="res://assets/rooms/poi_culture_hall/"
func _initialize() -> void:
	var template:=ConfigFile.new();assert(template.load("res://assets/rooms/poi_hotel_lobby/round_side_table.glb.import")==OK)
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	for asset in layout.assets:
		var path: String=KIT+asset.file+".import";var config:=ConfigFile.new();assert(config.load(path)==OK)
		for key in config.get_section_keys("params"):config.erase_section_key("params",key)
		for key in template.get_section_keys("params"):config.set_value("params",key,template.get_value("params",key))
		config.set_value("params","import_script/path","")
		assert(str(config.get_value("remap","uid","")).begins_with("uid://"));assert(config.save(path)==OK)
		print("CULTURE_IMPORT ",asset.name," ",config.get_value("remap","uid"))
	quit()
