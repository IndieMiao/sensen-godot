extends Node
const Art=preload("res://modules/farm/farm_art.gd")
const Outpost=preload("res://scenes/p0/p0_outpost.gd")
const NAMES=["porch_a","porch_b","kitchen_wing_a","kitchen_wing_b","master_farmhouse_a","master_farmhouse_b"]
var farm
var rt:P0Runtime
var fixture:Dictionary
var checks=[]
var captures=[]
var old_cameras={}
var old_navigation={}
var phase:String
var level:int
var look:String
var folder="res://../captures/"
func _ready():run.call_deferred()
func frames(n:int):
 for i in n:await get_tree().process_frame
func xyz(p:Vector3)->Array:return [p.x,p.y,p.z]
func check(ok:bool,label:String):
 checks.append({"passed":ok,"check":label})
 if not ok:push_error(label)
func mesh_from(path:String)->Mesh:
 var packed:PackedScene=load(path);var root:Node=packed.instantiate();var meshes=root.find_children("*","MeshInstance3D",true,false)
 if root is MeshInstance3D:meshes.push_front(root)
 assert(meshes.size()==1);var mesh:Mesh=meshes[0].mesh;root.free();return mesh
func respond(cmd:Dictionary):rt.session._finish(HTTPRequest.RESULT_SUCCESS,200,JSON.stringify({"ok":true,"state":fixture,"events":[]}).to_utf8_buffer(),cmd)
func begin(lv:int,style:String,p:String):
 level=lv;look=style;phase=p
 for name in NAMES:Art._meshes[name]=mesh_from(("res://qa_before/" if phase=="before" else "res://assets/farm/art/")+name+".glb")
 fixture=JSON.parse_string(FileAccess.get_file_as_string("res://view-lv%d-%s.json"%[level,look]))
 rt=P0Runtime.new();P0Runtime._instance=rt;rt.session.view=fixture;rt.session._received_ms=Time.get_ticks_msec()
 rt.session.transport=func(_m,_p,_b,c):respond.call_deferred(c)
 add_child(rt);rt.ui.hold_tips(3600000)
 farm=load("res://scenes/p0/p0_farm.tscn").instantiate();farm.set_script(load("res://review_farm.gd"));add_child(farm)
 await get_tree().create_timer(3.5).timeout;await frames(10);rt.ui.close_tip()
 check(not farm.actor.rig.is_busy(),"native actor assembled "+phase+str(level)+look)
 check(farm._bench.distance_to(Vector3(3.9,0,-10.725))<.00001,"original bench centre "+phase+str(level)+look)
 check(farm._house.distance_to(Vector3(6.175,0,-10.725))<.00001,"original house anchor "+phase+str(level)+look)
 var key=str(level)+look
 var nav:=JSON.stringify(farm.bp.masks)
 if phase=="before":old_cameras[key]={"transform":farm.cam.transform,"size":farm.cam.size};old_navigation[key]=nav
 elif old_cameras.has(key):
  check(farm.cam.transform.is_equal_approx(old_cameras[key].transform) and is_equal_approx(farm.cam.size,old_cameras[key].size),"same native before/after camera "+key)
  check(nav==old_navigation[key],"zero navigation-mask difference "+key)
func shot(kind:String):
 await frames(5);await RenderingServer.frame_post_draw
 var id="%s_lv%d_%s_%s"%[phase,level,look,kind];var image:=get_viewport().get_texture().get_image()
 check(image.get_size()==Vector2i(360,800),id+" native360x800")
 check(image.save_png(folder+id+".png")==OK,"saved "+id)
 var row={"name":id,"level":level,"look":look,"phase":phase,"kind":kind,"camera":{"position":xyz(farm.cam.position),"rotation":xyz(farm.cam.rotation_degrees),"size":farm.cam.size,"near":farm.cam.near,"far":farm.cam.far},"actor":xyz(farm.actor.position),"bench":xyz(farm._bench),"house":xyz(farm._house),"navigation_sha":JSON.stringify(farm.bp.masks).sha256_text()}
 if kind=="bench_seated":
  var skeleton:Skeleton3D=farm.actor.rig.skeleton;var points=[]
  for i in skeleton.get_bone_count():points.append(xyz(skeleton.global_transform*skeleton.get_bone_global_pose(i).origin))
  row["bone_points_world"]=points;row["pose"]="sit_idle; original bench seat0.67m; rig root0.33m (P0Outpost offset0.34m); isolated geometry check, not farm Rest gameplay"
 captures.append(row);print("SHOT ",id," camera_size=",farm.cam.size)
func close_view():
 farm._opening=false;farm._opening_zoom=false;farm._cam_follow.hold();farm._zoom=1.2
 farm._focus=farm._house+Vector3(-.55,0,.5);farm._place_camera();rt.ui.root.hide();farm.actor.visible=false
func sit():
 farm.actor.visible=true;farm.actor.teleport(farm._bench+Vector3(0,.33,0));farm.actor.lock(true);farm.actor.ground_height=func(_p):return .33
 farm.actor.face(farm._bench+Vector3(0,.33,2));Outpost._play_seated(farm.actor.rig,false)
 var ap:AnimationPlayer=farm.actor.rig.get_node("AnimationPlayer")
 check(ap.has_animation("sit_idle"),"existing sit_idle clip")
 await get_tree().create_timer(.6).timeout
 check(ap.current_animation=="sit_idle","seated pose remains active")
 await shot("bench_seated")
func approach():
 # Keep the real navigation approach, pause only the room transition to hold a still frame.
 farm.actor.visible=true;farm.review_hold_door=true
 var ok:bool=farm.actor.mover.set_target_position(farm._door)
 check(ok,"native door approach accepted")
 var n:=0
 while farm.actor.mover.is_moving() and n<1800:
  await get_tree().process_frame;n+=1
 check(not farm.actor.mover.is_moving(),"native door approach completed")
 check(farm.review_door_reached,"native door entry reached; only scene transition held for screenshot")
 farm.actor.face(farm._house);await frames(10)
 check(farm.actor.position.z-farm._house.z>.975,"actual approach stops outside wall hood cells")
 await shot("door_approach")
func finish():
 farm.queue_free();await frames(3);rt.queue_free();P0Runtime._instance=null;await frames(3)
func run():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 var cases=[[4,"a"],[5,"a"],[5,"b"],[8,"a"],[8,"b"],[15,"a"],[15,"b"]]
 for p in ["before","after"]:
  for c in cases:
   if p=="after" and c[0]==4:continue
   await begin(c[0],c[1],p);await shot("default")
   close_view();await frames(8);await shot("close")
   if level>=8:await sit()
   elif level==5 and phase=="after":await approach()
   await finish()
 var report={"base":"b46c6ea7","checks":checks,"captures":captures,"passed":checks.all(func(x):return x.passed),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 FileAccess.open("res://../render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print("HOMESTEAD_448_RENDER ",report.passed," checks=",checks.size()," captures=",captures.size())
 get_tree().quit(0 if report.passed else 1)
