extends Node
const ROOT="res://assets/landmarks/alcatraz_island/"
var vp: SubViewport
var world: Node3D
var camera: Camera3D
var island
var rig
var actor
var output: String
var dock_nodes=[]
var shore_nodes=[]
var report={"checks":[],"captures":[]}
func _ready(): run.call_deferred()
func check(ok,label):
 report.checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func capture(name):
 for i in 8:await RenderingServer.frame_post_draw
 var img=vp.get_texture().get_image()
 check(img.get_size()==vp.size,name+": dimensions")
 check(img.save_png(output+"/"+name+".png")==OK,"save "+name)
 report.captures.append({"name":name,"size":[vp.size.x,vp.size.y],"camera":str(camera.global_transform),"width_m":camera.size,
  "visible_draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
  "visible_primitives":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
 print("ALC_FOAM_CAPTURE ",name)
func light_scene():
 var env=WorldEnvironment.new();env.environment=Environment.new()
 env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e7e8de")
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color=Color("d5e4ee");env.environment.ambient_light_energy=.72;world.add_child(env)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-56,-34,0);sun.light_color=Color(1,.965,.88);sun.light_energy=.98
 sun.shadow_enabled=true;sun.shadow_opacity=.48;sun.directional_shadow_max_distance=120;world.add_child(sun)
 var floor=MeshInstance3D.new();floor.mesh=PlaneMesh.new();floor.mesh.size=Vector2(40,30)
 var mat=StandardMaterial3D.new();mat.albedo_color=Color("c7cebc");mat.roughness=.94;floor.material_override=mat;floor.position.y=-.02;world.add_child(floor)
func body_bounds():
 var bounds=AABB();var first=true
 for m in rig.find_children("*","MeshInstance3D",true,false):
  var b=actor.global_transform.affine_inverse()*m.global_transform*m.get_aabb()
  if first:bounds=b;first=false
  else:bounds=bounds.merge(b)
 return bounds
func add_nature():
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"alc_nature_placements.json"))
 # Replace only the owner's existing batches; never stack a second layout.
 var removed=0
 var owner_assets=["alc_rock_a","alc_rock_b","alc_rock_c","alc_shrub","alc_grass_tuft"]
 for zone in island.zones.values():
  for n in zone.get_children():
   if n is MultiMeshInstance3D:
    for asset in owner_assets:
     if str(n.name)==asset.to_pascal_case()+"Batch":
      removed+=n.multimesh.instance_count
      island.batch_nodes.erase(n);island._detail_batches.erase(n)
      zone.remove_child(n);n.queue_free()
 check(removed==manifest.points.size(),"replace all 114 owner placeholders exactly once")
 var batches={}
 for p in manifest.points:
  var key=str(p.zone)+"/"+str(p.asset)
  if not batches.has(key):batches[key]=[]
  batches[key].append(p)
 var nodes=[]
 for key in batches:
  var pts=batches[key];var asset=str(pts[0].asset);var mesh=island._mesh(asset)
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=pts.size()
  for i in pts.size():mm.set_instance_transform(i,island._transform_of(pts[i]))
  var n=MultiMeshInstance3D.new();n.name="Nature_"+asset;n.multimesh=mm;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  island.zones[pts[0].zone].add_child(n);nodes.append(n)
  island.batch_nodes.append(n)
  if pts[0].has("max_view_width_m"):
   n.set_meta("max_view_width_m",float(pts[0].max_view_width_m));island._detail_batches.append(n)
 report.nature_base_layout_commit=manifest.source_layout_commit
 report.removed_owner_placeholders=removed
 report.nature_instances=manifest.points.size();report.nature_batches=nodes.size()
 return nodes
func add_dock():
 var points=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"alc_dock_placements.json")).points
 var groups={}
 for p in points:
  if not groups.has(p.asset):groups[p.asset]=[]
  groups[p.asset].append(p)
 for name in groups:
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=island._mesh(name);mm.instance_count=groups[name].size()
  for i in groups[name].size():mm.set_instance_transform(i,island._transform_of(groups[name][i]))
  var n=MultiMeshInstance3D.new();n.name=name;n.multimesh=mm;island.zones.DockZone.add_child(n);dock_nodes.append(n)
 report.instances=points.size();report.batches=dock_nodes.size()
func add_shore():
 var spec=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"alc_shore_foam_placements.json"));var groups={}
 for p in spec.points:
  if not groups.has(p.asset):groups[p.asset]=[]
  groups[p.asset].append(p)
 for name in groups:
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=island._mesh(name);mm.instance_count=groups[name].size()
  for i in groups[name].size():mm.set_instance_transform(i,island._transform_of(groups[name][i]))
  var n=MultiMeshInstance3D.new();n.name=name;n.multimesh=mm;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;n.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
  island.zones.DockZone.add_child(n);shore_nodes.append(n)
 report.host_commit=spec.host_commit;report.nature_commit=spec.nature_commit;report.dock_commit=spec.dock_commit
 report.shore_instances=spec.points.size();report.shore_batches=shore_nodes.size();report.placed_triangles=spec.placed_triangles
 return shore_nodes
func projected_bounds(p):
 var b=island._mesh(p.asset).get_aabb();var t=island._transform_of(p)
 var rect=Rect2(camera.unproject_position(t*b.get_endpoint(0)),Vector2.ZERO)
 for i in range(1,8):rect=rect.expand(camera.unproject_position(t*b.get_endpoint(i)))
 return rect
