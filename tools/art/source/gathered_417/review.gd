extends Node
const Art=preload("res://modules/farm/farm_art.gd")
const Old=preload("res://old_art.gd")
const NAMES=["grove","rock_pile","reed_bank","clay_pit","herb_patch","hardwood_grove","flax_patch"]
var vp:SubViewport
var pond
var runtime
var out:String
var stats:Dictionary
var originals:Dictionary
var fixture={"energy":{"value":200,"cap":200},"coins":250,"bag":{"slots":[],"free":20},"fishing":{"cast_energy":5},"travel":{"here":"san_francisco"}}
var report={"checks":[],"captures":[],"assets":{},"pixel_widths":{},"intercepted_requests":[]}
func _ready():run.call_deferred()
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func xyz(p):return [p.x,p.y,p.z]
func meshes(node):
	var found=node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D:found.push_front(node)
	return found
func bounds(node):
	var lo=Vector3.INF;var hi=-Vector3.INF;var tri=0;var surfaces=0
	for m in meshes(node):
		for s in m.mesh.get_surface_count():
			surfaces+=1;var a=m.mesh.surface_get_arrays(s)
			tri+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3
			for v in a[Mesh.ARRAY_VERTEX]:
				var p=node.global_transform.affine_inverse()*m.global_transform*v;lo=lo.min(p);hi=hi.max(p)
	return {"bounds":[xyz(lo),xyz(hi)],"triangles":tri,"surfaces":surfaces,"dimensions_xyz":xyz(hi-lo)}
func original(name,at):
	return Old.build("spot_"+name,at) if name in ["grove","rock_pile","herb_patch"] else Art.instance(name,at)
func screen_rect(node):
	var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
	for m in meshes(node):
		for s in m.mesh.get_surface_count():
			for v in m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p=pond.cam.unproject_position(m.to_global(v));lo=lo.min(p);hi=hi.max(p)
	return [lo.x,lo.y,hi.x-lo.x,hi.y-lo.y]
func patch_rect(name,node):
	var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
	for v in stats[name].visibility_vertices:
		var p=pond.cam.unproject_position(node.to_global(Vector3(v[0],v[1],v[2])));lo=lo.min(p);hi=hi.max(p)
	return [lo.x,lo.y,hi.x-lo.x,hi.y-lo.y]
func load_pond(id):
	if is_instance_valid(pond):pond.queue_free();await get_tree().process_frame;await get_tree().process_frame
	pond=load("res://review_pond.gd").new();pond.setup({"pond_id":id});vp.add_child(pond)
	for i in 20:await get_tree().process_frame
	var ticks=0
	while pond.actor.rig.is_busy() and ticks<600:await get_tree().process_frame;ticks+=1
	check(not pond.actor.rig.is_busy(),id+": native player assembled")
	runtime.ui.set_view(fixture)
	runtime.ui.set_action({"icon":"hand","verb":"Gather","sub":"3 Energy","enabled":true,"amber":false,"cmd":{},"need":3})
	for i in 20:await get_tree().process_frame
	pond._update_camera()
func capture(name,ready=null,gathered=null):
	for i in 10:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(out+"/"+name+".png")==OK,"Saved "+name)
	var c={"name":name,"pixels":[vp.size.x,vp.size.y],"camera":str(pond.cam.global_transform),"width_m":pond.cam.size,
		"pitch_degrees":pond.cam.rotation_degrees.x,"zoom":pond._zoom,"player":xyz(pond.actor.position)}
	if ready!=null:c["ready_screen_rect"]=screen_rect(ready)
	if gathered!=null:c["gathered_screen_rect"]=screen_rect(gathered)
	report.captures.append(c);print("GATHERED_CAPTURE ",name)
func validate(name,node):
	var m=bounds(node);report.assets[name]=m;var old=originals[name].bounds
	check(m.triangles<=600 and m.surfaces==1,name+": <=600 triangles / one surface")
	check(m.triangles==int(stats[name].triangles),name+": imported triangle count matches delivered GLB")
	check(m.bounds[0][0]>=old[0][0]-.00001 and m.bounds[1][0]<=old[1][0]+.00001 and m.bounds[0][2]>=old[0][2]-.00001 and m.bounds[1][2]<=old[1][2]+.00001,name+": contained in original X/Z bounds")
	check(m.bounds[1][1]<old[1][1],name+": lower than original")
	check(node.scale==Vector3.ONE,name+": unit scale")
	check(node.mesh.get_surface_count()==1 and node.get_active_material(0)==Art.material(),name+": shared farm vertex material")
	check(node.find_children("*","Skeleton3D",true,false).is_empty() and node.find_children("*","AnimationPlayer",true,false).is_empty(),name+": no rig/animation")
