extends Node
## Real Mobile-rendered scene, deterministic art review and navigation checks.
var scene: AlcatrazIsland
var viewport: SubViewport
var results := {}
var destination: String
var failures: Array[String] = []
var metrics := {}
var route_distance := 0.0
var route_capture_at := 0.0
var route_capture_index := 0
var hud_boxes: Array = []
var hud_regions := {}
var hud_samples := 0
var hud_next_distance := 0.0
var hud_failures: Array = []

func check(key: String, passed: bool, evidence = null) -> void:
	results[key] = {"passed":passed, "evidence":evidence}
	if not passed:
		failures.append(key)
		push_error("ALCATRAZ_CHECK " + key + " " + str(evidence))

func _ready() -> void:
	print("ALCATRAZ_PHASE ready")
	destination = OS.get_environment("ALCATRAZ_REVIEW")
	if destination.is_empty():
		scene = load("res://scenes/landmark/alcatraz_island.tscn").instantiate()
		add_child(scene)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	viewport = SubViewport.new()
	viewport.size = Vector2i(360,800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	scene = load("res://scenes/landmark/alcatraz_island.tscn").instantiate()
	viewport.add_child(scene)
	print("ALCATRAZ_PHASE scene added")
	for i in 240:
		await get_tree().physics_frame
		if scene.navigation_ready(): break
	print("ALCATRAZ_PHASE nav ready ",scene.navigation_ready())
	check("navigation_ready",scene.navigation_ready())
	prepare_hud_audit()
	for i in 120:
		await get_tree().process_frame
		if not scene._rig.is_busy():break
	for i in 4:await get_tree().process_frame
	if OS.get_environment("ALCATRAZ_TOP_ONLY")=="1":
		scene.set_process(false)
		await top_layout_photo()
		var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(destination.path_join("verification.json")))
		baseline.view_metrics["04-top-layout"]=metrics["04-top-layout"]
		for key in results:
			if str(key).begins_with("04-top-layout"):baseline[key]=results[key]
		FileAccess.open(destination.path_join("verification.json"),FileAccess.WRITE).store_string(JSON.stringify(baseline,"\t")+"\n")
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	if OS.get_environment("ALCATRAZ_MOVIE")=="1":
		await colour_walk_movie()
		return
	if OS.get_environment("ALCATRAZ_SWEEP")=="1":
		await budget_sweep()
		return
	check("renderer", RenderingServer.get_current_rendering_method() == "mobile", RenderingServer.get_video_adapter_name())
	check("no_network_autoload", get_node_or_null("/root/Net") == null)
	check("farm_pitch",absf(scene._camera.rotation_degrees.x+43)<.01,scene._camera.rotation_degrees)
	check("farm_scale",is_equal_approx(scene._camera.size,6.72),scene._camera.size)
	check("spawn_on_navigation",NavigationServer3D.map_get_closest_point(scene._nav_map,scene._player.position).distance_to(scene._player.position)<.05)
	check("separate_navigation_map",scene._nav_map != scene.get_world_3d().navigation_map)
	print("ALCATRAZ_PHASE opening")
	await photograph("01-opening")
	check("three_loading_zones",scene.zones.size()==4 and ["DockZone","TerraceZone","SummitZone"].all(func(z): return scene.zones.has(z)))
	for zone_name in scene.layout.zones:
		check("zone_navigation_"+str(zone_name),scene.zones[zone_name].get_node_or_null("Navigation") is NavigationRegion3D)
	check("far_loading_zone",scene.zones.has("FarZone"))
	check("avatar_farm_scale_unchanged",scene._rig.scale.is_equal_approx(Vector3.ONE))
	var avatar_box := AABB()
	var first := true
	for mesh_node in scene._rig.find_children("*","MeshInstance3D",true,false):
		if mesh_node.mesh == null or mesh_node.name.to_lower().contains("shadow"): continue
		var box_: AABB = mesh_node.get_aabb()
		var transform_: Transform3D = scene._rig.global_transform.affine_inverse() * mesh_node.global_transform
		for k in 8:
			var point_: Vector3 = transform_ * box_.get_endpoint(k)
			if first:
				avatar_box = AABB(point_,Vector3.ZERO)
				first=false
			else: avatar_box=avatar_box.expand(point_)
	check("avatar_175cm",absf(avatar_box.size.y-1.75)<.08,str(avatar_box))
	results["avatar_projected_nominal_height_px"] = 1.75*cos(deg_to_rad(43))*360/6.72
	var live_surfaces := 0
	var live_triangles := 0
	for node in scene.find_children("*","MeshInstance3D",true,false):
		if node.mesh == null:continue
		live_surfaces += node.mesh.get_surface_count()
		for surface_index in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			var indices = arrays[Mesh.ARRAY_INDEX]
			live_triangles += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	check("live_surface_budget_including_avatar_and_scenery",live_surfaces<=80,live_surfaces)
	check("live_triangle_budget_including_avatar_and_scenery",live_triangles<=300000,live_triangles)
	for node in scene.batch_nodes:
		live_surfaces += node.multimesh.mesh.get_surface_count()
		for surface_index in node.multimesh.mesh.get_surface_count():
			var arrays: Array = node.multimesh.mesh.surface_get_arrays(surface_index)
			var indices = arrays[Mesh.ARRAY_INDEX]
			live_triangles += ((indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3) * node.multimesh.instance_count
	check("total_surface_budget_with_multimesh",live_surfaces<=80,live_surfaces)
	check("total_triangle_budget_with_multimesh",live_triangles<=300000,live_triangles)
	check("repeat_instancing",scene.batch_nodes.size()>0,scene.batch_nodes.size())
	check("offshore_anchor_20m",absf(float(scene.layout.far_anchor[2])-float(scene.layout.spawn[2])-20)<.01,scene.layout.far_anchor)
	check("tea_layout_contract",["camera","spawn","anchors","boundaries","walk_bounds","instances","lod_groups"].all(func(k):return scene.layout.has(k)))
	check("camera_contract",["position","target","size"].all(func(k):return scene.layout.camera.has(k)))
	var tree_count := 0
	var nature_counts := {}
	var unsupported: Array = []
	var encroaching: Array = []
	var wrong_owner: Array = []
	for p in scene.layout.instances:
		var is_tree: bool = str(p.asset).begins_with("alc_tree_")
		var is_liu: bool = p.asset in ["alc_rock_a","alc_rock_b","alc_rock_c","alc_shrub","alc_shrub_b","alc_grass_tuft"]
		if not is_tree and not is_liu:continue
		if is_tree:tree_count+=1
		nature_counts[p.asset]=int(nature_counts.get(p.asset,0))+1
		if p.get("owner","") != ("刘备" if is_liu else "赵云"):wrong_owner.append(p.name)
		var root := AlcatrazIsland._vec(p.position)
		var nearest := NavigationServer3D.map_get_closest_point(scene._nav_map,root)
		var clearance := 1.1 if is_tree else .65 if p.asset in ["alc_shrub","alc_shrub_b"] else .35
		if absf(nearest.y-root.y)<.25 and Vector2(nearest.x-root.x,nearest.z-root.z).length()<clearance:
			encroaching.append(p.name)
		if str(p.asset).begins_with("alc_rock_"):continue
		var ray := PhysicsRayQueryParameters3D.create(root+Vector3.UP*.08,root-Vector3.UP*.3)
		var support := scene.get_world_3d().direct_space_state.intersect_ray(ray)
		if support.is_empty() or absf(support.position.y-root.y)>.06:unsupported.append(p.name)
	check("twenty_to_thirty_instanced_trees",tree_count>=20 and tree_count<=30,tree_count)
	check("nature_owner_handoff",wrong_owner.is_empty(),wrong_owner)
	check("all_liu_prototypes_placed",["alc_rock_a","alc_rock_b","alc_rock_c","alc_shrub","alc_shrub_b","alc_grass_tuft"].all(func(k):return int(nature_counts.get(k,0))>0),nature_counts)
	check("vegetation_roots_on_terrain",unsupported.is_empty(),unsupported)
	check("vegetation_navigation_clearance",encroaching.is_empty(),encroaching)
	check("buildings_and_ferry_have_two_lods",scene.layout.lod_groups.size()==4 and scene.layout.lod_groups.all(func(g):return g.name in ["alc_museum","alc_lighthouse","alc_watertower","ferry"]))

	audit_garden_support()
	var corners_ok := true
	for p in [Vector2(0,0),Vector2(359,0),Vector2(0,799),Vector2(359,799)]:
		var hit = Plane(Vector3.UP,-.15).intersects_ray(scene._camera.project_ray_origin(p),scene._camera.project_ray_normal(p))
		corners_ok = corners_ok and hit != null and absf(hit.x)<256 and absf(hit.z)<256
	check("opening_sea_covers_corners",corners_ok)
	check("map_exit_visible",scene._exit_marker.visible,scene._exit_marker.position)
	# Walk and stop every 6.5 m for one default-camera screen, without teleporting.
	scene.set_process(false)
	await route_photo()
	# Walk the whole route through NavigationServer paths rather than teleporting for images.
	var path_lengths: Array[float] = []
	for i in range(1,scene.layout.walk_goals.size()):
		var goal := AlcatrazIsland._vec(scene.layout.walk_goals[i])
		scene.walk_to(goal)
		var length := 0.0
		for j in range(1,scene._path.size()):length += scene._path[j-1].distance_to(scene._path[j])
		path_lengths.append(length)
		check("route_%d_path"%i,scene._path.size()>1 and scene._path[-1].distance_to(goal)<.15,str(scene._path))
		# Fixed simulation steps accelerate QA only; these still call the actual walk/follow code.
		scene.set_process(false)
		for frame in 3600:
			var previous_position := scene._player.position
			scene._process(0.1)
			route_distance += previous_position.distance_to(scene._player.position)
			if route_distance>=hud_next_distance:
				var intrusion := hud_intrusions()
				hud_samples+=1
				if not intrusion.is_empty():hud_failures.append({"distance_m":route_distance,"intrusions":intrusion})
				hud_next_distance=route_distance+.5
			if route_distance>=route_capture_at:
				await route_photo()
			if scene._path_i>=scene._path.size(): break
		for frame in 90:scene._process(1.0/60.0)
		check("route_%d_arrived"%i,scene._player.position.distance_to(goal)<.15,str(scene._player.position))
		check("route_%d_follow"%i,scene._focus.distance_to(scene._follow_target())<.05,str(scene._focus))
		if i==1:await photograph("02-mid-hill")
		if i==scene.layout.walk_goals.size()-1:await photograph("03-visitor-center")
	results["walk_lengths_m"] = path_lengths
	var route_length := 0.0
	for length in path_lengths:route_length+=length
	check("route_about_120m",route_length>=110 and route_length<=130,route_length)
	var direct_path := scene.find_path(AlcatrazIsland._vec(scene.layout.spawn),AlcatrazIsland._vec(scene.layout.walk_goals[-1]))
	var direct_length := 0.0
	for k in range(1,direct_path.size()): direct_length+=direct_path[k-1].distance_to(direct_path[k])
	results["direct_spawn_to_museum_path_m"] = direct_length
	check("direct_route_reaches_museum",not direct_path.is_empty() and direct_path[-1].distance_to(AlcatrazIsland._vec(scene.layout.walk_goals[-1]))<.05)
	check("direct_route_about_120m",direct_length>=110 and direct_length<=130,direct_length)
	check("continuous_default_hud_clearance",hud_failures.is_empty(),{"samples":hud_samples,"failures":hud_failures})

	await route_photo(true)
	check("summit_height",absf(scene._player.position.y-10.0)<.05,scene._player.position.y)
	# Geometry collision exists at all three resting viewpoints; decorative assets have none.
	for key in scene.layout.review_points:
		var point := AlcatrazIsland._vec(scene.layout.review_points[key])
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.5)
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		check("floor_collision_"+key,not hit.is_empty(),str(hit.get("position")))
	for node in scene.mesh_nodes:
		if node.name.begins_with("Ferry") or node.name.begins_with("Gull"):
			check("decorative_"+node.name,node.find_children("*","CollisionObject3D",true,false).is_empty())
	var bad_floor: Array = []
	for polygon in scene.layout.navigation.polygons:
		var centre := Vector3.ZERO
		for index in polygon: centre += AlcatrazIsland._vec(scene.layout.navigation.vertices[index])
		centre /= float(polygon.size())
		var ray := PhysicsRayQueryParameters3D.create(centre+Vector3.UP*.5,centre-Vector3.UP*.5)
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or absf(hit.position.y-centre.y)>.20:
			bad_floor.append([str(centre),str(hit.get("position"))])
	check("all_nav_cells_physical_floor",bad_floor.is_empty(),bad_floor)
	# Outside sea taps terminate at nav, not on water; museum interior has no nav.
	var sea_nearest := NavigationServer3D.map_get_closest_point(scene._nav_map,Vector3(40,0,10))
	check("sea_not_walkable",sea_nearest.x<30,str(sea_nearest))
	var museum_nearest := NavigationServer3D.map_get_closest_point(scene._nav_map,Vector3(0,10,-13))
	check("museum_not_enterable",museum_nearest.z>=-8.01,str(museum_nearest))
	# Exercise the inherited gesture handlers on the actual scene.
	var before := scene._player.position
	var camera_before := scene._camera.position
	touch(Vector2(160,400),true,0)
	for i in 10:
		drag(Vector2(160+i*6,400+i*2),0)
		scene._process(1.0/60.0)
	touch(Vector2(214,418),false,0)
	for i in 60:scene._process(1.0/60.0)
	check("drag_moves_camera_without_walking",scene._camera.position.distance_to(camera_before)>.1 and scene._player.position.is_equal_approx(before))
	touch(Vector2(130,400),true,0)
	touch(Vector2(230,400),true,1)
	drag(Vector2(100,400),0)
	drag(Vector2(260,400),1)
	touch(Vector2(100,400),false,0)
	touch(Vector2(260,400),false,1)
	for i in 120:scene._process(1.0/60.0)
	check("pinch_changes_scale_without_walking",scene.camera_pan.zoom>1.01 and scene._player.position.is_equal_approx(before),scene.camera_pan.zoom)
	var retained_zoom := scene.camera_pan.zoom
	scene.walk_to(before)
	check("walking_keeps_zoom",is_equal_approx(retained_zoom,scene.camera_pan.zoom))
	scene.camera_pan.reset()
	scene._focus = scene._follow_target()
	scene._update_camera()
	var prior_camera := scene._camera.position
	scene.suspend()
	scene.resume()
	check("resume_preserves_view",scene._camera.position.is_equal_approx(prior_camera))
	var exited := [false]
	scene.exit_requested.connect(func():exited[0]=true)
	scene._exit_button.pressed.emit()
	check("map_exit_emits_request",exited[0])
	# Griffith-style +/- controls reach a strict 3x zoom-out limit.
	scene._player.position = AlcatrazIsland._vec(scene.layout.review_points.visitor_center)
	scene._focus = scene._follow_target()
	for i in 20:scene._zoom_buttons["ZoomOut"].pressed.emit()
	check("zoom_out_limit",absf(scene._camera.size-20.16)<.02,scene._camera.size)
	check("wide_oblique_angle",absf(scene._camera.rotation_degrees.y-60)<.01,scene._camera.rotation_degrees)
	await photograph("06-summit-zoom-out")
	# Pixel control catches visibility-range holes that projection-only checks miss.
	var with_tower := viewport.get_texture().get_image()
	var tower_nodes: Array[MeshInstance3D] = []
	for node in scene.mesh_nodes:
		if node.name.begins_with("AlcLighthouse"):
			tower_nodes.append(node)
			node.visible=false
	for i in 4:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var without_tower := viewport.get_texture().get_image()
	var changed := 0
	for y in range(0,340):
		for x in range(0,130):
			var a := with_tower.get_pixel(x,y)
			var b := without_tower.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.05:changed+=1
	check("wide_lighthouse_rendered_pixels",changed>100,changed)
	for node in tower_nodes:node.visible=true
	for i in 4:await get_tree().process_frame
	var front_visible := 0
	for x in range(-20,21):
		var point := scene._camera.unproject_position(Vector3(x,14.5,-7.76))
		if Rect2(8,45,344,690).has_point(point):front_visible+=1
	check("wide_museum_majority",front_visible>=25,front_visible/41.0)
	var tower := scene._camera.unproject_position(Vector3(-25,17.5,-11.5))
	check("wide_lighthouse_visible",Rect2(8,45,344,690).has_point(tower),tower)
	var tower_inside := true
	var tower_pose: Dictionary = scene.layout.placements.filter(func(p):return p.asset=="alc_lighthouse")[0]
	var tower_bounds: AABB = scene._transform_of(tower_pose)*scene._mesh("alc_lighthouse").get_aabb()
	for corner in 8:
		tower_inside = tower_inside and Rect2(0,0,360,800).has_point(scene._camera.unproject_position(tower_bounds.get_endpoint(corner)))
	check("wide_entire_tower_in_frame",tower_inside)
	for i in 20:scene._zoom_buttons["ZoomIn"].pressed.emit()
	check("zoom_in_limit",scene.camera_pan.zoom<=1.4001,scene.camera_pan.zoom)
	scene.camera_pan.reset(1.0)
	scene._update_camera()
	await top_layout_photo()
	scene._overview = true
	scene._focus = Vector3(0,6,0)
	scene._update_camera()
	await photograph("05-whole-island")
	results["view_metrics"] = metrics
	results["route_screens"] = route_capture_index
	results["status"] = "pass" if failures.is_empty() else "fail"
	results["failures"] = failures
	results["limits"] = ["Desktop Vulkan Mobile on gs66; not Android or physical-phone performance.","Walk simulation validates runtime paths; it is not a claim of real touch input.","Formal colour for owned modules; delegated meshes marked placeholder remain pending."]
	var file := FileAccess.open(destination.path_join("verification.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")+"\n")
	print("ALCATRAZ_REVIEW ",results.status," checks=",results.size()," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func photograph(name_: String) -> void:
	var capture_started := Time.get_ticks_msec()
	var samples: Array = []
	for frame in 12:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		samples.append(render_sample())
	print("ALCATRAZ_PHASE capture ",name_)
	var peak: Dictionary = samples[-1].duplicate()
	for sample in samples:
		for key in sample:peak[key]=maxi(int(peak[key]),int(sample[key]))
	metrics[name_] = peak
	metrics[name_]["samples"]=samples
	metrics[name_]["player_position"]=[scene._player.position.x,scene._player.position.y,scene._player.position.z]
	metrics[name_]["zoom"]=scene.camera_pan.zoom
	metrics[name_]["capture_ms"]=Time.get_ticks_msec()-capture_started
	if viewport.size==Vector2i(360,800):
		check(name_+"_triangle_budget",int(peak.visible_triangles)<=80000,peak.visible_triangles)
		check(name_+"_draw_budget",int(peak.total_draw_calls)<=60,peak.total_draw_calls)
		check(name_+"_presentation_draw_budget",int(peak.global_draw_calls)<=60,peak.global_draw_calls)
		if is_equal_approx(scene.camera_pan.zoom,1.0):
			check(name_+"_hud_tall_clearance",hud_intrusions().is_empty(),hud_intrusions())
	var image := viewport.get_texture().get_image()
	check(name_+"_size",image.get_size()==viewport.size,str(image.get_size()))
	var exposed := 0
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):
			var c := image.get_pixel(x,y)
			if c.r>.6 and c.b>.6 and c.g<.12:exposed+=1
	check(name_+"_no_background",exposed==0,exposed)
	if name_=="01-opening":
		var orange := 0
		for y in range(40,160):
			for x in range(0,140):
				var c := image.get_pixel(x,y)
				if c.r>c.g*1.3 and c.g>c.b*1.1 and c.r>.35:orange+=1
		check("bridge_visible_upper_left_pixels",orange>40,orange)
	DirAccess.make_dir_recursive_absolute(destination.path_join(name_).get_base_dir())
	image.save_png(destination.path_join(name_+".png"))
	var progress := FileAccess.open(destination.path_join("progress.tmp"),FileAccess.WRITE)
	progress.store_string(JSON.stringify({"view_metrics":metrics,"failures":failures},"\t"))
	progress.close()
	DirAccess.rename_absolute(destination.path_join("progress.tmp"),destination.path_join("progress.json"))

