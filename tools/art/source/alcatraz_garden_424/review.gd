extends Node
var island: AlcatrazIsland
var vp: SubViewport
var stats: Dictionary
var proposal: Dictionary
var garden := Node3D.new()
var batch_nodes: Array = []
var report := {"checks":[],"assets":{},"captures":[],"gallery":[],"focus_views":[],"ui_conflicts":[]}
const ROOT := "res://assets/landmarks/alcatraz_island/"
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
func transform_of(p: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,deg_to_rad(float(p.rotation_degrees[1]))),Vector3(p.position[0],p.position[1],p.position[2]))
func bounds_screen(p: Dictionary) -> Rect2:
	var transform:=transform_of(p);var mesh: Mesh=island._mesh(str(p.asset));var rect:=Rect2(island._camera.unproject_position(transform.origin),Vector2.ZERO)
	var box:=mesh.get_aabb()
	for i in 8:rect=rect.expand(island._camera.unproject_position(transform*box.get_endpoint(i)))
	return rect
func focus(at: Vector3) -> void:
	island._player.position=at;island._focus=island._follow_target();island._following=true;island._overview=false;island.camera_pan.reset(1.0);island._update_camera()
func build_garden() -> void:
	garden.name="ZhaoyunGardenProposal";island.add_child(garden)
	var paint:=StandardMaterial3D.new();paint.vertex_color_use_as_albedo=true;paint.vertex_color_is_srgb=false;paint.roughness=.9;paint.metallic_specular=.18
	var groups:={}
	for p in proposal.instances:
		var key: String=str(p.zone)+"/"+str(p.asset)
		if not groups.has(key):groups[key]=[]
		groups[key].append(p)
	for key in groups:
		var items: Array=groups[key];var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=island._mesh(items[0].asset);mm.instance_count=items.size()
		for i in items.size():mm.set_instance_transform(i,transform_of(items[i]))
		var node:=MultiMeshInstance3D.new();node.name=key.replace("/","_");node.multimesh=mm;node.material_override=paint;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;garden.add_child(node);batch_nodes.append(node)
	report.added_batches=groups.size();report.added_instances=proposal.instances.size()
