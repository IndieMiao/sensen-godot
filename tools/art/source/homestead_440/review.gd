extends Node
# Actual farm scene, offline fixture transport and private user data only.
var fixture: Dictionary
var runtime
var farm
var vp:SubViewport
var out: String
var smoke:MultiMeshInstance3D
var addons:Array[MeshInstance3D]=[]
var active_level=0
var active_variant=""
var report={"checks":[],"captures":[]}
const Art=preload("res://modules/farm/farm_art.gd")
func _ready():run.call_deferred()
func transport(_method,_path,_body,cmd):
 if cmd.get("type","")=="telemetry":return
 runtime.session._finish.call_deferred(HTTPRequest.RESULT_SUCCESS,200,JSON.stringify({"state":fixture,"events":[]}).to_utf8_buffer(),cmd)
func check(ok,label):
 report.checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func capture(name,check_signs=true):
 for i in 8:await RenderingServer.frame_post_draw
 var im=vp.get_texture().get_image()
 check(im.get_size()==Vector2i(360,800),name+" 360x800")
 im.save_png(out+"/"+name+".png")
 var parts:Array=[farm._looks._house]
 for node in addons:
  if node.visible:parts.append(node)
 var min_y=INF;var at=Vector2.ZERO;var height=0.0
 var screen_min=Vector2(INF,INF);var screen_max=Vector2(-INF,-INF)
 for node in parts:
  for p in node.mesh.get_faces():
   var screen=farm.cam.unproject_position(node.to_global(p))
   screen_min=screen_min.min(screen);screen_max=screen_max.max(screen)
   height=max(height,node.to_global(p).y-farm._house.y)
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
  for node in parts:
   var faces=node.mesh.get_faces()
   for i in range(0,faces.size(),3):
    var a=node.to_global(faces[i]);var b=node.to_global(faces[i+1]);var c=node.to_global(faces[i+2])
    if Geometry3D.segment_intersects_triangle(origin,point,a,b,c)!=null:hit=true;break
  if check_signs:check(not hit,name+" "+entry[0]+" unobstructed by house")
  sign_views[entry[0]]={"screen":[xy.x,xy.y],"house_occludes":hit}
 if name.ends_with("default"):
  check(min_y>=150,name+" model top below y150 limit")
  check(smoke_min_y>=150,name+" smoke full-cycle bound below y150 limit")
  check(screen_min.x>=0 and screen_max.x<=360 and screen_max.y<=800,name+" complete model inside viewport")
 var component_boxes={}
 for kind in ["porch","kitchen_wing"]:
  if active_level==0 or (kind=="kitchen_wing" and active_level==5):continue
  var bounds=Art.mesh_for(kind+"_"+active_variant).get_aabb()
  var corners=[]
  for i in 8:
   var point=farm.cam.unproject_position(farm._house+bounds.get_endpoint(i))
   corners.append([point.x,point.y])
  component_boxes[kind]={"screen_corners":corners,"position":str(bounds.position),"size":str(bounds.size)}
 report.captures.append({"name":name,"highest_pixel":[at.x,at.y],"screen_bounds":[[screen_min.x,screen_min.y],[screen_max.x,screen_max.y]],"component_boxes":component_boxes,"smoke_full_cycle_top_bound_px":smoke_min_y,"model_height_m":height,"camera_size":farm.cam.size,"camera_position":str(farm.cam.position),"camera_rotation":str(farm.cam.rotation_degrees),"signs":sign_views})
