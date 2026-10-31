extends Node
## SGODOT-321 neutral spatial study. Existing shell geometry is never modified.
const HALL="res://assets/rooms/_shared/shell_hall/"
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var shell: Node3D
var furniture: Node3D
var overlay: Node3D
var avatar
var avatar_floor_offset=0.0
var plans: Dictionary
var measurements: Dictionary
var plan: Dictionary
var report={"checks":[],"layouts":{},"captures":[]}
var output: String
var neutral: StandardMaterial3D
var seat_material: StandardMaterial3D
var detail_material: StandardMaterial3D
var wall_panels=[]

func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func material(color):
	var mat=StandardMaterial3D.new();mat.albedo_color=Color(color);mat.roughness=.9;mat.metallic_specular=.18
	return mat

func setup():
	viewport=SubViewport.new();viewport.size=Vector2i(360,800);viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	world=Node3D.new();viewport.add_child(world)
	var environment=Environment.new();environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("D9E1E4");environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("EEF0E9");environment.ambient_light_energy=.55
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var we=WorldEnvironment.new();we.environment=environment;world.add_child(we)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=Vector3(-6,7,2);sun.look_at(Vector3.ZERO)
	sun.light_color=Color("FFF6E8");sun.light_energy=1.0;sun.shadow_enabled=true
	sun.shadow_opacity=.55;sun.shadow_bias=.05;sun.shadow_normal_bias=.25
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1;camera.far=40;camera.current=true;world.add_child(camera)
	neutral=material("DADCD7");seat_material=material("8499A5");detail_material=material("BBC4C7")
	shell=load("res://scenes/shell_hall/shell_hall_art.tscn").instantiate();world.add_child(shell)
	for mesh in shell.find_children("*","MeshInstance3D",true,false):
		if "glass" in str(mesh.name).to_lower():
			var glass=material("CEDFE2");glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color.a=.2;mesh.material_override=glass
		elif "hall_floor" in str(mesh.get_path()):
			var floor_material=ShaderMaterial.new();var shader=Shader.new()
			shader.code="""shader_type spatial;
uniform vec4 floor_color : source_color = vec4(.855,.863,.843,1.0);
uniform vec4 path_color : source_color = vec4(.38,.50,.64,1.0);
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){vec2 p=world.xz-vec2(.04,.18);float r=length(p);
bool path=world.y>.079 && (abs(p.x)<.35 || abs(p.y)<.35 || (r>.96 && r<1.66));
ALBEDO=path?path_color.rgb:floor_color.rgb;ROUGHNESS=.9;SPECULAR=.18;}
"""
			floor_material.shader=shader;mesh.material_override=floor_material
		else:mesh.material_override=neutral
	for y in [1.75,2.45]:
		var panel=proxy_mesh({"kind":"box","size":[.03,.5 if y<2 else .45,.80 if y<2 else .45]},detail_material)
		panel.position=Vector3(-3.04,.08+y,0);world.add_child(panel)
		wall_panels.append(panel)
	for spec in [["notice_board",[.70,.90,.025],[0,1.63,-2.96]],["blank_sign",[1.0,.35,.025],[0,3.08,-2.96]]]:
		var node=proxy_mesh({"kind":"box","size":spec[1]},detail_material);node.name=spec[0];node.position=vec(spec[2]);world.add_child(node)
		wall_panels.append(node)
	check(shell.layout.floor_y==.08,"Unmodified shell floor at Y=.08m")
	check(shell.layout.footprint==[6.8,6.4],"Unmodified shell footprint 6.8x6.4m")

func pose(width,pitch=43.0,yaw=45.0,focus=Vector3(0,1.1,.35)):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0)
	camera.position=focus+camera.basis.z*22

func proxy_mesh(spec,mat):
	var node=MeshInstance3D.new()
	if spec.kind=="cylinder":
		var mesh=CylinderMesh.new();mesh.top_radius=spec.size[0]/2;mesh.bottom_radius=mesh.top_radius
		mesh.height=spec.size[1];mesh.radial_segments=32;mesh.rings=1;node.mesh=mesh
	else:
		var mesh=BoxMesh.new();mesh.size=vec(spec.size);node.mesh=mesh
	node.material_override=mat
	return node

