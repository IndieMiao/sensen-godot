extends Node
const KIT="res://assets/props/fish_trap_marker/"
var vp:SubViewport
var pond
var runtime
var fishing: FishingPresentation
var fixture:Dictionary
var output:String
var report={"checks":[],"captures":[],"transport_calls":0}
func _ready():run.call_deferred()
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func xyz(p):return [p.x,p.y,p.z]
func mesh_bounds(root):
	var lo=Vector3.INF;var hi=-Vector3.INF;var triangles=0;var surfaces=0
	for node in root.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null:continue
		for surface in node.mesh.get_surface_count():
			surfaces+=1;var a=node.mesh.surface_get_arrays(surface)
			triangles+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3
			for v in a[Mesh.ARRAY_VERTEX]:
				var p=root.global_transform.affine_inverse()*node.global_transform*v;lo=lo.min(p);hi=hi.max(p)
	return {"bounds":[xyz(lo),xyz(hi)],"size":xyz(hi-lo),"triangles":triangles,"surfaces":surfaces}
func screen_rect(root):
	if not root.is_visible_in_tree():return []
	var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
	for node in root.find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree():continue
		for surface in node.mesh.get_surface_count():
			for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p=pond.cam.unproject_position(node.to_global(vertex));lo=lo.min(p);hi=hi.max(p)
	check(lo.is_finite() and hi.is_finite(),"Finite screen bounds for "+str(root.name))
	return [lo.x,lo.y,hi.x-lo.x,hi.y-lo.y]
