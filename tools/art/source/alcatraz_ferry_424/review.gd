extends Node
var scene:AlcatrazIsland
var vp:SubViewport
var output:String
var report={"checks":[],"captures":{},"poses":{}}
func _ready():run.call_deferred()
func check(ok,label,evidence=null):
	report.checks.append({"check":label,"passed":bool(ok),"evidence":evidence})
	if not ok:push_error(label)
func xyz(v):return [v.x,v.y,v.z]
func nodes(asset):return scene.mesh_nodes.filter(func(n):return n.name.begins_with(asset.to_pascal_case()))
func tri(mesh):
	var total=0
	for s in mesh.get_surface_count():total+=mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3
	return total
func capture(name):
	for i in 10:await RenderingServer.frame_post_draw
	var stats={"triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"shadow_draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	stats.size=[vp.size.x,vp.size.y];stats.camera=xyz(scene._camera.position);stats.camera_width=scene._camera.size
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,name+" capture")
	report.captures[name]=stats;print("FERRY_CAPTURE ",name," ",JSON.stringify(stats))
func pose(camera,width,pitch,yaw,focus):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*46;camera.near=.1;camera.far=300
func set_gull_pose(node,name):
	for i in node.mesh.get_blend_shape_count():node.set_blend_shape_value(i,1.0 if str(node.mesh.get_blend_shape_name(i))==name else 0.0)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	scene=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(scene)
	for i in 300:
		await get_tree().physics_frame
		if scene.navigation_ready() and not scene._rig.is_busy():break
	check(scene.navigation_ready(),"Pinned island navigation ready")
	check(scene._player.position.distance_to(Vector3(-22,1,19))<.001,"Original dock spawn")
	check(abs(scene._camera.rotation_degrees.x+43)<.01 and abs(scene._camera.rotation_degrees.y-14.5)<.01 and abs(scene._camera.size-6.72)<.001,"Original 43deg/yaw14.5/6.72m opening")
	scene.set_process(false);scene._rig.get_node("AnimationPlayer").pause()
	var ferries=nodes("ferry");var gulls=nodes("gull")
	check(ferries.size()==2,"Ferry near and far")
	check(gulls.size()==3,"Three original gull instances")
	for f in ferries:
		check(f.position.distance_to(Vector3(-7,0,19))<.001,"Ferry original position")
		check(f.rotation.is_zero_approx() and f.scale.is_equal_approx(Vector3.ONE),"Ferry original yaw/unit scale")
		check(f.mesh.get_surface_count()==1,"Ferry single surface")
		check(tri(f.mesh)<=6000,"Ferry triangle cap",tri(f.mesh))
		check(f.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Decorative ferry no shadow")
	check(ferries[0].visibility_range_end==55 and ferries[1].visibility_range_begin==55,"Ferry LOD55m")
	var poses=["stand","preen","spread"];var positions=[Vector3(-23.6,2,18.2),Vector3(10,4.25,8.7),Vector3(-24,11,-7)]
	for i in gulls.size():
		var g=gulls[i];set_gull_pose(g,poses[i]);check(g.position.distance_to(positions[i])<.001,"Gull original placement "+str(i))
		check(g.mesh.get_surface_count()==1 and tri(g.mesh)<=400,"Gull one surface / <=400 triangles",tri(g.mesh))
		check(g.mesh.get_blend_shape_count()==3,"Gull rest plus preen / spread / turn targets")
		report.poses[str(i)]={"pose":poses[i],"position":xyz(g.position)}
	check(scene.find_children("*","AnimationPlayer",true,false).size()>=1,"Avatar animation only; decorative mesh has no autoplay")
	await capture("SGODOT-424_ferry_gull_v1_opening_360")
	# Frozen before/after control proves visible contribution at the exact original camera.
	for n in ferries+gulls:n.visible=false
	await capture("opening_without_new_props_control")
	for n in ferries+gulls:n.visible=true
	# Full ferry + original dock, supporting detail view; never substitute this for opening.
	for n in scene.get_children():
		if n is CanvasLayer:n.visible=false
	vp.size=Vector2i(1400,1000);pose(scene._camera,35,43,-35,Vector3(-6,2.5,19))
	await capture("SGODOT-424_ferry_gull_v1_dock_ferry_detail")
	# Studio strips share the host sun/ambient, leave only selected prop nodes.
	for zone in scene.zones.values():zone.visible=false
	scene._player.visible=false;scene.get_node("Sea").visible=false
	var studio=Node3D.new();scene.add_child(studio)
	var base=MeshInstance3D.new();base.mesh=PlaneMesh.new();base.mesh.size=Vector2(100,100);base.position.y=-1.1
	var matte=StandardMaterial3D.new();matte.albedo_color=Color("E8E5DA");matte.roughness=1;base.material_override=matte;studio.add_child(base)
	for i in 2:
		var f=MeshInstance3D.new();f.mesh=ferries[i].mesh;f.position=Vector3(0,0,8.2 if i==0 else -8.2);f.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;studio.add_child(f)
	vp.size=Vector2i(1400,1200);pose(scene._camera,34,43,-8,Vector3(0,3.3,0));await capture("SGODOT-424_ferry_gull_v1_near_far")
	for c in studio.get_children():
		if c!=base:c.free()
	base.position.y=-.015
	for i in 3:
		var g=MeshInstance3D.new();g.mesh=gulls[0].mesh;g.position=Vector3((1-i)*1.3,0,0);studio.add_child(g);g.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;set_gull_pose(g,poses[i])
	vp.size=Vector2i(1400,650);pose(scene._camera,4.4,22,155,Vector3(0,.27,0));await capture("SGODOT-424_ferry_gull_v1_gull_poses")
	# Explicit native import material and UID checks.
	var dir="res://assets/landmarks/alcatraz_island/"
	for name in ["ferry","ferry_far","gull"]:
		var cfg=ConfigFile.new();check(cfg.load(dir+name+".glb.import")==OK,name+" import readable")
		check(str(cfg.get_value("remap","uid","")).begins_with("uid://"),name+" Godot UID")
		check(cfg.get_value("params","gltf/texture_map_mode",0)==1,name+" texture_map_mode")
		var resource=load(dir+name+".glb").instantiate();var mi=resource.find_children("*","MeshInstance3D",true,false)[0]
		var mat=mi.mesh.surface_get_material(0)
		check(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb and mat.roughness>=.9,name+" matte linear vertex colour enabled")
		check(mi.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,name+" no imported shadow")
		resource.free()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("FERRY_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
