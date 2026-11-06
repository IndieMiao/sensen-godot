@tool
extends EditorScenePostImport
const ROOT="res://assets/rooms/_shared/church_kit/"
func _post_import(scene:Node)->Object:
	var name=get_source_file().get_file().get_basename()
	var catalog=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"kit_manifest.json"))
	var kind=catalog.assets[name].material
	var material=load(ROOT+("glass_palette_classic.tres" if kind=="glass" else "opaque_atlas.tres" if kind=="atlas" else "opaque_vertex.tres"))
	var meshes=scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D:meshes.push_front(scene)
	for mi in meshes:
		for surface in mi.mesh.get_surface_count():mi.mesh.surface_set_material(surface,material)
		if kind=="glass" or name in ["flower_pedestal","grass_surround"]:mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return scene
