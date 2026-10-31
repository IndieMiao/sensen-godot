extends Node
## Actual Vulkan Mobile art review, full-height capsule routes and existing sit pose.
const KIT="res://assets/rooms/tea_house/"
var vp: SubViewport
var world: Node3D
var camera: Camera3D
var room: Node3D
var rig
var overlay: Node3D
var output: String
var standing_transform: Transform3D
var report={"checks":[],"captures":[],"routes":[],"colour_points":{},"plant_controls":[]}

func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func mat(color):
	var m=StandardMaterial3D.new();m.albedo_color=Color(color);m.roughness=.85;return m

func setup():
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp);world=Node3D.new();vp.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("DDE8E7")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.54
	env.ambient_light_color=Color("F1EBDD");env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=Vector3(-6,7,2);sun.look_at(Vector3.ZERO)
	sun.light_color=Color("FFF1D8");sun.light_energy=1.05;sun.shadow_enabled=true;sun.shadow_opacity=.55
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.shadow_bias=.05;sun.shadow_normal_bias=.30
	camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.near=.1;camera.far=50;world.add_child(camera)
	room=load("res://scenes/tea_house/tea_house_art.tscn").instantiate();world.add_child(room)
	overlay=Node3D.new();world.add_child(overlay)
	for anchor in room.layout.anchors:
		if anchor.name.begins_with("seat_") or anchor.name.begins_with("npc_") or anchor.name=="spawn":
			var label=Label3D.new();label.text=anchor.name;label.font_size=28;label.pixel_size=.0032
			label.position=vec(anchor.position)+Vector3(0,.10,0);label.rotation_degrees.x=-90;label.no_depth_test=true;overlay.add_child(label)
	for point in room.layout.preflight.standing_positions_xz:
		var node=MeshInstance3D.new();var mesh=CylinderMesh.new();mesh.top_radius=.25;mesh.bottom_radius=.25;mesh.height=.018
		node.mesh=mesh;node.material_override=mat("81C8C0");node.position=Vector3(point[0],.10,point[1]);overlay.add_child(node)
	overlay.visible=false