func render_sample() -> Dictionary:
	var visible_triangles := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	var visible_calls := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var shadow_calls := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var canvas_calls := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return {"visible_triangles":visible_triangles,"visible_draw_calls":visible_calls,"shadow_draw_calls":shadow_calls,"canvas_draw_calls":canvas_calls,"total_draw_calls":visible_calls+shadow_calls+canvas_calls,"global_draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}

func route_photo(force := false) -> void:
	if not force and route_distance+.001<route_capture_at:return
	# Freeze actual walking at the sample and settle only the follow target.
	scene._focus = scene._follow_target()
	scene._update_camera()
	var name_ := "route/step-%02d-%03dm"%[route_capture_index,roundi(route_distance)]
	# Conservative imported tree bounds catch foreground crowns hiding the avatar
	# on the next terrace; ground/navigation clearance alone cannot catch this.
	var tree_occluders: Array = []
	for p in scene.layout.placements:
		if not str(p.asset).begins_with("alc_tree_"):continue
		var tree_bounds: AABB = scene._transform_of(p)*scene._mesh(p.asset).get_aabb()
		for height in [.5,.95,1.4]:
			var body_point: Vector3 = scene._player.position+Vector3.UP*float(height)
			var screen_point := scene._camera.unproject_position(body_point)
			var origin := scene._camera.project_ray_origin(screen_point)
			if tree_bounds.intersects_segment(origin,body_point)!=null:
				tree_occluders.append(p.name)
				break
	check(name_+"_avatar_clear_of_trees",tree_occluders.is_empty(),tree_occluders)
	var visible_interests: Array = []
	for point in scene.layout.interest_points:
		var world := AlcatrazIsland._vec(point.position)+Vector3.UP*.5
		var screen := scene._camera.unproject_position(world)
		if not scene._camera.is_position_behind(world) and Rect2(8,52,344,680).has_point(screen):visible_interests.append(point.name)
	# Architecture/ruins/gulls also count; rail and blank retaining walls do not.
	for p in scene.layout.placements:
		if p.asset not in ["alc_museum","alc_lighthouse","alc_watertower","ruins","gull","ferry"]:continue
		var world := AlcatrazIsland._vec(p.position)+Vector3.UP
		if Rect2(8,52,344,680).has_point(scene._camera.unproject_position(world)):visible_interests.append(p.name)
	check(name_+"_interest",not visible_interests.is_empty(),visible_interests)
	await photograph(name_)
	route_capture_index+=1
	route_capture_at=route_distance+6.5

func prepare_hud_audit() -> void:
	# Frozen b1 360x800 control geometry plus 12 px art clearance. No game UI is added.
	var contract: Dictionary = scene.layout.hud_clearance
	for key in contract.reserved_rects:
		var r: Array = contract.reserved_rects[key]
		hud_regions[key]=PackedVector2Array([Vector2(r[0],r[1]),Vector2(r[0]+r[2],r[1]),Vector2(r[0]+r[2],r[1]+r[3]),Vector2(r[0],r[1]+r[3])])
	for p in scene.layout.placements:
		if p.asset not in contract.tall_assets:continue
		var box: AABB = scene._mesh(p.asset).get_aabb()
		var upper_triangles := PackedVector3Array()
		if p.asset=="ferry":
			# The low bow may sit below HUD. Audit the cabin/funnel, without inventing
			# a 6 m tall wall over the entire 25 m hull's bounding box.
			var first := true
			for vertex in scene._mesh(p.asset).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if vertex.y<1.7:continue
				if first:box=AABB(vertex,Vector3.ZERO);first=false
				else:box=box.expand(vertex)
			box=box.expand(Vector3(box.position.x,1.6,box.position.z))
			var mesh_arrays: Array = scene._mesh(p.asset).surface_get_arrays(0)
			var vertices: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = mesh_arrays[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				var a := vertices[indices[i]]
				var b := vertices[indices[i+1]]
				var c := vertices[indices[i+2]]
				if maxf(a.y,maxf(b.y,c.y))<1.7:continue
				for point in [a,b,c]:upper_triangles.append(scene._transform_of(p)*point)
		hud_boxes.append({"name":p.name,"transform":scene._transform_of(p),"box":box,"contract":"current","triangles":upper_triangles})
		if contract.future_props.assets.has(p.asset):
			var future: Dictionary = contract.future_props.assets[p.asset]
			var lo := AlcatrazIsland._vec(future.min)
			var hi := AlcatrazIsland._vec(future.max)
			hud_boxes.append({"name":p.name,"transform":scene._transform_of(p),"box":AABB(lo,hi-lo),"contract":"props_802_bounds"})

func hud_intrusions() -> Array:
	var intrusions: Array = []
	for entry in hud_boxes:
		var points := PackedVector2Array()
		var box: AABB = entry.box
		var transform_: Transform3D = entry.transform
		for k in 8:points.append(scene._camera.unproject_position(transform_*box.get_endpoint(k)))
		var outline := Geometry2D.convex_hull(points)
		for region in hud_regions:
			if not Geometry2D.intersect_polygons(outline,hud_regions[region]).is_empty():
				# A whole-ship box would fill empty space above the low bow. Check
				# actual imported cabin/funnel triangles before reporting an overlap.
				var triangles: PackedVector3Array = entry.get("triangles",PackedVector3Array())
				if not triangles.is_empty():
					var actual := false
					for i in range(0,triangles.size(),3):
						var tri := PackedVector2Array([scene._camera.unproject_position(triangles[i]),scene._camera.unproject_position(triangles[i+1]),scene._camera.unproject_position(triangles[i+2])])
						if not Geometry2D.intersect_polygons(tri,hud_regions[region]).is_empty():actual=true;break
					if not actual:continue
				intrusions.append({"name":entry.name,"region":region,"contract":entry.contract})
	return intrusions

func touch(point: Vector2, pressed: bool, id: int) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.index = id
	scene._handle_camera_input(event,pressed)

func drag(point: Vector2, id: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point
	event.index = id
	scene._handle_camera_input(event,false)

func budget_sweep() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(destination.path_join("verification.json")))
	var rows: Array = []
	scene.set_process(false)
	for key in baseline.view_metrics:
		if not str(key).begins_with("route/"):continue
		scene._player.position = AlcatrazIsland._vec(baseline.view_metrics[key].player_position)
		for zoom in [.85,.68,.5,1.0/3.0]:
			scene.camera_pan.reset(zoom)
			scene._focus = scene._follow_target()
			scene._update_camera()
			var peak := {"visible_triangles":0,"total_draw_calls":0,"global_draw_calls":0}
			for frame in 2:
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var sample := render_sample()
				for metric in peak:peak[metric]=maxi(int(peak[metric]),int(sample[metric]))
			rows.append({"point":key,"zoom":zoom,"metrics":peak})
			if int(peak.visible_triangles)>80000 or int(peak.global_draw_calls)>60:
				failures.append(str(key)+" zoom "+str(zoom)+" "+str(peak))
	var report := {"status":"pass" if failures.is_empty() else "fail","rows":rows,"failures":failures}
	var file := FileAccess.open(destination.path_join("wide-sweep.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("WIDE_SWEEP ",report.status," ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func colour_walk_movie() -> void:
	# MovieWriter uses fixed 30 Hz simulation. Playback retains the normal walk
	# speed; the offline capture rate is not a device performance measurement.
	scene.set_process(false)
	for frame in 90:await get_tree().process_frame
	var ready_frame := Engine.get_frames_drawn()
	for frame in 60:await get_tree().process_frame
	var goal := AlcatrazIsland._vec(scene.layout.walk_goals[-1])
	scene.walk_to(goal)
	scene.set_process(true)
	var walk_frames := 0
	for frame in 2700:
		await get_tree().process_frame
		walk_frames+=1
		if scene._path_i>=scene._path.size():break
	scene.set_process(false)
	var arrived := scene._player.position.distance_to(goal)<.15
	for frame in 60:await get_tree().process_frame
	scene.camera_pan.reset(1.0/3.0)
	scene._focus=scene._follow_target()
	scene._update_camera()
	for frame in 90:await get_tree().process_frame
	var report := {"ready_frame":ready_frame,"fixed_fps":30,"normal_speed_walk_frames":walk_frames,"arrived":arrived,"final_position":str(scene._player.position),"limits":"Offline fixed-step art movie; not real touch or physical-device FPS."}
	FileAccess.open(destination.path_join("movie.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COLOUR_MOVIE ",report)
	get_tree().quit(0 if arrived else 1)

func audit_garden_support() -> void:
	var unsupported: Array = []
	for p in scene.layout.placements:
		if p.asset not in ["alc_flowerbed","alc_planter","alc_flowers_poppy","alc_flowers_lavender","alc_flowers_daisy","alc_hedge"]:continue
		var root := AlcatrazIsland._vec(p.position)
		var offsets := [Vector3.ZERO]
		if p.asset=="alc_flowerbed":
			for x in [-.82,.82]:
				for z in [-.82,.82]:offsets.append(Vector3(x,0,z))
		for offset: Vector3 in offsets:
			var ray := PhysicsRayQueryParameters3D.create(root+offset+Vector3.UP*.06,root+offset-Vector3.UP*.12)
			var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty():unsupported.append({"name":p.name,"point":str(root+offset)})
	check("garden_roots_and_flowerbed_corners_supported",unsupported.is_empty(),unsupported)
	check("three_dense_bands_per_terrace",scene.layout.garden_design.flower_bands.size()==9 and scene.layout.garden_design.flower_bands.all(func(b):return b.clusters>=4 and b.clusters<=6))

func top_layout_photo() -> void:
	# Imported geometry is actually shown in a top-down rendered layout.
	scene._hud.visible = false
	scene._overview = true
	scene._set_backdrop_visible(false)
	viewport.size = Vector2i(1000,1200)
	scene._camera.size = 74
	scene._camera.position = Vector3(0,85,0)
	scene._camera.far = 200
	scene._camera.rotation_degrees = Vector3(-90,0,0)
	scene._camera.near = .1
	for node in scene._detail_batches:node.visible=true
	for node in scene._unshadowed_batches:
		var transforms: Array = node.get_meta("instance_transforms")
		for i in transforms.size():node.multimesh.set_instance_transform(i,transforms[i])
		node.multimesh.visible_instance_count=-1
		node.visible=true
	await photograph("04-top-layout")
