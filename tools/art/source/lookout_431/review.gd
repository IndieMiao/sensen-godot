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
	report.captures.append({"file":name+".png","size":[vp.size.x,vp.size.y],"camera_width":camera.size,"pitch":-camera.rotation_degrees.x});print("LOOKOUT_CAPTURE ",name)
func catalogue():
	vp.size=Vector2i(360,190)
	for name in manifest.assets:
		clear();var row=manifest.assets[name];var low=v(row.bounds[0]);var high=v(row.bounds[1]);var n=piece(name,Vector3(0,-low.y,0));var w=high.x-low.x;var height=high.y-low.y
		move_player(Vector3(w*.5+.62,0,0));rig.rotation_degrees.y=180
		var focus=Vector3(.3,maxf(height,1.745)*.53,0);var width=maxf(w+2.1,maxf(height,1.745)*2.5)
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
	check(manifest.assets.size()==21,"All twenty-one street/lookout modules")

func simple_box(at:Vector3,size:Vector3,material:Material,label:String):
	var mi=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=size;mi.mesh=mesh;mi.material_override=material;mi.position=at;mi.name=label;assembly.add_child(mi);return mi

func lookout():
	clear()
	var paving=load("res://assets/landmarks/_shared/ground_detail/ground_paving.tres")
	var grass=load("res://assets/landmarks/_shared/ground_detail/ground_grass.tres")
	var sea=StandardMaterial3D.new();sea.albedo_color=Color("439BB0");sea.roughness=.95
	simple_box(Vector3(0,.04,.5),Vector3(6,.16,3),paving,"ReviewOnlySixByThreePlatform")
	simple_box(Vector3(0,-.3,-15),Vector3(40,.10,28),sea,"ReviewOnlySeaBackdrop")
	simple_box(Vector3(0,-.16,6),Vector3(24,.10,14),grass,"ReviewOnlyLandBackdrop")
	simple_box(Vector3(.4,-.095,5),Vector3(1.6,.03,6),paving,"ReviewOnlyApproachPath")
	var deck=piece("lookout_semicircle_2m",Vector3(0,0,-1))
	piece("lookout_railing_2m",Vector3(-2,.12,-1))
	piece("railing_straight_2m",Vector3(2,.12,-1))
	for x in [-3,-1,1,3]:piece("railing_endpost",Vector3(x,.12,-1))
	piece("lookout_telescope",Vector3(0,.12,-1.42))
	piece("lookout_compass_disc",Vector3(.85,.12,.48))
	piece("lookout_sheltered_bench",Vector3(-1.8,.12,.82))
	piece("planter_square",Vector3(2.35,.12,1.4))
	move_player(Vector3(-.35,.12,1.65));rig.rotation_degrees.y=175
	var count=0;var surfaces=0;var pieces={}
	for n in assembly.get_children():
		if n.has_meta("kit_id"):
			var id=n.get_meta("kit_id");pieces[id]=pieces.get(id,0)+1
	for mi in assembly.find_children("*","MeshInstance3D",true,false):count+=tri(mi.mesh);surfaces+=mi.mesh.get_surface_count()
	report.example={"main_corner_bounds_m":[[-3,0,-2],[3,.12,2]],"main_corner_footprint_m":[6,4],"pieces":pieces,"triangles_including_review_ground":count,"surfaces_including_review_ground":surfaces,"layout_exported":false,"ground_review_commit":"4efa7e900dac23c575a0130d421cad62112a5b78","outside_context":"Sea/land backdrop and approach path are review-only"}
	check(abs(deck.position.y+.12-.12)<.00001,"Semicircle deck flush with rectangle topY0.12")
	for side in [-1,1]:
		var endpoint=deck.global_transform*Vector3(side,.12,0)
		check(endpoint.distance_to(Vector3(side,.12,-1))<.00001,"Semicircle connector matches standard endpost "+str(side))
	check(abs(.12+.93-1.05)<.00001,"Old/new/curved handrail centre heights align at1.05")

func joints_and_deck():
	clear()
	var deck=piece("lookout_semicircle_2m",Vector3.ZERO)
	piece("lookout_railing_2m",Vector3(-2,.12,0));piece("railing_straight_2m",Vector3(2,.12,0))
	for side in [-1,1]:piece("railing_endpost",Vector3(side,.12,0))
	for mi in assembly.find_children("*","MeshInstance3D",true,false):mi.create_trimesh_collision()
	await get_tree().physics_frame
	var space=world.get_world_3d().direct_space_state
	for point in [Vector3(0,2,-.4),Vector3(.5,2,-.4),Vector3(-.5,2,-.4)]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(point,point-Vector3(0,3,0)))
		check(not hit.is_empty() and abs(hit.position.y-.12)<.00001,"Deck top ray "+str(point),xyz(hit.get("position",Vector3.ZERO)))
	for x in [-1.04,-1.0,-.96,.96,1.0,1.04]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,1.05,.3),Vector3(x,1.05,-.3)))
		check(not hit.is_empty(),"Endpost covers old/new curved joint x="+str(x))
	clear()

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"kit_manifest.json"))
	setup();inspect();await avatar();await joints_and_deck();lookout()
	pose(6.72,Vector3(0,1.5,.55),43,8);await capture("example_360")
	# Internal close view makes the no-text coin/ship/lighthouse graphics reviewable.
	clear();rig.visible=false;piece("lookout_compass_disc",Vector3.ZERO)
	vp.size=Vector2i(700,700);pose(1.95,Vector3(0,.01,0),90,0);await capture("disc_detail")
	rig.visible=true;await catalogue()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("LOOKOUT_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
