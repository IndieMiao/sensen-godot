extends Node
const AlcatrazIsland = preload("res://scenes/landmark/alcatraz_island.gd")
const KIT="res://assets/landmarks/alcatraz_island/"
var scene:AlcatrazIsland
var vp:SubViewport
var extras=[]
var gulls=[]
var ferry:Node3D
var players=[]
var phases=[]
var output:String
var report={"checks":[],"motion":{},"phase_offsets":[]}
func _ready():run.call_deferred()
func check(ok,label,evidence=null):
	report.checks.append({"check":label,"passed":bool(ok),"evidence":evidence})
	if not ok:push_error(label)
func xyz(v):return [v.x,v.y,v.z]
func first_mesh(n):return n.find_children("*","MeshInstance3D",true,false)[0]
func snap(view:SubViewport,path:String):
	assert(view.get_texture().get_image().save_png(output+"/"+path)==OK)
func close_view(size:Vector2i,focus:Vector3,width:float,pitch:float,yaw:float,distance=5.0):
	var view=SubViewport.new();view.size=size;view.world_3d=vp.find_world_3d();view.msaa_3d=Viewport.MSAA_4X;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.current=true;cam.size=width;cam.near=.05;cam.far=220;view.add_child(cam)
	cam.rotation_degrees=Vector3(-pitch,yaw,0);cam.position=focus+cam.basis.z*distance
	return view
