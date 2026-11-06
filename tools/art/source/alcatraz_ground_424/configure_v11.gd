extends SceneTree
func _initialize():
 var original=ConfigFile.new()
 assert(original.load("res://assets/landmarks/alcatraz_island/ground/alc_ground_fields.png.import")==OK)
 var path="res://baseline_ground/alc_ground_fields.png.import"
 var baseline=ConfigFile.new();assert(baseline.load(path)==OK)
 for key in original.get_section_keys("params"):
  baseline.set_value("params",key,original.get_value("params",key))
 assert(baseline.save(path)==OK)
 quit()
