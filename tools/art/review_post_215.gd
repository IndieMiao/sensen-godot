extends Node
const KIT="res://assets/rooms/post_office/"
var report={"checks":[],"assets":{},"captures":[],"sockets":{}}
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var heading:Label
var footer:Label
var output:String
var contract:Dictionary
var sun:DirectionalLight3D
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(p):return [p.x,p.y,p.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func pot(variant,at):
	var model=load("res://assets/props/stove_pot/stove_pot.glb").instantiate();world.add_child(model);model.position=at
	for child in model.get_children():child.visible=child.name==variant
	return model
func setup(layout,size):
	vp=SubViewport.new();vp.size=size;vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;get_tree().root.add_child(vp)
	world=Node3D.new();vp.add_child(world)
	var lighting=layout.get("review_lighting",{})
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(lighting.get("background","e9e7d4"))
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(lighting.get("ambient_color","fff0dc"));env.ambient_light_energy=lighting.get("ambient",.70)
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	sun=DirectionalLight3D.new();world.add_child(sun);sun.position=vec(lighting.get("sun_position",[-6,7,1.5]));sun.look_at(Vector3.ZERO)
	sun.light_color=Color(lighting.get("sun_color","ffe6c2"));sun.light_energy=lighting.get("sun",1.05);sun.shadow_enabled=true
	sun.shadow_bias=lighting.get("shadow_bias",.045);sun.shadow_normal_bias=lighting.get("shadow_normal_bias",.4)
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.directional_shadow_max_distance=lighting.get("shadow_distance",30);sun.light_angular_distance=1.4
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1 if lighting.is_empty() else .05;camera.far=70 if lighting.is_empty() else 4000
	camera.current=true;world.add_child(camera)
	var layer=CanvasLayer.new();vp.add_child(layer)
	heading=Label.new();heading.position=Vector2(12,16);heading.add_theme_font_size_override("font_size",13 if size.x==360 else 24);heading.add_theme_color_override("font_color",Color("394b42"));layer.add_child(heading)
	footer=Label.new();footer.position=Vector2(12,size.y-90);footer.add_theme_font_size_override("font_size",11 if size.x==360 else 18);footer.add_theme_color_override("font_color",Color("394b42"));layer.add_child(footer)
	for label in [heading,footer]:
		label.add_theme_color_override("font_outline_color",Color("fffdf4"));label.add_theme_constant_override("outline_size",4)
func pose(focus,size,pitch,yaw):
	camera.size=size;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*20
func capture(id):
	for i in 12:await RenderingServer.frame_post_draw
	var img=vp.get_texture().get_image();check(img.save_png(output+"/"+id+".png")==OK,"Saved "+id)
	report.captures.append({"id":id,"width":img.get_width(),"height":img.get_height(),"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y,"camera_size":camera.size,"camera_position":xyz(camera.position)})
	print("POST_REVIEW_CAPTURE ",id)
func shared_model(path,at,yaw=0.0):
	var model=load(path).instantiate();world.add_child(model);model.position=at;model.rotation_degrees.y=yaw
	var mat=StandardMaterial3D.new();mat.albedo_texture=load(KIT+"room_albedo_ao.png");mat.roughness=.8;mat.metallic_specular=.28
	for mesh in model.find_children("*","MeshInstance3D",true,false):mesh.material_override=mat
	return model
func avatar(at,slots={},scale_factor=1.0):
	var rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.position=at;rig.rotation_degrees.y=45;rig.scale=Vector3.ONE*scale_factor
	var config=Avatar.slot_table.default_config()
	for k in slots:config.slots[StringName(k)]=slots[k]
	rig.apply_config(config);var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"real avatar assembled");rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
	return rig
func lights(layout):
	for r in layout.get("review_lighting",{}).get("points",[]):
		var lamp=OmniLight3D.new();world.add_child(lamp);lamp.position=vec(r.position);lamp.light_color=Color(r.color);lamp.light_energy=r.energy;lamp.omni_range=r.range
func supplemental_213():
	var kit="res://assets/rooms/basic_room/"
	var layout=JSON.parse_string(FileAccess.get_file_as_string(kit+"layout.json"));var anchors=JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/rooms/farmhouse.anchors.json"));var at={}
	for a in anchors.anchors:at[a.name]=vec(a.position)
	setup(layout,Vector2i(360,800));var room=load("res://scenes/basic_room/basic_room_art.tscn").instantiate();world.add_child(room)
	for prop in anchors.props:
		var model=load(prop.scene).instantiate();room.add_child(model);model.position=vec(prop.position);model.rotation_degrees.y=prop.yaw_degrees
	var fire=OmniLight3D.new();world.add_child(fire);fire.position=vec(anchors.hearth_glow);fire.light_color=Color("ffb041");fire.light_energy=.7;fire.omni_range=1.1
	var big=pot("pot_big",at.use_stove_1)
	var off=vec(layout.camera.position)-vec(layout.camera.target);var yaw=rad_to_deg(atan2(off.x,off.z));pose(Vector3.ZERO,10.75,43,yaw)
	# Same art_span/frame_all and focus projection as pinned P0Room. At 360x800
	# the art horizontal span sets diorama size; all tap anchors are inside it.
	var right=camera.basis.x;var lo=INF;var hi=-INF
	for m in room.find_children("*","MeshInstance3D",true,false):
		if not m.is_visible_in_tree():continue
		var box=m.global_transform*m.get_aabb()
		for i in 8:
			var q=box.get_endpoint(i).dot(right);lo=minf(lo,q);hi=maxf(hi,q)
	var base=maxf(layout.camera.size,(hi-lo)/.9);var diorama=clampf((hi-lo)/.84,base*.8,base);var width=diorama*.42
	pose(at.cam_stove,width,43,yaw);var band_center=(98.0/800+.29)/2;var focus=at.cam_stove+camera.basis.y*(band_center-.5)*(width*800/360)
	pose(focus,width,43,yaw)
	heading.text="BASIC / STOVE 1 / BIG POT\ncam_stove / runtime push-in"
	footer.text="SGODOT-213 / LIU BEI\nfarm-dev f8c3391c / 360 x 800\nLatest stove + pot / exact anchor focus"
	check(at.use_stove_1.distance_to(Vector3(-2.5,.98,-2.495))<.000001,"213 current stove 1 socket")
	var screen=camera.unproject_position(at.cam_stove);check(abs(screen.y/800-band_center)<.00001,"cam_stove at runtime band center")
	report.supplement_213={"farm_commit":"f8c3391c8c0606ae664fb8e06ad85068aa199f69","cam_stove":xyz(at.cam_stove),"pot_bottom":xyz(big.position),"diorama_size":diorama,"focus_size":width,"focus_multiplier":.42,"band":[98.0/800,.29],"cam_stove_screen":[screen.x,screen.y]}
	await capture("SGODOT-213_KITCHEN_v1_cam_stove_big_pot_360")
	vp.size=Vector2i(1080,2400);heading.scale=Vector2.ONE*3;footer.scale=Vector2.ONE*3;heading.position*=3;footer.position*=3
	await capture("SGODOT-213_KITCHEN_v1_cam_stove_big_pot_3x")
	vp.free()
func imported_audit():
	var stats=JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"))
	for asset in stats.assets:
		var model=load(KIT+asset.name+".glb").instantiate();add_child(model);var tris=0;var surfaces=0;var box=AABB();var first=true
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			for si in mesh.mesh.get_surface_count():
				var data=mesh.mesh.surface_get_arrays(si);tris+=data[Mesh.ARRAY_INDEX].size()/3;surfaces+=1
				for v in data[Mesh.ARRAY_VERTEX]:
					var p=model.global_transform.affine_inverse()*mesh.global_transform*v
					if first:box=AABB(p,Vector3.ZERO);first=false
					else:box=box.expand(p)
		check(tris==asset.triangles,asset.name+" imported triangle count");check(surfaces==asset.surfaces,asset.name+" imported surface count")
		report.assets[asset.name]={"bounds":[xyz(box.position),xyz(box.end)],"size_xyz":xyz(box.size),"triangles":tris,"surfaces":surfaces};model.free()
	check(stats.scene_triangles<=200000 and stats.static_draw_surfaces<=60,"complete scene including plants meets budgets")
func physics_audit(room,layout):
	var body=CharacterBody3D.new();var capsule=CapsuleShape3D.new();capsule.radius=.21;capsule.height=1.745
	var cs=CollisionShape3D.new();cs.shape=capsule;cs.position.y=.8725;body.add_child(cs);world.add_child(body)
	await get_tree().physics_frame;await get_tree().physics_frame
	var paths=[["door to counter",Vector3(-2.6,.085,1.29),Vector3(-1.65,.085,.40)],["Pip approach",Vector3(-1.65,.085,.70),Vector3(-2.10,.085,1.20)],["Sam approach",Vector3(1.75,.085,.85),Vector3(2.45,.085,.85)],["central aisle",Vector3(-1.65,.085,.4),Vector3(1.75,.085,.4)]]
	for path in paths:
		body.position=path[1];var hit=body.move_and_collide(path[2]-path[1]);check(hit==null,path[0]+" actual player capsule clear")
		if hit:report[path[0]+"_blocked"]=str(hit.get_collider().get_path())
	for key in ["npc_pip","npc_sam","npc_keeper"]:
		var q=PhysicsShapeQueryParameters3D.new();q.shape=capsule;q.transform.origin=vec(layout.suggested_anchors[key].position)+Vector3(0,.878,0);q.exclude=[body.get_rid()]
		var hits=world.get_world_3d().direct_space_state.intersect_shape(q);check(hits.is_empty(),key+" stationary capsule clear")
	body.free()
func post_review():
	var layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	setup(layout,Vector2i(360,800));lights(layout)
	var room=load("res://scenes/post_office/post_office_art.tscn").instantiate();world.add_child(room)
	imported_audit();await physics_audit(room,layout)
	var actual_tris=0;var actual_surfaces=0
	for mesh in room.find_children("*","MeshInstance3D",true,false):
		for si in mesh.mesh.get_surface_count():actual_tris+=mesh.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX].size()/3;actual_surfaces+=1
	var stats=JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"))
	check(actual_tris==stats.scene_triangles,"actual placed triangles including plants match stats");check(actual_surfaces==stats.static_draw_surfaces,"actual placed surfaces including plants match stats")
	report.placed_scene={"triangles":actual_tris,"surfaces":actual_surfaces}
	var rig=await avatar(vec(layout.suggested_anchors.spawn.position))
	var off=vec(layout.camera.position)-vec(layout.camera.target);var yaw=rad_to_deg(atan2(off.x,off.z))
	pose(Vector3(-.50,1.35,.35),6.72,43,yaw)
	heading.text="POST / GAMEPLAY VIEW\n43 DEG / 6.72 M / 360 PX"
	footer.text="SGODOT-215 / LIU BEI\nPlayer at spawn / existing kit\nDesk moved left / approved"
	await capture("post_gameplay_43deg_360")
	pose(Vector3(-.25,1.65,.1),11.4,43,yaw)
	heading.text="POST / COMPLETE ROOM\n43 DEG / FULL DIORAMA";await capture("post_full_room_360")
	vp.size=Vector2i(1200,1000);heading.add_theme_font_size_override("font_size",24);footer.add_theme_font_size_override("font_size",18);footer.position=Vector2(12,915)
	await capture("post_full_room_panorama")
	rig.hide()
	var desk=room.get_node("packing_table");pose(desk.position+Vector3(0,1.10,0),3.6,43,yaw)
	heading.text="POST / STAMP DESK";footer.text="SGODOT-215 / LIU BEI\nSilver-white coffee pot / white cup / stamp + ink pad / blank open passport / plant";await capture("post_stamp_desk_detail")
	var npcs=JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/outpost_npcs.json")).npcs
	var actors={}
	for pair in [["res_pip","npc_pip"],["res_sam","npc_sam"],["sigrid","npc_keeper"]]:
		var n=npcs[pair[0]];var actor=await avatar(vec(layout.suggested_anchors[pair[1]].position),n.slots,n.scale);actors[pair[1]]=actor
	vp.size=Vector2i(360,800);heading.add_theme_font_size_override("font_size",13);footer.add_theme_font_size_override("font_size",11);footer.position=Vector2(12,720)
	pose(Vector3(-.50,1.35,.35),6.72,43,yaw)
	heading.text="POST / NPC POSITIONS\n43 DEG / 6.72 M / 360 PX";footer.text="SGODOT-215 / LIU BEI\nPip / Sam / Sigrid: actual NPC parts\nSuggestions only; runtime anchors unchanged"
	var pts={};var tagpts={}
	for key in actors:
		pts[key]=camera.unproject_position(actors[key].position)
		tagpts[key]=camera.unproject_position(actors[key].position+Vector3(0,2.32*actors[key].scale.y,0))
	pts.exit=camera.unproject_position(vec(layout.suggested_anchors.exit.position));tagpts.exit=camera.unproject_position(vec(layout.suggested_anchors.badge_exit.position))
	report.npc_screen_points={}
	for key in pts:report.npc_screen_points[key]={"feet":[pts[key].x,pts[key].y],"tag":[tagpts[key].x,tagpts[key].y]}
	report.npc_distances=[]
	var keys=pts.keys()
	for i in keys.size():
		for j in range(i+1,keys.size()):
			var a=keys[i];var b=keys[j];var dist=pts[a].distance_to(pts[b]);var tag_dist=tagpts[a].distance_to(tagpts[b])
			check(dist>=44 and tag_dist>=44,a+" / "+b+" >=44px both feet and tags");report.npc_distances.append({"a":a,"b":b,"feet_px":dist,"tag_px":tag_dist})
	for key in tagpts:
		var label=Label.new();heading.get_parent().add_child(label);label.text={"npc_pip":"Pip","npc_sam":"Sam","npc_keeper":"Sigrid","exit":"Exit"}[key];label.position=tagpts[key]+Vector2(-15,-12);label.add_theme_font_size_override("font_size",12);label.add_theme_color_override("font_color",Color("253e4a"));label.add_theme_color_override("font_outline_color",Color("fffdf4"));label.add_theme_constant_override("outline_size",4)
	await capture("post_npc_positions_360")
	report.suggested_anchors=layout.suggested_anchors
	# Separate annotated panorama keeps all four proposed positions visible.
	vp.size=Vector2i(1200,1000);heading.add_theme_font_size_override("font_size",24);footer.add_theme_font_size_override("font_size",18);footer.position=Vector2(12,915)
	pose(Vector3(-.25,1.65,.1),11.4,43,yaw)
	for child in heading.get_parent().get_children():
		if child is Label and child!=heading and child!=footer:child.hide()
	await capture("post_npc_positions_panorama")
	vp.free()
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	if "--post" in OS.get_cmdline_user_args():
		await post_review()
	else:
		await supplemental_213()
		setup({},Vector2i(1200,900))
		for name in ["compass_rug","stamp_desk_set","post_wall_lantern","post_table_lamp"]:
			var m=shared_model(KIT+name+".glb",Vector3.ZERO)
			pose(Vector3(0,.13,0),2.3 if name in ["compass_rug","stamp_desk_set"] else .95,60 if name=="compass_rug" else 30,20)
			heading.text="POST / "+name.replace("_"," ").to_upper();footer.text="SGODOT-215 / LIU BEI\nExisting 2048 atlas / no changed pixels"
			await capture("draft_"+name);m.free()
		vp.free()
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name();report.failures=report.checks.filter(func(c):return not c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("POST_215_GODOT_QA ",report.checks.size()," checks, ",report.failures.size()," failures");get_tree().quit(0 if report.failures.is_empty() else 1)
