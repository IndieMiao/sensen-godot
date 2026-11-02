extends Node
const MineArt=preload("res://modules/mining/mine_art.gd")
const MineCombat=preload("res://modules/mining/mine_combat.gd")
const MineCamera=preload("res://modules/farm/farm_camera.gd")
var identity:String
var spec:Dictionary
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var model:Node3D
var skeleton:Skeleton3D
var player:AnimationPlayer
var body:MeshInstance3D
var ground:MeshInstance3D
var environment:Environment
var sun:DirectionalLight3D
var output:String
var report={"checks":[],"animations":{},"captures":[]}

func _ready():run.call_deferred()
func xyz(p):return [p.x,p.y,p.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)

func setup():
	identity=ProjectSettings.get_setting("monster_review/identity")
	var path="res://assets/monsters/"+identity+"/"+identity
	spec=JSON.parse_string(FileAccess.get_file_as_string(path+".json"))
	vp=SubViewport.new();vp.size=Vector2i(480,480);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	world=Node3D.new();vp.add_child(world)
	environment=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("DCE4E2")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("F0F0F2")
	environment.ambient_light_energy=.65;environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var env=WorldEnvironment.new();env.environment=environment;world.add_child(env)
	sun=DirectionalLight3D.new();world.add_child(sun);sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_energy=.9;sun.light_color=Color("FFF6EA");sun.shadow_enabled=true;sun.shadow_opacity=.5
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1;camera.far=60;camera.current=true;world.add_child(camera)
	model=load(path+".glb").instantiate();world.add_child(model)
	var skels=model.find_children("*","Skeleton3D",true,false);var players=model.find_children("*","AnimationPlayer",true,false)
	check(skels.size()==1 and players.size()==1,"One Skeleton3D and AnimationPlayer imported")
	skeleton=skels[0];player=players[0]
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var meshes=model.find_children("*","MeshInstance3D",true,false)
	check(meshes.size()==1,"One skinned mesh")
	body=meshes[0]
	check(body.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Imported model disables real shadow casting")
	BlobShadow.attach(model,spec.radius*1.15)
	ground=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(8,8);ground.mesh=plane
	var mat=StandardMaterial3D.new();mat.albedo_color=Color("DCE4E2");mat.roughness=1
	ground.material_override=mat;ground.position.y=-.018;world.add_child(ground)
	for name in spec.anims:
		check(player.has_animation(name),"Required animation: "+name)
		if player.has_animation(name):
			var anim=player.get_animation(name)
			check(absf(anim.length-spec.anims[name].length)<.001,name+": exact JSON duration")
			anim.loop_mode=Animation.LOOP_LINEAR if spec.anims[name].get("loop",false) else Animation.LOOP_NONE
			check(anim.get_track_count()>0,name+": imported animation tracks")

func pose_camera(yaw=0.,pitch=0.,width=1.65,focus=Vector3(0,.76,0)):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*12

func points():
	skeleton.force_update_all_bone_transforms()
	var mesh=body.bake_mesh_from_current_skeleton_pose();var result=PackedVector3Array()
	for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		result.append(model.global_transform.affine_inverse()*body.global_transform*vertex)
	return result

func bounds(p):
	var lo=Vector3.INF;var hi=-Vector3.INF
	for point in p:lo=lo.min(point);hi=hi.max(point)
	return [xyz(lo),xyz(hi)]

func seek(name,time):
	player.stop();skeleton.reset_bone_poses();player.play(name);player.seek(time,true);player.advance(0)
	await get_tree().process_frame
	skeleton.force_update_all_bone_transforms()

func geometry():
	player.stop();skeleton.reset_bone_poses();await get_tree().process_frame
	var actual=bounds(points());var arrays=body.mesh.surface_get_arrays(0)
	check(body.mesh.get_surface_count()==1,"Single surface")
	check(arrays[Mesh.ARRAY_INDEX].size()/3==spec.triangles and spec.triangles<=1500,"Measured triangles <=1500")
	check(skeleton.get_bone_count()==spec.bones and spec.bones<=16,"Measured bones <=16")
	check(skeleton.find_bone("root")>=0,"Root bone named root")
	check(arrays[Mesh.ARRAY_TEX_UV2].size()==arrays[Mesh.ARRAY_VERTEX].size(),"UV2 tint mask survives import")
	check(arrays[Mesh.ARRAY_COLOR].size()==arrays[Mesh.ARRAY_VERTEX].size(),"Vertex colour survives import")
	check(body.skin!=null and body.skeleton!=NodePath(""),"Skinned mesh bound to skeleton")
	var mat=body.get_active_material(0)
	check(mat is StandardMaterial3D and mat.vertex_color_use_as_albedo and mat.albedo_texture==null,"Vertex paint material, no textures")
	check(model.transform.is_equal_approx(Transform3D.IDENTITY),"Unit root transform at ground origin")
	check(absf(actual[1][1]-spec.height)<.001,"Actual rest height matches JSON")
	if identity=="mob_cave_bat":
		check(absf(actual[1][0]-actual[0][0]-1)<.001,"One metre rest wingspan")
		var at=skeleton.global_transform*skeleton.get_bone_global_rest(skeleton.find_bone("body")).origin
		check(absf(at.y-1.0)<.001,"Hover body centre in rest at Y=1.0")
	elif identity=="mob_shroomling":
		check(absf(actual[1][0]-actual[0][0]-.60)<.001,"Shroom cap diameter .60m")
		check(absf(actual[0][1])<.0001 and absf(actual[1][1]-.70)<.01,"Shroom rests on ground and height about .70m including cap spots")
	var config=ConfigFile.new();config.load("res://assets/monsters/"+identity+"/"+identity+".glb.import")
	check(str(config.get_value("remap","uid","")).begins_with("uid://"),"Godot-generated import UID")
	report.geometry={"rest_bounds":actual,"triangles":spec.triangles,"bones":skeleton.get_bone_count(),
		"height":spec.height,"surface_count":body.mesh.get_surface_count(),"uid":config.get_value("remap","uid","")}

func motions():
	for name in spec.anims:
		var initial=PackedVector3Array();var maximum=0.;var frames=[];var root_id=skeleton.find_bone("root")
		var root_origin=skeleton.get_bone_global_rest(root_id).origin
		for i in range(9):
			var time=spec.anims[name].length*i/9.;await seek(name,time);var p=points()
			if i==0:initial=p
			else:
				for j in p.size():maximum=maxf(maximum,p[j].distance_to(initial[j]))
			check(skeleton.get_bone_global_pose(root_id).origin.distance_to(root_origin)<.00001,name+": no root translation at sample "+str(i))
			frames.append({"time":time,"bounds":bounds(p)})
		check(maximum>.004,name+": actual skinned vertices move")
		report.animations[name]={"length":spec.anims[name].length,"loop":spec.anims[name].get("loop",false),
			"max_vertex_displacement_m":maximum,"samples":frames}

func capture(name):
	for i in 5:await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image();check(image.save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"id":name,"pixels":[vp.size.x,vp.size.y],"width_m":camera.size,
		"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y})
	print("MONSTER_CAPTURE ",name)

func mine_context():
	ground.visible=false;var mine=MineArt.floor_scenery(1,false);world.add_child(mine)
	environment.background_color=Color("242125");environment.ambient_light_color=Color("e8dfea");environment.ambient_light_energy=.48
	sun.rotation_degrees=Vector3(-51,-38,0);sun.light_color=Color("ffe8ce");sun.light_energy=1.15;sun.shadow_opacity=.58
	sun.shadow_bias=.04;sun.shadow_normal_bias=.45;sun.shadow_blur=1.6
	var combat=MineCombat.new();var slime=combat._slime({"radius":.4},false);world.add_child(slime);combat.free()
	slime.position=Vector3(5.4,0,-3.1)
	for name in ["HealthFill","HealthTrack","Health"]:slime.get_node(name).visible=false
	model.position=Vector3(4.2,0,-3.1);await seek("idle",.125)
	var avatar=Avatar.create_rig()
	for child in avatar.get_children():
		if child is RigActivity:child.free()
	avatar.assembler=AvatarAssemblerMerged.new();world.add_child(avatar);avatar.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while avatar.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not avatar.is_busy(),"Actual reference player assembled")
	avatar.play_motion("idle");var anim=avatar.get_node("AnimationPlayer");anim.seek(.3,true);anim.pause()
	var lo=INF;var hi=-INF
	for node in avatar.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		var mesh=node.bake_mesh_from_current_skeleton_pose() if node.skin!=null else node.mesh
		if mesh==null:continue
		for i in mesh.get_surface_count():
			for vertex in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				var p=avatar.global_transform.affine_inverse()*node.global_transform*vertex;lo=minf(lo,p.y);hi=maxf(hi,p.y)
	avatar.scale=Vector3.ONE*1.745/(hi-lo);avatar.position=Vector3(3.0,-lo*avatar.scale.y,-3.1);avatar.rotation_degrees.y=180
	vp.size=Vector2i(360,800);camera.size=MineCamera.close_view_size(Vector2(360,800))/.8
	MineCamera.place(camera,Vector3(4.2,.7,-3.1));await capture("mine_default_43deg")
	report.mine={"source":"Unmodified farm-dev mine_art.gd and mine_combat.gd slime", "floor":1,
		"player_height_m":1.745,"slime_radius_m":.4,"camera_zoom":.8,"width_m":camera.size}

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	setup()
	if "--context-only" in OS.get_cmdline_user_args():
		report=JSON.parse_string(FileAccess.get_file_as_string(output+"/godot-validation.json"))
	else:
		await geometry()
		player.stop();skeleton.reset_bone_poses();await get_tree().process_frame
		for view in [["front",0],["side",90],["back",180]]:
			if identity=="mob_shroomling":pose_camera(view[1],0,1.05,Vector3(0,.37,0))
			else:pose_camera(view[1])
			await capture(view[0])
		await motions()
		for name in spec.anims:
			var time=spec.anims[name].get("hit_at",spec.anims[name].get("emit_at",spec.anims[name].length*.5))
			if name in ["idle","move","fly_high"]:time=spec.anims[name].length*.125
			if name=="die":time=spec.anims[name].length*.85
			await seek(name,time)
			if identity=="mob_shroomling":pose_camera(20,18,1.15,Vector3(0,.35,0))
			else:pose_camera(20,18,1.75,Vector3(0,.70,0))
			await capture("action_"+name)
	await mine_context()
	check(report.has("mine") and FileAccess.file_exists(output+"/mine_default_43deg.png"),"Mine comparison completed")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Actual Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	var f=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t")+"\n");f.close()
	print("MONSTER_VALIDATION ",identity," ",report.passed)
	vp.queue_free();await get_tree().process_frame;await get_tree().process_frame
	get_tree().quit(0 if report.passed else 1)