func pixel_diff(a:Image,b:Image,rect:Rect2i):
 var count=0;var total=0.0;var largest=0.0
 for y in range(rect.position.y,rect.end.y):
  for x in range(rect.position.x,rect.end.x):
   var c=a.get_pixel(x,y);var d=b.get_pixel(x,y);var delta=max(abs(c.r-d.r),max(abs(c.g-d.g),abs(c.b-d.b)))
   count+=int(delta>1.0/255);total+=delta;largest=max(largest,delta)
 return {"changed_pixels":count,"max_rgb_255":largest*255,"mean_max_rgb_255":total*255/(rect.size.x*rect.size.y)}
func run():
 output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
 vp=SubViewport.new();vp.size=Vector2i(1400,900);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(700,450);display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;add_child(display)
 world=Node3D.new();vp.add_child(world);light_scene()
 # Independent blue review floor, not the host sea/material.
 for n in world.get_children():
  if n is MeshInstance3D:n.material_override.albedo_color=Color("9fb9bd");n.position.y=-.018
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.size=13.8
 camera.position=Vector3(0,10,15);world.add_child(camera);camera.look_at(Vector3(0,.4,0));camera.make_current()
 var positions={"alc_foam_strip_a":Vector3(-4.5,0,-2),"alc_foam_strip_b":Vector3(0,0,-2),"alc_foam_strip_c":Vector3(4.5,0,-2),"alc_foam_ring":Vector3(-3.6,0,2.2),"alc_buoy":Vector3(-.2,0,2.2),"alc_driftwood":Vector3(2,0,2.2)}
 for name in positions:
  var n=load(ROOT+name+".glb").instantiate();n.position=positions[name];world.add_child(n)
 actor=Node3D.new();actor.position=Vector3(4.3,0,2.2);world.add_child(actor);rig=Avatar.create_rig();rig.assembler=AvatarAssemblerMerged.new();actor.add_child(rig);rig.apply_config(Avatar.load_outfit())
 for i in 12:await get_tree().process_frame
 var waits=0
 while rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not rig.is_busy(),"complete lineup avatar");var bounds=body_bounds();actor.scale=Vector3.ONE*(1.75/bounds.size.y);report.lineup_avatar_height=1.75;rig.play_motion("idle")
 rig.process_mode=Node.PROCESS_MODE_DISABLED
 await capture("01_six_assets");var foam_static=vp.get_texture().get_image()
 for i in 30:await RenderingServer.frame_post_draw
 report.static_foam_control=pixel_diff(foam_static,vp.get_texture().get_image(),Rect2i(0,0,1400,900))
 check(report.static_foam_control.max_rgb_255==0,"independent foam and floats static / no flicker")
 world.queue_free();await get_tree().process_frame;await get_tree().process_frame
 vp.size=Vector2i(360,800);island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
 for i in 12:await get_tree().process_frame
 waits=0
 while island._rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not island._rig.is_busy(),"host avatar assembled")
 add_nature();add_dock();island.set_process(false);island._rig.process_mode=Node.PROCESS_MODE_DISABLED
 # Freeze only QA clock so host sea animation does not contaminate overlay comparisons.
 Engine.time_scale=0.0;report.comparison_clock="QA Engine.time_scale=0 after assembly; host sea shader/material unmodified"
 camera=island._camera;island._focus=island._follow_target();island._update_camera()
 await capture("02_opening_before");var before=vp.get_texture().get_image()
 add_shore()
 await capture("03_dock_opening");var after=vp.get_texture().get_image()
 check(island._player.position.is_equal_approx(Vector3(-22,1,19)),"original dock spawn")
 check(is_equal_approx(camera.size,6.72),"original default camera width")
 var placements=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"alc_shore_foam_placements.json"));var projections=[]
 for p in placements.points:
  var rect=projected_bounds(p);check(not rect.intersects(Rect2(0,45,180,115)),p.name+": outside bridge/city strip")
  if p.asset in ["alc_buoy","alc_driftwood"]:
   for button in island._zoom_buttons.values():check(not rect.intersects(button.get_global_rect().grow(12)),p.name+": clear of zoom controls")
   check(not rect.intersects(island._exit_marker.get_global_rect().grow(8)),p.name+": clear of Map button")
  projections.append({"name":p.name,"rect_xywh":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
 report.opening_projected_bounds=projections;report.bridge_control=pixel_diff(before,after,Rect2i(0,45,180,115));check(report.bridge_control.max_rgb_255==0,"bridge and city pixels unchanged")
 report.opening_overlay=pixel_diff(before,after,Rect2i(0,160,360,560));check(report.opening_overlay.changed_pixels>100,"foam/float visible in opening")
 for i in 30:await RenderingServer.frame_post_draw
 var later=vp.get_texture().get_image();report.static_control=pixel_diff(after,later,Rect2i(0,45,360,700));check(report.static_control.max_rgb_255==0,"fixed-time host comparison stable")
 # Full shoreline detail from fixed supplementary camera; original environment.
 island._hud.hide();island._set_backdrop_visible(false);vp.size=Vector2i(1100,900)
 camera.size=17;camera.position=Vector3(-42,15,32);camera.look_at(Vector3(-24,0,14.8));camera.far=300
 await capture("04_shore_closeup")
 for n in shore_nodes:n.hide()
 await capture("05_shore_before")
 for n in shore_nodes:n.show()
 camera.size=13;camera.position=Vector3(14,11,28);camera.look_at(Vector3(8,0,14))
 await capture("06_rock_contacts")
 vp.size=Vector2i(1300,1100);camera.size=78;camera.position=Vector3(64,78,98);camera.look_at(Vector3(0,3,-2))
 await capture("07_whole_island")
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 check(report.renderer.method=="mobile","Mobile renderer")
 report.passed=report.checks.all(func(c):return c.passed)
 FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 Engine.time_scale=1.0
 print("ALC_FOAM_RENDER ",report.passed);get_tree().quit(0 if report.passed else 1)
