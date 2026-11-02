extends Node
var vp: SubViewport
var world: Node3D
var camera: Camera3D
var rig
var overlay: Node3D
var plan: Dictionary
var output: String
var report={"checks":[],"captures":[],"routes":[]}

func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func mat(color):
	var m=StandardMaterial3D.new();m.albedo_color=Color(color);m.roughness=.9;return m
func block(name,position,size,visible=true):
	var body=StaticBody3D.new();body.name=name;body.position=position;world.add_child(body)
	var shape=BoxShape3D.new();shape.size=size;var collision=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	if visible:
		var mesh=MeshInstance3D.new();var box=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.material_override=mat("D9DBD4");body.add_child(mesh)
	return body

func setup():
	plan=JSON.parse_string(FileAccess.get_file_as_string("res://blockout_plan.json"))
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp);world=Node3D.new();vp.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("D8E2E5")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.55;env.ambient_light_color=Color("EEF0E9")
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=Vector3(-6,7,2);sun.look_at(Vector3.ZERO)
	sun.light_color=Color("FFF6E8");sun.light_energy=1.;sun.shadow_enabled=true;sun.shadow_opacity=.55
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.shadow_bias=.05;sun.shadow_normal_bias=.25
	camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.near=.1;camera.far=50;world.add_child(camera)
	block("Floor",Vector3(0,-.03,0),Vector3(6.8,.22,6.4))
	block("Landing",Vector3(.30,-.03,3.6),Vector3(1.30,.22,1.2))
	block("LeftWall",Vector3(-3.30,1.93,0),Vector3(.20,3.7,6.4))
	block("BackWall",Vector3(0,1.93,-3.10),Vector3(6.8,3.7,.20))
	block("RightBoundary",Vector3(3.26,1.58,0),Vector3(.12,3.,6.4),false)
	block("FrontLeftBoundary",Vector3(-1.775,1.58,3.06),Vector3(2.85,3.,.12),false)
	block("FrontRightBoundary",Vector3(2.075,1.58,3.06),Vector3(2.25,3.,.12),false)
	block("LandingLeft",Vector3(-.41,1.58,3.6),Vector3(.12,3,1.2),false)
	block("LandingRight",Vector3(1.01,1.58,3.6),Vector3(.12,3,1.2),false)
	block("LandingEnd",Vector3(.30,1.58,4.26),Vector3(1.3,3,.12),false)
	for item in plan.items:
		var model_name=item.kind if item.kind in ["table","stool","plant"] else item.name
		var root=Node3D.new();root.name=item.name;root.position=vec(item.position);world.add_child(root)
		var model=load("res://models/"+model_name+".glb").instantiate();root.add_child(model)
		var low=Vector3.INF;var high=-Vector3.INF
		for node in model.find_children("*","MeshInstance3D",true,false):
			node.material_override=mat("7F9C88" if item.kind=="stool" else "A7B5B0")
			for vertex in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var point=root.global_transform.affine_inverse()*node.global_transform*vertex;low=low.min(point);high=high.max(point)
		var body=StaticBody3D.new();root.add_child(body);var collision=CollisionShape3D.new();body.add_child(collision)
		if item.radius!=null:
			var shape=CylinderShape3D.new();shape.radius=item.radius;shape.height=high.y-low.y;collision.shape=shape
			check(absf(high.x-low.x-item.radius*2)<.0001 and absf(high.z-low.z-item.radius*2)<.0001,item.name+": measured GLB diameter")
		else:
			var shape=BoxShape3D.new();shape.size=vec(item.size);collision.shape=shape
			check((high-low).distance_to(vec(item.size))<.0001,item.name+": measured GLB full envelope")
		collision.position=(low+high)/2
		if item.kind=="stool":check(absf(high.y-.715)<.0001,item.name+": measured seat height .715m")
	overlay=Node3D.new();world.add_child(overlay)
	for anchor in plan.anchors:
		if anchor.name.begins_with("seat_"):check(absf(anchor.position[1]-.795)<.0001,anchor.name+": world seat Y=.795")
		if anchor.name.begins_with("seat_") or anchor.name.begins_with("npc_"):
			var label=Label3D.new();label.text=anchor.name;label.font_size=28;label.pixel_size=.0035
			label.position=vec(anchor.position)+Vector3(0,.10,0);label.rotation_degrees.x=-90;label.no_depth_test=true;overlay.add_child(label)
	for point in plan.preflight.standing_positions_xz:
		var node=MeshInstance3D.new();var mesh=CylinderMesh.new();mesh.top_radius=.25;mesh.bottom_radius=.25;mesh.height=.018
		node.mesh=mesh;node.material_override=mat("81C8C0");node.position=Vector3(point[0],.10,point[1]);overlay.add_child(node)
	overlay.visible=false

func pose(width,pitch=43.,yaw=45.,focus=Vector3(0,1.0,.4)):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*22
func query(point,radius=.25):
	var shape=CapsuleShape3D.new();shape.radius=radius;shape.height=1.745
	var query=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.margin=.002
	query.transform.origin=point+Vector3.UP*.8725;return query
func routes():
	await get_tree().physics_frame;var space=world.get_world_3d().direct_space_state
	for group in [[plan.preflight.routes,.25],[plan.preflight.main_routes,.35]]:
		for route in group[0]:
			var failures=[];var path=route.points_xz
			for i in range(path.size()-1):
				var a=Vector3(path[i][0],.085,path[i][1]);var b=Vector3(path[i+1][0],.085,path[i+1][1]);var q=query(a,group[1]);q.motion=b-a
				if not space.intersect_shape(query(a,group[1]),1).is_empty() or space.cast_motion(q)[0]<.9999:failures.append(i)
			check(failures.is_empty(),route.name+": actual capsule radius "+str(group[1])+" route")
			report.routes.append({"name":route.name,"radius":group[1],"failed_segments":failures,"segments":path.size()-1})
	for point in plan.preflight.standing_positions_xz:
		check(space.intersect_shape(query(Vector3(point[0],.085,point[1])),1).is_empty(),"Reachable standing point "+str(point))

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

func capture(name):
	for i in 8:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append(name);print("TEA_BLOCKOUT_CAPTURE ",name)

func run():
	output=ProjectSettings.globalize_path("res://../blockout_captures");DirAccess.make_dir_recursive_absolute(output)
	setup();await avatar();await routes()
	pose(6.72);await capture("default_43deg_360")
	vp.size=Vector2i(1200,1000);pose(11.8,43,45,Vector3(0,1.7,.3));await capture("overview")
	rig.visible=false;overlay.visible=true;vp.size=Vector2i(1200,1200);pose(8.5,90,0,Vector3(0,0,.5));await capture("topdown_capsules")
	report.passed=report.checks.all(func(c):return c.passed)
	var file=FileAccess.open(output+"/validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("TEA_BLOCKOUT_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
