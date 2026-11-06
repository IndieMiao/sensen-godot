extends SceneTree
func _initialize():
 var root="res://assets/landmarks/alcatraz_island/"
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(root+"alc_nature_manifest.json"))
 for name in manifest.assets:
  var path=root+name+".glb.import";var cfg=ConfigFile.new();assert(cfg.load(path)==OK)
  cfg.set_value("params","meshes/generate_lods",false)
  cfg.set_value("params","animation/import",false)
  cfg.set_value("params","_subresources",{"materials":{"Alcatraz nature / matte vertex colour":{"use_external/enabled":true,"use_external/path":root+"alc_nature_material.tres"}}})
  assert(cfg.save(path)==OK)
 quit()
