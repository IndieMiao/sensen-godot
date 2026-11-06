extends Node
const ROOT="res://assets/landmarks/alcatraz_island/"
var vp: SubViewport
var world: Node3D
var camera: Camera3D
var island
var rig
var actor
var output: String
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
 print("ALC_NATURE_CAPTURE ",name)
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
func run():
 output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
 vp=SubViewport.new();vp.size=Vector2i(1500,650);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(720,400);display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;add_child(display)
 world=Node3D.new();vp.add_child(world);light_scene()
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.size=17
 camera.position=Vector3(0,8,20);world.add_child(camera);camera.look_at(Vector3(0,.6,0));camera.make_current()
 var positions={"alc_rock_a":-6.7,"alc_rock_b":-4.55,"alc_rock_c":-1.55,"alc_shrub":1.5,"alc_shrub_b":3.2,"alc_grass_tuft":4.9}
 var models=[]
 for name in positions:
  var n=load(ROOT+name+".glb").instantiate();n.position=Vector3(positions[name],0,0);world.add_child(n);models.append(n)
 actor=Node3D.new();actor.position=Vector3(6.4,0,0);world.add_child(actor)
 rig=Avatar.create_rig();rig.assembler=AvatarAssemblerMerged.new();actor.add_child(rig)
 rig.apply_config(Avatar.load_outfit())
 for i in 10:await get_tree().process_frame
 var waits=0
 while rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not rig.is_busy(),"complete avatar assembled")
 var bounds=body_bounds();check(bounds.size.y>1.5 and bounds.size.y<2,"avatar complete bounds")
 actor.scale=Vector3.ONE*(1.75/bounds.size.y);report.lineup_avatar_height=1.75;report.avatar_source_height=bounds.size.y
 await capture("01_scale_lineup")
 actor.hide()
 # Close-ups are supplementary; lineup above is the shared absolute scale.
 camera.size=9;camera.position=Vector3(-4,5,11);camera.look_at(Vector3(-3.5,.7,0))
 await capture("02_rock_detail")
 camera.size=5.6;camera.position=Vector3(3.3,3.2,7);camera.look_at(Vector3(3.3,.35,0))
 await capture("03_foliage_detail")
 world.queue_free();await get_tree().process_frame;await get_tree().process_frame
 vp.size=Vector2i(1100,900)
 island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
 for i in 12:await get_tree().process_frame
 waits=0
 while island._rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not island._rig.is_busy(),"blockout avatar assembled")
 var nature=add_nature();island.set_process(false);island._hud.hide();island._set_backdrop_visible(false)
 camera=island._camera;camera.far=300;camera.size=18
 for n in nature:n.show() # whole-scene art review displays every authored item
 island._player.position=Vector3(-19.5,1,11.8)
 camera.position=Vector3(-44,18,33);camera.look_at(Vector3(-23,1.4,9))
 await capture("04_blockout_shore")
 camera.size=20;camera.position=Vector3(31,23,20);camera.look_at(Vector3(19,4,3))
 await capture("05_blockout_terraces")
 camera.size=77;camera.position=Vector3(67,75,97);camera.look_at(Vector3(0,4,-2));vp.size=Vector2i(1300,1100)
 await capture("06_whole_island")
 # Default opening confirms the right-bottom framing remains unobstructed.
 island._player.position=island._vec(island.layout.spawn);vp.size=Vector2i(360,800)
 island._set_backdrop_visible(true);island._focus=island._follow_target();island._update_camera();island._hud.show()
 await capture("07_default_opening")
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 check(report.renderer.method=="mobile","Mobile renderer")
 report.passed=report.checks.all(func(c):return c.passed)
 FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("ALC_NATURE_RENDER ",report.passed)
 get_tree().quit(0 if report.passed else 1)
