extends Node
## Actual Godot Mobile/Vulkan captures, never Blender beauty renders.
const KIT = "res://assets/rooms/tackle_shop/"
var layout: Dictionary
var output: String
var vp: SubViewport
var world: Node3D
var room: Node3D
var camera: Camera3D
var report = {"checks": [], "assets": {}, "captures": []}
func _ready(): run.call_deferred()
func vec(a): return Vector3(a[0], a[1], a[2])
func xyz(p): return [p.x, p.y, p.z]
func check(ok, label):
	report.checks.append({"check": label, "passed": ok})
	if not ok: push_error(label)
func pose(focus, width, pitch=43.0, yaw=45.0):
	camera.size = width
	camera.rotation_degrees = Vector3(-pitch, yaw, 0)
	camera.position = focus + camera.basis.z * 20
func capture(id):
	for i in 12: await RenderingServer.frame_post_draw
	var img = vp.get_texture().get_image()
	check(img.save_png(output + "/" + id + ".png") == OK, "Capture " + id)
	report.captures.append({"name": id, "resolution": [img.get_width(), img.get_height()],
		"pitch": -camera.rotation_degrees.x, "yaw": camera.rotation_degrees.y,
		"orthographic_width": camera.size, "position": xyz(camera.position)})
	print("TACKLE_CAPTURE ", id)
func setup():
	vp = SubViewport.new(); vp.size = Vector2i(1440, 1440); vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp); world = Node3D.new(); vp.add_child(world)
	var lighting = layout.review_lighting
	var env = Environment.new(); env.background_mode = Environment.BG_COLOR
	env.background_color = Color(lighting.background); env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(lighting.ambient_color); env.ambient_light_energy = lighting.ambient
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we = WorldEnvironment.new(); we.environment = env; world.add_child(we)
	var sun = DirectionalLight3D.new(); world.add_child(sun)
	sun.position = vec(lighting.sun_position); sun.look_at(vec(lighting.sun_target))
	sun.light_color = Color(lighting.sun_color); sun.light_energy = lighting.sun; sun.shadow_enabled = true
	sun.shadow_bias = lighting.shadow_bias; sun.shadow_normal_bias = lighting.shadow_normal_bias
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = lighting.shadow_distance; sun.light_angular_distance = 1.4
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH; camera.near = .05; camera.far = 100; camera.current = true
	world.add_child(camera)
	var ground = MeshInstance3D.new(); var plane = PlaneMesh.new(); plane.size = Vector2(100,100)
	ground.mesh = plane; ground.position.y = -.285
	var mat = StandardMaterial3D.new(); mat.albedo_color = Color(lighting.background); mat.roughness = 1.0
	ground.material_override = mat; world.add_child(ground)
	room = load("res://scenes/tackle_shop/tackle_shop_art.tscn").instantiate(); world.add_child(room)
func audit():
	var expected = JSON.parse_string(FileAccess.get_file_as_string(KIT + "asset_stats.json"))
	var total = 0; var surfaces = 0
	for a in layout.assets:
		var group = room.get_node(a.name); var count = 0; var surface_count = 0; var bounds = AABB(); var first = true
		for m in group.find_children("*", "MeshInstance3D", true, false):
			count += m.mesh.get_faces().size()/3; surface_count += m.mesh.get_surface_count()
			var box = group.global_transform.affine_inverse() * m.global_transform * m.mesh.get_aabb()
			bounds = box if first else bounds.merge(box); first = false
			check(m.material_override == null, "No node-wide material override: " + a.name)
			for index in m.mesh.get_surface_count():
				var material = m.get_active_material(index)
				check(material == m.mesh.surface_get_material(index) and m.get_surface_override_material(index) == null,
					"Imported per-surface material retained: " + a.name)
				check(material.albedo_texture != null and material.albedo_texture.get_size() == Vector2(2048,2048), "2048 atlas: " + a.name)
				check(is_equal_approx(material.metallic_specular, .28), "Matte specular .28: " + a.name)
				if a.name == "fishbowl_glass":
					check(material.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA,BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS] and is_equal_approx(material.albedo_color.a,.075), "Imported glass alpha .075")
				else:
					check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Opaque surface: " + a.name)
		var row = expected.assets.filter(func(s): return s.name == a.name)[0]
		check(count == row.triangles and surface_count == 1, "Imported count/surface: " + a.name)
		report.assets[a.name] = {"triangles": count, "surfaces": surface_count, "bounds": [xyz(bounds.position), xyz(bounds.end)]}
		total += count; surfaces += surface_count
	for i in layout.instances:
		total += report.assets[i.asset].triangles; surfaces += report.assets[i.asset].surfaces
	check(total <= 200000 and total == expected.scene_triangles, "Placed room triangle budget")
	check(surfaces <= 60 and surfaces == expected.static_draw_surfaces, "Placed room surface budget")
	check(room.find_children("*","DirectionalLight3D",true,false).is_empty() and room.find_children("*","WorldEnvironment",true,false).is_empty(),
		"Environment and sunlight belong to consumer")
	check(room.find_children("*","Light3D",true,false).size() == 3, "Three authored local lamp lights")
	check(report.assets.rod_rack.triangles + report.assets.float_barrel.triangles <= 1200, "Rod rack plus float barrel <= 1200")
	check(room.get_node("rod_rack").position.z - .50 > -1.37 + .64, "Rod tips beside porthole aperture")
	for id in ["npc_keeper", "stand_counter", "npc_kai", "stand_kai", "npc_rafa", "stand_rafa", "use_fish_board", "stand_fish_board", "spawn", "exit", "badge_exit"]:
		check(room.get_node_or_null(id) is Marker3D, "Suggested anchor " + id)
	report.scene_triangles = total; report.scene_surfaces = surfaces
