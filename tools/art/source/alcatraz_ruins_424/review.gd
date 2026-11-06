extends Node
var island: AlcatrazIsland
var vp: SubViewport
var stats: Dictionary
var proposal: Dictionary
var details:=Node3D.new()
var report:={"checks":[],"assets":{},"captures":[],"gallery":[],"ui_conflicts":[]}
const ROOT:="res://assets/landmarks/alcatraz_island/"
func _ready() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func frames(n: int) -> void:
	for i in n:await get_tree().process_frame
func photo(name: String) -> void:
	await frames(6);RenderingServer.force_draw(true)
	var image:=vp.get_texture().get_image();check(image.save_png("res://../"+name+".png")==OK,"saved "+name)
	report.captures.append({"name":name,"size":[image.get_width(),image.get_height()],"camera":str(vp.get_camera_3d().global_transform),"width_m":vp.get_camera_3d().size,"player":str(island._player.position)})
func at(p: Dictionary) -> Transform3D:return Transform3D(Basis(Vector3.UP,deg_to_rad(float(p.rotation_degrees[1]))),Vector3(p.position[0],p.position[1],p.position[2]))
func focus(pos: Vector3) -> void:
	island._player.position=pos;island._focus=island._follow_target();island._following=true;island._overview=false;island.camera_pan.reset(1.0);island._update_camera()
func bounds_screen(p: Dictionary) -> Rect2:
	var t:=at(p);var mesh: Mesh=island._mesh(str(p.asset));var box:=mesh.get_aabb();var rect:=Rect2(island._camera.unproject_position(t.origin),Vector2.ZERO)
	for i in 8:rect=rect.expand(island._camera.unproject_position(t*box.get_endpoint(i)))
	return rect
