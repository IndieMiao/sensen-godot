extends Node
const KIT="res://assets/rooms/mine_hut/"
var report={"checks":[],"assets":{},"captures":[]}
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var heading:Label
var footer:Label
var output:String
var room:Node3D
var rig
var layout:Dictionary
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(p):return [p.x,p.y,p.z]
func check(ok,label):
 report.checks.append({"check":label,"passed":ok})
 if not ok:push_error(label)
func setup(size):
 vp=SubViewport.new();vp.size=size;vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;get_tree().root.add_child(vp)
 world=Node3D.new();vp.add_child(world)
 var lighting=layout.review_lighting
 var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(lighting.background)
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(lighting.ambient_color);env.ambient_light_energy=lighting.ambient;env.tonemap_mode=Environment.TONE_MAPPER_ACES
 var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
 var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=vec(lighting.sun_position);sun.look_at(Vector3.ZERO)
 sun.light_color=Color(lighting.sun_color);sun.light_energy=lighting.sun;sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.directional_shadow_max_distance=30;sun.shadow_bias=.035;sun.shadow_normal_bias=.3;sun.light_angular_distance=4
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.near=.05;camera.far=100;camera.current=true;world.add_child(camera)
 var layer=CanvasLayer.new();vp.add_child(layer)
 heading=Label.new();heading.position=Vector2(12,16);heading.add_theme_font_size_override("font_size",13 if size.x==360 else 22);heading.add_theme_color_override("font_color",Color("4c4338"));layer.add_child(heading)
 footer=Label.new();footer.position=Vector2(12,size.y-66);footer.add_theme_font_size_override("font_size",11 if size.x==360 else 17);footer.add_theme_color_override("font_color",Color("4c4338"));layer.add_child(footer)
 room=load("res://scenes/mine_hut/mine_hut_art.tscn").instantiate();world.add_child(room)
func pose(focus,size,pitch=43.0,yaw=45.0):
 camera.size=size;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*20
func capture(id):
 for i in 16:await RenderingServer.frame_post_draw
 var img=vp.get_texture().get_image();check(img.save_png(output+"/"+id+".png")==OK,"Saved "+id)
 report.captures.append({"id":id,"width":img.get_width(),"height":img.get_height(),"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y,"size":camera.size,"position":xyz(camera.position),"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"rendered_primitives":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)})
 print("MINE_HUT_CAPTURE ",id)
func audit():
 var stats=JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"));var total=0;var surfaces=0
 for asset in stats.assets:
  var m=load(KIT+asset.name+".glb").instantiate();add_child(m);var box=AABB();var first=true;var tris=0;var count=0;var uv_ok=true
  for mesh in m.find_children("*","MeshInstance3D",true,false):
   for si in mesh.mesh.get_surface_count():
    var a=mesh.mesh.surface_get_arrays(si);count+=1;tris+=a[Mesh.ARRAY_INDEX].size()/3
    for v in a[Mesh.ARRAY_VERTEX]:
     var p=m.global_transform.affine_inverse()*mesh.global_transform*v
     if first:box=AABB(p,Vector3.ZERO);first=false
     else:box=box.expand(p)
    for uv in a[Mesh.ARRAY_TEX_UV]:uv_ok=uv_ok and uv.x>=0 and uv.y>=0 and uv.x<=1 and uv.y<=1
  check(tris==asset.triangles,asset.name+" imported triangles match");check(count==1,asset.name+" one surface");check(uv_ok,asset.name+" atlas UV within [0,1]")
  report.assets[asset.name]={"bounds":[xyz(box.position),xyz(box.end)],"size":xyz(box.size),"triangles":tris,"surfaces":count};total+=tris;surfaces+=count;m.free()
 check(total<=200000,"scene <=200k triangles");check(surfaces<=60,"scene <=60 surfaces");report.scene_triangles=total;report.scene_surfaces=surfaces
 var texture=load(KIT+"room_albedo_ao.png");check(texture.get_width()==2048 and texture.get_height()==2048,"one 2048 atlas")
func add_ivo():
 rig=Avatar.create_rig()
 for child in rig.get_children():
  if child is RigActivity:child.free()
 rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.position=vec(layout.suggested_anchors.npc_ivo.position);rig.rotation_degrees.y=45
 var config=Avatar.slot_table.default_config()
 for k in {"hairHat":"hairhat_npc_ivo","mask":"mask16_npc_ivo","cloth":"cloth1_npc_ivo","shoes":"shoes3"}:config.slots[StringName(k)]={"hairHat":"hairhat_npc_ivo","mask":"mask16_npc_ivo","cloth":"cloth1_npc_ivo","shoes":"shoes3"}[k]
 rig.apply_config(config);var ticks=0
 while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
 check(not rig.is_busy(),"Ivo real NPC parts assembled");rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
 report.ivo_look=config.slots
