extends SceneTree
const ROOT="res://assets/landmarks/_shared/water_edge/"
func _initialize():
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"manifest.json"))
 for name in manifest.assets:
  var c=ConfigFile.new();assert(c.load(ROOT+name+".glb.import")==OK)
  c.set_value("params","nodes/root_script",null)
  c.set_value("params","meshes/generate_lods",false);c.set_value("params","animation/import",false)
  c.set_value("params","_subresources",{"materials":{"Water edge / shared foam":{"use_external/enabled":true,"use_external/path":ROOT+"water_edge_material.tres"}}})
  assert(c.save(ROOT+name+".glb.import")==OK)
 var c=ConfigFile.new();assert(c.load(ROOT+"water_edge_soft.png.import")==OK)
 c.set_value("params","compress/mode",0);c.set_value("params","mipmaps/generate",true)
 c.set_value("params","detect_3d/compress_to",0)
 assert(c.save(ROOT+"water_edge_soft.png.import")==OK)
 quit()
