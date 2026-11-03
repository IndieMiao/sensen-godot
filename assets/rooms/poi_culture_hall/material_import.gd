@tool
extends EditorScenePostImport
func _post_import(scene: Node) -> Object:
	for mesh in scene.find_children("*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_surface_count():
			var material:=mesh.get_active_material(index) as StandardMaterial3D
			if material==null:continue
			material.vertex_color_use_as_albedo=true
			material.vertex_color_is_srgb=false
			material.metallic_specular=.22 if material.resource_name=="CultureBotanical" else .28
			if material.resource_name=="CultureBotanical":
				material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold=.45
				material.cull_mode=BaseMaterial3D.CULL_DISABLED
	return scene
