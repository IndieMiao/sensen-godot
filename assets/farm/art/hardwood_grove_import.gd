@tool
extends EditorScenePostImport
## Same opaque matte linear vertex paint used by the farm gathering art.
func _post_import(scene: Node) -> Object:
	var meshes: Array=scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D:meshes.push_front(scene)
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			var material:=mesh.get_active_material(surface) as StandardMaterial3D
			assert(material!=null)
			material.vertex_color_use_as_albedo=true
			material.vertex_color_is_srgb=false
			material.roughness=.9
			material.metallic=0
			material.metallic_specular=.18
	return scene
