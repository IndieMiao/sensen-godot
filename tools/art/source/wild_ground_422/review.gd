extends Node
## Native P0 opening camera, avatar and HUD inside an exact-size viewport.
var vp: SubViewport
var pond
var runtime
var output: String
var fixture = {"energy":{"value":200,"cap":200}, "coins":180,
	"bag":{"slots":[],"free":22},"fishing":{"cast_energy":5},"travel":{"here":"san_francisco"}}
var report = {"checks":[],"captures":[],"intercepted_requests":[]}
func _ready(): run.call_deferred()
func check(ok, label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok: push_error(label)
func xyz(p): return [p.x,p.y,p.z]
func load_pond(shape):
	if is_instance_valid(pond):
		pond.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	var entries = SystemPonds.data().locations.filter(func(e): return e.template_id == shape and e.region_id == "los_angeles")
	var entry: Dictionary = entries[0]
	pond = load("res://review_pond.gd").new()
	pond.setup({"pond_id":entry.id})
	vp.add_child(pond)
	for i in 25: await get_tree().process_frame
	var ticks = 0
	while pond.actor.rig.is_busy() and ticks < 600:
		await get_tree().process_frame
		ticks += 1
	check(not pond.actor.rig.is_busy(), shape + ": native player assembled")
	runtime.ui.set_view(fixture)
	runtime.ui.set_action(pond._action_state(fixture))
	for i in 20: await get_tree().process_frame
	pond._update_camera()
	check(pond._opening and not pond._parked, shape + ": native default opening")
	check(pond.actor.position.is_equal_approx(Vector3(6.125,0,-1.625)), shape + ": unchanged spawn")
func material(shape):
	var m = ShaderMaterial.new()
	m.shader = load("res://pond_ground.sample.gdshader")
	m.set_shader_parameter("meadow_color",load("res://assets/ponds/ground/meadow_color.png"))
	m.set_shader_parameter("ground_layout",load("res://assets/ponds/ground/"+shape+"_layout.png"))
	return m
func capture(name):
	for i in 16: await RenderingServer.frame_post_draw
	var image = vp.get_texture().get_image()
	check(image.get_size() == vp.size, name + ": exact dimensions")
	check(image.save_png(output + "/" + name + ".png") == OK, "saved " + name)
	var data = {"name":name,"pixels":[vp.size.x,vp.size.y],"pond":pond.entry.id,
		"camera":str(pond.cam.global_transform),"pitch_degrees":pond.cam.rotation_degrees.x,
		"width_m":pond.cam.size,"player":xyz(pond.actor.position),
		"draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	report.captures.append(data)
	print("WILD_GROUND_CAPTURE ",name)
func run():
	output = ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(output)
	vp = SubViewport.new()
	vp.size = Vector2i(360,800)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var display = TextureRect.new()
	display.texture = vp.get_texture()
	display.size = Vector2(360,800)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(display)
	runtime = P0Runtime.new()
	P0Runtime._instance = runtime
	runtime.session.transport = func(method,path,_body,meta):
		report.intercepted_requests.append({"method":method,"path":path,"type":meta.get("type","")})
	vp.add_child(runtime)
	runtime.set_process(false)
	runtime.session.set_process(false)
	for shape in ["crescent","gourd","meander"]:
		vp.size = Vector2i(360,800)
		runtime.ui.root.visible = true
		await load_pond(shape)
		var ground = pond.get_node("Scenery/BankGround")
		var original = ground.material_override
		# The staging script pins procedural shader time in the private copies.
		await capture(shape + "_before_360x800")
		ground.material_override = material(shape)
		await capture(shape + "_after_360x800")
		runtime.ui.root.visible = false
		vp.size = Vector2i(1000,1100)
		pond.cam.size = 20.8
		pond.cam.position = Vector3(6,30,-8)
		pond.cam.look_at(Vector3(6,0,-8),Vector3(0,0,-1))
		await capture(shape + "_overhead")
		ground.material_override = original
		await capture(shape + "_overhead_before")
	report.renderer = {"method":RenderingServer.get_current_rendering_method(),
		"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string}
	check(report.renderer.method == "mobile", "Godot Mobile renderer")
	check(report.intercepted_requests.all(func(r): return r.type == "telemetry" or r.method == HTTPClient.METHOD_GET),
		"only intercepted startup queries; no game mutations")
	report.passed = report.checks.all(func(c): return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WILD_GROUND_VERIFY ",report.passed)
	get_tree().quit(0 if report.passed else 1)
