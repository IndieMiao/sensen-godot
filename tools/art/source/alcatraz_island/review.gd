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
	for i in 120:
		await get_tree().process_frame
		if not scene._rig.is_busy():break
	for i in 4:await get_tree().process_frame
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
	for x in [-26.85,-23.15]:
		for y in [10,25]:
			for z in [-13.35,-9.65]:
				tower_inside = tower_inside and Rect2(0,0,360,800).has_point(scene._camera.unproject_position(Vector3(x,y,z)))
	check("wide_entire_tower_in_frame",tower_inside)
	for i in 20:scene._zoom_buttons["ZoomIn"].pressed.emit()
	check("zoom_in_limit",scene.camera_pan.zoom<=1.4001,scene.camera_pan.zoom)
	scene.camera_pan.reset(1.0)
	scene._update_camera()
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
	await photograph("04-top-layout")
	scene._overview = true
	scene._focus = Vector3(0,6,0)
	scene._update_camera()
	await photograph("05-whole-island")
	results["view_metrics"] = metrics
	results["route_screens"] = route_capture_index
	results["status"] = "pass" if failures.is_empty() else "fail"
	results["failures"] = failures
	results["limits"] = ["Desktop Vulkan Mobile on gs66; not Android or physical-phone performance.","Walk simulation validates runtime paths; it is not a claim of real touch input.","Blockout only, awaiting layout review."]
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
		for zoom in [.5,1.0/3.0]:
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
