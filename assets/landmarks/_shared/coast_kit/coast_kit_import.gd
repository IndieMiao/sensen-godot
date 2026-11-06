@tool
extends EditorScenePostImport

const KIT := "res://assets/landmarks/_shared/coast_kit/"

func _post_import(scene: Node) -> Object:
	var asset := get_source_file().get_file().get_basename()
	var rock := asset.begins_with("coast_rock_") or asset.begins_with("coast_scatter_")
	var material: Material = load(KIT + ("coast_cool_gray.tres" if rock else "coast_warm_sand.tres"))
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D:
		meshes.push_front(scene)
	for node in meshes:
		# Put the material on the mesh itself so extracting it for MultiMesh retains it.
		for surface in node.mesh.get_surface_count():
			node.mesh.surface_set_material(surface, material)
	return scene
