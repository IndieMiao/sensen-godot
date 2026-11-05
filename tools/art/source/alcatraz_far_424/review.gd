extends Node
const KIT="res://assets/landmarks/alcatraz_island/"
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var assets:Node3D
var rig
var output:String
var report={"checks":[],"captures":[],"imported":{}}
func _ready():run.call_deferred()
func check(ok,name):
	report.checks.append({"check":name,"passed":bool(ok)})
	if not ok:push_error(name)
func setup():
	vp=SubViewport.new();vp.size=Vector2i(1400,1200);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	world=Node3D.new();vp.add_child(world);assets=Node3D.new();world.add_child(assets)
	var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color("DCE9EA");e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color("DAE6ED");e.ambient_light_energy=.72
	var we=WorldEnvironment.new();we.environment=e;world.add_child(we)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-56,-34,0);sun.light_color=Color(1,.965,.88);sun.light_energy=.98;sun.shadow_enabled=true;sun.shadow_opacity=.45;world.add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.current=true;camera.far=200;world.add_child(camera)
	var floor=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(100,100);floor.mesh=plane;var m=StandardMaterial3D.new();m.albedo_color=Color("C9CCBD");m.roughness=.95;floor.material_override=m;floor.position.y=-.012;world.add_child(floor)
func add(name,at):
	var n=load(KIT+name+".glb").instantiate();n.name=name;n.position=at;assets.add_child(n)
	return n
func caption(text,at):
	var n=Label3D.new();n.text=text;n.font_size=42;n.pixel_size=.012;n.position=at;n.billboard=BaseMaterial3D.BILLBOARD_ENABLED;n.no_depth_test=true;n.modulate=Color("314D55");assets.add_child(n)
func pose(width,focus,pitch=20.,yaw=15.):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*50
func capture(name):
	for i in 6:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"id":name,"size":[vp.size.x,vp.size.y],"camera_width_m":camera.size});print("ALC_CAPTURE ",name)
func clear_assets():
	for c in assets.get_children():c.free()
func avatar():
	rig=Avatar.create_rig()
	for n in rig.get_children():
		if n is RigActivity:n.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Default player assembled")
	rig.play_motion("idle");var anim=rig.get_node("AnimationPlayer");anim.seek(.3,true);anim.pause()
	var low=INF;var high=-INF
	for n in rig.find_children("*","MeshInstance3D",true,false):
		if n.mesh==null or not n.is_visible_in_tree():continue
		var m=n.bake_mesh_from_current_skeleton_pose() if n.skin!=null else n.mesh
		for s in m.get_surface_count():
			for v in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p=rig.global_transform.affine_inverse()*n.global_transform*v;low=minf(low,p.y);high=maxf(high,p.y)
	rig.scale=Vector3.ONE*1.75/(high-low);rig.position.y=-low*rig.scale.y;rig.rotation_degrees.y=180
	report.player={"height_m":1.75,"source_height":high-low}
func geometry():
	var m=JSON.parse_string(FileAccess.get_file_as_string(KIT+"alc_far_manifest.json"));var total=0
	for name in m.assets:
		var n=add(name,Vector3.ZERO);var tri=0;var surfaces=0
		for mesh in n.find_children("*","MeshInstance3D",true,false):
			for s in mesh.mesh.get_surface_count():
				tri+=mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3;surfaces+=1
				var mat=mesh.mesh.surface_get_material(s)
				check(mat is StandardMaterial3D and mat.vertex_color_use_as_albedo and mat.albedo_texture==null,name+" imported vertex colour / no texture")
		check(tri==m.assets[name].triangles and surfaces==1,name+" actual triangle count / single surface")
		report.imported[name]={"triangles":tri,"surfaces":surfaces};total+=tri;n.free()
	check(total<=40000,"All seven assets combined <=40000 triangles")
	for n in ["alc_lighthouse","alc_watertower"]:
		var ratio=float(report.imported[n+"_far"].triangles)/report.imported[n].triangles
		check(ratio>=.18 and ratio<=.30,n+" far triangles approximately one quarter")
	report.total_triangles=total
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output);setup();geometry();await avatar()
	for spec in [["lighthouse","alc_lighthouse",15.0],["watertower","alc_watertower",12.0]]:
		clear_assets();add(spec[1],Vector3(-4.2,0,0));add(spec[1]+"_far",Vector3(4.2,0,0))
		caption("NEAR / %.0f m"%spec[2],Vector3(-4.2,-.7,0));caption("FAR / %.0f m"%spec[2],Vector3(4.2,-.7,0))
		rig.position.x=0;rig.position.z=2;pose(21.5,Vector3(0,spec[2]*.44,0),12,0)
		await capture(spec[0]+"_lod_scale")
	clear_assets();add("alc_lighthouse",Vector3(-4.5,0,0));add("alc_watertower",Vector3(4.5,0,0));rig.position.x=0;rig.position.z=2
	pose(21.5,Vector3(0,6.6,0),18,18);await capture("towers_player_175")
	clear_assets();rig.visible=false
	add("alc_far_hills",Vector3(0,0,-.4));add("alc_far_skyline",Vector3(3.5,0,0));add("alc_far_goldengate",Vector3(-7,0,.4))
	pose(23,Vector3(0,1.5,0),8,0);vp.size=Vector2i(1500,650);await capture("scenic_cards")
	report.passed=report.checks.all(func(c):return c.passed);report.renderer=RenderingServer.get_current_rendering_method()
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("ALC_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
