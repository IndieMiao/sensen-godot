extends SceneTree
const KIT := "res://assets/monsters/mob_rock_beetle/"
const MODEL := KIT + "mob_rock_beetle.glb"
func _initialize() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT + "mob_rock_beetle.json"))
	var model = load(MODEL).instantiate()
	var config := ConfigFile.new()
	assert(config.load(MODEL + ".import") == OK)
	config.set_value("params","gltf/texture_map_mode",1)
	config.set_value("params","meshes/generate_lods",false)
	config.set_value("params","meshes/light_baking",0)
	config.set_value("params","animation/fps",60)
	config.set_value("params","nodes/use_name_suffixes",false)
	config.set_value("params","import_script/path","res://assets/monsters/material_import.gd")
	var sub := {"nodes":{},"animations":{}}
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var key := str(mesh.get_meta("import_id", "PATH:" + str(model.get_path_to(mesh))))
		sub.nodes[key] = {"mesh_instance/cast_shadow":0}
		print("BEETLE_IMPORT_NODE ",key)
	for name_ in spec.anims:
		sub.animations[name_] = {"settings/loop_mode":1 if spec.anims[name_].get("loop",false) else 0}
	config.set_value("params","_subresources",sub)
	config.save(MODEL + ".import")
	print("BEETLE_UID ",config.get_value("remap","uid",""))
	for skeleton in model.find_children("*","Skeleton3D",true,false): print("BEETLE_BONES ",skeleton.get_bone_count())
	for player in model.find_children("*","AnimationPlayer",true,false): print("BEETLE_ANIMS ",player.get_animation_list())
	model.free()
	quit()
