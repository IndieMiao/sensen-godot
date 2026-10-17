@tool
extends EditorScenePostImport
## Godot 4.7.2 retains GLB alpha/roughness/atlas bindings but defaults imported
## metallic_specular to .5. Calibrate that one authored parameter per surface.
## Do not replace, merge or override the imported opaque/glass materials.

func _post_import(scene: Node) -> Object:
	var count := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		for index in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(index)
			if material is BaseMaterial3D and material.resource_name in ["TackleRoomAtlas", "TackleFishbowlGlass"]:
				material.metallic_specular = .28
				count += 1
	print("TACKLE_SURFACE_IMPORT ",get_source_file()," ",count)
	return scene