func capture(name):
	for i in 12:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"name":name,"pixels":[vp.size.x,vp.size.y],"camera":str(pond.cam.global_transform),
		"pitch":pond.cam.rotation_degrees.x,"width_m":pond.cam.size,
		"trap_screen_rect":screen_rect(pond._trap_float),"bobber_screen_rect":screen_rect(fishing._bobber)})
	print("TRAP_CAPTURE ",name)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	vp=SubViewport.new();vp.size=Vector2i(720,1600);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	runtime=P0Runtime.new();P0Runtime._instance=runtime
	runtime.session.transport=func(_method,_path,_body,_meta):report.transport_calls+=1
	vp.add_child(runtime);runtime.set_process(false);runtime.session.set_process(false)
	pond=load("res://review_pond.gd").new();pond.setup({"pond_id":"pond_san_francisco_01"});vp.add_child(pond)
	for i in 20:await get_tree().process_frame
	var ticks=0
	while pond.actor.rig.is_busy() and ticks<600:await get_tree().process_frame;ticks+=1
	check(not pond.actor.rig.is_busy(),"Native b1 player assembled")
	var spot=pond._trap_at();check(not spot.is_empty(),"Native pond trap placement plan exists")
	if spot.is_empty():get_tree().quit(1);return
	pond.actor.teleport(spot.origin);pond.actor.set_process(false);pond.actor.set_physics_process(false)
	fixture={"fishing":{"trap":{"traps":[{"place":pond.p0_place(),"fish":0,"keep":3,"fits":0,"all_fit":true,"back_fits":true}],"slots":1}}}
	pond._trap_frame(fixture)
	pond._trap_float.position.y=.055
	check(pond._trap_float.scale.is_equal_approx(Vector3.ONE),"Formal marker imported at unit scale; no legacy 1.6 multiplier")
	var target=spot.target+Vector3(.9,0,0)
	if not FishingModel.contains(str(pond.entry.id),target,.15,pond.site_spec):target=spot.target-Vector3(.9,0,0)
	check(FishingModel.contains(str(pond.entry.id),target,.15,pond.site_spec),"Comparison cast bobber is inside actual pond water")
	fishing=FishingPresentation.new();fishing.float_scale=pond.FLOAT_SCALE;fishing.float_ring=false
	fishing.close_up=false;fishing.line_px=pond.LINE_PX;fishing.line_color=pond.LINE_INK
	pond.add_child(fishing);fishing.configure_remote({"target":[target.x,target.z],"phase":"waiting"},pond.actor,pond.actor.rig,pond.cam)
	fishing.set_process(false);fishing._water=pond.get_node(str(pond.entry.id));fishing.step(0)
	pond._focus=(spot.origin+spot.target+target)/3+Vector3.UP*.65
	pond._opening=false;pond._parked=true;pond._update_camera()
	var default_transform=pond.cam.transform;var default_size=pond.cam.size
	check(absf(pond.cam.rotation_degrees.x+43)<.001,"Native pond camera pitch 43 degrees")
	var model_stats=mesh_bounds(pond._trap_float);report.model=model_stats
	check(model_stats.triangles==500 and model_stats.surfaces==1,"Actual imported marker 500 triangles / one surface")
	check(absf(model_stats.bounds[0][1]+.05)<.00001 and absf(model_stats.bounds[1][1]-.38)<.00001,"Actual marker waterline origin: -.05 to +.38m")
	check(absf(model_stats.size[0]-.45)<.00001 and absf(model_stats.size[2]-.45)<.00001,"Actual cage width .45m")
	for mesh in pond._trap_float.find_children("*","MeshInstance3D",true,false):
		check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Marker casts no shadow")
		var mat=mesh.get_active_material(0)
		check(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb and mat.roughness>=.85,"Matte linear vertex colour material")
		check(mat.albedo_texture==null,"Marker has no texture")
	var bobber=mesh_bounds(fishing._bobber)
	var cast_width=bobber.size[0]*fishing._bobber.scale.x
	check(absf(cast_width-.218383863842247)<.00001,"Native cast bobber measured vertex width .21838m at original 1.6 scale")
	report.comparison={"native_bobber":bobber,"bobber_scale":fishing._bobber.scale.x,"bobber_width_m":cast_width,
		"trap_buoy_width_m":.30,"width_ratio":.30/cast_width,"trap_origin":xyz(pond._trap_float.position),"cast_target":xyz(target),"player":xyz(pond.actor.position)}
	runtime.ui.root.visible=false
	await capture("bank_43deg_comparison")
	fishing.visible=false
	pond.cam.size=1.15;pond.cam.rotation_degrees=Vector3(-25,25,0)
	pond.cam.position=pond._trap_float.position+Vector3.UP*.17+pond.cam.basis.z*8
	vp.size=Vector2i(1200,1000);await capture("marker_closeup")
	vp.size=Vector2i(360,800);pond.cam.transform=default_transform;pond.cam.size=default_size
	fishing.visible=true
	for i in 3:await get_tree().process_frame
	runtime.ui.root.visible=true;pond._trap_frame(fixture)
	pond._trap_float.position.y=.055
	var mark=pond.cam.unproject_position(pond._trap_float.position+Vector3(0,.6,0))
	var prompt=pond.P0Trap.prompt(fixture,pond.p0_place())
	runtime.ui.name_bar(pond.TRAP_ID,P0Logic.icon(pond.TRAP_ID),prompt.text,prompt.fact,mark,true,-1,false,-1,mark)
	for i in 30:await get_tree().process_frame
	var bar=runtime.ui._name_bars.get(pond.TRAP_ID)
	check(bar!=null and bar.visible and bar.text=="Fish Trap" and bar.fact=="0/3" and bar.icon==P0Logic.icon(pond.TRAP_ID),"Native b1 trap icon/name strip visible with real prompt")
	# The requested overlay view isolates the native world prompt from unrelated fixture HUD controls.
	for node in runtime.ui.root.get_children():
		if node is CanvasItem and node!=runtime.ui._kit:node.visible=false
	for node in runtime.ui._kit.get_children():
		if node is CanvasItem and node!=bar:node.visible=false
	var bar_rect=bar.get_global_rect()
	report.prompt={"text":bar.text,"fact":bar.fact,"world_height_above_origin_m":.6,"screen": [mark.x,mark.y],
		"logical_viewport":[360,800],"bar_rect":[bar_rect.position.x,bar_rect.position.y,bar_rect.size.x,bar_rect.size.y],
		"source":"native P0Trap.prompt / P0Ui.name_bar"}
	await capture("native_icon_name_bar")
	var trap_rect=screen_rect(pond._trap_float)
	var projected=Rect2(trap_rect[0],trap_rect[1],trap_rect[2],trap_rect[3])
	report.prompt["model_bounds_overlap_px2"]=bar_rect.intersection(projected).get_area()
	# A separate, explicitly labelled integration proposal; retain the original .6m capture above.
	var proposed=pond.cam.unproject_position(pond._trap_float.position+Vector3(0,.9,0))
	runtime.ui.name_bar(pond.TRAP_ID,P0Logic.icon(pond.TRAP_ID),prompt.text,prompt.fact,proposed,true,-1,false,-1,proposed)
	for i in 12:await get_tree().process_frame
	var proposed_rect=bar.get_global_rect()
	report.prompt_proposal={"height_m":.9,"runtime_change_committed":false,
		"bar_rect":[proposed_rect.position.x,proposed_rect.position.y,proposed_rect.size.x,proposed_rect.size.y],
		"model_bounds_overlap_px2":proposed_rect.intersection(projected).get_area(),"gap_px":projected.position.y-proposed_rect.end.y}
	check(proposed_rect.intersection(projected).get_area()<.01,"Review-only .9m prompt proposal clears actual model vertex projection")
	await capture("prompt_height_proposal_090m")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Actual Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TRAP_VALIDATION ",report.passed)
	fishing.finish();pond.queue_free();runtime.queue_free();P0Runtime._instance=null
	await get_tree().process_frame;get_tree().quit(0 if report.passed else 1)
