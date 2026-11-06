extends Node
var island: AlcatrazIsland
var vp: SubViewport
var stats: Dictionary
var report:={"checks":[],"assets":{},"captures":[],"gallery":[]}
const ROOT="res://assets/landmarks/alcatraz_island/"
func _ready() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func frames(n: int) -> void:
	for i in n:await get_tree().process_frame
func box_of(root: Node3D) -> AABB:
	var found:=root.find_children("*","MeshInstance3D",true,false)
	if root is MeshInstance3D:found.push_front(root)
	var box:=AABB();var first:=true
	for node in found:
		if node.mesh==null or "shadow" in str(node.name).to_lower():continue
		var aabb: AABB=node.get_aabb();var transform: Transform3D=root.global_transform.affine_inverse()*node.global_transform
		for i in 8:
			var p:=transform*aabb.get_endpoint(i)
			if first:box=AABB(p,Vector3.ZERO);first=false
			else:box=box.expand(p)
	return box
func screen_rect(root: Node3D,cam: Camera3D) -> Array:
	var box:=box_of(root);var rect:=Rect2(cam.unproject_position(root.global_position),Vector2.ZERO)
	for i in 8:rect=rect.expand(cam.unproject_position(root.to_global(box.get_endpoint(i))))
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
func capture(name: String) -> void:
	await frames(8);RenderingServer.force_draw(true)
	var pic:=vp.get_texture().get_image();check(pic.save_png("res://../"+name+".png")==OK,"capture "+name)
	report.captures.append({"name":name,"size":[pic.get_width(),pic.get_height()],"camera":str(vp.get_camera_3d().global_transform),"width_m":vp.get_camera_3d().size,"pitch":vp.get_camera_3d().rotation_degrees.x})
