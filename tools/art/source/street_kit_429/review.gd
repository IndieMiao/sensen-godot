extends Node
const KIT="res://assets/landmarks/_shared/street_kit/"
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var assembly:Node3D
var rig
var env:Environment
var output:String
var manifest:Dictionary
var report={"checks":[],"captures":[],"catalog":{}}
func _ready():run.call_deferred()
func xyz(v):return [v.x,v.y,v.z]
func v(a):return Vector3(a[0],a[1],a[2])
func check(ok,label,evidence=null):
	report.checks.append({"check":label,"passed":bool(ok),"evidence":evidence})
	if not ok:push_error(label)
func setup():
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	world=Node3D.new();vp.add_child(world);assembly=Node3D.new();world.add_child(assembly)
	env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("DDE8E7");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("FFF0DC");env.ambient_light_energy=.65
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.light_color=Color("FFF1D8");sun.light_energy=1.0;sun.shadow_enabled=true;sun.shadow_opacity=.50;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.shadow_bias=.05;sun.shadow_normal_bias=.25;world.add_child(sun)
	camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.near=.1;camera.far=120;world.add_child(camera)
func pose(width:float,focus:Vector3,pitch=43.0,yaw=45.0):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*42
func piece(name:String,at:Vector3,yaw=0.0):
	var n=load(KIT+name+".glb").instantiate();n.name=name+"_"+str(assembly.get_child_count());assembly.add_child(n);n.position=at;n.rotation_degrees.y=yaw;n.set_meta("kit_id",name)
	return n
func clear():
	for n in assembly.get_children():n.free()
func tri(mesh):
	var total=0
	for s in mesh.get_surface_count():total+=mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3
	return total
func avatar():
	rig=Avatar.create_rig()
	for c in rig.get_children():
		if c is RigActivity:c.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	for i in 900:
		if not rig.is_busy():break
		await get_tree().process_frame
	check(not rig.is_busy(),"Default avatar assembled")
	rig.play_motion("idle");var player=rig.get_node("AnimationPlayer");player.seek(.3,true);player.pause()
	var lo=INF;var hi=-INF
	for mi in rig.find_children("*","MeshInstance3D",true,false):
		if not mi.is_visible_in_tree() or mi.mesh==null:continue
		var mesh=mi.bake_mesh_from_current_skeleton_pose() if mi.skin!=null else mi.mesh
		for s in mesh.get_surface_count():
			for p in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var q=rig.global_transform.affine_inverse()*mi.global_transform*p;lo=minf(lo,q.y);hi=maxf(hi,q.y)
	rig.scale=Vector3.ONE*1.745/(hi-lo);rig.set_meta("floor_lift",-lo*rig.scale.y);rig.rotation_degrees.y=200
	report.avatar={"height_m":1.745,"source_height_m":hi-lo}
func move_player(at:Vector3):rig.position=at+Vector3.UP*float(rig.get_meta("floor_lift",0))
func capture(name:String):
	for i in 6:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"file":name+".png","size":[vp.size.x,vp.size.y],"camera_width":camera.size,"pitch":-camera.rotation_degrees.x});print("STREET_CAPTURE ",name)
func catalogue():
	vp.size=Vector2i(360,250)
	for name in manifest.assets:
		clear();var row=manifest.assets[name];var low=v(row.bounds[0]);var high=v(row.bounds[1]);var n=piece(name,Vector3(0,-low.y,0));var w=high.x-low.x;var height=high.y-low.y
		move_player(Vector3(w*.5+.62,0,0));rig.rotation_degrees.y=180
		var focus=Vector3(.3,maxf(height,1.745)*.48,0);var width=maxf(w+2.1,maxf(height,1.745)*1.85)
		pose(width,focus,24,22);await capture("catalog_"+name)
		report.catalog[name]={"bounds":row.bounds,"triangles":row.triangles,"avatar_height":1.745,"pose_lift_m":-low.y}

func inspect():
	for name in manifest.assets:
		var n=piece(name,Vector3.ZERO);var meshes=n.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==1,name+" one mesh")
		var total=0;var surfaces=0
		for mi in meshes:
			total+=tri(mi.mesh);surfaces+=mi.mesh.get_surface_count()
			var mat=mi.mesh.surface_get_material(0)
			check(mat is StandardMaterial3D and mat.vertex_color_use_as_albedo,name+" matte vertex material")
			check(mat.albedo_texture==null and mat.roughness>=.88,name+" no texture; roughness")
		check(total==manifest.assets[name].triangles and total<=800,name+" triangle budget",total)
		check(surfaces==1,name+" single surface")
		n.free()
	check(manifest.assets.size()==16,"All sixteen requested modules")