func box_body(parent,center,size):
	var body=StaticBody3D.new();body.name="MeasuredBounds";body.position=center
	var collision=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=size
	collision.shape=shape;body.add_child(collision);parent.add_child(body)

func cylinder_body(parent,radius,height,center):
	var body=StaticBody3D.new();body.name="MeasuredRoundBounds";body.position=center
	var collision=CollisionShape3D.new();var shape=CylinderShape3D.new();shape.radius=radius;shape.height=height
	collision.shape=shape;body.add_child(collision);parent.add_child(body)

func small_table():
	var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[.30,.05,.725],[.055,.65,.375],[.18,.05,.025]]:
		var cylinder=CylinderMesh.new();cylinder.top_radius=part[0];cylinder.bottom_radius=part[0]
		cylinder.height=part[1];cylinder.radial_segments=24;cylinder.rings=1
		surface.append_from(cylinder,0,Transform3D(Basis.IDENTITY,Vector3(0,part[2],0)))
	var node=MeshInstance3D.new();node.mesh=surface.commit();node.mesh.resource_name="small_round_table_mobile"
	node.material_override=detail_material
	return node

func imported_bounds(root):
	var result=AABB();var first=true
	var meshes=root.find_children("*","MeshInstance3D",true,false)
	if root is MeshInstance3D:meshes.push_front(root)
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point=root.global_transform.affine_inverse()*mesh.global_transform*vertex
				if first:result=AABB(point,Vector3.ZERO);first=false
				else:result=result.expand(point)
	return result

func instantiate_plan(spec):
	if furniture!=null:furniture.free()
	if overlay!=null:overlay.free()
	furniture=Node3D.new();furniture.name="Blockout_"+spec.id;world.add_child(furniture)
	overlay=Node3D.new();overlay.name="CapsuleRoutes";world.add_child(overlay);overlay.visible=false
	plan=spec
	for item in spec.items:
		var pivot=Node3D.new();pivot.name=item.name;pivot.position=vec(item.position);pivot.rotation_degrees.y=item.yaw_degrees
		furniture.add_child(pivot)
		var model
		if item.asset=="small_round_table":model=small_table()
		else:
			var path="res://assets/rooms/_shared/plants/peace_lily.glb" if item.asset=="peace_lily" else HALL+item.source_asset+".glb"
			model=load(path).instantiate()
		model.scale=vec(item.scale);pivot.add_child(model)
		var meshes=model.find_children("*","MeshInstance3D",true,false)
		if model is MeshInstance3D:meshes.push_front(model)
		for mesh in meshes:
			mesh.material_override=seat_material if item.asset in ["sofa_three_seat","armchair","sofa_narrow","armchair_narrow"] else detail_material
			if item.asset=="peace_lily":
				mesh.material_override=material("A5B49D");mesh.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var low=vec(item.bounds_local[0]);var high=vec(item.bounds_local[1])
		var actual=imported_bounds(pivot)
		check(actual.position.distance_to(low)<.0002 and actual.end.distance_to(high)<.0002,spec.id+" real imported bounds match footprint: "+item.name)
		if item.asset in ["round_side_table","small_round_table"]:cylinder_body(pivot,high.x,high.y,Vector3(0,high.y/2,0))
		elif item.asset=="peace_lily":cylinder_body(pivot,item.pot_collision.radius,item.pot_collision.height,Vector3(0,item.pot_collision.height/2,0))
		else:box_body(pivot,(low+high)/2,high-low)
		check(model.scale.y==1 and model.scale.z==1,spec.id+" original seat height and depth: "+item.name)
		if spec.id!="A2":check(model.scale==Vector3.ONE,spec.id+" actual kit scale 1: "+item.name)
	for item in spec.fixed:
		var node=proxy_mesh(item,neutral if item.name.begins_with("sculpture") else detail_material)
		node.name=item.name;node.mesh.resource_name=item.name+"_mobile"
		node.position=vec(item.position);node.rotation_degrees.y=item.yaw_degrees;furniture.add_child(node)
		if item.collidable:
			if item.kind=="cylinder":cylinder_body(node,item.size[0]/2,item.size[1],Vector3.ZERO)
			else:box_body(node,Vector3.ZERO,vec(item.size))
	for seat in spec.anchors:
		var marker=Marker3D.new();marker.name=seat.name;marker.position=vec(seat.position)
		marker.rotation_degrees.y=seat.yaw_degrees;marker.set_meta("module",seat.module);furniture.add_child(marker)
		check(absf(marker.position.y-.795)<.0001,spec.id+" seat .715m above shell floor: "+seat.name)
	avatar.position=vec(spec.spawn)+Vector3.UP*(.005+avatar_floor_offset)
	report.layouts[spec.id]={"seats":spec.seat_count,"routes":[],"minimum_sculpture_clearance_m":spec.sculpture_clearance_m}
	var nodes=shell.find_children("*","MeshInstance3D",true,false)+furniture.find_children("*","MeshInstance3D",true,false)+wall_panels
	var triangles=0;var surfaces=0
	for mesh in nodes:
		for surface in mesh.mesh.get_surface_count():
			var arrays=mesh.mesh.surface_get_arrays(surface);surfaces+=1
			triangles+=arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size()/3
	report.layouts[spec.id].white_blockout_budget={"triangles":triangles,"surfaces":surfaces,"excludes":"fixture avatar and debug overlays; proxy cost is not final detailed art"}
	check(triangles<=150000 and surfaces<=50,spec.id+" blockout placed budget")

