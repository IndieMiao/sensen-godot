extends SceneTree
func _initialize():
	var dest=OS.get_cmdline_user_args()[0]
	for folder in ["assets/rooms/poi_church","scenes/poi_church"]:
		for name in DirAccess.get_files_at("res://"+folder):
			if name.ends_with(".import"):
				var c=ConfigFile.new();assert(c.load("res://"+folder+"/"+name)==OK)
				assert(c.has_section_key("remap","uid"),"Godot import must generate UID: "+name)
				if name.ends_with(".glb.import"):assert(c.get_value("params","gltf/texture_map_mode",0)==1)
				assert(c.save(dest+"/"+folder+"/"+name)==OK)
			elif name.ends_with(".gd.uid"):
				DirAccess.copy_absolute(ProjectSettings.globalize_path("res://"+folder+"/"+name),dest+"/"+folder+"/"+name)
	quit()
