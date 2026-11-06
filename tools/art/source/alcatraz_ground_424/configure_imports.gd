extends SceneTree
func _initialize():
 for name in ["alc_ground_fields", "alc_ground_surfaces"]:
  var path="res://assets/landmarks/alcatraz_island/ground/"+name+".png.import"
  var cfg=ConfigFile.new()
  assert(cfg.load(path)==OK)
  cfg.set_value("params","compress/mode",2)
  cfg.set_value("params","compress/high_quality",true)
  cfg.set_value("params","mipmaps/generate",true)
  cfg.set_value("params","process/normal_map_invert_y",false)
  assert(cfg.save(path)==OK)
 quit()
