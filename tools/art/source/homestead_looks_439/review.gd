extends Node
## Actual P0Farm, native camera / lighting / HUD, isolated local transport.
var rt: P0Runtime
var farm
var fixture: Dictionary
var checks: Array=[]
var report:={"assets":{},"captures":[],"visibility":[],"scenery_moves":[],"hidden_scenery":[]}
var reference_camera:Transform3D
var reference_size:=0.0
var reference_walk:=""
var mesh_cache:={}
const FarmArt:=preload("res://modules/farm/farm_art.gd")
const NAMES:=["porch_a","porch_b","kitchen_wing_a","kitchen_wing_b"]
func _ready() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 checks.append({"check":label,"passed":ok})
 if not ok:push_error(label)
func frames(n:int) -> void:
 for i in n:await get_tree().process_frame
func respond(cmd:Dictionary) -> void:
 rt.session._finish(HTTPRequest.RESULT_SUCCESS,200,JSON.stringify({"ok":true,"state":fixture,"events":[]}).to_utf8_buffer(),cmd)
func array3(v:Vector3) -> Array:return [v.x,v.y,v.z]
func screen(p:Vector3) -> Array:
 var q:Vector2=farm.cam.unproject_position(p);return [q.x,q.y]
func camera_state() -> Dictionary:
 return {"position":array3(farm.cam.position),"basis":[array3(farm.cam.basis.x),array3(farm.cam.basis.y),array3(farm.cam.basis.z)],"pitch":farm.cam.rotation_degrees.x,"yaw":farm.cam.rotation_degrees.y,"width":farm.cam.size,"zoom":farm._zoom,"actor":array3(farm.actor.position)}
func parts() -> Array:
 var result:Array=[]
 for stage in ["porch","kitchen_extension"]:result.append_array(farm._looks.parts(stage))
 return result
func relocate_preview(stage:String) -> void:
 if stage in ["porch","kitchen"]:
  var hidden:=0
  for node in farm._scenery.find_children("*","MultiMeshInstance3D",true,false):
   var mm:MultiMesh=node.multimesh
   if mm.mesh!=FarmArt.mesh_for("stepping_stone"):continue
   var keep:Array[Transform3D]=[]
   for i in mm.instance_count:
    var transform:=mm.get_instance_transform(i);var relative:Vector3=transform.origin-farm._house
    if absf(relative.x)<.82 and relative.z>1.04 and relative.z<1.93:
     hidden+=1;report.hidden_scenery.append({"object":"door stepping stone","source_instance":i,"position":array3(transform.origin),"reason":"new flush landing replaces its visual surface; navigation unchanged"})
    else:keep.append(transform)
   mm.instance_count=keep.size()
   for i in keep.size():mm.set_instance_transform(i,keep[i])
  check(hidden==2,"two overlapping visual stepping stones replaced by flush landing")
 if stage!="kitchen":return
 var bench:Node3D=farm.find_child("Bench",true,false)
 check(bench!=null,"actual left bench found")
 if bench:
  var old:=bench.position;bench.position.x-=1.30;farm._bench=bench.position
  report.scenery_moves.append({"node":"Bench","from":array3(old),"to":array3(bench.position),"anchor_from":[5,16],"anchor_to":[3,16],"note":"preview only; program must move anchor/footprint/interaction together"})
 var old_bush:Vector3=farm._house+Vector3(-1.75,0,-.9);var moved:=0
 for n in farm._scenery.find_children("*","MultiMeshInstance3D",true,false):
  var mm:MultiMesh=n.multimesh
  for i in mm.instance_count:
   var t:=mm.get_instance_transform(i)
   if t.origin.distance_to(old_bush)<.0001:
    t.origin.x-=1.5;mm.set_instance_transform(i,t);moved+=1
    report.scenery_moves.append({"node":"Bush instance "+str(i),"from":array3(old_bush),"to":array3(t.origin),"note":"preview only; no RNG calls or navigation edits"})
 check(moved==1,"one left-house shrub moved out of the wing")
func begin_farm(level:int,look:String,stage:String) -> void:
 OS.set_environment("HOMESTEAD_439_STAGE",stage)
 fixture=JSON.parse_string(FileAccess.get_file_as_string("res://view-lv%d.json"%level))
 for row in fixture.homestead.looks:
  if row.id in ["porch","kitchen_extension"]:row.look=look
 rt=P0Runtime.ensure();rt.session.view=fixture;rt.session._received_ms=Time.get_ticks_msec()
 rt.session.transport=func(_method,_path,_body,cmd):respond.call_deferred(cmd)
 await frames(3)
 farm=load("res://scenes/p0/p0_farm.tscn").instantiate();add_child(farm)
 await get_tree().create_timer(4.0).timeout
 check(not farm.actor.rig.is_busy(),"game player assembled "+look+" "+stage)
 check(str(farm._looks._house.mesh.resource_path).contains("house_cottage"),"unchanged cottage under attachments "+look+" "+stage)
 var expected:=0 if stage=="current" else (2 if stage=="kitchen" else 1)
 check(parts().size()==expected,"actual look_parts count "+look+" "+stage)
 for node in parts():
  check((node as Node3D).position.is_equal_approx(farm._house) and node.scale.is_equal_approx(Vector3.ONE),"part uses house anchor / scale one: "+str(node.name))
  var mat:StandardMaterial3D=node.material_override
  check(mat!=null and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb and is_equal_approx(mat.roughness,.9),"actual FarmArt vertex material: "+str(node.name))
 relocate_preview(stage)
 await frames(10)
