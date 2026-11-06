extends SceneTree
func _initialize():
 for name in ["ground_fields", "ground_surfaces"]:
  var path="res://assets/landmarks/_shared/ground_detail/"+name+".png.import"
  var cfg=ConfigFile.new()
  assert(cfg.load(path)==OK)
  cfg.set_value("params","compress/mode",2)
  cfg.set_value("params","compress/high_quality",true)
  cfg.set_value("params","mipmaps/generate",true)
  assert(cfg.save(path)==OK)
 quit()
