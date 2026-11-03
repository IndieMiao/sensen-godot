extends SceneTree
const KIT:="res://assets/rooms/poi_culture_hall/"
func _initialize() -> void:
	var template:=ConfigFile.new();assert(template.load("res://assets/rooms/poi_hotel_lobby/round_side_table.glb.import")==OK)
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	for asset in layout.assets:
		if str(asset.name).begins_with("blockout_"):continue
		var path: String=KIT+asset.file+".import";var config:=ConfigFile.new();assert(config.load(path)==OK)
		for key in config.get_section_keys("params"):config.erase_section_key("params",key)
		for key in template.get_section_keys("params"):config.set_value("params",key,template.get_value("params",key))
		config.set_value("params","import_script/path",KIT+"material_import.gd")
		assert(str(config.get_value("remap","uid","")).begins_with("uid://"));assert(config.save(path)==OK)
		print("CULTURE_IMPORT ",asset.name," ",config.get_value("remap","uid"))
	var texture:=ConfigFile.new();var texture_path:=KIT+"room_albedo_ao.png.import"
	assert(texture.load(texture_path)==OK)
	texture.set_value("params","mipmaps/generate",true);texture.set_value("params","compress/mode",2)
	assert(texture.save(texture_path)==OK)
	quit()
