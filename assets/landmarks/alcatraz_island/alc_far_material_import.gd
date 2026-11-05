@tool
extends EditorScenePostImport
## Imported colours are linear glTF COLOR_0. Only these seven alc_* assets use it.
func _post_import(scene:Node)->Object:
	var source=get_source_file().get_file()
	var nodes=scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D:nodes.push_front(scene)
	for node in nodes:
		for i in node.mesh.get_surface_count():
			var m=node.mesh.surface_get_material(i) as StandardMaterial3D
			if m:
				m.vertex_color_use_as_albedo=true
				m.vertex_color_is_srgb=false
				m.roughness=.94
				m.metallic_specular=.15
		if source.begins_with("alc_far_"):node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return scene
