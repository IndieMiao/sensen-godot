extends Node
## Real Godot Mobile captures, actual imported vertices and physics capsule sweeps.
const KIT = "res://assets/rooms/poi_city_park/"
const FarmArt = preload("res://modules/farm/farm_art.gd")
var vp: SubViewport
var world: Node3D
var cam: Camera3D
var park: Node3D
var rig
var output: String
var standing_transform: Transform3D
var report = {"checks": [], "captures": [], "capsule_routes": [], "recolour_controls": []}

func _ready(): run.call_deferred()
func xyz(v): return [v.x, v.y, v.z]
func vec(a): return Vector3(a[0], a[1], a[2])
func check(ok, label):
	report.checks.append({"check": label, "passed": bool(ok)})
	if not ok: push_error(label)

func create_world():
	vp = SubViewport.new()
	vp.size = Vector2i(360, 800)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	world = Node3D.new(); vp.add_child(world)
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("CFE5EF")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("E6EADA")
	env.ambient_light_energy = .50
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we = WorldEnvironment.new(); we.environment = env; world.add_child(we)
	var sun = DirectionalLight3D.new(); world.add_child(sun)
	sun.rotation_degrees = Vector3(-51,-38,0)
	sun.light_color = Color("FFF3DA"); sun.light_energy = 1.05
	sun.shadow_enabled = true; sun.shadow_opacity = .65
	sun.shadow_bias = .035; sun.shadow_normal_bias = .25; sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 0
	cam = Camera3D.new(); cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = .1; cam.far = 80
	world.add_child(cam)
	park = load("res://scenes/poi_city_park/poi_city_park_art.tscn").instantiate()
	world.add_child(park)

func pose(focus, width, pitch=43.0, yaw=45.0):
	cam.size = width
	cam.rotation_degrees = Vector3(-pitch, yaw, 0)
	cam.position = focus + cam.basis.z*24

