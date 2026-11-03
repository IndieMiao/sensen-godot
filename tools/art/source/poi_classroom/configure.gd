extends SceneTree
const KIT:="res://assets/rooms/poi_classroom/"
func _initialize() -> void:
	var template:=ConfigFile.new();assert(template.load("res://assets/rooms/poi_hotel_lobby/round_side_table.glb.import")==OK)
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	for asset in layout.assets:
		var name_: String=asset.name
		if name_.begins_with("props/"):continue
		var path: String=KIT+str(name_)+".glb.import"
		var current:=ConfigFile.new();assert(current.load(path)==OK)
		for key in current.get_section_keys("params"):current.erase_section_key("params",key)
		for key in template.get_section_keys("params"):current.set_value("params",key,template.get_value("params",key))
		current.set_value("params","import_script/path",KIT+"material_import.gd")
		assert(str(current.get_value("remap","uid","")).begins_with("uid://"))
		assert(current.save(path)==OK)
		print("CLASSROOM_IMPORT ",name_," ",current.get_value("remap","uid"))
	var texture:=ConfigFile.new();var path:=KIT+"room_albedo_ao.png.import"
	assert(texture.load(path)==OK)
	texture.set_value("params","mipmaps/generate",true)
	texture.set_value("params","compress/mode",2)
	assert(texture.save(path)==OK)
	quit()