func angle_view(yaw_deg,center,size):
 var pitch=deg_to_rad(farm.FarmCamera.PITCH_DEG);var yaw=deg_to_rad(yaw_deg)
 farm.cam.size=size
 farm.cam.position=center+Vector3(sin(yaw)*11*cos(pitch),11*sin(pitch),cos(yaw)*11*cos(pitch))
 farm.cam.look_at(center,Vector3.UP);farm.FarmCamera.fit_ground_depth(farm.cam)
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
     t.origin.x-=1.5;layer.multimesh.set_instance_transform(i,t);shifted_shrub=true
 check(shifted_shrub,"authorized left shrub preview relocation")
 report.scenery_preview={"bench_grid_before":[5,16],"bench_grid_after":[3,16],"left_shrub_shift_m":[-1.5,0,0],"production_scripts_modified":false,"close_views_hide_distant_actor":true}
 var hidden_stones=0
 for node in farm._scenery.find_children("*","MultiMeshInstance3D",true,false):
  var mm:MultiMesh=node.multimesh
  if mm.mesh!=Art.mesh_for("stepping_stone"):continue
  var keep:Array[Transform3D]=[]
  for i in mm.instance_count:
   var transform=mm.get_instance_transform(i);var relative=transform.origin-farm._house
   if absf(relative.x)<.82 and relative.z>1.04 and relative.z<1.93:hidden_stones+=1
   else:keep.append(transform)
  mm.instance_count=keep.size()
  for i in keep.size():mm.set_instance_transform(i,keep[i])
 check(hidden_stones==2,"two original stepping stones replaced by exact 439 flush landing")
 report.scenery_preview["hidden_overlapping_stepping_stones"]=hidden_stones
 var original_smoke_position=smoke.global_position
 for v in ['a','b']:
  for name in ['porch_'+v,'kitchen_wing_'+v]:
   var node=Art.instance(name,farm._house);farm.add_child(node);addons.append(node)
  for level in [5,8,15]:
   active_level=level;active_variant=v
   var prefix="lv"+str(level)+"-"+v
   farm._looks._house.mesh=Art.mesh_for("house_cottage" if level<15 else "master_farmhouse_"+v)
   farm._chef_sign_model(v)
   for i in addons.size():addons[i].visible=level==8 or (level==5 and i==0)
   smoke.global_position=original_smoke_position if level<15 else farm._house+Vector3(-.66,farm._looks._house.mesh.get_aabb().end.y,-.39)
   await capture(prefix+"-default")
   var saved_size=farm.cam.size;var saved_transform=farm.cam.transform
   var saved_near=farm.cam.near;var saved_far=farm.cam.far
   runtime.ui.hide();farm.actor.visible=false
   farm.cam.size=6.72;farm.FarmCamera.place(farm.cam,farm._house+Vector3(-.8,1.6,.3));farm.FarmCamera.fit_ground_depth(farm.cam)
   await capture(prefix+"-close")
   farm.cam.size=saved_size;farm.cam.transform=saved_transform
   farm.cam.near=saved_near;farm.cam.far=saved_far;runtime.ui.show();farm.actor.visible=true
   # 45-degree future layout review: retain the real default scale and house
   # screen position. Only yaw changes; no production camera/layout edit.
   var old_screen=farm.cam.unproject_position(farm._house)
   angle_view(45.0,farm._house,saved_size)
   var delta=farm.cam.project_position(old_screen,10)-farm.cam.project_position(Vector2(180,400),10)
   farm.cam.position-=delta;farm.FarmCamera.fit_ground_depth(farm.cam)
   await capture(prefix+"-45-default")
   runtime.ui.hide();farm.actor.visible=false
   angle_view(45.0,farm._house+Vector3(-.50,1.7,0),6.72)
   await capture(prefix+"-45-close")
   # Reverse diagonal verifies the rear + left elevations using the same real
   # farm/light. Existing trees may overlap; no scenery is removed for review.
   angle_view(225.0,farm._house+Vector3(-.50,1.7,0),6.72)
   await capture(prefix+"-rear-left",false)
   farm.cam.size=saved_size;farm.cam.transform=saved_transform
   farm.cam.near=saved_near;farm.cam.far=saved_far;runtime.ui.show();farm.actor.visible=true
  for node in addons:node.queue_free()
  addons.clear()
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 FileAccess.open(out+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("HOMESTEAD_RENDER ",report);get_tree().quit()
