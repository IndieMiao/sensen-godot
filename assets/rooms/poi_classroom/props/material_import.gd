@tool
extends EditorScenePostImport
## Match N1: glTF COLOR_0 is linear; texture-map mode 1 needs explicit enablement.
func _post_import(scene: Node) -> Object:
	var mesh_name=get_source_file().get_file().get_basename()+"_mobile"
	for node in scene.find_children("*","MeshInstance3D",true,false):
		node.mesh.resource_name=mesh_name
		for surface in node.mesh.get_surface_count():
			var material=node.get_active_material(surface) as StandardMaterial3D
			var arrays=node.mesh.surface_get_arrays(surface)
			if material!=null and arrays[Mesh.ARRAY_COLOR]!=null and arrays[Mesh.ARRAY_COLOR].size()>0:
				material.vertex_color_use_as_albedo=true
				material.vertex_color_is_srgb=false
				material.metallic_specular=.18
	return scene
