extends SceneTree
## Offline still renderer, never a gameplay/benchmark scene.
var viewport: SubViewport
var camera: Camera3D
var slug: String
var layout: Dictionary
var output_dir: String
var errors: Array[String] = []
var view_stats: Array = []

func surface_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh: count += node.mesh.get_surface_count()
	for child in node.get_children(): count += surface_count(child)
	return count

func _initialize() -> void:
	call_deferred("_render")

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _render() -> void:
	var args := OS.get_cmdline_user_args()
	slug = args[0]
	output_dir = args[1]
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/" + slug + "/layout.json"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1400,1400)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var room := (load("res://scenes/" + slug + "/" + slug + "_art.tscn") as PackedScene).instantiate()
	world.add_child(room)
	assert(room.module_count == layout.assets.size() + layout.instances.size() + layout.shared_plants.size(), "Missing module instances")
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	ground.position.y = -.425
	var mat := ShaderMaterial.new()
	var backdrop := Shader.new()
	backdrop.code = """shader_type spatial;
render_mode unshaded;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float t=smoothstep(-5.0,5.0,world_pos.x+world_pos.z);
 vec3 mint=vec3(0.52,0.76,0.69); vec3 cream=vec3(1.0,0.88,0.61);
 float edge=max(abs(world_pos.x),abs(world_pos.z))-3.04;
 float contact=1.0-smoothstep(-.1,.65,edge);
 ALBEDO=mix(mint,cream,t)*(1.0-contact*.13);
}"""
	mat.shader = backdrop
	if slug != "coffee_shop":
		var bg := Color(layout.lighting.background)
		backdrop.code = "shader_type spatial; render_mode unshaded; void fragment(){ ALBEDO=vec3(%f,%f,%f); }" % [bg.srgb_to_linear().r,bg.srgb_to_linear().g,bg.srgb_to_linear().b]
	ground.material_override = mat
	world.add_child(ground)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(layout.lighting.background)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(layout.lighting.ambient)
	env.ambient_light_energy = layout.lighting.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(layout.lighting.sun_color)
	sun.light_energy = layout.lighting.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	sun.light_angular_distance = layout.lighting.angular_distance
	world.add_child(sun)
	sun.position = _vec(layout.lighting.sun_position)
	sun.look_at(_vec(layout.lighting.sun_target))
	for fixture: Dictionary in layout.lighting.lamps:
		var lamp := OmniLight3D.new()
		lamp.position = _vec(fixture.position)
		lamp.light_color = Color(fixture.color)
		lamp.light_energy = fixture.energy
		lamp.omni_range = fixture.range
		lamp.shadow_enabled = false
		world.add_child(lamp)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .05
	camera.far = 150
	world.add_child(camera)
	camera.current = true
	var views := [
		["godot-whole",_vec(layout.camera.position),_vec(layout.camera.target),float(layout.camera.size)],
		["model-front",Vector3(0,1.5,20),Vector3(0,1.5,0),9.8 if slug == "coffee_shop_0" else 8.0],
		["model-side",Vector3(20,1.5,0),Vector3(0,1.5,0),9.8 if slug == "coffee_shop_0" else 8.0],
		["model-top",Vector3(.001,20,0),Vector3.ZERO,9.8 if slug == "coffee_shop_0" else 8.0],
		["godot-detail",Vector3(5,4.6,8),Vector3(-.15,1.6,-1.8),4.3],
		["godot-detail-plants",Vector3(5,4.5,8),Vector3(-2.05,1.35,-.4),3.9]
	]
	for extra: Dictionary in layout.get("review_views", []):
		views.append([str(extra.name),_vec(extra.position),_vec(extra.target),float(extra.size)])
	for view in views:
		camera.position = view[1]
		camera.look_at(view[2])
		camera.size = view[3]
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		assert(image.get_size() == viewport.size)
		assert(image.save_png(output_dir + "/" + view[0] + ".png") == OK)
		view_stats.append({"view":view[0],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"rendered_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
		print("SHOP_CAPTURE ",view[0])
	var result := {"slug":slug,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"instances":room.module_count,"static_surfaces":surface_count(room),"resolution":[1400,1400],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"views":view_stats,"scope":"offline art render; no mobile/gameplay/performance acceptance"}
	var file := FileAccess.open(output_dir + "/godot-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ")+"\n")
	print("SHOP_REVIEW_PASS ",JSON.stringify(result))
	quit()
