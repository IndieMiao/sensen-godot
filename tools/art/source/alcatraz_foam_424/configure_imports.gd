extends SceneTree
const ROOT="res://assets/landmarks/alcatraz_island/"
func _initialize():
 var m=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"alc_shore_foam_manifest.json"))
 for name in m.assets:
  var c=ConfigFile.new();assert(c.load(ROOT+name+".glb.import")==OK)
  c.set_value("params","meshes/generate_lods",false);c.set_value("params","animation/import",false)
  var is_foam=str(name).begins_with("alc_foam")
  var slot="Alcatraz foam / shared soft alpha" if is_foam else "Alcatraz shore props / matte vertex colour"
  c.set_value("params","_subresources",{"materials":{slot:{"use_external/enabled":true,"use_external/path":ROOT+("alc_foam_material.tres" if is_foam else "alc_shore_props_material.tres")}}})
  assert(c.save(ROOT+name+".glb.import")==OK)
 var c=ConfigFile.new();assert(c.load(ROOT+"alc_foam_soft.png.import")==OK)
 c.set_value("params","compress/mode",0);c.set_value("params","mipmaps/generate",true);assert(c.save(ROOT+"alc_foam_soft.png.import")==OK)
 quit()
