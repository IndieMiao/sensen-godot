extends SceneTree
func _initialize():
 var cfg=ConfigFile.new();assert(cfg.load("res://project.godot")==OK)
 cfg.set_value("application","run/main_scene","res://android_review.tscn")
 cfg.set_value("display","window/size/viewport_width",360)
 cfg.set_value("display","window/size/viewport_height",800)
 cfg.set_value("display","window/stretch/mode","canvas_items")
 cfg.set_value("display","window/stretch/aspect","expand")
 cfg.set_value("display","window/handheld/orientation",1)
 # Existing isolated software-emulator workaround; not a game setting.
 cfg.set_value("display","window/frame_pacing/android/enable_frame_pacing",false)
 cfg.set_value("input_devices","pointing/android/enable_long_press_as_right_click",false)
 cfg.set_value("input_devices","pointing/android/enable_pan_and_scale_gestures",true)
 assert(cfg.save("res://project.godot")==OK)
 var p=ConfigFile.new()
 for key in {"name":"Android Alcatraz Ground QA","platform":"Android","runnable":true,"export_filter":"all_resources","include_filter":"*.json"}:
  p.set_value("preset.0",key,{"name":"Android Alcatraz Ground QA","platform":"Android","runnable":true,"export_filter":"all_resources","include_filter":"*.json"}[key])
 var opts={"gradle_build/use_gradle_build":false,"architectures/arm64-v8a":false,"architectures/x86_64":true,
  "version/code":42406,"version/name":"424-ground-v1.1","package/unique_name":"com.sensen.alcatrazground424qa","package/name":"Alcatraz Ground Art QA","package/signed":true}
 p.set_value("preset.0","exclude_filter","")
 for key in opts:p.set_value("preset.0.options",key,opts[key])
 assert(p.save("res://export_presets.cfg")==OK)
 FileAccess.open("res://android_review.tscn",FileAccess.WRITE).store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://android_review.gd" id="1"]\n[node name="GroundInputReview" type="Node"]\nscript=ExtResource("1")\n')
 quit()