func finish_farm() -> void:
 farm.queue_free();rt.queue_free();await frames(4)
func shot(name:String) -> void:
 await frames(8);RenderingServer.force_draw(true)
 var image:=get_viewport().get_texture().get_image()
 check(image.get_size()==Vector2i(360,800),"native 360x800 "+name)
 check(image.save_png("res://../"+name+".png")==OK,"saved "+name)
 report.captures.append({"name":name,"camera":camera_state(),"size":[image.get_width(),image.get_height()]})
func hit_by_addon(target:Vector3) -> String:
 var point:Vector2=farm.cam.unproject_position(target)
 var origin:Vector3=farm.cam.project_ray_origin(point)
 var end:=target+(origin-target).normalized()*.002
 for node in parts():
  var path:String=node.mesh.resource_path
  if not mesh_cache.has(path):
   var a:Array=node.mesh.surface_get_arrays(0);mesh_cache[path]=[a[Mesh.ARRAY_VERTEX],a[Mesh.ARRAY_INDEX]]
  var v:PackedVector3Array=mesh_cache[path][0];var ids:PackedInt32Array=mesh_cache[path][1]
  var inv:Transform3D=node.global_transform.affine_inverse();var p:=inv*origin;var q:=inv*end
  for i in range(0,ids.size(),3):
   if Geometry3D.segment_intersects_triangle(p,q,v[ids[i]],v[ids[i+1]],v[ids[i+2]])!=null:return str(node.name)
 return ""
func visibility(label:String) -> void:
 var targets:={"homestead_icon":farm._sign+farm.get_script().get_script_constant_map()["SIGN_BADGE"],"upgrade_icon":farm._plaque+Vector3(0,.85,0),"chef_board":farm._chef_sign+Vector3(-.332,1.285,0)}
 var ppm:float=get_viewport().get_visible_rect().size.x/farm.cam.size
 for icon in ["homestead_icon","upgrade_icon"]:
  var centre:Vector3=targets[icon]
  for i in 16:
   var angle:=float(i)*TAU/16.0
   targets[icon+"_edge_"+str(i)]=centre+(farm.cam.global_basis.x*cos(angle)+farm.cam.global_basis.y*sin(angle))*(16.0/ppm)
 for i in 3:
  for j in 3:targets["door_%d_%d"%[i,j]]=farm._house+Vector3(-.53+i*.18,.20+j*.27,.90)
 for key in targets:
  var hit:=hit_by_addon(targets[key]);check(hit=="",label+": addons leave "+str(key)+" visible")
  report.visibility.append({"capture":label,"target":key,"screen":screen(targets[key]),"blocked_by":hit})
func run() -> void:
 var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://homestead_stats.json"))
 for name in NAMES:
  var mesh:Mesh=FarmArt.mesh_for(name);var count:int=mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3
  check(mesh.get_surface_count()==1 and count==spec.assets[name].triangles and count<=1500,"imported budget "+name)
  var cfg:=ConfigFile.new();assert(cfg.load("res://assets/farm/art/"+name+".glb.import")==OK)
  check(str(cfg.get_value("remap","uid","")).begins_with("uid://") and FileAccess.get_file_as_string("res://assets/farm/art/"+name+".glb.import").contains("nodes/root_script=null"),"UID/root_script "+name)
  report.assets[name]={"sha256":FileAccess.get_sha256("res://assets/farm/art/"+name+".glb"),"triangles":count,"uid":cfg.get_value("remap","uid")}
 for look in ["a","b"]:
  for stage in ["current","porch","kitchen"]:
   await begin_farm(8,look,stage)
   if reference_size==0:
    reference_camera=farm.cam.transform;reference_size=farm.cam.size;reference_walk=JSON.stringify(farm.bp.masks.walkable)
   check(farm.cam.transform.is_equal_approx(reference_camera) and is_equal_approx(farm.cam.size,reference_size),"same native opening camera "+look+" "+stage)
   check(JSON.stringify(farm.bp.masks.walkable)==reference_walk,"unchanged navigation mask "+look+" "+stage)
   check(absf(farm.cam.rotation_degrees.x+43)<.01,"43 degree opening "+look+" "+stage)
   visibility(look+"_"+stage)
   await shot(look+"_"+stage)
   await finish_farm()
 for look in ["a","b"]:
  await begin_farm(10,look,"kitchen")
  farm.actor.visible=false # Prop close-up: avoid the offscreen player head at the lower edge.
  farm._opening=false;farm._opening_zoom=false;farm._cam_follow.hold();farm._zoom=1.2
  farm._focus=farm._house+Vector3(-.5,0,1.1);farm._place_camera();await frames(10)
  visibility(look+"_sign_view")
  await shot(look+"_sign_view")
  await finish_farm()
 report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 check(report.renderer.method=="mobile","Vulkan Mobile target renderer")
 report.icon_clearance_radius_px=16
 report.checks=checks;report.passed=checks.all(func(c):return c.passed)
 FileAccess.open("res://../render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("HOMESTEAD_439_RENDER ",report.passed," ",checks.size()," checks")
 get_tree().quit(0 if report.passed else 1)
