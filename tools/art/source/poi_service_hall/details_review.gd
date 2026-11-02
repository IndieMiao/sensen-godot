extends Node
## Prop review only. Neutral unchanged shell supplies the camera occlusion fixture.
const KIT="res://assets/rooms/poi_service_hall/"
var vp: SubViewport
var world: Node3D
var camera: Camera3D
var props: Node3D
var shell: Node3D
var rig
var atlas: StandardMaterial3D
var manifest: Dictionary
var output: String
var report={"checks":[],"captures":[],"occlusion":{}}

func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func material(color):
	var mat=StandardMaterial3D.new();mat.albedo_color=Color(color);mat.roughness=.85;mat.metallic_specular=.18
	return mat

func setup():
	manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"prop_manifest.json"))
	vp=SubViewport.new();vp.size=Vector2i(1400,1000);vp.own_world_3d=true
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
	camera.near=.1;camera.far=80;camera.current=true;world.add_child(camera)
	atlas=material("FFFFFF");atlas.albedo_texture=load(KIT+"hall_albedo_ao_n2.png")
	atlas.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	props=Node3D.new();world.add_child(props)
	check(atlas.albedo_texture.get_size()==Vector2(2048,2048),"One 2048x2048 same-layout hall atlas")

func pose(width,pitch=43.,yaw=45.,focus=Vector3(0,1.1,.35)):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0)
	camera.position=focus+camera.basis.z*22

func add_prop(name,position,yaw=0.):
	var model=load(KIT+name+".glb").instantiate();model.name=name
	props.add_child(model);model.position=position;model.rotation_degrees.y=yaw
	for node in model.find_children("*","MeshInstance3D",true,false):node.material_override=atlas
	return model

func clear_props():
	for child in props.get_children():child.free()

func geometry():
	var total=0;var surfaces=0
	for spec in manifest.assets:
		var model=add_prop(spec.name,Vector3.ZERO)
		var low=Vector3.INF;var high=-Vector3.INF;var tris=0;var count=0
		for node in model.find_children("*","MeshInstance3D",true,false):
			for surface in node.mesh.get_surface_count():
				count+=1
				var arrays=node.mesh.surface_get_arrays(surface)
				tris+=arrays[Mesh.ARRAY_INDEX].size()/3
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					var point=model.global_transform.affine_inverse()*node.global_transform*vertex
					low=low.min(point);high=high.max(point)
		check(tris==spec.triangles and count==1,spec.name+": imported triangles and one surface")
		check(low.distance_to(vec(spec.measured.bounds[0]))<.0001 and high.distance_to(vec(spec.measured.bounds[1]))<.0001,
			spec.name+": actual Godot vertices match GLB metre bounds")
		var config=ConfigFile.new();check(config.load(KIT+spec.file+".import")==OK,spec.name+": import config loads")
		check(str(config.get_value("remap","uid","")).begins_with("uid://"),spec.name+": import UID")
		check(config.get_value("params","gltf/texture_map_mode",0)==1,spec.name+": texture_map_mode=1")
		total+=tris*int(spec.quantity);surfaces+=count*int(spec.quantity);model.free()
	report.imported={"placed_prop_triangles":total,"placed_prop_surfaces":surfaces,
		"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(total<35000 and surfaces==11,"Independent props fit reserved scene budget")

func floor_mesh():
	var floor=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=Vector3(15,.08,11)
	floor.mesh=mesh;floor.position.y=-.04;floor.material_override=material("DADCD7");world.add_child(floor)
	return floor

func capture(name):
	for i in 8:await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image();check(image.save_png(output+"/"+name+".png")==OK,"Saved "+name)
	report.captures.append({"id":name,"pixels":[vp.size.x,vp.size.y],"pitch":-camera.rotation_degrees.x,
		"yaw":camera.rotation_degrees.y,"width_m":camera.size})
	print("N2_DETAIL_CAPTURE ",name)

func avatar():
	rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig)
	rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Reference character assembled")
	rig.play_motion("idle");var animation=rig.get_node("AnimationPlayer");animation.seek(.3,true);animation.pause()
	var low=INF;var high=-INF
	for node in rig.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		var mesh=node.bake_mesh_from_current_skeleton_pose() if node.skin!=null else node.mesh
		if mesh==null:continue
		for surface in mesh.get_surface_count():
			for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p=rig.global_transform.affine_inverse()*node.global_transform*vertex
				low=minf(low,p.y);high=maxf(high,p.y)
	rig.scale=Vector3.ONE*1.745/(high-low);rig.position=Vector3(-3.7,-low*rig.scale.y,2.2)
	rig.rotation_degrees.y=180
	report.avatar={"height_m":1.745,"root_offset_y":rig.position.y}