func avatar_fixture():
	avatar=Avatar.create_rig()
	for child in avatar.get_children():
		if child is RigActivity:child.free()
	avatar.assembler=AvatarAssemblerMerged.new();world.add_child(avatar)
	avatar.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while avatar.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not avatar.is_busy(),"Actual fixture avatar assembled")
	avatar.play_motion("idle");var animation=avatar.get_node("AnimationPlayer");animation.seek(.3,true);animation.pause()
	var low=INF;var high=-INF
	for mesh in avatar.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null or not mesh.is_visible_in_tree():continue
		var posed=mesh.bake_mesh_from_current_skeleton_pose() if mesh.skin!=null else mesh.mesh
		for i in posed.get_surface_count():
			for vertex in posed.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				var point=avatar.global_transform.affine_inverse()*mesh.global_transform*vertex
				low=minf(low,point.y);high=maxf(high,point.y)
	avatar.scale=Vector3.ONE*(1.745/(high-low));avatar.rotation_degrees.y=180
	avatar_floor_offset=-low*avatar.scale.y
	report.avatar={"source_height_m":high-low,"scale":avatar.scale.y,"standing_height_m":1.745,"local_foot_min_y":low}

func capsule(point,radius=.25):
	var query=PhysicsShapeQueryParameters3D.new();var shape=CapsuleShape3D.new()
	shape.height=1.745;shape.radius=radius;query.shape=shape
	query.transform.origin=point+Vector3.UP*.8725;query.margin=.001
	return query

func validate_routes():
	await get_tree().physics_frame
	var space=world.get_world_3d().direct_space_state
	check(plan.seat_count==plan.anchors.size(),plan.id+" declared seat count matches actual markers")
	check(plan.sculpture_clearance_m>=.70,plan.id+" sculpture ring has at least .70m clearance")
	var ring_radius=.93+minf(plan.sculpture_clearance_m,.90)/2
	for i in range(96):
		var p=Vector3(.04+cos(i*TAU/96)*ring_radius,.09,.18+sin(i*TAU/96)*ring_radius)
		check(space.intersect_shape(capsule(p,.35),1).is_empty(),plan.id+" .70m circle clearance sample "+str(i))
	for i in range(14):
		var p=Vector3(0,.09,1.48+i*.1)
		check(space.intersect_shape(capsule(p,.35),1).is_empty(),plan.id+" .70m main entry route "+str(i))
	for route in plan.navigation_plan.routes:
		var points=[]
		for p in route.points_xz:points.append(Vector3(p[0],.09,p[1]))
		var blocked=[]
		for i in range(points.size()-1):
			var query=capsule(points[i]);query.motion=points[i+1]-points[i]
			var sweep=space.cast_motion(query)
			if sweep[0]<.999 or not space.intersect_shape(capsule(points[i+1]),1).is_empty():blocked.append(i)
		check(blocked.is_empty(),plan.id+" native capsule sweep to "+route.module+" "+str(route.target))
		report.layouts[plan.id].routes.append({"module":route.module,"target":route.target,"blocked_segments":blocked,"points":points.map(func(p):return xyz(p))})
		line(points,Color("4E9971"))
	for point in plan.navigation_plan.standing_positions_xz:
		var p=Vector3(point[0],.09,point[1])
		check(space.intersect_shape(capsule(p),1).is_empty(),plan.id+" standing capsule free: "+str(point))
		circle(p,.25,Color("447BA8"))
	for seat in plan.anchors:circle(Vector3(seat.position[0],.10,seat.position[2]),.15,Color("DC9D36"))
	var central=Vector3(.04,.10,.18);circle(central,1.63,Color("7A9EA8"))
	var measure=plan.clearance.ring_measurement_xz
	line([Vector3(measure[0][0],.1,measure[0][1]),Vector3(measure[1][0],.1,measure[1][1])],Color("D57343"))
	check(plan.navigation_plan.standing_positions_xz.size()==16,plan.id+" sixteen reachable standing positions")
	check(space.intersect_shape(capsule(vec(plan.exit)+Vector3.UP*.01),1).is_empty(),plan.id+" exit anchor clearance")

