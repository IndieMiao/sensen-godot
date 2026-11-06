extends "res://review.gd"
## Offline Android smoke fixture. Owner scene / controls remain unchanged.
var elapsed := 0.0
var ready_for_review := false
var command_seq := 0
func _ready(): mobile_run.call_deferred()
func mobile_run():
 island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();add_child(island)
 for i in 12:await get_tree().process_frame
 add_nature()
 ready_for_review=true
func _process(dt):
 if not ready_for_review:return
 elapsed+=dt
 if elapsed<.5:return
 elapsed=0
 if FileAccess.file_exists("user://nature_command.json"):
  var c=JSON.parse_string(FileAccess.get_file_as_string("user://nature_command.json"))
  if c is Dictionary and int(c.get("seq",0))>command_seq:
   command_seq=int(c.seq)
   if c.get("view","")=="whole":island.toggle_overview()
 var buttons={}
 for key in island._zoom_buttons:
  var b=island._zoom_buttons[key].get_global_rect().get_center();buttons[key]=[b.x,b.y]
 var goal=island._camera.unproject_position(Vector3(-22,1,17))
 var p=island._player.position
 var f=island._focus
 var data={"revision":"alcatraz-nature-424-v1","pid":OS.get_process_id(),"seq":command_seq,
  "assembled":not island._rig.is_busy(),"navigation_ready":island.navigation_ready(),
  "actor":[p.x,p.y,p.z],"focus":[f.x,f.y,f.z],"zoom":island.camera_pan.zoom,
  "buttons":buttons,"walk_tap":[goal.x,goal.y],"running":island._running,
  "nature_instances":report.nature_instances,"nature_batches":report.nature_batches,
  "renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),
  "frames":Engine.get_frames_drawn(),"viewport":str(get_viewport().get_visible_rect().size)}
 FileAccess.open("user://nature_state.tmp",FileAccess.WRITE).store_string(JSON.stringify(data))
 DirAccess.rename_absolute("user://nature_state.tmp","user://nature_state.json")