func occlusion():
	var triangles=[]
	for name in ["sculpture_base","sculpture_body"]:
		for node in props.get_node(name).find_children("*","MeshInstance3D",true,false):
			var arrays=node.mesh.surface_get_arrays(0);var vertices=arrays[Mesh.ARRAY_VERTEX];var indices=arrays[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				triangles.append([node.global_transform*vertices[indices[i]],node.global_transform*vertices[indices[i+1]],
					node.global_transform*vertices[indices[i+2]]])
	for name in ["notice_board","brochure_rack","call_screen"]:
		var spec=manifest.assets.filter(func(s):return s.name==name)[0]
		var node=props.get_node(name);var lo=vec(spec.measured.bounds[0]);var hi=vec(spec.measured.bounds[1])
		var blocked=0;var tested=0
		for x in range(1,10):
			for y in range(1,10):
				var local=Vector3(lerpf(lo.x,hi.x,x/10.),lerpf(lo.y,hi.y,y/10.),hi.z+.003)
				var target=node.global_transform*local;var origin=target+camera.global_basis.z*24
				tested+=1
				for tri in triangles:
					if Geometry3D.segment_intersects_triangle(origin,target,tri[0],tri[1],tri[2])!=null:
						blocked+=1;break
		report.occlusion[name]={"tested":tested,"blocked_by_sculpture":blocked}
		check(blocked==0,"Actual sculpture triangles do not occlude "+name+" at default 43 degrees")

func run():
	output=ProjectSettings.globalize_path("res://../details_captures");DirAccess.make_dir_recursive_absolute(output)
	setup();geometry();var floor=floor_mesh()
	add_prop("display_niche_1",Vector3(-2.6,0,-1.2));add_prop("display_niche_2",Vector3(-1.15,0,-1.2))
	add_prop("brochure_rack",Vector3(.4,0,-1.2));add_prop("water_dispenser",Vector3(1.65,0,-1.2))
	add_prop("notice_board",Vector3(.3,2.05,-1.35));add_prop("name_plaque",Vector3(1.5,2.1,-1.35))
	add_prop("call_screen",Vector3(2.8,1.8,-1.35));add_prop("window_flowerbox",Vector3(2.6,0,.35))
	add_prop("sculpture_base",Vector3(-.7,0,1.6));add_prop("sculpture_body",Vector3(-.7,.4,1.6))
	await avatar();pose(9.0,30,15,Vector3(-.2,1.05,.4));await capture("props_overview")
	rig.visible=false;clear_props();add_prop("sculpture_base",Vector3.ZERO);add_prop("sculpture_body",Vector3(0,.4,0))
	vp.size=Vector2i(1000,1000);pose(2.6,23,15,Vector3(0,.8,0));await capture("sculpture_detail")
	clear_props();add_prop("display_niche_1",Vector3(-.72,0,0));add_prop("display_niche_2",Vector3(.72,0,0))
	pose(3.2,12,10,Vector3(0,1.2,0));await capture("niche_displays")
	clear_props();add_prop("call_screen",Vector3(-.65,1.7,0));add_prop("notice_board",Vector3(.45,1.6,0))
	add_prop("name_plaque",Vector3(-.5,2.4,0));add_prop("brochure_rack",Vector3(-.55,0,.15))
	add_prop("water_dispenser",Vector3(1.1,0,.05));add_prop("window_flowerbox",Vector3(-1.5,0,.15))
	pose(4.3,12,15,Vector3(-.3,1.25,0));await capture("boards_and_service_props")
	clear_props();floor.free()
	shell=load("res://scenes/shell_hall/shell_hall_art.tscn").instantiate();world.add_child(shell)
	for node in shell.find_children("*","MeshInstance3D",true,false):
		if "glass" not in str(node.name).to_lower():node.material_override=material("DADCD7")
	add_prop("sculpture_base",Vector3(.04,.08,.18));add_prop("sculpture_body",Vector3(.04,.48,.18),45)
	add_prop("display_niche_1",Vector3(-1.65,.08,-2.98));add_prop("display_niche_2",Vector3(1.65,.08,-2.98))
	add_prop("brochure_rack",Vector3(-.10,.08,-2.55),8);add_prop("water_dispenser",Vector3(3.02,.08,-2.60))
	add_prop("notice_board",Vector3(0,1.63,-2.83));add_prop("name_plaque",Vector3(0,3.08,-2.96))
	add_prop("call_screen",Vector3(-3.04,1.83,0),90)
	add_prop("window_flowerbox",Vector3(-2.91,1.06,-1.78),90)
	var second=add_prop("window_flowerbox",Vector3(-2.91,1.06,1.78),90);second.name="window_flowerbox_2"
	rig.visible=true;rig.position=Vector3(0,.08+report.avatar.root_offset_y,2.5)
	vp.size=Vector2i(360,800);pose(6.72);await capture("fixed_props_default_43deg_360");occlusion()
	vp.size=Vector2i(1200,1000);pose(12.0,43,45,Vector3(0,1.85,.1));await capture("fixed_props_overview")
	report.passed=report.checks.all(func(c):return c.passed)
	var file=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("N2_DETAILS_VALIDATION ",report.passed)
	get_tree().quit(0 if report.passed else 1)