func run() -> void:
	stats=JSON.parse_string(FileAccess.get_file_as_string("res://ruin_details_stats.json")).assets;proposal=JSON.parse_string(FileAccess.get_file_as_string("res://ruin_details_placements.json"))
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var display:=TextureRect.new();display.texture=vp.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);display.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(display)
	island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
	for i in 300:
		await get_tree().physics_frame
		if island.navigation_ready() and not island._rig.is_busy():break
	check(island.navigation_ready() and not island._rig.is_busy(),"v6 navigation and game avatar ready")
	island.set_process(false)
	var paint:=StandardMaterial3D.new();paint.vertex_color_use_as_albedo=true;paint.vertex_color_is_srgb=false;paint.roughness=.9;paint.metallic_specular=.18
	for name in stats:
		var mesh: Mesh=island._mesh(name);var arrays:=mesh.surface_get_arrays(0);var triangles: int=arrays[Mesh.ARRAY_INDEX].size()/3
		check(mesh.get_surface_count()==1 and triangles==stats[name].triangles and triangles<=400,name+": current mesh one surface / <=400 triangles")
		var b: Array=stats[name].bounds
		check(mesh.get_aabb().position.is_equal_approx(Vector3(b[0][0],b[0][1],b[0][2])) and mesh.get_aabb().end.is_equal_approx(Vector3(b[1][0],b[1][1],b[1][2])),name+": imported AABB matches")
		var cfg:=ConfigFile.new();assert(cfg.load(ROOT+name+".glb.import")==OK);var cache: String=cfg.get_value("remap","path")
		check(FileAccess.get_file_as_string(cache.trim_suffix(".scn")+".md5").contains('source_md5="'+FileAccess.get_md5(ROOT+name+".glb")+'"'),name+": cache source hash current")
		check(str(cfg.get_value("remap","uid","")).begins_with("uid://") and cfg.get_value("params","gltf/texture_map_mode")==1,name+": Godot UID/import contract")
		report.assets[name]={"triangles":triangles,"surfaces":mesh.get_surface_count(),"sha256":FileAccess.get_sha256(ROOT+name+".glb"),"uid":cfg.get_value("remap","uid")}
	details.name="ZhaoyunRuinsDetails";island.add_child(details)
	for name in stats:
		var points: Array=proposal.instances.filter(func(p):return p.asset==name)
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=island._mesh(name);mm.instance_count=points.size()
		for i in points.size():mm.set_instance_transform(i,at(points[i]))
		var node:=MultiMeshInstance3D.new();node.name=name;node.multimesh=mm;node.material_override=paint;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;details.add_child(node)
	check(details.get_child_count()==5,"five MultiMesh batches")
	# Only the blank plaque and wall vines exceed 0.8m; scan them against the v6 tall-object UI mask.
	var route:=PackedVector3Array();var last:=Vector3(proposal.route[0][0],proposal.route[0][1],proposal.route[0][2])
	for point in proposal.route.slice(1):
		var goal:=Vector3(point[0],point[1],point[2]);var path:=island.find_path(last,goal);check(not path.is_empty() and path[-1].distance_to(goal)<.3,"unchanged route reaches "+str(goal))
		for p in path:
			if route.is_empty() or route[-1].distance_to(p)>.001:route.append(p)
		last=goal
	var masks: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://hud_contract.json")).reserved_rects;var samples:=0
	for i in range(1,route.size()):
		var steps:=maxi(1,ceili(route[i-1].distance_to(route[i])/.5))
		for j in steps:
			var pos:=route[i-1].lerp(route[i],float(j)/steps);focus(pos);samples+=1
			for p in proposal.instances:
				if p.asset not in ["alc_ruin_plaque","alc_ruin_vine"]:continue
				var rect:=bounds_screen(p)
				for key in masks:
					var m: Array=masks[key]
					if rect.intersects(Rect2(m[0],m[1],m[2],m[3])):report.ui_conflicts.append({"name":p.name,"asset":p.asset,"mask":key,"player":str(pos)})
	report.route_ui_samples=samples;check(report.ui_conflicts.is_empty(),"new high details clear native action/quickbar masks")
	focus(Vector3(8,3.25,7.5));await photo("native_route_43")
	# Local inspection camera, distinct from native route view; original ruins position preserved.
	island._hud.visible=false;var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.near=.05;cam.far=150;vp.add_child(cam);cam.rotation_degrees=Vector3(-43,-35,0);cam.make_current()
	vp.size=Vector2i(1500,1050);cam.size=15;cam.position=Vector3(17.4,4.9,4.9)+cam.basis.z*40
	await photo("ruins_area_43")
	# Smaller inspection captures show attached leaves and the flat debris shapes.
	vp.size=Vector2i(1200,900);cam.size=7.2;cam.position=Vector3(16.6,4.2,5.65)+cam.basis.z*40
	await photo("ruins_details_close")
	for zone in island.zones.values():zone.visible=false
	details.visible=false;island.get_node("Sea").visible=false
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(200,200);floor.mesh=plane;var fm:=StandardMaterial3D.new();fm.albedo_color=Color("CCC9BC");fm.roughness=.95;floor.material_override=fm;floor.position=Vector3(0,-.006,38);island.add_child(floor)
	vp.size=Vector2i(1500,950);cam.global_basis=island._camera.global_basis;cam.size=11.5;cam.position=Vector3(0,.60,38)+cam.basis.z*40
	var points={"alc_ruin_arch":Vector3(-4,0,38),"alc_ruin_rubble":Vector3(-1.6,0,38.5),"alc_ruin_vine":Vector3(.35,0,38),"alc_ruin_flowers":Vector3(1.85,0,38.5),"alc_ruin_plaque":Vector3(3.2,0,38)}
	for name in points:
		var n:=MeshInstance3D.new();n.mesh=island._mesh(name);n.material_override=paint;n.position=points[name];island.add_child(n)
		report.gallery.append({"asset":name,"label_at":str(cam.unproject_position(n.position+Vector3(0,0,.85)))})
	island._player.position=Vector3(4.6,0,38);island._rig.rotation.y=.2;report.avatar_label_at=str(cam.unproject_position(island._player.position+Vector3(0,0,.65)))
	await photo("five_details_avatar")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};check(report.renderer.method=="mobile","Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open("res://../render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n");print("RUINS_RENDER ",report.passed," ",report.checks.size()," checks; UI conflicts ",report.ui_conflicts.size())
	get_tree().quit(0 if report.passed else 1)
