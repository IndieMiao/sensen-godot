extends Node
const KIT="res://assets/rooms/poi_culture_hall/props/"
var vp:SubViewport
var world:Node3D
var props:Node3D
var camera:Camera3D
var ground:MeshInstance3D
var manifest:Dictionary
var output:String
var report={"checks":[],"captures":[],"assets":{}}
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func matte(color):
	var m=StandardMaterial3D.new();m.albedo_color=Color(color);m.roughness=.9;m.metallic_specular=.18;return m
func fixture(name,position,size):
	var node=MeshInstance3D.new();node.name=name;var mesh=BoxMesh.new();mesh.size=size;node.mesh=mesh
	node.material_override=matte("FFFFFF");node.position=position;world.add_child(node);return node
func setup():
	manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"prop_manifest.json"))
	vp=SubViewport.new();vp.size=Vector2i(400,440);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	world=Node3D.new();vp.add_child(world);props=Node3D.new();world.add_child(props)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color.WHITE
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("F5F6F1");env.ambient_light_energy=.45
	env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=Vector3(-4,7,4);sun.look_at(Vector3.ZERO)
	sun.light_energy=.65;sun.light_color=Color("FFF5E7");sun.shadow_enabled=true;sun.shadow_opacity=.35
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.05;camera.far=80;camera.current=true;world.add_child(camera)
	ground=fixture("White ground",Vector3(0,-.04,0),Vector3(40,.08,40));ground.visible=false
func pose(width,pitch,yaw,focus):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*22
func add_prop(asset,position,instance_name="",parent=null):
	var node=load(KIT+asset+".glb").instantiate();node.name=asset if instance_name=="" else instance_name
	if parent==null:parent=props
	parent.add_child(node);node.position=position;return node
func geometry():
	var unique=0;var placed=0;var surfaces=0
	for spec in manifest.assets:
		var model=add_prop(spec.name,Vector3.ZERO);var lo=Vector3.INF;var hi=-Vector3.INF;var tris=0;var count=0;var glass=0
		for node in model.find_children("*","MeshInstance3D",true,false):
			check(node.mesh.resource_name==spec.name+"_mobile",spec.name+": mobile mesh resource name")
			for surface in node.mesh.get_surface_count():
				count+=1;var a=node.mesh.surface_get_arrays(surface);tris+=a[Mesh.ARRAY_INDEX].size()/3
				for v in a[Mesh.ARRAY_VERTEX]:
					var p=model.global_transform.affine_inverse()*node.global_transform*v;lo=lo.min(p);hi=hi.max(p)
				var mat=node.get_active_material(surface)
				check(mat is StandardMaterial3D and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb,spec.name+": linear vertex color enabled")
				check(mat.albedo_texture==null,spec.name+": no textures")
				if mat.resource_name.begins_with("CultureGlass"):
					glass+=1;check(mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and absf(mat.albedo_color.a-.16)<.001,"Cabinet glass is its own translucent surface")
				else:check(mat.roughness>=.85 and mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,spec.name+": opaque matte surface")
		check(tris==spec.triangles and tris<=600 and count==spec.surfaces,spec.name+": imported budget")
		check(glass==(1 if spec.name=="display_cabinet" else 0),spec.name+": only cabinet has glass")
		check(lo.distance_to(vec(spec.bounds[0]))<.0001 and hi.distance_to(vec(spec.bounds[1]))<.0001,spec.name+": actual imported bounds")
		var cfg=ConfigFile.new();check(cfg.load(KIT+spec.file+".import")==OK,spec.name+": import config")
		check(str(cfg.get_value("remap","uid","")).begins_with("uid://") and cfg.get_value("params","gltf/texture_map_mode",0)==1,spec.name+": UID / texture_map_mode=1")
		check(model.find_children("seat_*","",true,false).is_empty(),spec.name+": no seating anchors")
		if spec.name=="name_sign":
			var anchor=model.find_child("sign_door",true,false)
			check(anchor!=null and anchor.position.distance_to(vec(spec.anchors[0].position))<.0001,"Blank sign anchor center")
		report.assets[spec.name]={"triangles":tris,"surfaces":count,"bounds":[xyz(lo),xyz(hi)]}
		unique+=tris;placed+=tris*int(spec.quantity);surfaces+=count*int(spec.quantity);model.free()
	report.unique_triangles=unique;report.placed_triangles=placed;report.placed_surfaces=surfaces
