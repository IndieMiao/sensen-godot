extends Node
const ROOT = "res://assets/landmarks/alcatraz_island/ground/"
var vp: SubViewport
var island
var camera: Camera3D
var output: String
var originals = {}
var targets = {}
var terrain = preload(ROOT + "alc_terrain_detail.tres")
var dock = preload(ROOT + "alc_dock_detail.tres")
var report = {"checks": [], "captures": [], "controls": {}, "host_commit": "bf0c31b1c871011008b455434d167224d14de59c"}

func _ready(): run.call_deferred()
func check(ok, label):
 report.checks.append({"passed": bool(ok), "check": label})
 if not ok: push_error(label)
func set_finish(enabled, amount=1.0):
 terrain.set_shader_parameter("strength", amount)
 dock.set_shader_parameter("strength", amount)
 for n in targets:
  n.material_override = targets[n] if enabled else originals[n]
func capture(name):
 for i in 8: await RenderingServer.frame_post_draw
 var img = vp.get_texture().get_image()
 check(img.save_png(output+"/"+name+".png") == OK, "save "+name)
 report.captures.append({"name": name, "size": [vp.size.x,vp.size.y], "camera": str(camera.global_transform), "width_m": camera.size,
  "visible_draw_calls": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
  "visible_primitives": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
 print("ALC_GROUND_CAPTURE ", name)
 return img
func difference(a: Image, b: Image, rect: Rect2i):
 var total=0.0; var maximum=0.0; var changed=0
 for y in range(rect.position.y, rect.end.y):
  for x in range(rect.position.x, rect.end.x):
   var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
   var delta=max(abs(c.r-d.r),max(abs(c.g-d.g),abs(c.b-d.b)))
   total+=delta;maximum=max(maximum,delta);changed+=int(delta>1.0/255)
 return {"mean_max_rgb_255":total*255/(rect.size.x*rect.size.y),"max_rgb_255":maximum*255,"changed_pixels":changed}
func pair(name):
 set_finish(false)
 var before=await capture(name+"-before")
 set_finish(true, 0.0)
 var zero=await capture(name+"-zero-control")
 var rect=Rect2i(Vector2i.ZERO,vp.size)
 var control=difference(before,zero,rect)
 report.controls[name+"_zero"]=control
 check(control.mean_max_rgb_255<0.1, name+": original material reproduced at strength zero")
 set_finish(true)
 var after=await capture(name+"-after")
 var changed=difference(before,after,rect)
 report.controls[name+"_finish"]=changed
 check(changed.changed_pixels>100, name+": detail visibly applied")
 if name=="opening":
  # The historical 180px box also includes land at x=159..179 in this host.
  # Keep the broad measurement, and separately test the actual bridge/city band.
  report.controls.legacy_bridge_rectangle=difference(before,after,Rect2i(0,45,180,115))
  var bridge=difference(before,after,Rect2i(0,45,150,115))
  report.controls.bridge=bridge
  check(bridge.max_rgb_255==0, "bridge/city pixels unchanged")
 return after
func run():
 output=ProjectSettings.globalize_path("res://../captures")
 DirAccess.make_dir_recursive_absolute(output)
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true
 vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,800);add_child(display)
 island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
 for i in 16:await get_tree().process_frame
 var waits=0
 while island._rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not island._rig.is_busy(),"full host avatar assembled")
 island.set_process(false);island._rig.process_mode=Node.PROCESS_MODE_DISABLED
 Engine.time_scale=0.0
 camera=island._camera
 # Only four material_override assignments in this disposable QA project.
 for n in island.mesh_nodes:
  var name_=str(n.name)
  if name_.begins_with("AlcGround") or name_.begins_with("Dock"):
   originals[n]=n.material_override
   targets[n]=dock if name_.begins_with("Dock") else terrain
 check(targets.size()==4,"exactly three terrain meshes and one dock")
 check(island._player.position.is_equal_approx(Vector3(-22,1,19)),"original opening spawn")
 check(is_equal_approx(camera.size,6.72),"default camera width")
 await pair("opening")
 for view in ["mid_hill","summit"]:
  var key="mid_hill" if view=="mid_hill" else "visitor_center"
  var p=island.layout.review_points[key]
  island._player.position=island._vec(p);island._focus=island._follow_target();island._update_camera()
  await pair(view)
 # Additional whole-island and closeup views retain the host lighting.
 island._hud.hide();island._set_backdrop_visible(false)
 vp.size=Vector2i(1200,1000);camera.size=72;camera.position=Vector3(60,75,95);camera.look_at(Vector3(0,4,-2));camera.far=300
 await pair("whole_island")
 vp.size=Vector2i(1100,800);camera.size=9;camera.position=Vector3(-12,17,8);camera.look_at(Vector3(-12,5.5,0))
 await pair("grass_paving_detail")
 vp.size=Vector2i(900,900);camera.size=3.6;camera.position=Vector3(-22,12,24);camera.look_at(Vector3(-22,1,17))
 await pair("dock_grain_detail")
 var last=vp.get_texture().get_image()
 for i in 30:await RenderingServer.frame_post_draw
 report.controls.static=difference(last,vp.get_texture().get_image(),Rect2i(Vector2i.ZERO,vp.size))
 check(report.controls.static.max_rgb_255==0,"static detail at fixed camera / QA clock")
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 report.comparison_clock="QA Engine.time_scale=0; original host water and all host files unchanged"
 report.passed=report.checks.all(func(c):return c.passed)
 FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 Engine.time_scale=1.0
 get_tree().quit(0 if report.passed else 1)
