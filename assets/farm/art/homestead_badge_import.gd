@tool
extends EditorScenePostImport
## Raw glTF has no portable visibility or Marker3D class; preserve both on import.
func _post_import(scene: Node) -> Object:
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("Tier_"):
			mesh.visible = mesh.name == "Tier_wood"
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(surface) as StandardMaterial3D
			assert(mat != null)
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = false
			mat.roughness = .9
			mat.metallic = 0.0
			mat.metallic_specular = .18
	for socket in ["BadgeNumber", "BadgeLv"]:
		var original := scene.find_child(socket, true, false) as Node3D
		assert(original != null)
		var marker := Marker3D.new()
		marker.name = socket
		marker.transform = original.transform
		original.replace_by(marker)
		marker.owner = scene
		marker.set_meta("surface_offset_m", .003)
		marker.set_meta("face_diameter_m", .65)
		original.free()
	return scene