func validate_resource(root:Node3D,length:float):
	check(root.get_script()==null,root.name+" has no runtime root script")
	check(root.find_children("*","Camera3D",true,false).is_empty() and root.find_children("*","Light3D",true,false).is_empty() and root.find_children("*","CollisionObject3D",true,false).is_empty(),root.name+" no camera/lights/collision")
	var ap=root.get_node("AnimationPlayer");check(ap.autoplay.is_empty() and not ap.is_playing(),root.name+" no autoplay")
	var a=ap.get_animation("idle");check(abs(a.length-length)<.0001 and a.loop_mode==Animation.LOOP_LINEAR,root.name+" idle length and seamless loop",a.length)
	var track_paths=[]
	for i in a.get_track_count():
		var path=String(a.track_get_path(i));track_paths.append(path)
		check(not path.begins_with(".:") and not path.begins_with(":") and not path.contains("Model:position"),root.name+" track does not move root: "+path)
	report[root.name+"_tracks"]=track_paths
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	for dir in ["opening_frames","gull0_frames","gull1_frames","gull2_frames","ferry_frames"]:DirAccess.make_dir_recursive_absolute(output+"/"+dir)
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	scene=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(scene)
	for i in 300:
		await get_tree().physics_frame
		if scene.navigation_ready() and not scene._rig.is_busy():break
	check(scene.navigation_ready(),"Original island navigation ready")
	scene.set_process(false);scene._rig.get_node("AnimationPlayer").pause()
	check(scene._player.position.is_equal_approx(Vector3(-22,1,19)),"Original player spawn")
	check(abs(scene._camera.size-6.72)<.001 and abs(scene._camera.rotation_degrees.x+43)<.01 and abs(scene._camera.rotation_degrees.y-14.5)<.01,"Original opening 43/yaw14.5/6.72m")
	for mi in scene.mesh_nodes:
		if mi.name.begins_with("Gull") or mi.name.begins_with("Ferry"):mi.visible=false
	var rng=RandomNumberGenerator.new();rng.seed=424202611
	var points=[Vector3(-23.6,2,18.2),Vector3(10,4.25,8.7),Vector3(-24,11,-7)]
	for i in 3:
		var g=load(KIT+"gull.tscn").instantiate();g.name="Gull"+str(i);scene.add_child(g);g.position=points[i];gulls.append(g);validate_resource(g,8.5)
		check(g.find_children("*","MeshInstance3D",true,false).size()==1,"Gull "+str(i)+" single independent mesh instance")
		var ap=g.get_node("AnimationPlayer");players.append(ap);var phase=(float(i)+rng.randf_range(.1,.9))*8.5/3.0;phases.append(phase)
		report.phase_offsets.append(phase)
		ap.play("idle");ap.pause();ap.seek(phase,true)
		extras.append(close_view(Vector2i(280,240),g.position+Vector3(0,.29,0),1.7,23,-90 if i==2 else 155))
	ferry=load(KIT+"ferry.tscn").instantiate();ferry.name="Ferry";scene.add_child(ferry);ferry.position=Vector3(-7,0,19);validate_resource(ferry,4.0)
	var ferry_ap=ferry.get_node("AnimationPlayer");ferry_ap.play("idle");ferry_ap.pause();ferry_ap.seek(0,true)
	check(ferry.find_children("*","MeshInstance3D",true,false).size()==3,"Ferry references exactly near, far and flag meshes")
	check(ferry.get_node("BodyRig/Near/ferry").visibility_range_end==55 and ferry.get_node("BodyRig/Far/ferry_far").visibility_range_begin==55,"Ferry retains shared 55m LOD")
	extras.append(close_view(Vector2i(840,470),Vector3(-7,3.2,19),32,30,-35,46))
	# Independent full-period samples: roots fixed, endpoints identical, quiet duty cycle.
	var quiet=0;var count=256;var root_drift=0.0;var max_weight=0.0;var overlap=0;var min_bob=INF;var max_bob=-INF
	for i in count:
		var t=float(i)/30;players[0].seek(t,true)
		var mi=first_mesh(gulls[0]);var weights=[]
		for j in mi.mesh.get_blend_shape_count():weights.append(mi.get_blend_shape_value(j))
		if weights.all(func(w):return abs(w)<.001):quiet+=1
		for w in weights:max_weight=maxf(max_weight,w)
		if weights.filter(func(w):return w>.001).size()>1:overlap+=1
		root_drift=maxf(root_drift,gulls[0].position.distance_to(points[0]))
	for i in 121:
		ferry_ap.seek(float(i)/30,true);var y=ferry.get_node("BodyRig").position.y;min_bob=minf(min_bob,y);max_bob=maxf(max_bob,y)
		root_drift=maxf(root_drift,ferry.position.distance_to(Vector3(-7,0,19)))
	check(root_drift<.000001,"All animation roots remain at placement",root_drift)
	check(float(quiet)/count>.60,"Gull mostly motionless",float(quiet)/count)
	check(overlap==0 and max_weight<=1.00001,"Turn / preen / flap separated; weights bounded")
	check(abs(min_bob+.02)<.00001 and abs(max_bob-.02)<.00001,"Ferry child moves only +/-2cm",[min_bob,max_bob])
	check(phases[0]!=phases[1] and phases[1]!=phases[2],"Three caller-supplied random start offsets")
	for root in gulls+[ferry]:
		var ap=root.get_node("AnimationPlayer");var a=ap.get_animation("idle")
		for track in a.get_track_count():
			var first=a.track_get_key_value(track,0);var last=a.track_get_key_value(track,a.track_get_key_count(track)-1)
			check(is_equal_approx(first,last) if first is float else first.is_equal_approx(last),root.name+" loop endpoint equal "+str(track))
	report.motion={"gull_idle_s":8.5,"quiet_fraction":float(quiet)/count,"ferry_period_s":4,"ferry_min_y":min_bob,"ferry_max_y":max_bob,"root_drift":root_drift}
	for i in 8:await RenderingServer.frame_post_draw
	var bridge_start:Image
	var peak_tri=0;var peak_draw=0
	for frame in 180:
		var t=float(frame)/30
		for i in 3:players[i].seek(fmod(t+phases[i],8.5),true)
		ferry_ap.seek(fmod(t,4),true)
		await get_tree().process_frame;await RenderingServer.frame_post_draw
		snap(vp,"opening_frames/%04d.png"%frame)
		for i in 3:snap(extras[i],"gull%d_frames/%04d.png"%[i,frame])
		snap(extras[3],"ferry_frames/%04d.png"%frame)
		peak_tri=maxi(peak_tri,vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		peak_draw=maxi(peak_draw,vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)+vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		if frame==0:
			bridge_start=vp.get_texture().get_image().get_region(Rect2i(0,55,120,90))
			for j in extras.size():
				var visible=extras[j].get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
				check(visible>0,"Supplementary viewport "+str(j)+" renders scene geometry",visible)
		if frame%30==0:print("ANIM_FRAME ",frame)
	var bridge_end=vp.get_texture().get_image().get_region(Rect2i(0,55,120,90))
	check(bridge_start.get_data()==bridge_end.get_data(),"Opening bridge area unchanged through motion")
	check(peak_tri<=80000 and peak_draw<=60,"Opening visible budgets",[peak_tri,peak_draw])
	report.video={"frames":180,"fps":30,"duration_s":6,"method":"Godot deterministic animation sampling; camera/time scale unchanged, encoded at 30fps; not a GPU throughput measurement","peak_opening_triangles":peak_tri,"peak_opening_draws_including_shadows":peak_draw}
	for spec in [["stand",0.0],["turn_head",1.65],["preen",4.0],["spread",6.48]]:
		players[0].seek(spec[1],true)
		for i in 3:await RenderingServer.frame_post_draw
		snap(extras[0],"pose_"+spec[0]+".png")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n");print("ANIM_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