func physics_audit():
 # Real engine sweep using a human-size capsule, not an AABB stand-in.
 var body=CharacterBody3D.new();body.name="QA_character_capsule";var shape=CapsuleShape3D.new();shape.radius=.25;shape.height=1.745
 var cs=CollisionShape3D.new();cs.shape=shape;cs.position.y=.8725;body.add_child(cs);world.add_child(body)
 await get_tree().physics_frame;await get_tree().physics_frame
 body.position=Vector3(-.30,.089,-1.50)
 var result=body.move_and_collide(Vector3(0,0,-2))
 check(result!=null,"closed mine stops actual capsule sweep")
 if result:report.mine_collision={"collider":str(result.get_collider().get_path()),"stop":xyz(body.position)};check("mine_entrance" in str(result.get_collider().get_path()),"mine entrance blocker hit before rear wall")
 # Open approach positive control and NPC stand area clearance.
 body.position=Vector3(0,.089,2.55);result=body.move_and_collide(Vector3(0,0,-1.9));check(result==null,"spawn to central rug passage clear")
 body.position=Vector3(.80,.089,.05);result=body.move_and_collide(Vector3(.60,0,-.89));check(result==null,"stand to Ivo location clear")
 body.position=Vector3(0,.089,2.55);result=body.move_and_collide(Vector3(0,0,.51));check(result==null,"exit threshold approach clear")
 body.free()
 # Nameplate box must contain no room surface, measured from actual imported mesh bounds.
 var zone=AABB(vec(layout.nameplate_clearance.center)-vec(layout.nameplate_clearance.size)/2,vec(layout.nameplate_clearance.size))
 var hits=[]
 for m in room.find_children("*","MeshInstance3D",true,false):
  var box=m.global_transform*m.get_aabb()
  if box.intersects(zone):hits.append(str(m.get_path()))
 check(hits.is_empty(),"Ivo nameplate volume clear of overhead geometry");report.nameplate_intersections=hits
func run():
 output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
 layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"));audit()
 setup(Vector2i(360,800));await add_ivo();await physics_audit()
 pose(Vector3(0,1.15,0),6.72);heading.text="MINE HUT / GAMEPLAY VIEW\n43 DEG / 6.72 M / 360 PX";footer.text="SGODOT-308 / LIU BEI\nIvo + exit only / mine is closed\nFull room shown in separate panorama";await capture("gameplay_43deg_360")
 pose(Vector3(0,1.25,0),12.4);heading.text="MINE HUT / FULL ROOM\n43 DEG / PANORAMA";footer.text="SGODOT-308 / LIU BEI\n6.8 x 6.4 m floor / shared 2048 atlas\nWarm lamps + salt-fish stove";await capture("full_room_43deg_360")
 vp.size=Vector2i(1200,1000);heading.add_theme_font_size_override("font_size",22);footer.add_theme_font_size_override("font_size",17);footer.position=Vector2(12,900)
 await capture("full_room_panorama")
 rig.hide();pose(Vector3(-.30,1.48,-2.60),3.75,18,12);heading.text="MINE ENTRANCE / CLOSED";footer.text="SGODOT-308 / LIU BEI\nCross braces + physical blocker / rail, cart and hanging lanterns";await capture("mine_entrance_detail")
 pose(Vector3(2.0,1.19,-2.35),2.6,35,25);heading.text="SORTING BENCH / VERDIGRIS ORE";footer.text="SGODOT-308 / LIU BEI\nReused workbench / grey stone, dark ore, copper-green rock and quartz";await capture("sorting_table_detail")
 rig.show();pose(Vector3(1.3,1.25,-.8),4.3,43,45);heading.text="IVO / POSITION + NAMEPLATE CLEARANCE";footer.text="SGODOT-308 / LIU BEI\nOriginal Ivo helmet + beard / canvas shirt / black boots\nFeet (1.40, 0.082, -0.84) m; headroom kept clear";await capture("ivo_position")
 pose(Vector3(1.4,1.15,-.84),3.3,20,45);heading.text="IVO / FRONT THREE-QUARTER";footer.text="SGODOT-308 / LIU BEI\nSame actual NPC look, extra eye-level review";await capture("ivo_character_detail")
 rig.hide();pose(Vector3(-2.6,1.22,-.62),3.5,25,75);heading.text="LEFT HEARTH / TWO SALT-GRILLED FISH";footer.text="SGODOT-308 / LIU BEI\nMetal stove, slab, firewood / reused shelf and lantern";await capture("stove_detail")
 pose(Vector3(0,.2,0),9.4,90,0);heading.text="MINE HUT / TOP VIEW";footer.text="SGODOT-308 / LIU BEI\nOpen central passage / Ivo on right / front-centre exit";await capture("top_view")
 report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name();report.failures=report.checks.filter(func(c):return not c.passed)
 FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("MINE_HUT_QA ",report.checks.size()," checks, ",report.failures.size()," failures");get_tree().quit(0 if report.failures.is_empty() else 1)
