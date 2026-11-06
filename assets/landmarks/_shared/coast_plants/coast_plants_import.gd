@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	var material := preload("res://assets/landmarks/_shared/coast_plants/coast_plants_matte.tres")
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D:
		meshes.push_front(scene)
	for node in meshes:
		# Store on the Mesh so MultiMesh consumers retain the vertex colours.
		for surface in node.mesh.get_surface_count():
			node.mesh.surface_set_material(surface, material)
	return scene
