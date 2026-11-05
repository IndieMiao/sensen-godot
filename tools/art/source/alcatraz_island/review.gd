extends Node
## Real Mobile-rendered scene, deterministic art review and navigation checks.
var scene: AlcatrazIsland
var viewport: SubViewport
var results := {}
var destination: String
var failures: Array[String] = []

func check(key: String, passed: bool, evidence = null) -> void:
	results[key] = {"passed":passed, "evidence":evidence}
	if not passed:
		failures.append(key)
		push_error("ALCATRAZ_CHECK " + key)

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
	scene = load("res://scenes/landmark/alcatraz_island.tscn").instantiate()
	viewport.add_child(scene)
	print("ALCATRAZ_PHASE scene added")
	for i in 240:
		await get_tree().physics_frame
		if scene.navigation_ready(): break
	print("ALCATRAZ_PHASE nav ready ",scene.navigation_ready())
	check("navigation_ready",scene.navigation_ready())
	for i in 80: await get_tree().process_frame
	check("renderer", RenderingServer.get_current_rendering_method() == "mobile", RenderingServer.get_video_adapter_name())
	check("no_network_autoload", get_node_or_null("/root/Net") == null)
	check("farm_scale",is_equal_approx(scene._camera.size,7.0),scene._camera.size)
	check("spawn_on_navigation",NavigationServer3D.map_get_closest_point(scene._nav_map,scene._player.position).distance_to(scene._player.position)<.05)
	check("separate_navigation_map",scene._nav_map != scene.get_world_3d().navigation_map)
	print("ALCATRAZ_PHASE opening")
	await photograph("01-opening")
	var bridge_points: Array[Vector2] = []
	for p in [Vector3(7.065,.35,4.8),Vector3(7.4775,1.04,4.8),Vector3(8.5225,1.04,4.8),Vector3(8.935,.35,4.8)]:
		bridge_points.append(scene._camera.unproject_position(p))
	check("bridge_projection_opening",bridge_points.all(func(p): return Rect2(0,0,360,800).has_point(p)),str(bridge_points))
	var corners_ok := true
	for p in [Vector2(0,0),Vector2(359,0),Vector2(0,799),Vector2(359,799)]:
		var hit = Plane(Vector3.UP,-.15).intersects_ray(scene._camera.project_ray_origin(p),scene._camera.project_ray_normal(p))
		corners_ok = corners_ok and hit != null and absf(hit.x)<256 and absf(hit.z)<256
	check("opening_sea_covers_corners",corners_ok)
	check("map_exit_visible",scene._exit_button.visible,scene._exit_button.position)
	# Walk the whole route through NavigationServer paths rather than teleporting for images.
	var path_lengths: Array[float] = []
	for i in range(1,scene.layout.route.size()):
		var goal := AlcatrazIsland._vec(scene.layout.route[i])
		scene.walk_to(goal)
		var length := 0.0
		for j in range(1,scene._path.size()):length += scene._path[j-1].distance_to(scene._path[j])
		path_lengths.append(length)
		check("route_%d_path"%i,scene._path.size()>1 and scene._path[-1].distance_to(goal)<.15,str(scene._path))
		# Fixed simulation steps accelerate QA only; these still call the actual walk/follow code.
		scene.set_process(false)
		for frame in 1800:
			scene._process(1.0/60.0)
			if scene._path_i>=scene._path.size(): break
		for frame in 90:scene._process(1.0/60.0)
		check("route_%d_arrived"%i,scene._player.position.distance_to(goal)<.15,str(scene._player.position))
		check("route_%d_follow"%i,scene._focus.distance_to(scene._player.position)<.05,str(scene._focus))
		if i==4:await photograph("02-mid-hill")
		if i==scene.layout.route.size()-1:await photograph("03-visitor-center")
	results["walk_lengths_m"] = path_lengths
	check("summit_height",absf(scene._player.position.y-5.6)<.05,scene._player.position.y)
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
	var sea_nearest := NavigationServer3D.map_get_closest_point(scene._nav_map,Vector3(18,0,10))
	check("sea_not_walkable",sea_nearest.x<8,str(sea_nearest))
	var museum_nearest := NavigationServer3D.map_get_closest_point(scene._nav_map,Vector3(0,5.6,-10))
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
	scene._focus = scene._player.position
	scene._update_camera()
	var prior_camera := scene._camera.position
	scene.suspend()
	scene.resume()
	check("resume_preserves_view",scene._camera.position.is_equal_approx(prior_camera))
	var exited := [false]
	scene.exit_requested.connect(func():exited[0]=true)
	scene._exit_button.pressed.emit()
	check("map_exit_emits_request",exited[0])
	# Imported geometry is actually shown in a top-down rendered layout.
	scene._hud.visible = false
	viewport.size = Vector2i(1000,1200)
	scene._camera.size = 27
	scene._camera.position = Vector3(0,55,1)
	scene._camera.rotation_degrees = Vector3(-90,0,0)
	scene._camera.near = .1
	await photograph("04-top-layout")
	scene._overview = true
	scene._focus = Vector3(0,2.5,1)
	scene._update_camera()
	await photograph("05-whole-island")
	results["status"] = "pass" if failures.is_empty() else "fail"
	results["failures"] = failures
	results["limits"] = ["Desktop Vulkan Mobile on gs66; not Android or physical-phone performance.","Walk simulation validates runtime paths; it is not a claim of real touch input.","Blockout only, awaiting layout review."]
	var file := FileAccess.open(destination.path_join("verification.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")+"\n")
	print("ALCATRAZ_REVIEW ",results.status," checks=",results.size()," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func photograph(name_: String) -> void:
	for frame in 8:await get_tree().process_frame
	print("ALCATRAZ_PHASE capture ",name_)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(name_+"_size",image.get_size()==viewport.size,str(image.get_size()))
	var exposed := 0
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):
			var c := image.get_pixel(x,y)
			if c.r>.6 and c.b>.6 and c.g<.12:exposed+=1
	check(name_+"_no_background",exposed==0,exposed)
	image.save_png(destination.path_join(name_+".png"))

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
