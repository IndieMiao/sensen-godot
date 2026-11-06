extends Node
const KIT="res://assets/rooms/_shared/church_kit/"
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
func piece(name:String,at:Vector3,yaw=0.0,palette=""):
	var n=load(KIT+name+".glb").instantiate();n.name=name+"_"+str(assembly.get_child_count());assembly.add_child(n);n.position=at;n.rotation_degrees.y=yaw;n.set_meta("kit_id",name)
	if palette!="":
		for mi in n.find_children("*","MeshInstance3D",true,false):mi.material_override=load(KIT+"glass_palette_"+palette+".tres")
	return n
func clear():
	for n in assembly.get_children():n.free()
func tri(mesh):
	var total=0
	for s in mesh.get_surface_count():total+=mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3
	return total
func inspect():
	for name in manifest.assets:
		var n=piece(name,Vector3.ZERO);var meshes=n.find_children("*","MeshInstance3D",true,false);var count=0;var surfaces=0
		check(meshes.size()==1,name+" one mesh")
		for mi in meshes:
			count+=tri(mi.mesh);surfaces+=mi.mesh.get_surface_count()
			var mat=mi.mesh.surface_get_material(0);var kind=manifest.assets[name].material
			check(mat is ShaderMaterial if kind=="glass" else mat is StandardMaterial3D,name+" material family")
			if kind=="glass":check(mat.get_shader_parameter("palette_texture").get_size()==Vector2(8,1),name+" 8-cell palette resource")
			elif kind=="atlas":
				check(mat.albedo_texture.get_size()==Vector2(2048,2048),name+" shared poi_church atlas")
				check(mat.albedo_texture.resource_path=="res://assets/rooms/poi_church/room_albedo_ao.png",name+" atlas dependency path")
			else:check(mat.vertex_color_use_as_albedo,name+" opaque vertex colour enabled")
		check(count==manifest.assets[name].triangles and surfaces==1,name+" measured count/surface",[count,surfaces])
		n.free()
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
	report.captures.append({"file":name+".png","size":[vp.size.x,vp.size.y],"camera_width":camera.size,"pitch":-camera.rotation_degrees.x});print("KIT_CAPTURE ",name)
func sample_chapel():
	clear()
	# Eight-metre square floor. Review fixture only: no layout, anchors, navigation,
	# service data or runtime scene is exported from these placements.
	for x in [-3,-1,1,3]:
		for z in [-3,-1,1,3]:piece("floor_tile_2m",Vector3(x,-.12,z))
	piece("grass_surround",Vector3(0,.55,0))
	piece("wall_corner_2m",Vector3(-4,0,-4))
	piece("wall_corner_2m",Vector3(4,0,-4),-90)
	piece("wall_corner_2m",Vector3(-4,0,4),90)
	for x in [-2,0,2]:
		piece("wall_rose_2m" if x==0 else "wall_pointed_2m",Vector3(x,0,-4))
		if x!=0:piece("pointed_glass",Vector3(x,0,-4),0,"meadow")
	for z in [-2,0,2]:
		piece("wall_door_2m" if z==0 else "wall_pointed_2m",Vector3(-4,0,z),90)
		if z!=0:piece("pointed_glass",Vector3(-4,0,z),90,"meadow")
	piece("rose_frame",Vector3(0,3.25,-4));piece("rose_glass",Vector3(0,3.25,-4),0,"meadow")
	for q in [-3,-1,1,3]:
		piece("roof_band_2m",Vector3(q,4.8,-4));piece("roof_band_2m",Vector3(-4,4.8,q),90)
		piece("beam_2m",Vector3(q,6.8,-1.1))
	for x in [-1.95,1.95]:
		for z in [-.25,1.60]:piece("wood_pew",Vector3(x,0,z))
	piece("steps_2m",Vector3(0,0,-2.75));piece("altar_table",Vector3(0,.54,-3.05))
	piece("pipe_organ",Vector3(-3.25,0,-2.6),90)
	for x in [-1.55,1.55]:piece("flower_pedestal",Vector3(x,0,-2.75))
	piece("iron_chandelier",Vector3(0,5.0,-1.1))
	var lamp=OmniLight3D.new();lamp.position=Vector3(0,5.15,-1.1);lamp.light_color=Color("FFDC9C");lamp.light_energy=.65;lamp.omni_range=4;lamp.shadow_enabled=false;assembly.add_child(lamp)
	move_player(Vector3(0,0,2.2));rig.rotation_degrees.y=180
	var count=0;var surfaces=0;var pieces={}
	for n in assembly.get_children():
		if n.has_meta("kit_id"):var id=n.get_meta("kit_id");pieces[id]=pieces.get(id,0)+1
	for mi in assembly.find_children("*","MeshInstance3D",true,false):count+=tri(mi.mesh);surfaces+=mi.mesh.get_surface_count()
	report.example={"floor_footprint_m":[8,8],"triangles":count,"surfaces":surfaces,"pieces":pieces,"pews":4,"maze":false,"game_layout_exported":false,"palette":"meadow","centre_aisle_m":3.9-(manifest.assets.wood_pew.bounds[1][0]-manifest.assets.wood_pew.bounds[0][0])}
	check(count<=200000 and surfaces<=60,"Example fits room budget",[count,surfaces])