func capture(name):
	for i in 6:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"id":name,"pixels":[vp.size.x,vp.size.y],"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y,"width_m":camera.size})
	print("CULTURE_CAPTURE ",name)
func individual(spec):
	var at=Vector3(0,-spec.bounds[0][1],0);var model=add_prop(spec.name,at)
	var pitch=25.;var yaw=20.
	if spec.origin=="back_center":pitch=0; yaw=0
	if spec.name=="floor_mosaic":pitch=75; yaw=0
	if spec.name in ["exhibit_leaf_fossil","exhibit_shell_fragment","exhibit_spiral_fossil","exhibit_shallow_bowl"]:pitch=55
	if spec.name=="exhibit_ammonite":pitch=15; yaw=12
	camera.rotation_degrees=Vector3(-pitch,yaw,0)
	var lo=Vector3.INF;var hi=-Vector3.INF
	for x in [spec.bounds[0][0],spec.bounds[1][0]]:
		for y in [spec.bounds[0][1],spec.bounds[1][1]]:
			for z in [spec.bounds[0][2],spec.bounds[1][2]]:
				var p=camera.basis.inverse()*(Vector3(x,y,z)+at);lo=lo.min(p);hi=hi.max(p)
	var width=maxf((hi.x-lo.x)/.78,(hi.y-lo.y)*vp.size.x/vp.size.y/.74)
	pose(width,pitch,yaw,(vec(spec.bounds[0])+vec(spec.bounds[1]))*.5+at);await capture(spec.name);model.free()
func avatar():
	var rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Actual player assembled")
	rig.play_motion("idle");var anim=rig.get_node("AnimationPlayer");anim.seek(.3,true);anim.pause()
	var lo=INF;var hi=-INF
	for node in rig.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		var mesh=node.bake_mesh_from_current_skeleton_pose() if node.skin!=null else node.mesh
		if mesh==null:continue
		for surface in mesh.get_surface_count():
			for v in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p=rig.global_transform.affine_inverse()*node.global_transform*v;lo=minf(lo,p.y);hi=maxf(hi,p.y)
	rig.scale=Vector3.ONE*1.745/(hi-lo);rig.position=Vector3(.40,-lo*rig.scale.y,2.20);rig.rotation_degrees.y=180
	report.avatar={"height_m":1.745,"actual_unscaled_bounds_y":[lo,hi],"scale":rig.scale.x}
func scale_review():
	ground.visible=true;vp.size=Vector2i(1800,1800)
	fixture("Gallery backing - scale fixture only",Vector3(0,1.675,-2.65),Vector3(2.60,3.35,.04))
	add_prop("display_cabinet",Vector3(-1.55,0,.75),"glass_case_1")
	add_prop("display_cabinet",Vector3(1.55,0,.75),"glass_case_2")
	add_prop("exhibit_plinth",Vector3(2.20,0,2.30),"display_plinth")
	add_prop("floor_mosaic",Vector3(0,0,.55));add_prop("name_sign",Vector3(0,3.13,-2.625))
	for spec in manifest.assets:
		if spec.has("gallery_offset"):add_prop(spec.name,Vector3(0,2.18,-2.625)+vec(spec.gallery_offset))
		if spec.has("display_assignment"):
			var slot=spec.display_assignment;add_prop(spec.name,vec(slot.position),slot.instance_name,props.get_node(slot.container))
	await avatar();pose(7.8,43,45,Vector3(0,1.45,.3));await capture("scale_43deg")
	pose(2.5,35,25,Vector3(-1.55,1.17,.75));vp.size=Vector2i(1000,1000);await capture("cabinet_glass_detail")
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	setup();geometry()
	for spec in manifest.assets:await individual(spec)
	await scale_review();check(RenderingServer.get_current_rendering_method()=="mobile","Actual Mobile renderer")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	report.passed=report.checks.all(func(c):return c.passed)
	var file=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("CULTURE_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