func fixture(at, yaw):
	var rig = Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity: child.free()
	rig.assembler = AvatarAssemblerMerged.new(); world.add_child(rig)
	rig.position = at; rig.rotation.y = deg_to_rad(yaw)
	rig.apply_config(Avatar.slot_table.default_config())
	var ticks = 0
	while rig.is_busy() and ticks < 900: await get_tree().process_frame; ticks += 1
	check(not rig.is_busy(), "Scale fixture assembled")
	rig.play_motion("idle"); var player = rig.get_node("AnimationPlayer"); player.seek(.3, true); player.pause()
	return rig
func run():
	output = ProjectSettings.globalize_path("res://../captures"); DirAccess.make_dir_recursive_absolute(output)
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	setup(); audit()
	pose(Vector3(0,1.20,0),10.2); await capture("whole-43deg")
	for light in room.find_children("*","Light3D",true,false):light.visible=false
	await capture("whole-lamps-off")
	for light in room.find_children("*","Light3D",true,false):light.visible=true
	vp.size = Vector2i(360,800); pose(Vector3(-.05,1.1,-.10),6.72); await capture("game-360-6p72m")
	report.game_anchor_projections = {}
	for id in ["npc_keeper", "npc_kai", "npc_rafa", "spawn", "exit", "use_fish_board"]:
		var point = camera.unproject_position(room.get_node(id).global_position)
		report.game_anchor_projections[id] = [point.x, point.y]
	vp.size = Vector2i(1440,1080)
	pose(Vector3(-.36,1.25,-1.56),3.8,28,12); await capture("counter")
	pose(Vector3(-2.88,1.0,-.10),2.7,18,80); await capture("rod-rack")
	pose(Vector3(-2.80,2.20,.84),2.8,12,80); await capture("wall-decoration")
	pose(Vector3(-2.70,.65,-1.65),2.1,30,65); await capture("rope-crate")
	pose(Vector3(-2.43,.78,1.98),2.35,35,45); await capture("kai-corner")
	pose(Vector3(2.75,.65,-1.0),2.45,35,38); await capture("rafa-corner")
	vp.size = Vector2i(1440,1440)
	pose(Vector3(0,1.2,0),8.0,0,0); await capture("orthographic-front")
	pose(Vector3(0,1.2,0),8.0,0,90); await capture("orthographic-left")
	pose(Vector3(0,0,.15),8.0,90,0); await capture("orthographic-top")
	for id in ["npc_keeper", "npc_kai", "npc_rafa", "spawn"]:
		var anchor = room.get_node(id)
		await fixture(anchor.position, 45)
	pose(Vector3(0,1.2,0),10.2); await capture("standing-clearance")
	report.renderer = RenderingServer.get_current_rendering_method()
	report.adapter = RenderingServer.get_video_adapter_name()
	report.failures = report.checks.filter(func(c): return not c.passed)
	FileAccess.open(output + "/godot-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report,"\t") + "\n")
	print("TACKLE_QA ", report.checks.size(), " checks; ", report.failures.size(), " failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)
