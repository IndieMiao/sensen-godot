extends SceneTree
func _initialize() -> void:
	var path:="res://assets/mine/types/quarry/backdrop.glb.import"
	var generated:=ConfigFile.new()
	assert(generated.load(path)==OK)
	var template:=ConfigFile.new()
	assert(template.load("res://assets/mine/backdrop/mine_backdrop.glb.import")==OK)
	var target:=ConfigFile.new()
	for section in ["remap","deps"]:
		for key in generated.get_section_keys(section):
			target.set_value(section,key,generated.get_value(section,key))
	for key in template.get_section_keys("params"):
		target.set_value("params",key,template.get_value("params",key))
	assert(str(target.get_value("remap","uid")).begins_with("uid://"))
	assert(target.get_value("params","import_script/path")=="")
	assert(target.save(path)==OK)
	print("QUARRY_IMPORT ",target.get_value("remap","uid"))
	quit()
