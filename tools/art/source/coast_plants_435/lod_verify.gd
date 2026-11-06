extends Node
var vp: SubViewport
var camera: Camera3D
var root:=Node3D.new()
var report:={"checks":[],"captures":[],"assets":{}}
const KIT:="res://assets/landmarks/_shared/coast_plants/"
func _ready() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func frames(n: int) -> void:
	for i in n:await get_tree().process_frame
func mesh(name: String) -> Mesh:
	var scene: Node=load(KIT+name+".glb").instantiate();var found:=scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D:found.push_front(scene)
	check(found.size()==1,name+": one imported mesh")
	var m: Mesh=found[0].mesh;scene.free();return m
func photograph(name: String,near: MeshInstance3D,far: MeshInstance3D,center: Vector3,distance: float,expected: int) -> void:
	camera.position=center+camera.basis.z*distance
	await frames(10);RenderingServer.force_draw(true)
	var image:=vp.get_texture().get_image();check(image.save_png("res://../"+name+".png")==OK,"capture "+name)
	var primitives:=vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	check(primitives==expected,name+": engine renders only the expected LOD triangles")
	check(absf(camera.position.distance_to(center)-distance)<.0001,name+": actual camera-to-common-AABB distance")
	report.captures.append({"name":name,"camera_to_common_aabb_m":camera.position.distance_to(center),"camera_to_pivot_m":camera.position.length(),"triangles":primitives,"expected_triangles":expected,"draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"camera":str(camera.global_transform),"width_m":camera.size,"yaw":camera.rotation_degrees.y,"pitch":camera.rotation_degrees.x,"size":[image.get_width(),image.get_height()]})
func run() -> void:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(KIT+"manifest.json"))
	var stats:={"assets":{}}
	for group in manifest.lod_groups:
		var e: Dictionary=manifest.assets[group.far].duplicate();e.near=group.near;e.near_bounds=manifest.assets[group.near].bounds;e.near_triangles=manifest.assets[group.near].triangles;stats.assets[group.far]=e
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp);vp.add_child(root)
	var display:=TextureRect.new();display.texture=vp.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);display.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(display)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("E8E3D3");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("D5E4EE");environment.environment.ambient_light_energy=.72;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-56,-34,0);sun.light_color=Color(1,.965,.88);sun.light_energy=.98;sun.light_specular=.18;root.add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.size=6.72;camera.near=.05;camera.far=150;camera.rotation_degrees=Vector3(-43,14.5,0);root.add_child(camera);camera.make_current()
	var paint:=StandardMaterial3D.new();paint.vertex_color_use_as_albedo=true;paint.vertex_color_is_srgb=false;paint.roughness=.94;paint.metallic_specular=.15
	for name in stats.assets:
		var e: Dictionary=stats.assets[name];var near:=MeshInstance3D.new();var far:=MeshInstance3D.new();near.mesh=mesh(e.near);far.mesh=mesh(name)
		check(near.mesh.get_surface_count()==1 and far.mesh.get_surface_count()==1,name+": one surface for each LOD")
		var lo:=Vector3(e.near_bounds[0][0],e.near_bounds[0][1],e.near_bounds[0][2]);var hi:=Vector3(e.near_bounds[1][0],e.near_bounds[1][1],e.near_bounds[1][2]);var box:=AABB(lo,hi-lo);var center:=box.get_center()
		for node in [near,far]:node.custom_aabb=box;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)
		near.visibility_range_end=40;near.visibility_range_end_margin=0;far.visibility_range_begin=40;far.visibility_range_begin_margin=0
		var count: int=far.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3
		check(count==e.triangles and count<=120,name+": imported far triangle budget")
		check(far.mesh.get_aabb().position.is_equal_approx(box.position) and far.mesh.get_aabb().end.is_equal_approx(box.end),name+": exact matching full bounds and root origin")
		var cfg:=ConfigFile.new();assert(cfg.load(KIT+name+".glb.import")==OK);var cache: String=cfg.get_value("remap","path")
		check(str(cfg.get_value("remap","uid","")).begins_with("uid://") and cfg.get_value("params","gltf/texture_map_mode")==1,name+": Godot UID / import contract")
		check(FileAccess.get_file_as_string(cache.trim_suffix(".scn")+".md5").contains('source_md5="'+FileAccess.get_md5(KIT+name+".glb")+'"'),name+": current imported source")
		report.assets[name]={"sha256":FileAccess.get_sha256(KIT+name+".glb"),"triangles":count,"uid":cfg.get_value("remap","uid"),"near_sha256":FileAccess.get_sha256(KIT+str(e.near)+".glb"),"common_aabb":str(box)}
		camera.rotation_degrees=Vector3(-43,14.5,0)
		await photograph(e.near+"_39m",near,far,center,39,int(e.near_triangles))
		await photograph(e.near+"_41m",near,far,center,41,count)
		for d in [39.95,40.05]:await photograph(e.near+"_boundary_"+str(d),near,far,center,d,int(e.near_triangles) if d<40 else count)
		# Same orthographic framing at the game's wide yaw; includes back/side silhouettes.
		vp.size=Vector2i(400,600)
		for yaw in [60.0,150.0,240.0]:
			camera.rotation_degrees=Vector3(-43,yaw,0)
			await photograph(e.near+"_yaw"+str(int(yaw))+"_39m",near,far,center,39,int(e.near_triangles))
			await photograph(e.near+"_yaw"+str(int(yaw))+"_41m",near,far,center,41,count)
		near.queue_free();far.queue_free();await frames(2);vp.size=Vector2i(360,800)
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};check(report.renderer.method=="mobile","Godot Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open("res://../lod-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n");print("COAST_PLANTS_LOD ",report.passed," ",report.checks.size()," checks")
	get_tree().quit(0 if report.passed else 1)