func catalogue():
	vp.size=Vector2i(360,220)
	for name in manifest.assets:
		clear();var row=manifest.assets[name];var low=v(row.bounds[0]);var high=v(row.bounds[1]);var n=piece(name,Vector3(0,-low.y,0));var w=high.x-low.x;var height=high.y-low.y
		move_player(Vector3(w*.5+.62,0,0));rig.rotation_degrees.y=180
		var focus=Vector3(.3,maxf(height,1.745)*.48,0);var width=maxf(w+2.1,maxf(height,1.745)*1.85)
		pose(width,focus,17,18);await capture("catalog_"+name)
		report.catalog[name]={"bounds":row.bounds,"triangles":row.triangles,"avatar_height":1.745,"pose_lift_m":-low.y}
func joins_and_openings():
	clear()
	var nodes=[piece("wall_straight_2m",Vector3.ZERO),piece("wall_pointed_2m",Vector3(2,0,0)),piece("wall_corner_2m",Vector3(4,0,0),-90),piece("wall_rose_2m",Vector3(8,0,0)),piece("wall_door_2m",Vector3(10,0,0))]
	for n in nodes:
		for mi in n.find_children("*","MeshInstance3D",true,false):mi.create_trimesh_collision()
	await get_tree().physics_frame
	var space=world.get_world_3d().direct_space_state
	for x in [.9999,1.0,1.0001]:
		for y in [.05,.30,1.0,2.0,4.5,4.75]:
			var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,y,2),Vector3(x,y,-2)))
			check(not hit.is_empty(),"Straight/window seam closed x="+str(x)+" y="+str(y))
	# Corner bend4/yaw-90 has an endpoint at x3, exactly meeting the window end.
	for x in [2.9999,3.0,3.0001]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,2,2),Vector3(x,2,-2)))
		check(not hit.is_empty(),"Corner joint closed x="+str(x))
	for point in [Vector3(2,2,2),Vector3(2,3.8,2),Vector3(8,3.25,2)]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(point,point-Vector3(0,0,4)))
		check(hit.is_empty(),"True window aperture "+str(point))
	for x in [8.9999,9.0,9.0001]:
		for y in [.05,1.5,2.7,4.7]:
			var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,y,2),Vector3(x,y,-2)))
			check(not hit.is_empty(),"Door/window seam closed x="+str(x)+" y="+str(y))
	# Through the masonry thickness, the opening is empty at the rear of the
	# recessed wood leaves; beside/above it the limestone piers/lintel close it.
	for point in [Vector3(9.31,.05,-.05),Vector3(10.69,2.55,-.05)]:
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(point,point-Vector3(0,0,.3))).is_empty(),"Door opening clear behind wooden leaf "+str(point))
	for point in [Vector3(9.29,1.5,-.05),Vector3(10.71,1.5,-.05),Vector3(10,2.61,-.05)]:
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(point-Vector3(0,0,.3),point)).is_empty(),"Door opening bounded by masonry "+str(point))
	clear()
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output);manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"kit_manifest.json"))
	setup();inspect();await avatar();await joins_and_openings();sample_chapel();pose(6.72,Vector3(-.70,1.30,-.30));await capture("example_360")
	vp.size=Vector2i(1400,1200);pose(15,Vector3(0,2.4,0));await capture("example_overview")
	clear();piece("wall_door_2m",Vector3.ZERO);move_player(Vector3(1.48,0,.35));rig.rotation_degrees.y=180
	vp.size=Vector2i(720,1000);pose(4.1,Vector3(.4,2.25,0),12,15);await capture("door_front")
	# Single shader parameter changes the whole glass set; all opaque pieces stay.
	clear();move_player(Vector3(2.2,0,0));piece("wall_pointed_2m",Vector3(-1.2,0,0));var a=piece("pointed_glass",Vector3(-1.2,0,0),0,"classic");piece("wall_pointed_2m",Vector3(1.2,0,0));piece("pointed_glass",Vector3(1.2,0,0),0,"meadow")
	rig.visible=false;vp.size=Vector2i(1000,900);pose(6.0,Vector3(0,2.4,0),7,0);await capture("palette_swap")
	rig.visible=true;await catalogue()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n");print("KIT_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