func line(points,color):
	var mesh=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(points.size()-1):
		mesh.surface_add_vertex(Vector3(points[i].x,.115,points[i].z));mesh.surface_add_vertex(Vector3(points[i+1].x,.115,points[i+1].z))
	mesh.surface_end();var node=MeshInstance3D.new();node.mesh=mesh
	var mat=material(color.to_html());mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;overlay.add_child(node)

func circle(point,radius,color):
	var points=[]
	for i in range(49):points.append(point+Vector3(cos(i*TAU/48),0,sin(i*TAU/48))*radius)
	line(points,color)

func capture(id):
	for i in 8:await RenderingServer.frame_post_draw
	var image=viewport.get_texture().get_image();check(image.save_png(output+"/"+id+".png")==OK,"Saved "+id)
	report.captures.append({"id":id,"size_px":[viewport.size.x,viewport.size.y],"camera_width_m":camera.size,
		"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y,"seat_screen_points":plan.anchors.map(func(s):
			var p=camera.unproject_position(vec(s.position));return {"name":s.name,"position":[p.x,p.y]})})
	var line_points=plan.clearance.ring_measurement_xz
	var middle=Vector3((line_points[0][0]+line_points[1][0])/2,.10,(line_points[0][1]+line_points[1][1])/2)
	var label_position=camera.unproject_position(middle)
	report.captures[-1].minimum_label_px=[label_position.x,label_position.y]
	print("N2_CAPTURE ",id)

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	plans=JSON.parse_string(FileAccess.get_file_as_string("res://blockout_layouts.json"))
	measurements=JSON.parse_string(FileAccess.get_file_as_string("res://measured_dependencies.json"))
	setup()
	if "--structure-only" in OS.get_cmdline_user_args():
		avatar=Node3D.new();world.add_child(avatar)
		for spec in plans.layouts:instantiate_plan(spec)
		var data={"layouts":report.layouts,"checks":report.checks,"passed":report.checks.all(func(c):return c.passed)}
		var json=FileAccess.open(output+"/budget-validation.json",FileAccess.WRITE);json.store_string(JSON.stringify(data,"\t")+"\n");json.close()
		get_tree().quit(0 if data.passed else 1);return
	await avatar_fixture()
	for spec in plans.layouts:
		instantiate_plan(spec);await validate_routes()
		viewport.size=Vector2i(360,800);pose(6.72);await capture(spec.id+"_default_43deg_360")
		viewport.size=Vector2i(1200,1000);pose(12.0,43,45,Vector3(0,1.85,.1));await capture(spec.id+"_overview_43deg")
		avatar.visible=false;viewport.size=Vector2i(1200,1100);pose(7.8,90,0,Vector3(0,0,0))
		await capture(spec.id+"_top_clean")
		overlay.visible=true;await capture(spec.id+"_top_capsule");overlay.visible=false;avatar.visible=true
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Actual Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	report.failures=report.checks.filter(func(c):return not c.passed)
	var file=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("N2_VALIDATION ",report.passed," ",report.failures)
	get_tree().quit(0 if report.passed else 1)
