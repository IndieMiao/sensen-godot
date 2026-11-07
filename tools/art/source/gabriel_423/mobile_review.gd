extends Node
var rig
var seq=0
var ready_model=false
var ticks=0
var vp:SubViewport
var button:Button
func _ready():run.call_deferred()
func run():
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_2X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;add_child(display)
 var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("e4f1ee");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("edf0ff");env.ambient_light_energy=.72
 var we=WorldEnvironment.new();we.environment=env;vp.add_child(we)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-32,-28,0);sun.light_energy=.95;vp.add_child(sun)
 var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.02;camera.near=.02;camera.far=6;vp.add_child(camera);camera.look_at_from_position(Vector3(0,.93,2.4),Vector3(0,.88,0));camera.current=true
 var avatar=get_node('/root/Avatar');rig=avatar.create_rig()
 for c in rig.get_children():
  if c is RigActivity:rig.remove_child(c);c.free()
 vp.add_child(rig)
 var cfg=avatar.slot_table.default_config()
 for slot in {"hairHat":"hairhat0","cloth":"cloth1_npc_gabriel","shoes":"shoes3"}:cfg.slots[StringName(slot)]={"hairHat":"hairhat0","cloth":"cloth1_npc_gabriel","shoes":"shoes3"}[slot]
 rig.apply_config(cfg)
 while rig.is_busy():await get_tree().process_frame
 rig.play_motion("idle");rig.get_node("AnimationPlayer").seek(0,true);rig.get_node("AnimationPlayer").pause();ready_model=true
 button=Button.new();button.text="Front / 3-4 / Walk";button.position=Vector2(70,755);button.size=Vector2(220,40);add_child(button);button.pressed.connect(change)
 await save_state()
func change():
 seq+=1
 rig.rotation.y=PI/4 if seq%3==1 else 0
 rig.play_motion("walk" if seq%3==2 else "idle")
 if seq%3!=2:rig.get_node("AnimationPlayer").seek(0,true);rig.get_node("AnimationPlayer").pause()
 await save_state()
func _process(_dt):
 ticks+=1
 if ready_model and ticks%30==0:await save_state()
func save_state():
 await RenderingServer.frame_post_draw
 var img=vp.get_texture().get_image();img.save_png("user://viewport.png")
 var ap=rig.get_node("AnimationPlayer")
 var state={"sequence":seq,"pid":OS.get_process_id(),"assembled":ready_model,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":[360,800],"frames":ticks,"animation":ap.current_animation,"time":ap.current_animation_position,"button":[180,775]}
 FileAccess.open("user://state.json",FileAccess.WRITE).store_string(JSON.stringify(state))
