extends Node
## Native QA observer. Shares the real3D world into a Steam-only measurement viewport.
## Primary host/camera/UI stay unchanged; optional single-puff control is measurement-only.
var output:String
var frames=[]
var recording=false
var ended=false
var start_wall:int
var tracked_host
var next_frame_usec=0
var buffered=[]
var alpha_view:SubViewport
var alpha_cam:Camera3D
func _ready():
	var base=OS.get_environment("STEAM_TEST_BASE")
	if base!="":
		var fixture=JSON.parse_string(FileAccess.get_file_as_string(base))
		assert(fixture is Dictionary and fixture.size()==1)
		FileAccess.open("user://p0_player.txt",FileAccess.WRITE).store_line(str(fixture.keys()[0]))
	output=OS.get_environment("STEAM_LIVE_OUTPUT")
	if output=="":set_process(false);return
	for sub in ["frames","layers","linear"]:DirAccess.make_dir_recursive_absolute(output+"/"+sub)
	RenderingServer.frame_post_draw.connect(capture)
func _process(_dt):
	if OS.get_environment("STEAM_PACE_30")=="1":
		var now=Time.get_ticks_usec()
		if next_frame_usec>now:OS.delay_usec(next_frame_usec-now)
		next_frame_usec=maxi(next_frame_usec+33333,Time.get_ticks_usec())
func capture():
	if ended:return
	var rt=P0Runtime._instance
	if not is_instance_valid(rt) or not is_instance_valid(rt.world):return
	var kitchen=rt.world.get("kitchen")
	if kitchen==null:return
	var host=kitchen.get("_wait_pot")
	if host==null or not host.visible or host.pot==null:return
	if alpha_view==null:
		alpha_view=SubViewport.new();alpha_view.size=host.view.size;alpha_view.world_3d=host.view.find_world_3d()
		alpha_view.transparent_bg=true;alpha_view.use_hdr_2d=true;alpha_view.msaa_3d=Viewport.MSAA_4X;alpha_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(alpha_view)
		alpha_cam=Camera3D.new();alpha_cam.projection=host._cam.projection;alpha_cam.keep_aspect=host._cam.keep_aspect;alpha_cam.size=host._cam.size;alpha_cam.near=host._cam.near;alpha_cam.far=host._cam.far;alpha_cam.cull_mask=1<<19;alpha_view.add_child(alpha_cam);alpha_cam.global_transform=host._cam.global_transform;alpha_cam.current=true
		var cloud=host.pot.find_child("Steam",true,false) as GPUParticles3D
		cloud.layers|=1<<19
		if OS.get_environment("STEAM_NATIVE_SINGLE")=="1":cloud.amount=1;cloud.restart()
		return
	var elapsed=float(kitchen.elapsed())
	if elapsed<1200:return
	if not recording:
		recording=true;start_wall=Time.get_ticks_msec();tracked_host=host
		print("STEAM_NATIVE_RECORD_START elapsed_ms=",elapsed," phase=",kitchen.phase)
	if kitchen.phase!="watch":finish("watch ended before90frames");return
	var steam=host.pot.find_child("Steam",true,false) as GPUParticles3D
	var lid=host.pot.get_node("PotRig/StovePot/pot_big/lid/lid_mesh") as MeshInstance3D
	var lid_top=INF
	for point in lid.mesh.get_faces():lid_top=minf(lid_top,host._cam.unproject_position(lid.global_transform*point).y)
	var i=frames.size();var layer=alpha_view.get_texture().get_image();var format=layer.get_format()
	var raw=layer.get_data();layer.convert(Image.FORMAT_RGBA8)
	buffered.append({"raw":raw,"layer":layer,"frame":get_viewport().get_texture().get_image()})
	var ring=kitchen.get("_ring")
	frames.append({"frame":i,"engine_frame":Engine.get_frames_drawn(),"elapsed_ms":elapsed,"wall_ms":Time.get_ticks_msec(),"phase":kitchen.phase,"layer_position":xy(host.global_position),"layer_size":xy(host.view.size),"layer_hdr":host.view.use_hdr_2d,"layer_format":format,"layer_is_half_float":format==Image.FORMAT_RGBAH,"layer_bytes":raw.size(),"camera_position":xyz(host._cam.position),"camera_rotation":xyz(host._cam.rotation_degrees),"camera_size":host._cam.size,"mouth":xy(host.mouth_screen()),"emitter_screen":xy(host._cam.unproject_position(steam.global_position)+host.global_position),"lid_top":lid_top+host.global_position.y,"lid_cutoff":steam.material_override.get_shader_parameter("lid_top_uv"),"steam_visible":steam.visible,"steam_emitting":steam.emitting,"particle_count":steam.amount,"ring_visible":ring.visible if ring!=null else false})
	if Time.get_ticks_msec()-start_wall>=3000:finish("")
func finish(reason):
	ended=true
	var capture_wall=Time.get_ticks_msec()-start_wall
	for i in buffered.size():
		FileAccess.open(output+"/linear/%03d.bin"%i,FileAccess.WRITE).store_buffer(buffered[i].raw)
		buffered[i].layer.save_png(output+"/layers/%03d.png"%i)
		buffered[i].frame.save_png(output+"/frames/%03d.png"%i)
	var r={"host_head":"5d50bf0c2aa3868aba89b777a3c8a4925cdd15c9","frames":frames,"frame_count":frames.size(),"error":reason,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"elapsed_wall_ms":capture_wall,"observer_scope":"Extra transparent measurement viewport shares native world and camera; only Steam has measurement layer19. Primary host/camera/UI unmodified."}
	FileAccess.open(output+"/native-measurements.json",FileAccess.WRITE).store_string(JSON.stringify(r,"\t")+"\n")
	print("STEAM_NATIVE_CAPTURE_DONE ",frames.size()," ",reason)
	if OS.get_environment("STEAM_OBSERVER_QUIT")=="1":get_tree().quit(0 if reason=="" else 2)
func _exit_tree():
	if recording and not ended:finish("process exited before90frames")
func xy(v):return [v.x,v.y]
func xyz(v):return [v.x,v.y,v.z]
