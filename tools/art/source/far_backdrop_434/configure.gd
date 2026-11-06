extends SceneTree
const KIT="res://assets/landmarks/_shared/far_backdrop/"
func _initialize():
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"manifest.json"))
 for name in manifest.assets:
  var config=ConfigFile.new();assert(config.load(KIT+name+".glb.import")==OK)
  config.set_value("params","nodes/root_script",null)
  config.set_value("params","meshes/generate_lods",false)
  config.set_value("params","meshes/ensure_tangents",false)
  config.set_value("params","meshes/create_shadow_meshes",false)
  config.set_value("params","meshes/light_baking",0)
  config.set_value("params","animation/import",false)
  config.set_value("params","gltf/texture_map_mode",1)
  config.set_value("params","import_script/path",KIT+"far_card_import.gd")
  assert(config.save(KIT+name+".glb.import")==OK)
 quit()
