extends Node
const Old=preload("res://zz_spot_art_old.gd")
var rt: P0Runtime
var pond
var fixture: Dictionary
var checks:=[]
var report:={}
func _ready() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func respond(cmd: Dictionary) -> void:
	rt.session._finish(HTTPRequest.RESULT_SUCCESS,200,JSON.stringify({"ok":true,"state":fixture,"events":[]}).to_utf8_buffer(),cmd)
func meshes(node: Node) -> Array:
	var out: Array=node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D:out.push_front(node)
	return out
func bounds(node: Node3D) -> AABB:
	var box:=AABB();var first:=true
	for mesh in meshes(node):
		var at: AABB=node.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		box=at if first else box.merge(at);first=false
	return box
func run() -> void:
	rt=P0Runtime.ensure();fixture=JSON.parse_string(FileAccess.get_file_as_string("res://view.json"))
	rt.session.view=fixture;rt.session._received_ms=Time.get_ticks_msec()
	rt.session.transport=func(_method,_path,_body,cmd):respond.call_deferred(cmd)
	for i in 3:await get_tree().process_frame
	var target: String=load("res://scenes/p0/p0_boot.gd").wanted()
	check(target=="pond:pond_san_francisco_03","P0_SCENE selects requested Fern Pond")
	pond=load("res://scenes/p0/p0_pond.tscn").instantiate();pond.setup({"pond_id":target.trim_prefix("pond:")});add_child(pond)
	# Art fixture has no multiplayer server; retain the native pond world and HUD.
	if pond.online:pond.online.stop()
	for i in 150:await get_tree().process_frame
	check(not pond.actor.rig.is_busy(),"native player fully assembled")
	check(pond.p0_dev(PackedStringArray(["goto","0.95","-8.4"])),"requested native goto debug step accepted")
	for i in 45:await get_tree().process_frame
	check(pond.actor.position.distance_to(Vector3(.95,0,-8.4))<.001,"player at requested stand")
	check(pond.bp.is_walkable(pond.bp.world_to_cell(pond.actor.position)),"player stand remains walkable")
	check(absf(pond.cam.rotation_degrees.x+43)<.001 and absf(pond.cam.size-6.72)<.001,"native default 43 degree / 6.72 m zoom")
	var model: Node3D=pond.get_node("Scenery/HardwoodL2")
	check(model.position.is_equal_approx(Vector3(-.3,0,-9)),"hardwood centred on L2")
	check(model.scale.is_equal_approx(Vector3.ONE),"native model scale 1.0")
	var box:=bounds(model)
	check(box.size.x<=1.5 and box.size.z<=1.5 and absf(box.size.y-2.3)<.001,"whole canopy and timber fit slot / height")
	var triangles:=0;var surfaces:=0
	for mesh in meshes(model):
		for surface in mesh.mesh.get_surface_count():
			triangles+=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3;surfaces+=1
			var mat:=mesh.get_active_material(surface) as StandardMaterial3D
			check(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb,"linear vertex colour in actual imported material")
			check(is_equal_approx(mat.roughness,.9) and mat.metallic==0 and is_equal_approx(mat.metallic_specular,.18),"farm matte material")
	check(triangles<=1200 and surfaces==1,"actual imported triangle and surface budget")
	check(model.find_children("*","Skeleton3D",true,false).is_empty() and model.find_children("*","AnimationPlayer",true,false).is_empty(),"static asset, no skeleton")
	var config:=ConfigFile.new();assert(config.load("res://assets/farm/art/hardwood_grove.glb.import")==OK)
	check(config.get_value("params","meshes/light_baking",0)==1 and config.get_value("params","gltf/texture_map_mode",0)==1,"light_baking=1 / texture_map_mode=1")
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for i in 8:
		var point: Vector2=pond.cam.unproject_position(model.to_global(box.get_endpoint(i)));low=low.min(point);high=high.max(point)
	var screen:=Rect2(low,high-low)
	check(Rect2(0,0,360,800).encloses(screen),"whole hardwood in native viewport")
	report.pond={"id":pond.p0_place(),"template":pond.entry.template_id,"slot":str(model.position),"stand":str(pond.actor.position),"mesh_bounds":str(box),"screen_rect":str(screen),"camera":str(pond.cam.transform),"view_width":pond.cam.size}
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image();check(image.save_png("res://../pond.png")==OK,"native pond screenshot saved")
	report.pond.pixels=str(image.get_size())
	# Four assets in their native scales under the same pond light/environment.
	var vp:=SubViewport.new();vp.size=Vector2i(1800,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var stage:=Node3D.new();vp.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=pond.environment.duplicate();stage.add_child(env)
	var sun: DirectionalLight3D=pond.get_node("PondSun").duplicate();stage.add_child(sun)
	var ground: MeshInstance3D=pond.get_node("Scenery/BankGround").duplicate();stage.add_child(ground)
	var names:=["Hardwood","Timber Grove","Reed Bank","Herb Patch"]
	var nodes: Array=[]
	var own=load("res://assets/farm/art/hardwood_grove.glb").instantiate();own.position=Vector3(-4.5,0,0);stage.add_child(own);nodes.append(own)
	for row in [["spot_grove",-1.5],["spot_reed_bank",1.5],["spot_herb_patch",4.5]]:
		var prop=Old.build(row[0],Vector3(row[1],0,0));stage.add_child(prop);nodes.append(prop)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.size=11.5;cam.near=.1;cam.far=80;vp.add_child(cam)
	cam.global_basis=pond.cam.global_basis;cam.global_position=Vector3(0,.95,0)+cam.global_basis.z*15;cam.make_current()
	for i in 15:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	image=vp.get_texture().get_image();check(image.save_png("res://../comparison.png")==OK,"four resource comparison saved")
	report.comparison=[]
	for i in nodes.size():report.comparison.append({"name":names[i],"position":str(nodes[i].position),"bounds":str(bounds(nodes[i]))})
	report.asset_sha256=FileAccess.get_sha256("res://assets/farm/art/hardwood_grove.glb")
	report.triangles=triangles;report.surfaces=surfaces;report.renderer=RenderingServer.get_current_rendering_method();report.gpu=RenderingServer.get_video_adapter_name()
	report.checks=checks;report.passed=checks.all(func(c):return c.passed)
	FileAccess.open("res://../render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("HARDWOOD_RENDER ",report.passed," checks=",checks.size()," cost=",triangles,"/",surfaces)
	vp.queue_free();pond.queue_free();rt.queue_free();await get_tree().process_frame;get_tree().quit(0 if report.passed else 1)