func geometry():
	var tris=0;var surfaces=0
	for node in room.find_children("*","MeshInstance3D",true,false):
		for i in node.mesh.get_surface_count():
			surfaces+=1;tris+=node.mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX].size()/3
			var original=node.mesh.surface_get_material(i)
			check(original is StandardMaterial3D and original.albedo_texture!=null,"Imported mesh retains external texture material: "+str(node.get_path()))
	var stats=JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"))
	check(tris==stats.scene_triangles and tris<=200000,"Actual placed imported triangles and budget")
	check(surfaces==stats.static_draw_surfaces and surfaces<=60,"Actual placed imported surfaces and budget")
	check(stats.plant_triangles<=100000,"Plant budget <=100k triangles")
	check(room.materials.opaque.albedo_texture.get_size()==Vector2(2048,2048),"One 2048x2048 atlas")
	for spec in room.layout.assets:
		var config=ConfigFile.new();check(config.load(KIT+spec.file+".import")==OK,spec.name+": actual import config")
		check(str(config.get_value("remap","uid","")).begins_with("uid://"),spec.name+": import UID")
		check(config.get_value("params","gltf/texture_map_mode",0)==1,spec.name+": texture_map_mode=1")
		if spec.vegetation or spec.name=="window_backdrop":
			for mesh in room.get_node(spec.name).find_children("*","MeshInstance3D",true,false):
				check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,spec.name+": no leaf/backdrop shadows")
	var seats=room.layout.anchors.filter(func(a):return a.name.begins_with("seat_"))
	check(seats.size()==12,"Twelve delivered seating anchors")
	for seat in seats:
		check(absf(seat.position[1]-.795)<.00001 and room.has_node(NodePath(seat.module)),seat.name+": real surface Y and module")
		if seat.name.begins_with("seat_table"):
			var number=str(seat.name).trim_prefix("seat_table").split("_")[0]
			var table=room.get_node("tea_table_"+number);var delta=table.position-vec(seat.position);delta.y=0
			check((-room.get_node(seat.name).basis.z).dot(delta.normalized())>.999,seat.name+": yaw faces the tea table")
	check(room.get_node("sign_name").get_meta("size")==[1.04,.26],"Blank door sign carries runtime text size")
	check(room.find_children("*","OmniLight3D",true,false).size()==3,"Exactly three local lantern lights")
	report.imported={"triangles":tris,"surfaces":surfaces,"plant_triangles":stats.plant_triangles,
		"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}

func pose(width,pitch=43.,yaw=45.,focus=Vector3(.10,1.1,.4)):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*22
func query(point,radius=.25):
	var shape=CapsuleShape3D.new();shape.radius=radius;shape.height=1.745
	var query=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.margin=.002
	query.transform.origin=point+Vector3.UP*.8725;return query
func routes():
	await get_tree().physics_frame;var space=world.get_world_3d().direct_space_state
	for group in [[room.layout.preflight.routes,.25],[room.layout.preflight.main_routes,.35]]:
		for route in group[0]:
			var failures=[];var path=route.points_xz
			for i in range(path.size()-1):
				var a=Vector3(path[i][0],.085,path[i][1]);var b=Vector3(path[i+1][0],.085,path[i+1][1]);var q=query(a,group[1]);q.motion=b-a
				if not space.intersect_shape(query(a,group[1]),1).is_empty() or space.cast_motion(q)[0]<.9999:failures.append(i)
			check(failures.is_empty(),route.name+": final art capsule radius "+str(group[1])+" route")
			report.routes.append({"name":route.name,"radius":group[1],"failed_segments":failures,"segments":path.size()-1})
	for point in room.layout.preflight.standing_positions_xz:
		check(space.intersect_shape(query(Vector3(point[0],.085,point[1])),1).is_empty(),"Standing point clear in final art "+str(point))

func avatar():
	rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Reference avatar assembled")
	rig.play_motion("idle");var animation=rig.get_node("AnimationPlayer");animation.seek(.3,true);animation.pause()
	var low=INF;var high=-INF
	for node in rig.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		var mesh=node.bake_mesh_from_current_skeleton_pose() if node.skin!=null else node.mesh
		if mesh==null:continue
		for surface in mesh.get_surface_count():
			for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p=rig.global_transform.affine_inverse()*node.global_transform*vertex;low=minf(low,p.y);high=maxf(high,p.y)
	rig.scale=Vector3.ONE*1.745/(high-low);rig.position=Vector3(.30,.08-low*rig.scale.y,2.55);rig.rotation_degrees.y=180
	standing_transform=rig.transform;report.avatar={"height_m":1.745,"source_height_m":high-low,"scale":rig.scale.y}

func capture(name):
	for i in 8:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"id":name,"pixels":[vp.size.x,vp.size.y],"width_m":camera.size,"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y})
	print("TEA_CAPTURE ",name)

func seated():
	var anchor=room.get_node("seat_table1_1");var animation=rig.get_node("AnimationPlayer")
	check(animation.has_animation("sit_idle"),"Existing production sit_idle clip")
	rig.play_motion("sit_idle");animation.seek(.35,true);animation.pause()
	rig.position=anchor.position-Vector3.UP*.34*rig.scale.y
	# Anchor yaw uses -Z forward; this fixture avatar's authored front is +Z.
	rig.rotation_degrees.y=anchor.rotation_degrees.y+180
	vp.size=Vector2i(1100,1000);pose(2.8,25,100,anchor.position+Vector3(0,.18,-.2));await capture("seated_stool")
	report.seated={"anchor":"seat_table1_1","seat_world_y":anchor.position.y,"seat_above_floor_m":.715,"clip":"sit_idle",
		"root":xyz(rig.position),"production_root_offset":.34,"animation_provenance":JSON.parse_string(FileAccess.get_file_as_string("res://animation-provenance.json"))}
	rig.transform=standing_transform;rig.play_motion("idle");animation.seek(.3,true);animation.pause()

func plant_controls():
	room.visible=false;rig.visible=false;vp.size=Vector2i(900,1000)
	for pair in [["olive_tree","corner_tree",2.6,1.0],["pothos","shelf_pothos",1.7,.10]]:
		var original=load("res://assets/rooms/_shared/plants/"+pair[0]+".glb").instantiate();world.add_child(original)
		var remapped=load(KIT+pair[1]+".glb").instantiate();world.add_child(remapped);remapped.visible=false
		var old_material=room.materials.foliage.duplicate();old_material.albedo_texture=load("res://assets/rooms/_shared/plants/room_albedo_ao.png")
		for node in original.find_children("*","MeshInstance3D",true,false):node.material_override=old_material;node.cast_shadow=0
		for node in remapped.find_children("*","MeshInstance3D",true,false):node.material_override=room.materials.foliage;node.cast_shadow=0
		pose(pair[2],25,35,Vector3(0,pair[3],0));await capture("plant_original_"+pair[0])
		original.visible=false;remapped.visible=true;await capture("plant_remapped_"+pair[0])
		report.plant_controls.append({"source":pair[0],"module":pair[1],"same_camera_light_geometry":true})
		original.free();remapped.free()
	room.visible=true;rig.visible=true

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	setup();geometry();await avatar();await routes()
	pose(6.72);await capture("default_43deg_360")
	vp.size=Vector2i(1200,1000);pose(11.8,43,45,Vector3(0,1.7,.3));await capture("overview")
	for sample in [["wall",Vector3(-3.19,2.50,1.50)],["beam",Vector3(-3.23,3.782,.90)],["floor",Vector3(2.50,.082,2.55)]]:
		var screen=camera.unproject_position(sample[1]);report.colour_points[sample[0]]=[screen.x,screen.y]
	rig.visible=false;overlay.visible=true;vp.size=Vector2i(1200,1200);pose(8.5,90,0,Vector3(0,0,.5));await capture("topdown_capsules")
	overlay.visible=false;rig.visible=true;await seated();rig.visible=false
	vp.size=Vector2i(1400,1000);pose(6.1,24,12,Vector3(.32,1.62,-2.35));await capture("counter_coffee_corner")
	pose(3.4,30,70,Vector3(-2.7,2.2,-.4));await capture("window_shadow_on")
	var sun=world.find_children("*","DirectionalLight3D",true,false)[0];sun.shadow_enabled=false
	await capture("window_shadow_off");sun.shadow_enabled=true
	pose(4.2,30,45,Vector3(-1.10,2.1,-1.50));await capture("lanterns_on")
	for light in room.find_children("*","OmniLight3D",true,false):light.visible=false
	await capture("lanterns_off")
	for light in room.find_children("*","OmniLight3D",true,false):light.visible=true
	await plant_controls()
	report.passed=report.checks.all(func(c):return c.passed)
	var file=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("TEA_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