func simple_box(at:Vector3,size:Vector3,material:Material,label:String):
	var mi=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=size;mi.mesh=mesh;mi.material_override=material;mi.position=at;mi.name=label;assembly.add_child(mi);return mi

func plaza():
	clear()
	var paving=load("res://assets/landmarks/_shared/ground_detail/ground_paving.tres")
	var grass=load("res://assets/landmarks/_shared/ground_detail/ground_grass.tres")
	check(paving is ShaderMaterial and int(paving.get_shader_parameter("finish_kind"))==2,"Pinned #830 paving material loaded")
	simple_box(Vector3(0,-.09,0),Vector3(6,.18,12),paving,"ReviewOnly12x6PavedPad")
	simple_box(Vector3(0,-.25,0),Vector3(36,.12,36),grass,"ReviewOnlyBackgroundGround")
	# Two-metre rail interfaces: corner arm1 + straight2 + corner arm1 = 4m.
	piece("railing_corner",Vector3(-2,0,-5))
	piece("railing_corner",Vector3(2,0,-5),-90)
	piece("railing_straight_2m",Vector3(0,0,-5))
	for x in [-1,1]:piece("railing_endpost",Vector3(x,0,-5))
	piece("railing_straight_2m",Vector3(-2,0,-3),90)
	piece("railing_endpost",Vector3(-2,0,-2))
	piece("railing_endpost",Vector3(2,0,-4))
	piece("lamp_double",Vector3(-2.45,0,-4.7))
	piece("lamp_single",Vector3(2.45,0,.3))
	piece("bench_wood",Vector3(-1.7,0,-.7),90)
	piece("bench_stone",Vector3(-1.7,0,2.0),90)
	piece("planter_long",Vector3(0,0,-4.45))
	piece("planter_square",Vector3(-1.9,0,4.3))
	piece("litter_bin",Vector3(-2.35,0,.65))
	piece("sign_standing",Vector3(1.95,0,4.8),-15)
	piece("bicycle_rack",Vector3(1.65,0,2.6),90)
	piece("umbrella_table",Vector3(1.0,0,-2.4))
	piece("drinking_fountain",Vector3(1.55,0,.4))
	for x in [-2.3,-.95,.95,2.3]:piece("bollard",Vector3(x,0,5.65))
	var stone=StandardMaterial3D.new();stone.albedo_color=Color("D9C4A3");stone.roughness=.95
	simple_box(Vector3(1.8,1.15,-5.7),Vector3(1.5,2.3,.20),stone,"ReviewOnlyWallSignMount")
	piece("sign_wall",Vector3(1.8,1.55,-5.59))
	move_player(Vector3(-.1,0,3.9));rig.rotation_degrees.y=185
	var count=0;var surfaces=0;var pieces={}
	for n in assembly.get_children():
		if n.has_meta("kit_id"):
			var id=n.get_meta("kit_id");pieces[id]=pieces.get(id,0)+1
	for mi in assembly.find_children("*","MeshInstance3D",true,false):count+=tri(mi.mesh);surfaces+=mi.mesh.get_surface_count()
	report.example={"paved_footprint_m":[6,12],"kit_pieces":pieces,"triangles_including_review_ground_and_mount":count,"surfaces_including_review_ground_and_mount":surfaces,"game_layout_exported":false,"ground_review_commit":"54b76f78f78eff3f992365c934586e170bd15fb1","ground_path":"assets/landmarks/_shared/ground_detail/ground_paving.tres"}
	check(pieces.size()==16,"Example uses every furniture module")

func joins():
	clear()
	var a=piece("railing_corner",Vector3(-2,0,0))
	var b=piece("railing_straight_2m",Vector3.ZERO)
	var c=piece("railing_corner",Vector3(2,0,0),-90)
	check((a.global_transform*Vector3(1,0,0)).distance_to(b.global_transform*Vector3(-1,0,0))<.00001,"Left corner/straight endpoint coincident")
	check((c.global_transform*Vector3(0,0,1)).distance_to(b.global_transform*Vector3(1,0,0))<.00001,"Right corner/straight endpoint coincident")
	clear()

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"kit_manifest.json"))
	setup();inspect();await avatar();joins();plaza()
	pose(6.72,Vector3(0,1.8,.4),43,8);await capture("example_360")
	vp.size=Vector2i(1400,1100);pose(15.8,Vector3(0,.8,0),43,28);await capture("example_overview")
	await catalogue()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("STREET_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
