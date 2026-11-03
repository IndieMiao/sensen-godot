@tool
extends EditorScenePostImport
## Texture mapping mode 1 does not enable COLOR_0 on the imported StandardMaterial.
func _post_import(scene: Node) -> Object:
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(index)
			var material := mesh.get_active_material(index) as StandardMaterial3D
			if material != null and arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() > 0:
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
	return scene
