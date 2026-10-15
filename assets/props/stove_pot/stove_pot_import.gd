@tool
extends EditorScenePostImport
## glTF import gives repeated names globally unique suffixes (mouth2), even
## under different parents. Restore the two specified local socket paths.
func _post_import(scene: Node) -> Object:
	for variant_name in ["pot_normal", "pot_big"]:
		var variant := scene.get_node(variant_name)
		for child in variant.get_children():
			if child.name.begins_with("mouth"):
				child.name = "mouth"
	return scene
