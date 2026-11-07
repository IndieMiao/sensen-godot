extends Node
# Actual farm scene, offline fixture transport and private user data only.
var fixture: Dictionary
var runtime
var farm
var vp:SubViewport
var out: String
var smoke:MultiMeshInstance3D
var report={"checks":[],"captures":[]}
const Art=preload("res://modules/farm/farm_art.gd")
func _ready():run.call_deferred()
func transport(_method,_path,_body,cmd):
 if cmd.get("type","")=="telemetry":return
 runtime.session._finish.call_deferred(HTTPRequest.RESULT_SUCCESS,200,JSON.stringify({"state":fixture,"events":[]}).to_utf8_buffer(),cmd)
func check(ok,label):
 report.checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func capture(name):
 for i in 8:await RenderingServer.frame_post_draw
 var im=vp.get_texture().get_image()
 check(im.get_size()==Vector2i(360,800),name+" 360x800")
 im.save_png(out+"/"+name+".png")
 var mesh=farm._looks._house.mesh
 var min_y=INF;var at=Vector2.ZERO
 for p in mesh.get_faces():
  var screen=farm.cam.unproject_position(farm._looks._house.to_global(p))
  if screen.y<min_y:min_y=screen.y;at=screen
 var smoke_min_y=INF
 # Original sphere radius=.11, rise=.70, scale=.55..1.90. Conservative full-cycle bound.
 for age_step in 101:
  var age=age_step/100.0
  var shift=Vector3(age*.20+sin(age*7)*.025,age*.70,0)
  var radius=.11*(.55+age*1.35)
  for dx in [-1,1]:
   for dy in [-1,1]:
    for dz in [-1,1]:
     smoke_min_y=min(smoke_min_y,farm.cam.unproject_position(smoke.to_global(shift+Vector3(dx,dy,dz)*radius)).y)
 var sign_views={}
 for entry in [["house_sign",farm._sign+Vector3(0,.45,0)],["upgrade_plaque",farm._plaque+Vector3(0,.35,0)],["chef_sign",farm._chef_sign+farm.CHEF_SIGN_HIT]]:
  var point:Vector3=entry[1];var xy=farm.cam.unproject_position(point)
  var origin=farm.cam.project_ray_origin(xy);var hit=false
  var faces=mesh.get_faces()
  for i in range(0,faces.size(),3):
   var a=farm._looks._house.to_global(faces[i]);var b=farm._looks._house.to_global(faces[i+1]);var c=farm._looks._house.to_global(faces[i+2])
   if Geometry3D.segment_intersects_triangle(origin,point,a,b,c)!=null:hit=true;break
  check(not hit,name+" "+entry[0]+" unobstructed by house")
  sign_views[entry[0]]={"screen":[xy.x,xy.y],"house_occludes":hit}
 if name.ends_with("default"):
  check(min_y>=150,name+" model top below y150 limit")
  check(smoke_min_y>=150,name+" smoke full-cycle bound below y150 limit")
 report.captures.append({"name":name,"highest_pixel":[at.x,at.y],"smoke_full_cycle_top_bound_px":smoke_min_y,"model_height_m":mesh.get_aabb().end.y,"camera_size":farm.cam.size,"camera_position":str(farm.cam.position),"camera_rotation":str(farm.cam.rotation_degrees),"signs":sign_views})
func run():
 out=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(out)
 fixture=JSON.parse_string(FileAccess.get_file_as_string("res://review-view.json"))
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,800);add_child(display)
 runtime=P0Runtime.new();P0Runtime._instance=runtime;runtime.session.transport=transport;runtime.session.use_line=false;vp.add_child(runtime)
 await get_tree().process_frame
 farm=load("res://scenes/p0/p0_farm.tscn").instantiate();vp.add_child(farm)
 for i in 240:await get_tree().process_frame
 # Keep the real default opening camera identical across all three variants.
 farm._opening=false;farm.set_process(false);runtime.set_process(false);runtime.session.set_process(false)
 runtime.ui._hide_tip();runtime.ui.tips=null
 runtime.ui.set_process(false)
 for child in farm.actor.find_children("*","AnimationPlayer",true,false):child.pause()
 smoke=farm.find_child("ChimneySmoke",true,false)
 check(smoke!=null,"original farm smoke found")
 # Freeze only the local review copy of smoke, at one common animation phase.
 var smoke_mat=smoke.material_override.duplicate()
 var smoke_shader=Shader.new();smoke_shader.code=smoke_mat.shader.code.replace("TIME","4.0")
 smoke_mat.shader=smoke_shader;smoke.material_override=smoke_mat
 await capture("current-default")
 # Preview the explicitly agreed programmer relocation; never change the pinned scripts.
 var bench=farm.find_child("Bench",true,false)
 bench.position.x-=1.3
 farm._bench.x-=1.3
 var shifted_shrub=false
 for layer in farm._scenery.get_children():
  if layer is MultiMeshInstance3D:
   for i in layer.multimesh.instance_count:
    var t=layer.multimesh.get_instance_transform(i)
    if t.origin.distance_to(farm._house+Vector3(-1.75,0,-.9))<.01:
     t.origin.x-=1.0;layer.multimesh.set_instance_transform(i,t);shifted_shrub=true
 check(shifted_shrub,"authorized left shrub preview relocation")
 report.scenery_preview={"bench_grid_before":[5,16],"bench_grid_after":[3,16],"left_shrub_shift_m":[-1,0,0],"production_scripts_modified":false}
 for v in ['a','b']:
  if not ResourceLoader.exists("res://assets/farm/art/master_farmhouse_"+v+".glb"):continue
  farm._looks._house.mesh=Art.mesh_for("master_farmhouse_"+v)
  farm._chef_sign_model(v)
  smoke.global_position=farm._house+Vector3(-.66,farm._looks._house.mesh.get_aabb().end.y,-.39)
  await capture("lv15-"+v+"-default")
  var saved_size=farm.cam.size;var saved_transform=farm.cam.transform
  var saved_near=farm.cam.near;var saved_far=farm.cam.far
  runtime.ui.hide()
  farm.cam.size=6.72;farm.FarmCamera.place(farm.cam,farm._house+Vector3(-.8,1.6,.3));farm.FarmCamera.fit_ground_depth(farm.cam)
  await capture("lv15-"+v+"-close")
  farm.cam.size=saved_size;farm.cam.transform=saved_transform
  farm.cam.near=saved_near;farm.cam.far=saved_far;runtime.ui.show()
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 FileAccess.open(out+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("HOMESTEAD_RENDER ",report);get_tree().quit()
