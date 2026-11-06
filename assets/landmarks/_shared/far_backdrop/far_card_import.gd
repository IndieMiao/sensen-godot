@tool
extends EditorScenePostImport
const KIT="res://assets/landmarks/_shared/far_backdrop/"

func _post_import(scene:Node)->Object:
 var name=get_source_file().get_file().get_basename()
 var kind="bridge" if name=="far_bridge" else "hills" if name.begins_with("far_hills_") else "city"
 var material=load(KIT+kind+".tres")
 var meshes=scene.find_children("*","MeshInstance3D",true,false)
 if scene is MeshInstance3D:meshes.push_front(scene)
 for node in meshes:
  for i in node.mesh.get_surface_count():node.mesh.surface_set_material(i,material)
  node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
  node.extra_cull_margin=100
 return scene