func run():
	out=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(out)
	stats=JSON.parse_string(FileAccess.get_file_as_string("res://asset_stats.json"));originals=JSON.parse_string(FileAccess.get_file_as_string("res://original_metrics.json"))
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	runtime=P0Runtime.new();P0Runtime._instance=runtime
	runtime.session.transport=func(method,path,_body,meta):report.intercepted_requests.append({"method":method,"path":path,"type":meta.get("type","")})
	vp.add_child(runtime);runtime.set_process(false);runtime.session.set_process(false)
	await load_pond("pond_san_francisco_03")
	runtime.ui.root.visible=false
	pond.cam.size=6.72;pond.cam.position=Vector3(6,.8,12)+pond.cam.basis.z*40
	for name in NAMES:
		var ready=original(name,Vector3(4.45,0,12));var gathered=Art.instance(name+"_gathered",Vector3(7.55,0,12))
		pond.add_child(ready);pond.add_child(gathered);validate(name,gathered)
		await capture("pair_"+name,ready,gathered)
		ready.queue_free();gathered.queue_free();await get_tree().process_frame
	# Native follow-camera state at the unchanged L1 stand; a ready L2 and a cooling L1.
	runtime.ui.root.visible=true;pond.actor.teleport(Vector3(.88,0,-6.62))
	pond._opening=false;pond._parked=false;pond._zoom=1;pond._cam_follow.held=false;pond.p0_recenter();pond._follow(.016)
	check(absf(pond.cam.size-6.72)<.0001 and absf(pond.cam.rotation_degrees.x+43)<.001,"Native following camera zoom 1, width 6.72m, pitch 43 degrees")
	for name in NAMES:
		var ready=original(name,Vector3(-.3,0,-9));var gathered=Art.instance(name+"_gathered",Vector3(-.3,0,-6.6))
		var icons={"grove":"wood","rock_pile":"stone","reed_bank":"reed","clay_pit":"clay","herb_patch":"herb","hardwood_grove":"hardwood","flax_patch":"flax"}
		runtime.ui.set_action({"icon":icons[name],"verb":"Gather","sub":"Ready in 3h 12m","enabled":false,"amber":false,"cmd":{},"need":0})
		pond.add_child(ready);pond.add_child(gathered);pond._follow(.016)
		var patch=patch_rect(name,gathered);var whole=screen_rect(gathered)
		report.pixel_widths[name]={"patch_screen_rect":patch,"patch_width_px":patch[2],"whole_screen_rect":whole,
			"patch_parts":stats[name].visibility_parts,"gathered_position":xyz(gathered.position),"ready_position":xyz(ready.position)}
		check(patch[2]>=20,name+": actual ground/flat-stone patch >=20px at follow zoom 1")
		check(whole[0]>=0 and whole[0]+whole[2]<=360 and whole[1]>=0 and whole[1]+whole[3]<=800,name+": full gathered mesh in frame")
		await capture("follow_"+name,ready,gathered)
		ready.queue_free();gathered.queue_free();await get_tree().process_frame
	await load_pond("pond_san_francisco_01")
	pond.actor.teleport(Vector3(6.88,0,-1.38));pond._opening=false;pond._parked=false;pond._zoom=1;pond._cam_follow.held=false;pond.p0_recenter();pond._follow(.016)
	var point=Node3D.new();point.position=Vector3(7.6,0,-1.4);pond.add_child(point)
	var ready=original("clay_pit",Vector3.ZERO);var gathered=Art.instance("clay_pit_gathered");point.add_child(ready);point.add_child(gathered)
	gathered.visible=false
	var anchor=point.position+Vector3(0,float(originals.clay_pit.bounds[1][1])+.35,0)
	var mark=pond.cam.unproject_position(anchor);var hit=pond.cam.unproject_position(point.position+Vector3(0,.18,0))
	runtime.ui.name_bar("clay_review",P0Logic.icon("clay"),"Clay Pit","",mark,true,-1,false,-1,hit)
	for i in 12:await get_tree().process_frame
	var before=runtime.ui._card_hits["clay_review"]
	ready.visible=false;gathered.visible=true
	runtime.ui.name_bar("clay_review",P0Logic.icon("clay"),"Clay Pit","Ready in 3h 12m",mark,true,-1,true,-1,hit)
	runtime.ui.set_action({"icon":"clay","verb":"Gather","sub":"Ready in 3h 12m","enabled":false,"amber":false,"cmd":{},"need":0})
	for i in 20:await get_tree().process_frame
	var bar=runtime.ui._name_bars["clay_review"]
	check(ready.transform==gathered.transform and ready.position==Vector3.ZERO,"Visible-state swap preserves resource-point model transform")
	check(runtime.ui._card_hits["clay_review"]==before,"Native name-bar hit anchor unchanged during cooldown swap")
	check(bar.dimmed and bar.fact=="Ready in 3h 12m" and bar.visible,"Native name bar dimmed with cooldown fact")
	check(is_equal_approx(bar._glyph.modulate.a,.45),"Native Dimmed icon opacity .45")
	report.cooldown={"fixture":true,"full_cooldown_seconds":14400,"remaining_seconds":11520,"text":bar.text,"fact":bar.fact,"dimmed":bar.dimmed,
		"resource_origin":xyz(point.position),"stand":xyz(pond.actor.position),"unchanged_anchor_world":xyz(anchor),"unchanged_hit_screen":[hit.x,hit.y]}
	await capture("pond_cooldown",null,gathered)
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Godot Mobile renderer")
	check(report.intercepted_requests.all(func(r):return r.type=="telemetry" or r.method==HTTPClient.METHOD_GET),"Only offline startup reads/telemetry intercepted, no gameplay requests")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(out+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("GATHERED_VERIFY ",report.passed," ",report.checks.size()," checks");get_tree().quit(0 if report.passed else 1)
