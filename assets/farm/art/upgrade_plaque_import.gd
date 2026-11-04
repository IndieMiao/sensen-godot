@tool
extends EditorScenePostImport
## Preserve the farm's matte linear vertex paint and expose the text mount as Marker3D.
func _post_import(scene: Node) -> Object:
	for mesh in scene.find_children("*","MeshInstance3D",true,false):
		mesh.mesh.resource_name="upgrade_plaque_mobile"
		for surface in mesh.mesh.get_surface_count():
			var material:=mesh.get_active_material(surface) as StandardMaterial3D
			assert(material!=null)
			material.vertex_color_use_as_albedo=true
			material.vertex_color_is_srgb=false
			material.roughness=.9
			material.metallic=0.0
			material.metallic_specular=.18
	var original:=scene.find_child("PlaqueText",true,false) as Node3D
	assert(original!=null)
	var marker:=Marker3D.new()
	marker.name="PlaqueText"
	marker.transform=original.transform
	original.replace_by(marker)
	marker.owner=scene
	marker.set_meta("size",Vector2(.38,.24))
	marker.set_meta("face_size",Vector2(.40,.28))
	marker.set_meta("surface_offset_m",.002)
	original.free()
	return scene
