extends "res://review.gd"
var ready_for_review=false
var elapsed=0.0
var sequence=0
var view="dock"
func _ready(): mobile_run.call_deferred()
func mobile_run():
 island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();add_child(island)
 for i in 12:await get_tree().process_frame
 add_nature();add_dock();ready_for_review=true
func assets_view():
 island._hud.hide();island.hide();island.set_process(false);island._environment.environment=null
 world=Node3D.new();add_child(world);light_scene()
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.size=9.2;world.add_child(camera)
 camera.position=Vector3(0,14,22);camera.look_at(Vector3(0,.7,0));camera.make_current()
 var places={"alc_dock_bollard":Vector3(-2.7,0,2),"alc_dock_crates":Vector3(0,0,2),"alc_dock_planter":Vector3(2.7,0,2),"alc_dock_shelter":Vector3(-1.8,0,-2),"alc_dock_welcome":Vector3(1.4,0,-2)}
 for name in places:
  var n=load(ROOT+name+".glb").instantiate();n.position=places[name];world.add_child(n)
 actor=Node3D.new();actor.position=Vector3(2.7,0,-2);world.add_child(actor)
 rig=Avatar.create_rig();rig.assembler=AvatarAssemblerMerged.new();actor.add_child(rig);rig.apply_config(Avatar.load_outfit())
 view="assets"
func _process(dt):
 if not ready_for_review:return
 elapsed+=dt
 if elapsed<.5:return
 elapsed=0
 if FileAccess.file_exists("user://dock_command.json"):
  var c=JSON.parse_string(FileAccess.get_file_as_string("user://dock_command.json"))
  if c is Dictionary and int(c.get("seq",0))>sequence:
   sequence=int(c.seq)
   if c.get("view","")=="assets":assets_view()
 var buttons={}
 for key in island._zoom_buttons:
  var b=island._zoom_buttons[key].get_global_rect().get_center();buttons[key]=[b.x,b.y]
 var data={"revision":"alcatraz-dock-424-v1","pid":OS.get_process_id(),"seq":sequence,"view":view,
  "assembled":not island._rig.is_busy() and (view!="assets" or not rig.is_busy()),"instances":report.instances,"batches":report.batches,
  "zoom":island.camera_pan.zoom,"buttons":buttons,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"frames":Engine.get_frames_drawn(),"viewport":str(get_viewport().get_visible_rect().size)}
 FileAccess.open("user://dock_state.tmp",FileAccess.WRITE).store_string(JSON.stringify(data))
 DirAccess.rename_absolute("user://dock_state.tmp","user://dock_state.json")
