@tool
extends EditorScenePostImport
## Match the N1/322 vertex-colour import contract; keep cabinet glass independent.
func _post_import(scene: Node) -> Object:
	var asset=get_source_file().get_file().get_basename()
	for node in scene.find_children("*","MeshInstance3D",true,false):
		node.mesh.resource_name=asset+"_mobile"
		if asset=="floor_mosaic":node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in node.mesh.get_surface_count():
			var material=node.get_active_material(surface) as StandardMaterial3D
			var arrays=node.mesh.surface_get_arrays(surface)
			if material!=null and arrays[Mesh.ARRAY_COLOR]!=null and arrays[Mesh.ARRAY_COLOR].size()>0:
				material.vertex_color_use_as_albedo=true;material.vertex_color_is_srgb=false
				if material.resource_name.begins_with("CultureGlass"):
					material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
					material.cull_mode=BaseMaterial3D.CULL_DISABLED
					material.metallic_specular=.35
				else:material.metallic_specular=.18
	return scene
