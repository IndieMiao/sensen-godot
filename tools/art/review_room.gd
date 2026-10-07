extends SceneTree
## Art-only import/render inspection. No player, network, UI or saved data.
var slug: String
var output_dir: String
var material_ids: Array[int] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	slug = args[0]
	output_dir = args[1]
	call_deferred("capture")

func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440,1080)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var kit := load("res://scenes/%s/%s_art.tscn" % [slug,slug]) as PackedScene
	assert(kit != null)
	var room := kit.instantiate()
	world.add_child(room)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/%s/layout.json" % slug))
	var lighting: Dictionary = layout.get("review_lighting", {})
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(lighting.get("background", "e8e4c8"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(lighting.get("ambient_color", "fff0dc"))
	environment.ambient_light_energy = float(lighting.get("ambient", .70))
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var env := WorldEnvironment.new()
	env.environment = environment
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(lighting.get("sun_color", "ffe6c2"))
	sun.light_energy = float(lighting.get("sun", 1.05))
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = float(lighting.get("shadow_distance", 35))
	sun.shadow_bias = float(lighting.get("shadow_bias", .025))
	sun.shadow_normal_bias = float(lighting.get("shadow_normal_bias", .18))
	sun.light_angular_distance = 1.4
	world.add_child(sun)
	sun.position = vec(lighting.get("sun_position", [-6,7,1.5]))
	sun.look_at(vec(lighting.get("sun_target", [0,0,0])))
	for lamp in lighting.get("points", []):
		var light := OmniLight3D.new()
		world.add_child(light)
		light.position = vec(lamp.position)
		light.light_color = Color(lamp.get("color", "ffb85e"))
		light.light_energy = float(lamp.get("energy", 1.0))
		light.omni_range = float(lamp.get("range", 2.4))
		light.shadow_enabled = false
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	ground.position.y = -.36
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(lighting.get("background", "eae4c8"))
	mat.roughness = 1
	ground.material_override = mat
	if lighting.get("background_gradient", false):
		var backdrop := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = """shader_type spatial; render_mode unshaded;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){float t=smoothstep(-4.0,6.0,dot(world_pos.xz,vec2(.66,.75)));
ALBEDO=mix(vec3(.64,.81,.74),vec3(.98,.92,.71),t);}
"""
		backdrop.shader = shader
		ground.material_override = backdrop
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Manifest size is Blender's horizontal orthographic span at 4:3.
	camera.size = float(layout.camera.size) * .75
	world.add_child(camera)
	camera.position = vec(layout.camera.position)
	camera.look_at(vec(layout.camera.target))
	camera.current = true
	if OS.get_cmdline_user_args().has("--preservation-control"):
		var old_fire := room.get_node_or_null("fire") as Node3D
		if old_fire: old_fire.visible = false
		for fx in layout.get("effects", []):
			var effect := room.get_node(str(fx.name)) as Node3D
			effect.visible = false; effect.set_process(false)
			effect.light.light_energy = float(fx.light.energy)
		for mesh in room.find_children("*", "MeshInstance3D", true, false):
			if mesh.material_override is ShaderMaterial: mesh.material_override.set_shader_parameter("ember_energy", 0.0)
	for i in range(20): await process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	assert(img.save_png(output_dir + "/godot.png") == OK)
	for view in layout.get("review_views", []):
		camera.position = vec(view.position)
		camera.look_at(vec(view.target))
		camera.size = float(view.size) * .75
		for i in range(4): await process_frame
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().save_png(output_dir + "/" + str(view.name) + ".png") == OK)
	var stats := {"scene":slug,"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"resolution":[1440,1080],
		"mesh_instances":0,"surfaces":0,"triangles":0,"colliders":0,"finite_aabbs":true,"particle_emitters":0,"particle_capacity":0}
	inspect(room,stats)
	stats["material_count"] = material_ids.size()
	if layout.has("anchors"):
		var hook_checks: Array = []
		for point in layout.anchors:
			var marker := room.find_child(str(point.name), true, false) as Marker3D
			assert(marker != null)
			var error: float = room.to_local(marker.global_position).distance_to(vec(point.position))
			assert(error < .0001 and marker.global_basis.y.normalized().dot(Vector3.UP) > .999)
			var evidence := {"name":point.name,"position_error_m":error,"up_dot":marker.global_basis.y.normalized().dot(Vector3.UP)}
			if point.has("module"): assert(marker.get_parent().name == str(point.module))
			if str(point.name).begins_with("stand_") or point.name == "spawn":
				var capsule := CapsuleShape3D.new(); capsule.radius = .21; capsule.height = 1.25
				var query := PhysicsShapeQueryParameters3D.new(); query.shape = capsule
				query.transform = Transform3D(Basis.IDENTITY, marker.global_position + Vector3.UP * .65)
				var space := world.get_world_3d().direct_space_state
				var hits := space.intersect_shape(query)
				assert(hits.is_empty())
				var ray := PhysicsRayQueryParameters3D.create(marker.global_position + Vector3.UP * .18, marker.global_position - Vector3.UP * .25)
				var floor_hit := space.intersect_ray(ray)
				assert(not floor_hit.is_empty() and floor_hit.normal.y > .7)
				evidence["capsule_clear"] = true; evidence["supported_floor"] = true
			hook_checks.append(evidence)
		stats["anchors"] = hook_checks
	assert(stats.mesh_instances == layout.assets.size() + layout.instances.size() + layout.get("shared_plants", []).size())
	assert(stats.finite_aabbs and stats.particle_capacity <= 40)
	var file := FileAccess.open(output_dir + "/godot-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"\t"))
	print("ROOM_RENDER_VERIFIED ",JSON.stringify(stats))
	quit()

func inspect(node: Node, stats: Dictionary) -> void:
	if node is GPUParticles3D:
		stats.particle_emitters += 1
		stats.particle_capacity += node.amount
		assert(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert(node.process_material.collision_mode == ParticleProcessMaterial.COLLISION_DISABLED)
	if node is MeshInstance3D:
		stats.mesh_instances += 1
		assert(node.material_override != null)
		if node.material_override is StandardMaterial3D: assert(node.material_override.albedo_texture != null)
		else: assert(node.material_override is ShaderMaterial and node.material_override.get_shader_parameter("room_atlas") != null)
		var material_id: int = node.material_override.get_instance_id()
		if not material_ids.has(material_id): material_ids.append(material_id)
		var box: AABB = node.get_aabb()
		stats.finite_aabbs = stats.finite_aabbs and box.position.is_finite() and box.size.is_finite() and box.size.length()>0
		for i in node.mesh.get_surface_count():
			stats.surfaces += 1
			var arrays: Array = node.mesh.surface_get_arrays(i)
			stats.triangles += arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()/3
	if node is CollisionShape3D: stats.colliders += 1
	for child in node.get_children():inspect(child,stats)
