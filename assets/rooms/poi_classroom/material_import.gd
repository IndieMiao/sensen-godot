@tool
extends EditorScenePostImport
## Mode 1 imports the atlas; scalar COLOR_0 supplies module-local contact AO.
func _post_import(scene: Node) -> Object:
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(index) as StandardMaterial3D
			if material != null:
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
				material.metallic_specular = .28
	return scene
