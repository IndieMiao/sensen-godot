@tool
extends EditorScenePostImport

func _post_import(scene:Node)->Object:
	var material=load("res://assets/landmarks/_shared/street_kit/street_matte.tres")
	var meshes=scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D:meshes.push_front(scene)
	for mi in meshes:
		for surface in mi.mesh.get_surface_count():mi.mesh.surface_set_material(surface,material)
	return scene
