extends Node
## Locked desktop Mobile review. Independent scene_bench remains unmodified.
const KIT="res://assets/rooms/poi_church/"
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var room:Node3D
var rig
var ui:Control
var overlay:Node3D
var output:String
var report={"checks":[],"captures":[],"routes":[]}
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label):
 report.checks.append({"check":label,"passed":bool(ok)})
 if not ok:push_error(label)
func setup():
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
 vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp);world=Node3D.new();vp.add_child(world)
 var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("DDE8E7")
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("FFF0DC");env.ambient_light_energy=.65
 env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
 var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
 var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=Vector3(-6,9,3);sun.look_at(Vector3.ZERO)
 sun.light_color=Color("FFF1D8");sun.light_energy=1.0;sun.shadow_enabled=true;sun.shadow_opacity=.5
 sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.shadow_bias=.05;sun.shadow_normal_bias=.25
 camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.near=.1;camera.far=80;world.add_child(camera)
 room=load("res://scenes/poi_church/poi_church_art.tscn").instantiate();world.add_child(room)
 ui=Control.new();vp.add_child(ui);ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
 overlay=Node3D.new();world.add_child(overlay);overlay.visible=false
func pose(width,pitch=43.,yaw=45.,focus=Vector3(0,1.4,-1.0)):
 camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*24
func run():
 setup();pose(6.72,43,45,Vector3(0,1.4,-1.0))
 var avatar=get_node("/root/Avatar")
 rig=avatar.create_rig()
 for c in rig.get_children():
  if c is RigActivity:rig.remove_child(c);c.free()
 world.add_child(rig)
 var cfg=avatar.slot_table.default_config()
 for slot in {"hairHat":"hairhat0","cloth":"cloth1_npc_gabriel","shoes":"shoes3"}:cfg.slots[StringName(slot)]={"hairHat":"hairhat0","cloth":"cloth1_npc_gabriel","shoes":"shoes3"}[slot]
 rig.apply_config(cfg)
 while rig.is_busy():await get_tree().process_frame
 rig.position=Vector3(-1.3,.54,-1.2);rig.rotation_degrees.y=180
 rig.play_motion("idle");var anim=rig.get_node("AnimationPlayer");anim.seek(0,true);anim.pause()
 for i in 5:await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png("res://output/gabriel-review/church-360x800.png")
 print("GABRIEL_CHURCH_CAPTURE: C 4d9668c2 art camera/light; temporary placement only; scale 1.0")
 get_tree().quit()