func run() -> void:
	stats=JSON.parse_string(FileAccess.get_file_as_string("res://garden_stats.json")).assets;proposal=JSON.parse_string(FileAccess.get_file_as_string("res://garden_placements.json"))
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var display:=TextureRect.new();display.texture=vp.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);display.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(display)
	island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
	for i in 300:
		await get_tree().physics_frame
		if island.navigation_ready() and not island._rig.is_busy():break
	check(island.navigation_ready() and not island._rig.is_busy(),"v6 navigation and actual game avatar ready")
	check(absf(island._camera.rotation_degrees.x+43)<.01 and is_equal_approx(island._camera.size,6.72),"native default 43deg / 6.72m")
	island.set_process(false)
	for name in stats:
		var mesh: Mesh=island._mesh(name);var a:=mesh.surface_get_arrays(0);var triangles: int=a[Mesh.ARRAY_INDEX].size()/3
		check(mesh.get_surface_count()==1 and triangles==int(stats[name].triangles) and triangles<=int(stats[name].triangle_limit),name+": imported one surface / correct triangle budget")
		var b: Array=stats[name].bounds
		check(mesh.get_aabb().position.is_equal_approx(Vector3(b[0][0],b[0][1],b[0][2])) and mesh.get_aabb().end.is_equal_approx(Vector3(b[1][0],b[1][1],b[1][2])),name+": current AABB")
		var cfg:=ConfigFile.new();assert(cfg.load(ROOT+name+".glb.import")==OK)
		var cache: String=cfg.get_value("remap","path");check(FileAccess.get_file_as_string(cache.trim_suffix(".scn")+".md5").contains('source_md5="'+FileAccess.get_md5(ROOT+name+".glb")+'"'),name+": imported cache matches current source")
		check(str(cfg.get_value("remap","uid","")).begins_with("uid://") and cfg.get_value("params","gltf/texture_map_mode")==1,name+": Godot UID and texture map mode")
		report.assets[name]={"triangles":triangles,"surfaces":mesh.get_surface_count(),"uid":cfg.get_value("remap","uid"),"sha256":FileAccess.get_sha256(ROOT+name+".glb")}
	build_garden()
	# Review every proposed look-point with the real default follow camera.
	for group in proposal.groups:
		focus(Vector3(group.walk_station[0],group.walk_station[1],group.walk_station[2]))
		var visible_count:=0
		for p in proposal.instances:
			if p.group!=group.name:continue
			var rect:=bounds_screen(p)
			if rect.intersects(Rect2(12,70,336,620)):visible_count+=1
		report.focus_views.append({"group":group.name,"visible_new_pieces":visible_count,"station":group.walk_station})
		check(visible_count>0,"garden colour visible at "+str(group.name))
	# Follow the actual navigable route and reserve the v6 tall-object HUD masks.
	var route:=PackedVector3Array();var last:=Vector3(proposal.route[0][0],proposal.route[0][1],proposal.route[0][2])
	for row in proposal.route.slice(1):
		var goal:=Vector3(row[0],row[1],row[2]);var path:=island.find_path(last,goal)
		check(not path.is_empty() and path[-1].distance_to(goal)<.3,"original route path reaches "+str(goal))
		for p in path:
			if route.is_empty() or route[-1].distance_to(p)>.001:route.append(p)
		last=goal
	var masks: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://hud_contract.json")).reserved_rects
	var sample_count:=0
	for i in range(1,route.size()):
		var length:=route[i-1].distance_to(route[i]);var steps:=maxi(1,ceili(length/.5))
		for j in steps:
			var at:=route[i-1].lerp(route[i],float(j)/steps);focus(at);sample_count+=1
			for p in proposal.instances:
				if p.asset!="alc_planter":continue # Low flowers/hedges have no tall silhouettes.
				var rect:=bounds_screen(p)
				for key in masks:
					var m: Array=masks[key]
					if rect.intersects(Rect2(m[0],m[1],m[2],m[3])):report.ui_conflicts.append({"asset":p.name,"mask":key,"player":str(at)})
	report.route_ui_samples=sample_count;check(report.ui_conflicts.is_empty(),"new planters clear v6 action/quickbar masks along the whole route")
	for row in [["opening",Vector3(-22,1,19)],["terrace_1",Vector3(-12,3.25,7.5)],["terrace_2",Vector3(-5.5,5.5,3)],["terrace_3",Vector3(1,7.75,-1.5)]]:
		focus(row[1]);await photo(row[0]+"_43")
	# Wide island view documents placement rhythm; don't alter production island lighting/layout.
	island._hud.visible=false;var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.near=.05;cam.far=150;vp.add_child(cam);cam.global_basis=island._camera.global_basis;cam.make_current()
	vp.size=Vector2i(1200,1400);cam.size=56;cam.position=Vector3(-6,5,1)+cam.basis.z*65
	await photo("terraces_overview")
	# Real-scale five-piece inspection with the game avatar.
	for zone in island.zones.values():zone.visible=false
	garden.visible=false;island.get_node("Sea").visible=false
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(200,200);floor.mesh=plane;var fm:=StandardMaterial3D.new();fm.albedo_color=Color("D9D4C7");fm.roughness=.95;floor.material_override=fm;floor.position=Vector3(0,-.006,38);island.add_child(floor)
	var paint:=StandardMaterial3D.new();paint.vertex_color_use_as_albedo=true;paint.vertex_color_is_srgb=false;paint.roughness=.9;paint.metallic_specular=.18
	vp.size=Vector2i(1500,850);cam.size=7.8;cam.position=Vector3(0,.50,38)+cam.basis.z*35
	var names: Array=stats.keys()
	for i in names.size():
		var n:=MeshInstance3D.new();n.mesh=island._mesh(names[i]);n.material_override=paint;n.position=Vector3(-3.05+i*1.20,0,38);island.add_child(n)
		report.gallery.append({"asset":names[i],"label_at":str(cam.unproject_position(n.position+Vector3(0,0,.65)))})
	island._player.position=Vector3(3.10,0,38);island._rig.rotation.y=.2
	report.avatar_label_at=str(cam.unproject_position(island._player.position+Vector3(0,0,.65)))
	await photo("five_props_avatar")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};check(report.renderer.method=="mobile","Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open("res://../render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("ALCATRAZ_GARDEN_RENDER ",report.passed," ",report.checks.size()," checks; UI samples ",sample_count)
	get_tree().quit(0 if report.passed else 1)
