@tool
extends EditorScenePostImport
## Asset import only: retain linear vertex colours and disable all cast shadows.
func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*","MeshInstance3D",true,false):
		node.mesh.resource_name="fish_trap_marker_mobile"
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in node.mesh.get_surface_count():
			var material=node.get_active_material(surface) as StandardMaterial3D
			if material!=null:
				material.vertex_color_use_as_albedo=true
				material.vertex_color_is_srgb=false
				material.metallic_specular=.12
	return scene
