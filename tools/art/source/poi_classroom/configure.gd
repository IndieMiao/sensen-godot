extends SceneTree
const KIT:="res://assets/rooms/poi_classroom/"
func _initialize() -> void:
	var template:=ConfigFile.new();assert(template.load("res://assets/rooms/poi_hotel_lobby/round_side_table.glb.import")==OK)
	for name_ in ["blockout_student_desk","blockout_student_stool","blockout_box","blockout_cylinder","blockout_ball"]:
		var path: String=KIT+str(name_)+".glb.import"
		var current:=ConfigFile.new();assert(current.load(path)==OK)
		for key in current.get_section_keys("params"):current.erase_section_key("params",key)
		for key in template.get_section_keys("params"):current.set_value("params",key,template.get_value("params",key))
		current.set_value("params","import_script/path","")
		assert(str(current.get_value("remap","uid","")).begins_with("uid://"))
		assert(current.save(path)==OK)
		print("CLASSROOM_IMPORT ",name_," ",current.get_value("remap","uid"))
	quit()