func imported_geometry():
	var tris = 0; var surfaces = 0
	for node in park.find_children("*", "MeshInstance3D", true, false):
		for i in node.mesh.get_surface_count():
			surfaces += 1
			var arrays = node.mesh.surface_get_arrays(i)
			tris += arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()/3
	var stats = JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"))
	check(tris == stats.scene_triangles, "Imported placed triangle count matches manifest")
	check(surfaces == stats.static_draw_surfaces, "Imported placed surfaces match manifest")
	check(tris <= 150000 and surfaces <= 50, "Placed N5 budget <= 150k triangles / 50 surfaces")
	check(stats.plant_triangles <= 100000, "Vegetation <= 100k triangles")
	check(park.atlas.albedo_texture.get_size() == Vector2(2048,2048), "One 2048x2048 N5 atlas")
	check(park.water.shader.resource_path == "res://modules/ponds/pond_water.gdshader", "Unchanged existing pond water shader")
	for spec in park.layout.assets:
		var config=ConfigFile.new()
		check(config.load(KIT+spec.file+".import")==OK and str(config.get_value("remap","uid","")).begins_with("uid://"),"Actual import UID exists: "+spec.name)
		check(config.get_value("params","gltf/texture_map_mode",0)==1,"Actual texture_map_mode=1: "+spec.name)
	var seats = park.layout.anchors.filter(func(a): return str(a.name).begins_with("seat_bench_"))
	check(seats.size() == 8, "Exactly eight seats on four green benches")
	for seat in seats:
		check(park.has_node(NodePath(seat.module)), "Seat owning module exists: "+seat.name)
		check(absf(seat.position[1]-.715)<.00001, "Seat height .715m: "+seat.name)
		var marker = park.get_node(NodePath(seat.name))
		var center = park.get_node(NodePath(seat.module)).position
		var target = (Vector3(0,0,.16)-Vector3(center.x,0,center.z)).normalized()
		check(marker.basis.z.dot(target) > .99, "Seat faces fountain: "+seat.name)
	check(park.get_node("sign_name").get_meta("size") == [1.45,.22], "Blank runtime sign carries usable size")
	report.imported = {"triangles":tris,"surfaces":surfaces,"plant_triangles":stats.plant_triangles,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(park.get_node("grass_extension").find_children("*","StaticBody3D",true,false).is_empty(),"Exterior grass is decorative, with no walkable floor collider")
	var limits=park.layout.walkable_bounds_xz
	check(Vector2(limits[0][0],limits[0][1]).is_equal_approx(Vector2(-4,-4)) and Vector2(limits[1][0],limits[1][1]).is_equal_approx(Vector2(4,4)),"Walkable park remains 8x8m")
	check(park.get_node("front_shrub").position.z==2.75 and not park.has_node("park_tree_5"),"Both entrance-side trees replaced by low shrubs")
	for i in range(1,9,2):
		check(absf(park.get_node("seat_bench_"+str(i)).position.distance_to(park.get_node("seat_bench_"+str(i+1)).position)-.70)<.0001,"Paired seats separated .70m: "+str(i))

func avatar():
	rig = Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity: child.free()
	rig.assembler = AvatarAssemblerMerged.new(); world.add_child(rig)
	rig.apply_config(Avatar.slot_table.default_config())
	var ticks = 0
	while rig.is_busy() and ticks < 900:
		await get_tree().process_frame; ticks += 1
	check(not rig.is_busy(), "Fixture avatar assembled")
	rig.play_motion("idle")
	var animation = rig.get_node("AnimationPlayer")
	animation.seek(.3,true); animation.pause()
	var low = INF; var high = -INF
	for node in rig.find_children("*","MeshInstance3D",true,false):
		if node.mesh == null or not node.is_visible_in_tree(): continue
		var posed = node.bake_mesh_from_current_skeleton_pose() if node.skin != null else node.mesh
		if posed == null: continue
		for i in posed.get_surface_count():
			for vertex in posed.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				var v = rig.global_transform.affine_inverse()*node.global_transform*vertex
				low = minf(low,v.y); high = maxf(high,v.y)
	var scale_factor = 1.745/(high-low)
	rig.scale = Vector3.ONE*scale_factor
	rig.position = Vector3(0,.04-low*scale_factor,2.65)
	rig.rotation_degrees.y = 180
	standing_transform = rig.transform
	report.avatar = {"source_height_m":high-low,"scale":scale_factor,"actual_height_m":1.745,"foot_position":[0,.04,2.65]}

func capture(id):
	for i in 8: await RenderingServer.frame_post_draw
	var image = vp.get_texture().get_image()
	check(image.save_png(output+"/"+id+".png") == OK, "Capture saved: "+id)
	report.captures.append({"id":id,"pixels":[vp.size.x,vp.size.y],"camera_width_m":cam.size,"pitch":-cam.rotation_degrees.x,"yaw":cam.rotation_degrees.y,"position":xyz(cam.position)})
	print("N5_CAPTURE ",id)
	if id in ["default_43deg_360","minimum_zoom_360"]:
		var corners=[]
		for pixel in [Vector2.ZERO,Vector2(vp.size.x,0),Vector2(0,vp.size.y),Vector2(vp.size)]:
			var origin=cam.project_ray_origin(pixel);var direction=cam.project_ray_normal(pixel)
			var point=origin+direction*((-.02-origin.y)/direction.y)
			corners.append(xyz(point))
			check(absf(point.x)<30 and absf(point.z)<30,"Grass extension covers viewport ray at "+id+" "+str(pixel))
		report[id+"_ground_corners"]=corners

func bench_closeup():
	var seat=park.get_node("seat_bench_1")
	var animation=rig.get_node("AnimationPlayer")
	check(animation.has_animation("sit_idle"),"Existing production sit_idle clip available")
	rig.play_motion("sit_idle");animation.seek(.35,true);animation.pause()
	rig.position=seat.position-Vector3.UP*.34*rig.scale.y
	rig.rotation_degrees.y=seat.rotation_degrees.y
	rig.visible=true
	var bench=park.get_node("green_bench")
	pose(bench.position+Vector3(0,.85,0),2.9,43,70)
	vp.size=Vector2i(1100,850)
	await capture("bench_seated_detail")
	report.seated={"clip":"sit_idle","seat":"seat_bench_1","seat_surface_y_m":seat.position.y,
		"root_position":xyz(rig.position),"standing_calibrated_height_m":1.745,
		"production_root_offset_m":.34,"scale":rig.scale.y,
		"animation_source":JSON.parse_string(FileAccess.get_file_as_string("res://animation-provenance.json"))}
	rig.transform=standing_transform
	rig.play_motion("idle");animation.seek(.3,true);animation.pause()

func capsule_query(point, radius=.25):
	var capsule = CapsuleShape3D.new()
	capsule.radius = radius; capsule.height = 1.745
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = point + Vector3.UP*.8725
	query.margin = .002
	return query

func physics_routes():
	await get_tree().physics_frame
	var space = world.get_world_3d().direct_space_state
	var cells = {}
	for z in range(81):
		for x in range(73):
			var pos = Vector3(-3.6+x*.1,.045,-3.6+z*.1)
			if space.intersect_shape(capsule_query(pos),1).is_empty(): cells[Vector2i(x,z)] = pos
	var spawn = Vector3(0,.045,2.65)
	var start = nearest_cell(spawn,cells)
	var queue = [start]; var previous = {start:start}; var index = 0
	while index < queue.size():
		var here = queue[index]; index += 1
		for delta in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			var next = here+delta
			if cells.has(next) and not previous.has(next):
				previous[next] = here; queue.append(next)
	var targets = [{"name":"central_plaza","point":Vector3(0,.045,1.08)}, {"name":"exit","point":Vector3(0,.045,4.2)}]
	for anchor in park.layout.anchors:
		if anchor.has("approach"):
			var point = vec(anchor.approach); point.y = .045
			targets.append({"name":anchor.name,"point":point})
	for target in targets:
		var end = nearest_cell(target.point,cells)
		var reached = previous.has(end) and cells[end].distance_to(target.point)<.09
		var route = [target.point]
		if reached:
			var cell = end
			while cell != start:
				route.append(cells[cell]); cell = previous[cell]
			route.append(cells[start]); route.append(spawn); route.reverse()
		var blocked = []
		if reached:
			for i in range(route.size()-1):
				var query = capsule_query(route[i]); query.motion = route[i+1]-route[i]
				var result = space.cast_motion(query)
				if result[0]<.9999 or not space.intersect_shape(capsule_query(route[i+1]),1).is_empty(): blocked.append(i)
		check(reached and blocked.is_empty(), "Actual .25m radius / 1.745m capsule route: "+target.name)
		report.capsule_routes.append({"target":target.name,"reachable":reached,"sweep_failures":blocked,"points":route.map(func(v): return xyz(v))})
	report.capsule = {"radius_m":.25,"height_m":1.745,"grid_step_m":.1,"tested_free_cells":cells.size(),"reachable_cells":previous.size(),"margin_m":.002}
	var standing = []
	for cell in queue:
		var point = cells[cell]
		if absf(point.x)>3.4 or point.z>3.3 or point.z< -3.3: continue
		if standing.all(func(other): return point.distance_to(other)>=.70): standing.append(point)
		if standing.size()==16: break
	check(standing.size()==16,"Sixteen reachable standing positions with >=.70m centre separation")
	report.standing_positions=standing.map(func(point): return xyz(point))
	var main_spokes=[]
	for axis in [0,1,2,3]:
		for step in range(12,28):
			var angle=axis*PI/2
			var point=Vector3(sin(angle)*step*.1,.045,.16+cos(angle)*step*.1)
			if not space.intersect_shape(capsule_query(point,.35),1).is_empty(): main_spokes.append(xyz(point))
	check(main_spokes.is_empty(),"Main radial connections have .70m physical clearance")
	report.main_clearance={"diameter_m":.70,"blocked_samples":main_spokes,"sample_spacing_m":.1}

func nearest_cell(point,cells):
	var best = Vector2i.ZERO; var distance = INF
	for cell in cells:
		var d = cells[cell].distance_squared_to(point)
		if d < distance: distance = d; best = cell
	return best

func controls():
	park.visible = false; rig.visible = false
	var control = Node3D.new(); world.add_child(control)
	for pair in [["tree_0","park_tree",4.0],["deco_fence","white_fence_segment",1.5],["deco_bench","bench_farm_control",2.3]]:
		var original = FarmArt.instance(pair[0]); control.add_child(original)
		var baked = load(KIT+pair[1]+".glb").instantiate(); control.add_child(baked)
		for node in baked.find_children("*","MeshInstance3D",true,false): node.material_override = park.atlas
		vp.size = Vector2i(720,720)
		var height = 1.3 if pair[0] == "tree_0" else .45
		pose(Vector3(0,height,0),pair[2],43,20)
		baked.visible = false; await capture("farm_original_"+pair[0])
		original.visible = false; baked.visible = true; await capture("atlas_baked_"+pair[0])
		report.recolour_controls.append({"source":pair[0],"baked":pair[1],"same_geometry_camera_light":true})
		original.free(); baked.free()
	control.free(); park.visible = true; rig.visible = true

func run():
	output = ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(output)
	create_world(); imported_geometry(); await avatar(); await physics_routes()
	pose(Vector3(0,.9,1.1),6.72)
	await capture("default_43deg_360")
	pose(Vector3(0,.9,1.1),8.4);await capture("minimum_zoom_360")
	pose(Vector3(0,.9,1.1),6.72)
	vp.size = Vector2i(1080,2400); await capture("default_43deg_hd")
	vp.size = Vector2i(1400,1100); pose(Vector3(0,.8,.1),12.2,43,0)
	await capture("panorama")
	await bench_closeup()
	vp.size = Vector2i(1100,1100); pose(Vector3(0,0,0),9.2,90,0)
	park.get_node("village_backdrop").visible = false; rig.visible = false
	await capture("topdown")
	vp.size = Vector2i(1200,900); pose(Vector3(0,.43,.16),3.8,43,25)
	await capture("fountain_detail")
	pose(Vector3(1.5,.18,1.66),2.5,52,25); await capture("parterre_detail")
	park.get_node("village_backdrop").visible = true
	pose(Vector3(0,.43,.16),2.0,55,0)
	await capture("water_t0")
	await get_tree().create_timer(1.0).timeout
	await capture("water_t1")
	await controls()
	report.passed = report.checks.all(func(c): return c.passed)
	report.failures = report.checks.filter(func(c): return not c.passed)
	var file = FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n"); file.close()
	print("N5_VALIDATION ",report.passed," ",report.failures)
	get_tree().quit(0 if report.passed else 1)