func metrics() -> Dictionary:
	var triangles:=0;var surfaces:=0
	for node in island.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null:continue
		surfaces+=node.mesh.get_surface_count()
		for i in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(i)
			triangles+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size())/3
	for node in island.batch_nodes:
		surfaces+=node.multimesh.mesh.get_surface_count()
		for i in node.multimesh.mesh.get_surface_count():
			var arrays: Array=node.multimesh.mesh.surface_get_arrays(i)
			triangles+=arrays[Mesh.ARRAY_INDEX].size()/3*node.multimesh.instance_count
	return {"resident_triangles":triangles,"resident_surfaces":surfaces,"visible_triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
func run() -> void:
	stats=JSON.parse_string(FileAccess.get_file_as_string("res://prop_stats.json")).assets
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var display:=TextureRect.new();display.texture=vp.get_texture();display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(display)
	island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
	for i in 300:
		await get_tree().physics_frame
		if island.navigation_ready() and not island._rig.is_busy():break
	check(island.navigation_ready(),"Marco blockout navigation ready")
	check(not island._rig.is_busy(),"real avatar fully assembled")
	check(island._rig.scale.is_equal_approx(Vector3.ONE),"avatar retains game scale 1.0")
	var avatar_box:=box_of(island._rig)
	check(absf(avatar_box.size.y-1.75)<.08,"actual avatar height approximately 1.75 m")
	report.avatar_aabb=str(avatar_box)
	check(is_equal_approx(island._camera.size,6.72) and absf(island._camera.rotation_degrees.x+43)<.01,"native opening 43deg / 6.72m")
	check(island._player.position.is_equal_approx(Vector3(-22,1,19)),"original dock spawn retained")
	for name in stats:
		var mesh: Mesh=island._mesh(name)
		check(mesh.get_surface_count()==1,name+": single mesh surface")
		var tris: int=mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3
		check(tris==int(stats[name].triangles) and tris<=int(stats[name].triangle_limit),name+": current imported triangles / budget")
		var a: Array=stats[name].bounds
		check(mesh.get_aabb().position.is_equal_approx(Vector3(a[0][0],a[0][1],a[0][2])) and mesh.get_aabb().end.is_equal_approx(Vector3(a[1][0],a[1][1],a[1][2])),name+": imported bounds match file")
		var cfg:=ConfigFile.new();check(cfg.load(ROOT+name+".glb.import")==OK,name+": .import present")
		check(str(cfg.get_value("remap","uid","")).begins_with("uid://") and cfg.get_value("params","gltf/texture_map_mode")==1,name+": Godot UID / texture map mode")
		var cache: String=cfg.get_value("remap","path")
		check(FileAccess.get_file_as_string(cache.trim_suffix(".scn")+".md5").contains('source_md5="'+FileAccess.get_md5(ROOT+name+".glb")+'"'),name+": import cache current")
		report.assets[name]={"triangles":tris,"uid":cfg.get_value("remap","uid"),"sha256":FileAccess.get_sha256(ROOT+name+".glb")}
	var count:=0;var slopes:=0
	for batch in island.batch_nodes:
		count+=batch.multimesh.instance_count
		var m:=batch.material_override as StandardMaterial3D
		check(m.vertex_color_use_as_albedo and not m.vertex_color_is_srgb and m.metallic==0,"MultiMesh farm-compatible linear vertex colour: "+str(batch.name))
	for p in island.layout.placements:
		if p.has("basis_columns") and str(p.asset)=="alc_rail_straight":
			var t: Transform3D=island._transform_of(p)
			check(t.basis.y.is_equal_approx(Vector3.UP),"sloped rail uprights remain vertical: "+str(p.name));slopes+=1
	check(count==442 and slopes==20,"all 442 repeated placements loaded, including 20 sloped rail segments")
	await capture("opening_43")
	report.opening_metrics=metrics();check(report.opening_metrics.resident_triangles<=300000 and report.opening_metrics.resident_surfaces<=80,"assembled scene resident geometry budget")
	island.set_process(false)
	# Extra integration close-up at a real staircase, unchanged layout and lighting.
	island._hud.visible=false
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.near=.05;cam.far=150;vp.add_child(cam);cam.global_basis=island._camera.global_basis;cam.make_current()
	vp.size=Vector2i(1200,900);cam.size=8.8;cam.position=Vector3(-22,2.2,10)+cam.basis.z*40
	await capture("rail_stair_detail")
	# Same light/environment, separate flat inspection platform; every prop remains scale 1.
	for zone in island.zones.values():zone.visible=false
	island.get_node("Sea").visible=false
	var stage:=Node3D.new();island.add_child(stage)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(200,200);floor.mesh=plane;var mat:=StandardMaterial3D.new();mat.albedo_color=Color("D9D4C7");mat.roughness=.95;floor.material_override=mat;floor.position=Vector3(0,-.008,38);stage.add_child(floor)
	var paint:=StandardMaterial3D.new();paint.vertex_color_use_as_albedo=true;paint.vertex_color_is_srgb=false;paint.roughness=.9;paint.metallic_specular=.18
	var points={"alc_tree_a":Vector3(-7,0,33),"alc_tree_b":Vector3(0,0,33),"alc_lamp":Vector3(5,0,33),"alc_bench":Vector3(-7,0,39),"alc_bin":Vector3(-3.5,0,39),"alc_sign":Vector3(-.4,0,39),"alc_flowerbed":Vector3(4,0,39),"alc_rail_straight":Vector3(-6,0,43.2),"alc_rail_corner":Vector3(-1,0,43.2),"alc_curb":Vector3(3,0,43.2)}
	vp.size=Vector2i(1500,1450);cam.size=23;cam.position=Vector3(-.8,2.4,37.7)+cam.basis.z*45
	for name in points:
		var node:=MeshInstance3D.new();node.mesh=island._mesh(name);node.material_override=paint;node.position=points[name];stage.add_child(node)
		report.gallery.append({"asset":name,"position":str(node.position),"screen_rect":screen_rect(node,cam),"label_at":str(cam.unproject_position(node.position+Vector3(0,0,.95)))})
	island._player.position=Vector3(8.0,0,33);island._rig.rotation.y=.2
	report.gallery_avatar={"height_m":avatar_box.size.y,"label_at":str(cam.unproject_position(island._player.position+Vector3(0,0,.6))),"screen_rect":screen_rect(island._rig,cam)}
	await capture("all_props_avatar")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open("res://../render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("ALCATRAZ_PROPS_RENDER ",report.passed," ",report.checks.size()," checks")
	get_tree().quit(0 if report.passed else 1)
