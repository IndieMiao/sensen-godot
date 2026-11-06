extends "res://review.gd"
var ready_for_review=false
var elapsed=0.0
var sequence=0
var view="opening"
func _ready(): mobile_run.call_deferred()
func mobile_run():
 if FileAccess.file_exists("user://ground_command.json"):DirAccess.remove_absolute("user://ground_command.json")
 island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();add_child(island)
 for i in 12:await get_tree().process_frame
 for n in island.mesh_nodes:
  var name_=str(n.name)
  if name_.begins_with("AlcGround") or name_.begins_with("Dock"):
   originals[n]=n.material_override
   targets[n]=dock if name_.begins_with("Dock") else terrain
 set_finish(true)
 ready_for_review=true
func _process(dt):
 if not ready_for_review:return
 elapsed+=dt
 if elapsed<.5:return
 elapsed=0
 if FileAccess.file_exists("user://ground_command.json"):
  var c=JSON.parse_string(FileAccess.get_file_as_string("user://ground_command.json"))
  if c is Dictionary and int(c.get("seq",0))>sequence:
   sequence=int(c.seq)
   view=c.get("view","opening")
   var key="visitor_center" if view=="summit" else view
   island._player.position=island._vec(island.layout.review_points[key])
   island._focus=island._follow_target();island._update_camera()
 var buttons={}
 for key in island._zoom_buttons:
  var b=island._zoom_buttons[key].get_global_rect().get_center();buttons[key]=[b.x,b.y]
 var data={"revision":"alcatraz-ground-424-v1.1","pid":OS.get_process_id(),"seq":sequence,"view":view,
  "assembled":not island._rig.is_busy(),"material_targets":targets.size(),"zoom":island.camera_pan.zoom,
  "buttons":buttons,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),
  "frames":Engine.get_frames_drawn(),"viewport":str(get_viewport().get_visible_rect().size)}
 FileAccess.open("user://ground_state.tmp",FileAccess.WRITE).store_string(JSON.stringify(data))
 DirAccess.rename_absolute("user://ground_state.tmp","user://ground_state.json")
