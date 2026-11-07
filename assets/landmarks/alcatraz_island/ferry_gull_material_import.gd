@tool
extends EditorScenePostImport
## Only the decorative ferry/ferry_far/gull imports; no runtime animation logic.
func _post_import(scene:Node)->Object:
	var meshes=scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D:meshes.push_front(scene)
	for node in meshes:
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in node.mesh.get_surface_count():
			var mat=node.mesh.surface_get_material(s) as StandardMaterial3D
			if mat:
				mat.vertex_color_use_as_albedo=true
				mat.vertex_color_is_srgb=false
				mat.roughness=.94
				mat.metallic_specular=.15
	return scene
