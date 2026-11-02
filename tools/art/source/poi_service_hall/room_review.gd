extends Node
const KIT="res://assets/rooms/poi_service_hall/"
var vp:SubViewport
var world:Node3D
var room:Node3D
var camera:Camera3D
var rig
var overlay:Node3D
var output:String
var report={"checks":[],"captures":[],"occlusion":{},"routes":[]}

func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)

func setup():
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	world=Node3D.new();vp.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("D9E1E4")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("EEF0E9")
	env.ambient_light_energy=.55;env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=Vector3(-6,7,2);sun.look_at(Vector3.ZERO)
	sun.light_color=Color("FFF6E8");sun.light_energy=1.;sun.shadow_enabled=true;sun.shadow_opacity=.55
	sun.shadow_bias=.05;sun.shadow_normal_bias=.25;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1;camera.far=40;camera.current=true;world.add_child(camera)
	room=load("res://scenes/poi_service_hall/poi_service_hall_art.tscn").instantiate();world.add_child(room)
	overlay=Node3D.new();world.add_child(overlay);overlay.visible=false

func pose(width,pitch=43.,yaw=45.,focus=Vector3(0,1.1,.35)):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*22

func geometry():
	var triangles=0;var surfaces=0;var textures={}
	for node in room.find_children("*","MeshInstance3D",true,false):
		for i in node.mesh.get_surface_count():
			var arrays=node.mesh.surface_get_arrays(i);surfaces+=1;triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
			var mat=node.get_active_material(i)
			check(mat is StandardMaterial3D and mat.albedo_texture!=null,"External atlas material: "+str(node.get_path()))
			if mat is StandardMaterial3D and mat.albedo_texture!=null:textures[mat.albedo_texture.resource_path]=true
	check(triangles==53892 and surfaces==34,"Actual assembled budget 53892 triangles / 34 surfaces")
	check(textures.size()==1 and textures.has(KIT+"hall_albedo_ao_n2.png"),"Single shared N2 skin including plants and shell")
	var seats=room.layout.anchors.filter(func(a):return a.name.begins_with("seat_"))
	check(seats.size()==8,"Eight user-approved seats")
	for seat in seats:
		var marker=room.get_node(seat.name);var direction=vec(seat.approach)-marker.position;direction.y=0
		check(absf(marker.position.y-.795)<.0001,seat.name+": actual seat height .715 above floor")
		check((-marker.basis.z).dot(direction.normalized())>.999,seat.name+": faces reachable front of furniture")
	for name in room.layout.assets:
		var config=ConfigFile.new();check(config.load(KIT+name+".glb.import")==OK,name+": import settings")
		check(str(config.get_value("remap","uid","")).begins_with("uid://"),name+": UID present")
		check(config.get_value("params","gltf/texture_map_mode",0)==1,name+": texture_map_mode=1")
	check(absf(room.get_node("wall_clock").position.y-2.53)<.001,"Clock centre 2.45m above floor")
	check(room.get_node("sign_name").get_meta("size")==[.88,.23],"Name plaque usable area retained")
	check(room.get_node("sculpture_body").basis.z.dot(camera.basis.z*Vector3(1,0,1))>.7,"Sculpture front faces default camera")
	report.imported={"triangles":triangles,"surfaces":surfaces,"textures":textures.keys(),
		"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}

func avatar():
	rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Reference character assembled")
	rig.play_motion("idle");var animation=rig.get_node("AnimationPlayer");animation.seek(.3,true);animation.pause()
	var low=INF;var high=-INF
	for node in rig.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		var mesh=node.bake_mesh_from_current_skeleton_pose() if node.skin!=null else node.mesh
		if mesh==null:continue
		for i in mesh.get_surface_count():
			for vertex in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				var p=rig.global_transform.affine_inverse()*node.global_transform*vertex;low=minf(low,p.y);high=maxf(high,p.y)
	rig.scale=Vector3.ONE*1.745/(high-low);rig.position=Vector3(0,.08-low*rig.scale.y,2.5);rig.rotation_degrees.y=180
	report.avatar={"height_m":1.745,"position":xyz(rig.position)}

func capsule(p,radius=.25):
	var q=PhysicsShapeQueryParameters3D.new();var shape=CapsuleShape3D.new();shape.height=1.745;shape.radius=radius
	q.shape=shape;q.margin=.001;q.transform.origin=p+Vector3.UP*.8725;return q

func line(points,color):
	var mesh=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(points.size()-1):
		mesh.surface_add_vertex(points[i]);mesh.surface_add_vertex(points[i+1])
	mesh.surface_end();var node=MeshInstance3D.new();node.mesh=mesh
	var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override=mat;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;overlay.add_child(node)

func circle(point,radius,color):
	var points=[]
	for i in range(49):points.append(point+Vector3(cos(i*TAU/48),0,sin(i*TAU/48))*radius)
	line(points,color)

func routes():
	await get_tree().physics_frame
	var space=world.get_world_3d().direct_space_state;var nav=room.layout.navigation
	for i in range(96):
		var p=Vector3(.04+cos(i*TAU/96)*1.38,.09,.18+sin(i*TAU/96)*1.38)
		check(space.intersect_shape(capsule(p,.35),1).is_empty(),"Main .70m ring capsule "+str(i))
	for i in range(14):
		var p=Vector3(0,.09,1.48+i*.1)
		check(space.intersect_shape(capsule(p,.35),1).is_empty(),"Main .70m entry capsule "+str(i))
	for route in nav.routes:
		var points=[];var blocked=[]
		for p in route.points_xz:points.append(Vector3(p[0],.09,p[1]))
		for i in range(points.size()-1):
			var q=capsule(points[i]);q.motion=points[i+1]-points[i];var sweep=space.cast_motion(q)
			if sweep[0]<.999 or not space.intersect_shape(capsule(points[i+1]),1).is_empty():blocked.append(i)
		check(blocked.is_empty(),"Native capsule sweep: "+route.name)
		report.routes.append({"name":route.name,"blocked_segments":blocked})
		if route.name.begins_with("seat_"):line(points.map(func(p):return p+Vector3.UP*.025),Color("3E9975"))
	for point in nav.standing_positions_xz:
		var p=Vector3(point[0],.115,point[1]);circle(p,.25,Color("397BC4"))
		check(space.intersect_shape(capsule(Vector3(p.x,.09,p.z)),1).is_empty(),"Standing capsule: "+str(point))
	for seat in room.layout.anchors:
		if seat.name.begins_with("seat_"):circle(Vector3(seat.position[0],seat.position[1]+.02,seat.position[2]),.13,Color("E5A62C"))
	var ends=nav.ring_measurement_xz;line([Vector3(ends[0][0],.12,ends[0][1]),Vector3(ends[1][0],.12,ends[1][1])],Color("D54A43"))
	report.navigation=nav

func occlusion():
	var triangles=[]
	for name in ["sculpture_base","sculpture_body"]:
		for node in room.get_node(name).find_children("*","MeshInstance3D",true,false):
			var arrays=node.mesh.surface_get_arrays(0);var p=arrays[Mesh.ARRAY_VERTEX];var idx=arrays[Mesh.ARRAY_INDEX]
			for i in range(0,idx.size(),3):triangles.append([node.global_transform*p[idx[i]],node.global_transform*p[idx[i+1]],node.global_transform*p[idx[i+2]]])
	for name in ["notice_board","brochure_rack","call_screen"]:
		var spec=room.layout.assets[name];var node=room.get_node(name);var lo=vec(spec.bounds[0]);var hi=vec(spec.bounds[1]);var blocked=0
		for x in range(1,10):
			for y in range(1,10):
				var target=node.global_transform*Vector3(lerpf(lo.x,hi.x,x/10.),lerpf(lo.y,hi.y,y/10.),hi.z+.003)
				var origin=target+camera.global_basis.z*24
				for tri in triangles:
					if Geometry3D.segment_intersects_triangle(origin,target,tri[0],tri[1],tri[2])!=null:blocked+=1;break
		report.occlusion[name]={"tested":81,"blocked_by_sculpture":blocked}
		check(blocked==0,"Sculpture does not block "+name)

func capture(name):
	for i in 8:await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image();check(image.save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"id":name,"pixels":[vp.size.x,vp.size.y],"pitch":-camera.rotation_degrees.x,
		"yaw":camera.rotation_degrees.y,"width_m":camera.size})
	print("N2_ROOM_CAPTURE ",name)

func run():
	var tabletop_only="--tabletop-only" in OS.get_cmdline_user_args()
	output=ProjectSettings.globalize_path("res://../room_captures_v1.1" if tabletop_only else "res://../room_captures");DirAccess.make_dir_recursive_absolute(output)
	setup();pose(6.72);geometry();await avatar();await routes();occlusion()
	await capture("default_43deg_360")
	if not tabletop_only:
		vp.size=Vector2i(1200,1000);pose(12,43,45,Vector3(0,1.85,.1));await capture("overview")
		rig.visible=false;overlay.visible=true;vp.size=Vector2i(1200,1100);pose(7.8,90,0,Vector3.ZERO);await capture("top_capsule")
	report.passed=report.checks.all(func(c):return c.passed)
	var f=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t")+"\n");f.close()
	print("N2_ROOM_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
