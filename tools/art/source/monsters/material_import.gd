@tool
extends EditorScenePostImport
## Match the existing N1 import fix: retain glTF vertex colour and disable real shadows.
func _post_import(scene: Node) -> Object:
	for mesh in scene.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var material=mesh.get_active_material(surface) as StandardMaterial3D
			var arrays=mesh.mesh.surface_get_arrays(surface)
			if material!=null and arrays[Mesh.ARRAY_COLOR]!=null and arrays[Mesh.ARRAY_COLOR].size()>0:
				material.vertex_color_use_as_albedo=true
				material.vertex_color_is_srgb=false
	return scene
