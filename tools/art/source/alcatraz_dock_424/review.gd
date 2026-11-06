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
 print("ALC_DOCK_CAPTURE ",name)
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
 report.source_layout_commit=manifest.source_layout_commit
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
func projected_bounds(p):
 var b=island._mesh(p.asset).get_aabb();var t=island._transform_of(p)
 var rect=Rect2(camera.unproject_position(t*b.get_endpoint(0)),Vector2.ZERO)
 for i in range(1,8):rect=rect.expand(camera.unproject_position(t*b.get_endpoint(i)))
 return rect
func check_opening():
 var points=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"alc_dock_placements.json")).points
 var zoom=[]
 for button in island._zoom_buttons.values():zoom.append(button.get_global_rect())
 var exit_rect=island._exit_marker.get_global_rect()
 report.opening_hud={"zoom_rects":str(zoom),"map_rect":str(exit_rect),"projected_props":[]}
 for p in points:
  var r=projected_bounds(p)
  report.opening_hud.projected_props.append({"name":p.name,"rect_xywh":[r.position.x,r.position.y,r.size.x,r.size.y]})
  if p.asset in ["alc_dock_shelter","alc_dock_welcome","alc_dock_planter"]:
   for box in zoom:check(not r.intersects(box.grow(12)),p.name+": clear of zoom buttons plus 12px")
   check(not r.intersects(Rect2(244,508,112,172).grow(12)),p.name+": future right-lower actions clear")
  if p.asset=="alc_dock_welcome":check(not r.intersects(exit_rect.grow(12)),"blank welcome clear of Map exit plus 12px")
 check(island._exit_marker.visible,"Map exit visible")
 check(island._player.position.is_equal_approx(Vector3(-22,1,19)),"pinned dock spawn unchanged")
 check(is_equal_approx(camera.size,6.72),"default camera 6.72m")
func run():
 output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
 vp=SubViewport.new();vp.size=Vector2i(1500,700);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(720,400);display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;add_child(display)
 world=Node3D.new();vp.add_child(world);light_scene()
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.size=13.5
 camera.position=Vector3(3,6.5,20);world.add_child(camera);camera.look_at(Vector3(0,.7,0));camera.make_current()
 var positions={"alc_dock_bollard":-5.5,"alc_dock_crates":-3.85,"alc_dock_shelter":-.9,"alc_dock_welcome":1.95,"alc_dock_planter":3.5}
 report.lineup_labels=[]
 for name in positions:
  var n=load(ROOT+name+".glb").instantiate();n.position=Vector3(positions[name],0,0);world.add_child(n)
  var pt=camera.unproject_position(n.position);report.lineup_labels.append({"asset":name,"screen_x":pt.x})
 actor=Node3D.new();actor.position=Vector3(5.3,0,0);world.add_child(actor)
 rig=Avatar.create_rig();rig.assembler=AvatarAssemblerMerged.new();actor.add_child(rig);rig.apply_config(Avatar.load_outfit())
 for i in 10:await get_tree().process_frame
 var waits=0
 while rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not rig.is_busy(),"complete avatar assembled")
 var bounds=body_bounds();check(bounds.size.y>1.5 and bounds.size.y<2,"complete human source bounds")
 actor.scale=Vector3.ONE*(1.75/bounds.size.y);report.lineup_avatar_height_m=1.75
 await capture("01_scale_lineup")
 # Extra 3/4 review resolves rope turns, seating and the blank board face.
 camera.size=8;camera.position=Vector3(-3.5,6,11);camera.look_at(Vector3(-2,.8,0));vp.size=Vector2i(1200,850)
 await capture("02_dock_detail")
 world.queue_free();await get_tree().process_frame;await get_tree().process_frame
 vp.size=Vector2i(360,800)
 island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
 for i in 12:await get_tree().process_frame
 waits=0
 while island._rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not island._rig.is_busy(),"blockout avatar assembled")
 add_nature()
 island.set_process(false);camera=island._camera;island._focus=island._follow_target();island._update_camera()
 await capture("03_opening_before")
 add_dock()
 for i in 4:await get_tree().process_frame
 island._update_camera();check_opening()
 await capture("04_dock_opening")
 vp.size=Vector2i(1100,1000);island._hud.hide();island._set_backdrop_visible(false)
 camera.size=11.8;camera.position=Vector3(-13,14,30);camera.look_at(Vector3(-22,1.1,15.5));camera.far=200
 await capture("05_dock_context")
 camera.size=13;camera.position=Vector3(-22,22,15.5);camera.look_at(Vector3(-22,1,15.5),Vector3(0,0,-1))
 await capture("06_dock_top")
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 check(report.renderer.method=="mobile","Mobile renderer")
 report.passed=report.checks.all(func(c):return c.passed)
 FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("ALC_DOCK_RENDER ",report.passed)
 get_tree().quit(0 if report.passed else 1)
