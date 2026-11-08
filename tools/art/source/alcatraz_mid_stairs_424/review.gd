extends Node
var scene:Node3D
var rt:P0Runtime
var folder:String
var report:Dictionary={"views":{},"openings":[],"tree_meshes":[],"nav_samples":[],"walk":{},"summit_probe":[]}
var audit:Node
func _ready():
 folder=OS.get_environment("ALC_MID_REVIEW");DirAccess.make_dir_recursive_absolute(folder)
 Net.use_transport(FakeTransport.new([]).callable())
 rt=P0Runtime.ensure();rt.session.transport=func(_m,_p,_b,_c):pass
 await get_tree().process_frame
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"));fixture.energy.value=200;fixture.coins=200;rt.session.view=fixture;rt.session.busy=false;rt.session.state_changed.emit(fixture,[])
 scene=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();scene.setup({"p0_visit":true,"landmark":"alcatraz_island","chip":"San Francisco · Alcatraz Island"});add_child(scene)
 for i in 150:await get_tree().process_frame
 for i in 120:
  if scene.navigation_ready():break
  await get_tree().physics_frame
 scene.set_process(false);scene._update_camera()
 report.layout_sha256=FileAccess.get_sha256("res://assets/landmarks/alcatraz_island/layout.json")
 report.runtime_script_sha256=FileAccess.get_sha256("res://scenes/landmark/alcatraz_island.gd")
 report.renderer=RenderingServer.get_current_rendering_method();report.gpu=RenderingServer.get_video_adapter_name()
 report.spawn_actual=xyz(scene.player_position());report.yaw=rad_to_deg(atan2(scene._camera.global_basis.z.x,scene._camera.global_basis.z.z));report.pitch=43.0
 audit=load("res://hud_helper.gd").new();audit.scene=scene;audit.prepare_hud_audit()
 await capture("opening")
 var goal=vec(scene.layout.review_points.visitor_center)
 var goals:Array=scene.layout.walk_goals.slice(1) if scene.layout.has("mid_stairs") else [xyz(goal)]
 var direct=scene.find_path(scene.player_position(),goal);report.direct_path_length=length_of(direct)
 var from_layout=path_via(vec(scene.layout.spawn),goals)
 var path=path_via(scene.player_position(),goals)
 report.layout_path=path_array(from_layout);report.layout_path_length=length_of(from_layout);report.runtime_path=path_array(path);report.runtime_path_length=length_of(path)
 # Export samples only after checking them against the LIVE navigation map.
 var seen:Dictionary={};var vertices:Array=scene.layout.navigation.vertices
 for poly in scene.layout.navigation.polygons:
  var points:PackedVector3Array=PackedVector3Array();var flat:PackedVector2Array=PackedVector2Array()
  for index in poly:points.append(vec(vertices[index]));flat.append(Vector2(vertices[index][0],vertices[index][2]))
  var normal=(points[1]-points[0]).cross(points[2]-points[0]);if absf(normal.y)<.00001:continue
  var minx=points[0].x;var maxx=minx;var minz=points[0].z;var maxz=minz
  for p in points:minx=minf(minx,p.x);maxx=maxf(maxx,p.x);minz=minf(minz,p.z);maxz=maxf(maxz,p.z)
  for ix in range(ceili(minx*2),floori(maxx*2)+1):
   for iz in range(ceili(minz*2),floori(maxz*2)+1):
    var x=ix*.5;var z=iz*.5
    if not Geometry2D.is_point_in_polygon(Vector2(x,z),flat):continue
    var y=points[0].y-(normal.x*(x-points[0].x)+normal.z*(z-points[0].z))/normal.y
    var q=Vector3(x,y,z);var near=NavigationServer3D.map_get_closest_point(scene._nav_map,q)
    if near.distance_to(q)>.025:continue
    var key="%.2f/%.3f/%.2f"%[x,y,z]
    if seen.has(key):continue
    seen[key]=true;report.nav_samples.append(xyz(q))
 for p in scene.layout.placements:
  if not str(p.asset).begins_with("alc_tree_") or str(p.asset).ends_with("_far"):continue
  var faces:PackedVector3Array=scene._mesh(p.asset).get_faces();var transformed:Array=[];var tr:Transform3D=scene._transform_of(p)
  for v in faces:transformed.append(xyz(tr*v))
  report.tree_meshes.append({"name":p.name,"asset":p.asset,"faces":transformed})
 # Exact query and physical overlap around the reported summit lamp; data only.
 var capsule=CapsuleShape3D.new();capsule.radius=.25;capsule.height=1.6
 for ix in range(-32,33):
  for iz in range(-32,-19):
   var q=Vector3(ix*.25,10,iz*.25);var near=NavigationServer3D.map_get_closest_point(scene._nav_map,q)
   var pp=scene.find_path(Vector3(0,10,-6),near);var hits:Array=[]
   var query=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,q+Vector3.UP*.9)
   for hit in scene.get_world_3d().direct_space_state.intersect_shape(query,16):hits.append(str(hit.collider.get_path()))
   report.summit_probe.append({"position":xyz(q),"snap":xyz(near),"snap_distance":near.distance_to(q),"path_end":xyz(pp[-1]) if pp.size()>0 else [],"colliders":hits})
 if scene.layout.has("mid_stairs"):
  for s in scene.layout.mid_stairs.flights:
   for kind in ["lower","upper"]:
    var r:Array=s[kind+"_platform"];var y:float=s.low if kind=="lower" else s.high
    var at=Vector3((r[0]+r[1])*.5,y,(s.z0+s.z1)*.5);var pp=scene.find_path(vec(scene.layout.spawn),at)
    report.openings.append({"flight":s.id,"kind":kind,"point":xyz(at),"path_points":pp.size(),"end_error":pp[-1].distance_to(at) if pp.size()>0 else 999.0})
 # Existing end stairs remain bidirectionally reachable; all endpoints use live paths.
 report.old_stairs=[]
 for spec in [[Vector3(-22,1,12),Vector3(-22,3.25,7.5)],[Vector3(8,3.25,7.5),Vector3(8,5.5,3)],[Vector3(-22,5.5,3),Vector3(-22,7.75,-1.5)],[Vector3(8,7.75,-1.5),Vector3(8,10,-6)]]:
  var forward=scene.find_path(spec[0],spec[1]);var backward=scene.find_path(spec[1],spec[0])
  report.old_stairs.append({"lower":xyz(spec[0]),"upper":xyz(spec[1]),"up_error":forward[-1].distance_to(spec[1]) if forward.size()>0 else 999.0,"down_error":backward[-1].distance_to(spec[0]) if backward.size()>0 else 999.0})
 # Actual walking code; numerical fixed timestep, rendered stills at route checkpoints.
 var goal_index=0;scene.walk_to(vec(goals[0]));var trace:Array=[];var distance=0.0;var previous=scene.player_position();var next_shot=length_of(path)*.20;var shot=1;var failures:Array=[];var hud_next=0.0;var foot_errors:Array=[]
 for i in 9000:
  scene._step_walk(1.0/60.0);scene._focus=scene._follow_target();scene._update_camera()
  var at=scene.player_position();distance+=at.distance_to(previous);previous=at
  if distance>=hud_next:
   var intrusions:Array=audit.hud_intrusions();if not intrusions.is_empty():failures.append({"distance":distance,"position":xyz(at),"intrusions":intrusions})
   trace.append(xyz(at));hud_next=distance+.5
  if scene.layout.has("mid_stairs"):
   for s in scene.layout.mid_stairs.flights:
    if at.x>s.x0+.03 and at.x<s.x1-.03 and at.z>s.z0+.05 and at.z<s.z1-.05 and at.y>s.low+.02 and at.y<s.high+.02:
     var hit=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.4,at-Vector3.UP*.5))
     if not hit.is_empty():foot_errors.append({"position":xyz(at),"ground":xyz(hit.position),"delta_y":at.y-hit.position.y,"collider":str(hit.collider.get_path())})
  if distance>=next_shot and shot<=4:
   await capture("route_%02d"%shot);shot+=1;next_shot=length_of(path)*(.20*shot)
  if not scene.walking():
   goal_index+=1
   if goal_index>=goals.size():break
   scene.walk_to(vec(goals[goal_index]))
 report.walk={"length_m":distance,"end":xyz(scene.player_position()),"error_m":scene.player_position().distance_to(goal),"hud_samples":trace.size(),"hud_failures":failures,"foot_samples":foot_errors,"trace_05m":trace}
 await capture("museum_front")
 if scene.layout.has("mid_stairs"):
  for spec in [["stairs_close",Vector3(-2.5,5.5,3.2)],["on_stair",Vector3(-1.85,4.15,5.5)]]:
   stand(spec[1]);await capture(spec[0])
  # A current-camera tap onto a known central tread; preserve the first physical hit.
  var tread=Vector3(-1.25,4.45,5.5);var pixel=scene._camera.unproject_position(tread)
  var origin=scene._camera.project_ray_origin(pixel);var ray=PhysicsRayQueryParameters3D.create(origin,origin+scene._camera.project_ray_normal(pixel)*200);ray.exclude=scene._boundary_rids
  var hit=scene.get_world_3d().direct_space_state.intersect_ray(ray)
  report.stair_click={"pixel":xy(pixel),"expected":xyz(tread),"hit":xyz(hit.position) if not hit.is_empty() else [],"collider":str(hit.collider.get_path()) if not hit.is_empty() else ""}
  scene.walk_to_screen(pixel);report.stair_click.path_end=xyz(scene._path[-1]) if scene._path.size()>0 else []
  await capture("stair_click")
 if scene.layout.has("mid_stairs"):
  report.click_checks=[]
  for s in scene.layout.mid_stairs.flights:
   var target=Vector3(-1.25,s.low+1.2,s.z0+.5)
   stand(target+Vector3(-.6 if s.east_up else .6,-.3,0))
   for f in 10:await get_tree().process_frame
   var pixel=scene._camera.unproject_position(target);var origin=scene._camera.project_ray_origin(pixel)
   var ray=PhysicsRayQueryParameters3D.create(origin,origin+scene._camera.project_ray_normal(pixel)*200);ray.exclude=scene._boundary_rids
   var hit=scene.get_world_3d().direct_space_state.intersect_ray(ray);scene.walk_to_screen(pixel)
   report.click_checks.append({"flight":s.id,"point":xyz(target),"hit":xyz(hit.position) if not hit.is_empty() else [],"collider":str(hit.collider.get_path()) if not hit.is_empty() else "","path_end":xyz(scene._path[-1]) if scene._path.size()>0 else []})
 stand(Vector3(-3.75,10,-7.35));await capture("summit_lamp_left")
 scene.camera_pan.reset(6.72/11.0);stand(Vector3(-4.5,10,-5.9));await capture("summit_flowerbed_11m")
 report.hud_contract=scene.layout.hud_clearance
 FileAccess.open(folder.path_join("review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 await overview()
 print("ALC_MID_COMPLETE ",report.runtime_path_length,"m, samples ",report.nav_samples.size()," end_error ",report.walk.error_m," HUD failures ",failures.size())
 audit.free();get_tree().quit()
func stand(at:Vector3):
 scene.dev_stand(at);scene._rig.play_motion("idle");scene._focus=scene._follow_target();scene._update_camera()
func capture(label:String):
 for i in 30:await get_tree().process_frame
 await RenderingServer.frame_post_draw
 var im=get_viewport().get_texture().get_image();assert(im.get_size()==Vector2i(360,800));assert(im.save_png(folder.path_join(label+".png"))==OK)
 report.views[label]={"player":xyz(scene.player_position()),"camera_position":xyz(scene._camera.position),"camera_basis":[xyz(scene._camera.global_basis.x),xyz(scene._camera.global_basis.y),xyz(scene._camera.global_basis.z)],"camera_size":scene._camera.size,"triangles":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(v:Vector3):return [v.x,v.y,v.z]
func xy(v:Vector2):return [v.x,v.y]
func path_array(path):
 var out:Array=[]
 for v in path:out.append(xyz(v))
 return out
func length_of(path):
 var result=0.0
 for i in range(1,path.size()):result+=path[i].distance_to(path[i-1])
 return result

func path_via(start:Vector3,goals:Array)->PackedVector3Array:
 var combined=PackedVector3Array();var previous=start
 for a in goals:
  var part=scene.find_path(previous,vec(a))
  for point in part:
   if combined.is_empty() or combined[-1].distance_to(point)>.0001:combined.append(point)
  if not part.is_empty():previous=part[-1]
 return combined

func overview():
 var vp=SubViewport.new();vp.size=Vector2i(1200,1000);vp.world_3d=get_viewport().world_3d;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.size=70;cam.far=250;vp.add_child(cam);cam.position=Vector3(0,50,0);cam.look_at(Vector3.ZERO,Vector3.FORWARD);cam.current=true
 scene._set_backdrop_visible(false)
 for node in scene._detail_groups:node.visible=true
 for node in scene._detail_batches:node.visible=true
 for node in scene._unshadowed_batches:
  var transforms:Array=node.get_meta("instance_transforms");var bounds:Array=node.get_meta("instance_bounds");var box:AABB=bounds[0]
  for i in transforms.size():node.multimesh.set_instance_transform(i,transforms[i]);box=box.merge(bounds[i])
  node.multimesh.visible_instance_count=transforms.size();node.multimesh.custom_aabb=box;node.visible=true
 for group in scene.tree_batches:
  var box:AABB=group.bounds[0]
  for i in group.transforms.size():group.near.multimesh.set_instance_transform(i,group.transforms[i]);box=box.merge(group.bounds[i])
  group.near.multimesh.visible_instance_count=group.transforms.size();group.near.multimesh.custom_aabb=box;group.near.visible=true;group.far.visible=false
 for i in 10:await get_tree().process_frame
 await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png(folder.path_join("topdown.png"))
 vp.queue_free()
