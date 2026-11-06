extends Node
var island: AlcatrazIsland
var vp: SubViewport
var stats: Dictionary
var proposal: Dictionary
var paint: Material
var report:={"checks":[],"assets":{},"captures":[],"replacements":[],"gallery":[]}
var original_batches:={}
var replacement_batches: Array[MultiMeshInstance3D]=[]
const KIT:="res://assets/landmarks/alcatraz_island/"
func _ready() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func frames(n: int) -> void:
	for i in n:await get_tree().process_frame
func photo(name: String) -> void:
	await frames(8);RenderingServer.force_draw(true)
	var image:=vp.get_texture().get_image();check(image.save_png("res://../"+name+".png")==OK,"capture "+name)
	var cam:=vp.get_camera_3d()
	report.captures.append({"name":name,"size":[image.get_width(),image.get_height()],"camera":str(cam.global_transform),"width_m":cam.size,"pitch":cam.rotation_degrees.x,"yaw":cam.rotation_degrees.y,"player":str(island._player.position),"triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
func replace_trees() -> void:
	var removed:=0
	for node in island.batch_nodes:
		var old_asset:=""
		for a in ["alc_tree_a","alc_tree_b"]:
			if node.multimesh.mesh==island._mesh(a):old_asset=a
		if old_asset.is_empty():continue
		original_batches[node]=node.multimesh
		var keep: Array[Transform3D]=[]
		for i in node.multimesh.instance_count:
			var t: Transform3D=node.multimesh.get_instance_transform(i);var drop:=false
			for p in proposal.replacements:
				if p.old_asset==old_asset and t.origin.distance_to(AlcatrazIsland._vec(p.position))<.001:
					check(t.is_equal_approx(island._transform_of(p)),p.source_name+": original transform retained")
					drop=true;removed+=1;break
			if not drop:keep.append(t)
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=node.multimesh.mesh;mm.instance_count=keep.size()
		for i in keep.size():mm.set_instance_transform(i,keep[i])
		node.multimesh=mm;node.visible=not keep.is_empty()
	check(removed==proposal.replacements.size(),"exactly the 12 named old instances removed")
	for asset in ["alc_tree_c","alc_tree_d"]:
		for zone in ["TerraceZone","SummitZone"]:
			var points: Array=proposal.replacements.filter(func(p):return p.asset==asset and p.zone==zone)
			if points.is_empty():continue
			var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=island._mesh(asset);mm.instance_count=points.size()
			for i in points.size():mm.set_instance_transform(i,island._transform_of(points[i]))
			var node:=MultiMeshInstance3D.new();node.name=asset+"_review_batch";node.multimesh=mm;node.material_override=paint;island.zones[zone].add_child(node);replacement_batches.append(node)
	check(replacement_batches.size()==2,"two new type/zone batches, no duplicate trees")
func run() -> void:
	stats=JSON.parse_string(FileAccess.get_file_as_string("res://trees_cd_stats.json")).assets
	proposal=JSON.parse_string(FileAccess.get_file_as_string("res://trees_cd_replacements.json"))
	vp=SubViewport.new();vp.size=Vector2i(720,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var display:=TextureRect.new();display.texture=vp.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);display.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(display)
	island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
	for i in 300:
		await get_tree().physics_frame
		if island.navigation_ready() and not island._rig.is_busy():break
	check(island.navigation_ready() and not island._rig.is_busy(),"published v7 island / real game avatar ready")
	island.set_process(false);island._hud.visible=false;paint=island.batch_nodes[0].material_override
	for name in stats:
		var mesh: Mesh=island._mesh(name);var count: int=mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3
		check(mesh.get_surface_count()==1 and count==stats[name].triangles and count<=(120 if name.ends_with("_far") else 500),name+": imported budget / one surface")
		var cfg:=ConfigFile.new();assert(cfg.load(KIT+name+".glb.import")==OK)
		check(str(cfg.get_value("remap","uid","")).begins_with("uid://") and cfg.get_value("params","gltf/texture_map_mode")==1,name+": Godot UID / import")
		var cache: String=cfg.get_value("remap","path")
		check(FileAccess.get_file_as_string(cache.trim_suffix(".scn")+".md5").contains('source_md5="'+FileAccess.get_md5(KIT+name+".glb")+'"'),name+": actual current import")
		report.assets[name]={"sha256":FileAccess.get_sha256(KIT+name+".glb"),"triangles":count,"uid":cfg.get_value("remap","uid")}
	for p in proposal.replacements:
		var old: Array=island.layout.placements.filter(func(x):return x.name==p.source_name)
		check(old.size()==1 and old[0].asset==p.old_asset and island._transform_of(old[0]).is_equal_approx(island._transform_of(p)),p.source_name+": matches published layout")
		var root:=AlcatrazIsland._vec(p.position);var nearest:=NavigationServer3D.map_get_closest_point(island._nav_map,root)
		var horizontal:=Vector2(nearest.x-root.x,nearest.z-root.z).length()
		check(absf(nearest.y-root.y)>=.25 or horizontal>=1.1,p.source_name+": original root clears navigation")
		report.replacements.append({"source_name":p.source_name,"new_asset":p.asset,"root":p.position,"nearest_navigation":str(nearest),"horizontal_clearance_m":horizontal})
	# Matched inspection view of the east slope; original scene lighting and terrain.
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.near=.05;cam.far=200;vp.add_child(cam);cam.make_current()
	cam.rotation_degrees=Vector3(-43,35,0);cam.size=27;cam.position=Vector3(18,9,-4)+cam.basis.z*60
	island._player.position=Vector3(8,5.5,3);island._rig.rotation.y=.2
	await photo("slope_before")
	replace_trees()
	await photo("slope_after")
	check(report.captures[0].camera==report.captures[1].camera,"before/after identical camera")
	# Separate full-size prototype lineup under precisely the same environment.
	for zone in island.zones.values():zone.visible=false
	island.get_node("Sea").visible=false
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(200,200);floor.mesh=plane
	var fm:=StandardMaterial3D.new();fm.albedo_color=Color("D9D5C7");fm.roughness=.95;floor.material_override=fm;floor.position=Vector3(0,-.008,38);island.add_child(floor)
	vp.size=Vector2i(1500,950);cam.rotation_degrees=Vector3(-43,0,0);cam.size=24;cam.position=Vector3(.4,3.2,38)+cam.basis.z*50
	var points={"alc_tree_a":Vector3(-8,0,38),"alc_tree_b":Vector3(-2.2,0,38),"alc_tree_c":Vector3(3.1,0,38),"alc_tree_d":Vector3(7.4,0,38)}
	for name in points:
		var n:=MeshInstance3D.new();n.mesh=island._mesh(name);n.material_override=paint;n.position=points[name];island.add_child(n)
		report.gallery.append({"asset":name,"position":str(n.position),"label_at":str(cam.unproject_position(n.position+Vector3(0,0,.9))),"height_m":n.mesh.get_aabb().size.y})
	island._player.position=Vector3(10.6,0,38);island._rig.rotation.y=.2
	check(island._rig.scale.is_equal_approx(Vector3.ONE),"game avatar original 1.75m scale")
	report.avatar_label_at=str(cam.unproject_position(island._player.position+Vector3(0,0,.9)))
	await photo("four_trees_avatar")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};check(report.renderer.method=="mobile","Vulkan Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open("res://../render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TREE_CD_RENDER ",report.passed," ",report.checks.size()," checks")
	get_tree().quit(0 if report.passed else 1)
