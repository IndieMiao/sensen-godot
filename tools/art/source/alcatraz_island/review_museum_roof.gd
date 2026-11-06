extends "res://review.gd"
## Roof-only comparison in the current Mobile renderer and unchanged island.
var near_node: MeshInstance3D
var current_mesh: Mesh
var previous_mesh: Mesh

func _ready() -> void:
	destination = OS.get_environment("ALCATRAZ_REVIEW")
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
	add_child(display)
	scene = load("res://scenes/landmark/alcatraz_island.tscn").instantiate()
	viewport.add_child(scene)
	for i in 240:
		await get_tree().physics_frame
		if scene.navigation_ready() and not scene._rig.is_busy():break
	scene.set_process(false)
	scene._rig.process_mode = Node.PROCESS_MODE_DISABLED
	for root in scene.animated_roots:
		var player := root.get_node("AnimationPlayer") as AnimationPlayer
		player.pause()
		player.seek(0,true)
	prepare_hud_audit()
	check("navigation_ready",scene.navigation_ready())
	check("renderer_mobile",RenderingServer.get_current_rendering_method()=="mobile",RenderingServer.get_video_adapter_name())
	for node in scene.mesh_nodes:
		if node.name.begins_with("AlcMuseum") and not node.name.begins_with("AlcMuseumFar"):near_node=node
	current_mesh = near_node.mesh
	var old_scene := load("res://baseline/alc_museum.glb").instantiate() as Node3D
	previous_mesh = old_scene.find_children("*","MeshInstance3D",true,false)[0].mesh
	old_scene.free()
	check("museum_bounds_unchanged",current_mesh.get_aabb().is_equal_approx(previous_mesh.get_aabb()),
		{"before":str(previous_mesh.get_aabb()),"after":str(current_mesh.get_aabb())})
	check("one_opaque_surface",current_mesh.get_surface_count()==1 and near_node.material_override is StandardMaterial3D and near_node.material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED)
	check("placement_unchanged",near_node.position.is_equal_approx(Vector3(0,10,-13)),str(near_node.position))
	await audit_museum_lod()
	for spec in [["opening","01-opening"],["mid_hill","02-mid-hill"],["visitor_center","03-visitor-center"]]:
		set_view(AlcatrazIsland._vec(scene.layout.review_points[spec[0]]),1)
		await photograph(spec[1])
	set_view(AlcatrazIsland._vec(scene.layout.review_points.visitor_center),1.0/3.0)
	await photograph("04-summit-wide-after")
	near_node.mesh = previous_mesh
	await photograph("04-summit-wide-before")
	near_node.mesh = current_mesh
	# Record the original 360 route/zoom combinations against the same 60 draw ceiling.
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://baseline/verification.json"))
	var rows: Array = []
	for key in baseline.view_metrics:
		if not str(key).begins_with("route/"):continue
		var zooms: Array = [1.4,1.15,1.0,.9,.85,.8,.68,.6,.5,.4,1.0/3.0]
		for press in range(1,8):zooms.append(pow(1.15,-press))
		for zoom in zooms:
			set_view(AlcatrazIsland._vec(baseline.view_metrics[key].player_position),zoom)
			var peak := {"visible_triangles":0,"global_draw_calls":0}
			for frame in 2:
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var sample := render_sample()
				for metric in peak:peak[metric]=maxi(int(peak[metric]),int(sample[metric]))
			rows.append({"point":key,"zoom":zoom,"metrics":peak})
			if peak.visible_triangles>80000 or peak.global_draw_calls>60:failures.append(str(key)+" "+str(peak))
	FileAccess.open(destination.path_join("wide-sweep.json"),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"failures":failures},"\t")+"\n")
	viewport.size = Vector2i(1000,900)
	scene._hud.visible = false
	scene._overview = true
	scene._focus = Vector3(0,6,0)
	scene.camera_pan.reset(1.0)
	scene._update_camera()
	# Overview uses the actual 55 m far LOD, delivered separately by Huang Zhong.
	await photograph("05-whole-island-current-lods")
	await model_view("06-museum-before",previous_mesh,false)
	await model_view("06-museum-after",current_mesh,false)
	await model_view("07-skylight-detail",current_mesh,true)
	results["status"] = "pass" if failures.is_empty() else "fail"
	results["failures"] = failures
	results["view_metrics"] = metrics
	results["near_triangles"] = current_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3
	results["scope"] = "Near roof only; actual far LOD retains v9 pending Huang Zhong. Desktop Vulkan Mobile, not physical-phone FPS."
	FileAccess.open(destination.path_join("verification.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t")+"\n")
	print("ROOF_REVIEW ",results.status," ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func set_view(point: Vector3, zoom: float) -> void:
	scene._player.position = point
	scene.camera_pan.reset(zoom)
	scene._focus = scene._follow_target()
	scene._update_camera()

func model_view(filename: String, mesh: Mesh, close: bool) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1000,700) if not close else Vector2i(800,600)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var environment := WorldEnvironment.new()
	environment.environment = scene._environment.environment.duplicate()
	environment.environment.background_color = Color("E5E7DF")
	view.add_child(environment)
	for child in scene.get_children():
		if child is DirectionalLight3D:view.add_child(child.duplicate())
	var model := MeshInstance3D.new()
	model.mesh = mesh
	model.material_override = near_node.material_override
	view.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 48 if not close else 7
	camera.near = .05
	camera.far = 200
	camera.rotation_degrees = Vector3(-43,25,0)
	view.add_child(camera)
	camera.position = (Vector3(0,4.3,0) if not close else Vector3(0,8.7,.6))+camera.basis.z*65
	camera.current = true
	for frame in 10:await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(destination.path_join(filename+".png"))
	view.free()
	for frame in 2:await RenderingServer.frame_post_draw
