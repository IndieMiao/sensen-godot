extends SceneTree
## Isolated farm-dev fixture only. Real Avatar rig, resident lighting, fixed camera/scale.
const SLOTS = {"hairHat":"hairhat0_npc_gabriel","cloth":"cloth36_npc_gabriel","shoes":"shoes4","glass":"glass0"}
var elapsed=0.0
func _initialize():run.call_deferred()
func _process(delta):
 elapsed+=delta
 return elapsed>180
func run():
 if DisplayServer.get_name()=="headless":quit(2);return
 var KP=load("res://modules/p0/p0_keeper_portraits.gd")
 var OA=load("res://modules/net/online_appearance.gd")
 var avatar=root.get_node("Avatar")
 var kp=KP.new();root.add_child(kp)
 var dir="res://output/gabriel-review"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
 var npcs=JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/outpost_npcs.json")).npcs
 var looks={"gabriel":SLOTS,"kai":npcs.res_old_kai.slots,"mei":npcs.mei.slots}
 var report={"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"slots":SLOTS,"scale":1.0,"captures":[],"motion":{}}
 for id in looks:
  kp._stage(Vector2i(360,800));kp._backdrop(true)
  var rig=avatar.create_rig()
  for c in rig.get_children():
   if c is RigActivity:rig.remove_child(c);c.free()
  kp._viewport.add_child(rig)
  rig.apply_config(OA.config({"version":1,"slots":looks[id]},true))
  var waited=0
  while rig.is_busy() and waited<900:await process_frame;waited+=1
  assert(not rig.is_busy())
  rig.play_motion("idle")
  var ap=rig.get_node("AnimationPlayer");ap.seek(0,true);ap.pause()
  for view in ["front","three-quarter","back"] if id=="gabriel" else ["front"]:
   rig.rotation.y={"front":0.0,"three-quarter":PI/4,"back":PI}[view]
   kp._aim(Vector3(0,.88,0),2.02,.05)
   for frame in 3:await process_frame
   var image:Image=await kp._render()
   assert(image.save_png(dir+"/"+id+"-"+view+".png")==OK)
   report.captures.append({"id":id,"view":view,"size":[360,800],"camera_size":2.02})
  if id=="gabriel":
   rig.rotation.y=0
   for motion in ["idle","walk"]:
    rig.play_motion(motion);ap.seek(.05,true)
    var first=rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone("Wrist_L"))
    ap.seek(.65,true)
    var second=rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone("Wrist_L"))
    report.motion[motion]={"animation":ap.current_animation,"wrist_moves":not first.is_equal_approx(second)}
   ap.pause()
  kp._viewport.remove_child(rig);rig.free()
 var thumbnailer=PartThumbnailer.new();thumbnailer.catalog=avatar.catalog;root.add_child(thumbnailer)
 for id in ["cloth36_npc_gabriel","hairhat0_npc_gabriel"]:
  var thumb=await thumbnailer.thumbnail(id)
  assert(thumb!=null)
  assert(thumb.get_image().save_png("res://assets/avatar/thumbs/"+id+".png")==OK)
 FileAccess.open(dir+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("GABRIEL_REVIEW ",JSON.stringify(report))
 thumbnailer.free();kp.free();quit()
