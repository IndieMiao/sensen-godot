extends Node
## Same fixed Gabriel pose, with mesh/skin from each independent cold FBX import.
const SLOTS={"hairHat":"hairhat0_npc_gabriel","cloth":"cloth36_npc_gabriel","shoes":"shoes3_npc_gabriel","glass":"glass0"}
func _ready():run.call_deferred()
func run():
 var out=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(out)
 var vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_2X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,800);add_child(display)
 var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("e4f1ee");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("edf0ff");env.ambient_light_energy=.72
 var we=WorldEnvironment.new();we.environment=env;vp.add_child(we)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-32,-28,0);sun.light_energy=.95;vp.add_child(sun)
 var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=.02;camera.far=6;vp.add_child(camera);camera.current=true
 var avatar=get_node("/root/Avatar")
 var current=load("res://assets/avatar/parts/shoes3_npc_gabriel.res")
 var report={"slots":SLOTS,"captures":[],"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string}
 for phase in ["before","after"]:
  var candidate=current.duplicate()
  candidate.mesh=load("res://snapshots/"+phase+"_mesh.res").duplicate(true)
  candidate.skin=load("res://snapshots/"+phase+"_skin.res")
  assert(candidate.mesh.get_surface_count()==current.mesh.get_surface_count())
  for i in candidate.mesh.get_surface_count():
   assert(var_to_bytes(candidate.mesh.surface_get_arrays(i))==var_to_bytes(current.mesh.surface_get_arrays(i)))
   candidate.mesh.surface_set_material(i,current.mesh.surface_get_material(i))
  assert(candidate.skin.get_bind_count()==current.skin.get_bind_count())
  for i in candidate.skin.get_bind_count():
   assert(candidate.skin.get_bind_name(i)==current.skin.get_bind_name(i))
   assert(candidate.skin.get_bind_bone(i)==current.skin.get_bind_bone(i))
   assert(candidate.skin.get_bind_pose(i)==current.skin.get_bind_pose(i))
  avatar.cache.put("shoes3_npc_gabriel",candidate,120000)
  var rig=avatar.create_rig()
  for child in rig.get_children():
   if child is RigActivity:rig.remove_child(child);child.free()
  vp.add_child(rig)
  var cfg=avatar.slot_table.default_config()
  for slot in SLOTS:cfg.slots[StringName(slot)]=SLOTS[slot]
  rig.apply_config(cfg)
  var waited=0
  while rig.is_busy() and waited<900:await get_tree().process_frame;waited+=1
  assert(not rig.is_busy());assert(rig._loaded_defs[&"shoes"]==candidate)
  rig.play_motion("idle");rig.get_node("AnimationPlayer").seek(0,true);rig.get_node("AnimationPlayer").pause()
  for close in [false,true]:
   vp.size=Vector2i(360,320) if close else Vector2i(360,800)
   rig.rotation.y=PI/4 if close else 0.0
   camera.size=.58 if close else 2.02
   var target=Vector3(0,.18,0) if close else Vector3(0,.88,0)
   camera.look_at_from_position(target+Vector3(0,.12 if close else .05,2.4),target)
   for i in 12:await RenderingServer.frame_post_draw
   var im=vp.get_texture().get_image();var filename=phase+("-feet.png" if close else "-full.png")
   assert(im.save_png(out+"/"+filename)==OK)
   report.captures.append({"file":filename,"size":[im.get_width(),im.get_height()],"camera_size":camera.size,"camera_transform":str(camera.transform),"rig_rotation":str(rig.rotation_degrees),"pose":"idle@0","fresh_imported_mesh_skin_used":true})
  vp.remove_child(rig);rig.free()
 report.fresh_mesh_skin_equal_current_runtime_part=true
 FileAccess.open(out+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("GABRIEL_FBX_REVIEW_PASS");get_tree().quit()
