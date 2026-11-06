extends Node
## Native P0 opening camera, avatar and HUD inside an exact-size viewport.
var vp: SubViewport
var pond
var after_vp: SubViewport
var after_cam: Camera3D
var after_ui
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
	for i in 12: await get_tree().process_frame
	var ticks = 0
	while pond.actor.rig.is_busy() and ticks < 600:
		await get_tree().process_frame
		ticks += 1
	check(not pond.actor.rig.is_busy(), shape + ": native player assembled")
	runtime.ui.set_view(fixture)
	runtime.ui.set_action(pond._action_state(fixture))
	for i in 8: await get_tree().process_frame
	pond._update_camera()
	check(pond._opening and not pond._parked, shape + ": native default opening")
	check(pond.actor.position.is_equal_approx(Vector3(6.125,0,-1.625)), shape + ": unchanged spawn")
func capture_pair(shape, overhead := false):
	after_vp.size = vp.size
	after_cam.global_transform = pond.cam.global_transform
	after_cam.projection = pond.cam.projection
	after_cam.keep_aspect = pond.cam.keep_aspect
	after_cam.near = pond.cam.near
	after_cam.far = pond.cam.far
	after_cam.size = pond.cam.size
	for i in 8: await RenderingServer.frame_post_draw
	# Both readbacks are from the same rendered frame, with shared animated world.
	var before = vp.get_texture().get_image()
	var after = after_vp.get_texture().get_image()
	for pair in [[before,"before",vp],[after,"after",after_vp]]:
		var name = shape + ("_overhead" + ("_before" if pair[1] == "before" else "") if overhead else "_"+pair[1]+"_360x800")
		check(pair[2].get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) > 10, name + ": visible 3D scene")
		check(pair[0].get_size() == vp.size, name + ": exact dimensions")
		check(pair[0].save_png(output+"/"+name+".png") == OK, "saved " + name)
		report.captures.append({"name":name,"pixels":[vp.size.x,vp.size.y],"pond":pond.entry.id,
			"camera":str(pond.cam.global_transform),"pitch_degrees":pond.cam.rotation_degrees.x,
			"width_m":pond.cam.size,"player":xyz(pond.actor.position),"same_frame":Engine.get_frames_drawn(),
			"draw_calls":pair[2].get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
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
		ground.layers = 1 << 18
		var study = MeshInstance3D.new()
		study.mesh = ground.mesh
		study.transform = ground.transform
		study.layers = 1 << 19
		study.material_override = load("res://ground_study.gd").material(original,shape)
		ground.get_parent().add_child(study)
		for param in ["grass_detail","surface_flow"]:
			check(study.material_override.get_shader_parameter(param) == original.get_shader_parameter(param),shape+": retained "+param+" texture binding")
		pond.cam.cull_mask = ((1 << 20)-1) & ~(1 << 19)
		after_vp = SubViewport.new()
		after_vp.size = vp.size
		after_vp.world_3d = vp.find_world_3d()
		after_vp.msaa_3d = vp.msaa_3d
		after_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(after_vp)
		after_cam = Camera3D.new()
		after_cam.cull_mask = ((1 << 20)-1) & ~(1 << 18)
		after_vp.add_child(after_cam)
		after_cam.make_current()
		after_ui = P0Ui.new()
		after_vp.add_child(after_ui)
		after_ui.space = runtime.ui.space
		after_ui.place = runtime.ui.place
		after_ui.set_surface("pond")
		after_ui.set_mode("fish", load("res://modules/p0/p0_city.gd").chip_for(str(pond.entry.name),str(pond.entry.id)))
		after_ui.set_view(fixture)
		after_ui.set_action(pond._action_state(fixture))
		await capture_pair(shape)
		runtime.ui.root.visible = false
		after_ui.root.visible = false
		vp.size = Vector2i(1000,1100)
		pond.cam.size = 20.8
		pond.cam.position = Vector3(6,30,-8)
		pond.cam.look_at(Vector3(6,0,-8),Vector3(0,0,-1))
		await capture_pair(shape,true)
		after_vp.queue_free()
		await get_tree().process_frame
	report.renderer = {"method":RenderingServer.get_current_rendering_method(),
		"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string}
	check(report.renderer.method == "mobile", "Godot Mobile renderer")
	check(report.intercepted_requests.all(func(r): return r.type == "telemetry" or r.method == HTTPClient.METHOD_GET),
		"only intercepted startup queries; no game mutations")
	report.passed = report.checks.all(func(c): return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WILD_GROUND_VERIFY ",report.passed)
	get_tree().quit(0 if report.passed else 1)
