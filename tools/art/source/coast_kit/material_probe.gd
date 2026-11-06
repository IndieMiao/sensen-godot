extends SceneTree
## Actual GPU checks for palette switching, opacity, world height and MultiMesh.
const KIT := "res://assets/landmarks/_shared/coast_kit/"
var vp: SubViewport
var world := Node3D.new()
var node := MeshInstance3D.new()
var report := {"checks":[],"captures":[],"metrics":{}}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	report.checks.append({"check":label,"passed":ok})
	if not ok: push_error(label)
func frames(n: int) -> void:
	for i in n: await process_frame
func capture(label: String) -> Image:
	await frames(6); RenderingServer.force_draw(true)
	var image := vp.get_texture().get_image()
	image.save_png("res://../probe_"+label+".png")
	report.captures.append({"name":label,"draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	return image
func maximum_difference(a: Image,b: Image,area: Rect2i) -> float:
	var value := 0.0
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var p := a.get_pixel(x,y); var q := b.get_pixel(x,y)
			value=maxf(value,maxf(absf(p.r-q.r),maxf(absf(p.g-q.g),absf(p.b-q.b))))
	return value
func first_wet_row(dry: Image,wet: Image) -> int:
	for y in range(15,100):
		if maximum_difference(dry,wet,Rect2i(58,y,4,1))>1.5/255.0:return y
	return -1
func plane_with_code(code: float) -> ArrayMesh:
	var quad := QuadMesh.new();quad.size=Vector2.ONE
	var arrays := quad.surface_get_arrays(0);var colors:=PackedColorArray()
	var colour := Color("AD9D86").srgb_to_linear();colour.a=code
	for vertex in arrays[Mesh.ARRAY_VERTEX]:colors.append(colour)
	arrays[Mesh.ARRAY_COLOR]=colors
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return result
func run() -> void:
	report["source_sha256"]={}
	for file in ["coast_surface.gdshader","coast_cool_gray.tres","coast_warm_sand.tres","coast_kit_import.gd"]:
		report.source_sha256[file]=FileAccess.get_sha256(KIT+file)
	vp=SubViewport.new();vp.size=Vector2i(120,120);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp);vp.add_child(world)
	var display:=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,360);root.add_child(display)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("323232");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;world.add_child(env)
	var sun:=DirectionalLight3D.new();sun.light_energy=.2;world.add_child(sun)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.size=1.2;cam.position=Vector3(0,.5,2);world.add_child(cam);cam.make_current()
	node.mesh=plane_with_code(.125);node.position.y=.5;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;world.add_child(node)
	var mat:=load(KIT+"coast_cool_gray.tres").duplicate() as ShaderMaterial
	mat.set_shader_parameter("wet_strength",0.0);mat.set_shader_parameter("rock_palette",0);node.material_override=mat
	var mesh_id:=node.mesh.get_instance_id();var material_id:=mat.get_instance_id()
	var sand: Image=await capture("sand")
	mat.set_shader_parameter("rock_palette",1)
	var grey: Image=await capture("grey")
	check(node.mesh.get_instance_id()==mesh_id and mat.get_instance_id()==material_id,"palette switches one uniform on the same mesh and material")
	check(maximum_difference(sand,grey,Rect2i(20,20,80,80))>.08,"two palettes are visibly distinct")
	var reference:=StandardMaterial3D.new();reference.albedo_color=Color("777A75");reference.roughness=.94;reference.metallic_specular=.15;node.material_override=reference
	var standard: Image=await capture("v3_reference")
	var colour_error:=maximum_difference(grey,standard,Rect2i(20,20,80,80))
	report.metrics["v3_base_max_rgb_error_255"]=colour_error*255
	check(colour_error<=2.0/255.0,"cool palette matches #801 v3 colour under native lighting")
	check(mat.next_pass==null,"single material pass")
	node.mesh=plane_with_code(.75);node.material_override=mat;mat.set_shader_parameter("rock_palette",0);mat.set_shader_parameter("water_level",.15);mat.set_shader_parameter("wet_height",.25)
	var dry: Image=await capture("dry")
	mat.set_shader_parameter("wet_strength",.38)
	var wet: Image=await capture("wet")
	check(maximum_difference(dry,wet,Rect2i(20,20,80,45))<.004,"wet band leaves surfaces above water + 0.25m unchanged")
	check(maximum_difference(dry,wet,Rect2i(20,92,80,6))>.025,"waterline region visibly darkens")
	var first:=first_wet_row(dry,wet);report.metrics["wet_start_pixel_row"]=first
	check(first>=68 and first<=80,"wet fade starts at water + 0.25m")
	var depths: Array[float]=[]
	for y in [78,84,90,96]:depths.append(maximum_difference(dry,wet,Rect2i(58,y,4,1)))
	check(depths[0]<depths[1] and depths[1]<=depths[2] and depths[2]<=depths[3],"wetness fades smoothly instead of adding a hard stripe")
	mat.set_shader_parameter("water_level",.35)
	var raised: Image=await capture("raised_water")
	var raised_first:=first_wet_row(dry,raised);report.metrics["raised_water_start_pixel_row"]=raised_first
	check(abs(first-raised_first-20)<=2,"raising water 0.20m moves the wet band by 20 pixels")
	mat.set_shader_parameter("water_level",.15);node.position.y=.6;mat.set_shader_parameter("wet_strength",0.0)
	var moved_dry: Image=await capture("moved_dry")
	mat.set_shader_parameter("wet_strength",.38)
	var moved_wet: Image=await capture("moved_wet")
	check(abs(first_wet_row(moved_dry,moved_wet)-first)<=1,"translated mesh stays aligned to world water height")
	node.visible=false
	var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=node.mesh;mm.instance_count=1;mm.set_instance_transform(0,Transform3D(Basis(),Vector3(0,.6,0)))
	var batch:=MultiMeshInstance3D.new();batch.multimesh=mm;batch.material_override=mat;batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;world.add_child(batch)
	mat.set_shader_parameter("wet_strength",0.0);var batch_dry: Image=await capture("multimesh_dry")
	mat.set_shader_parameter("wet_strength",.38);var batch_wet: Image=await capture("multimesh_wet")
	check(abs(first_wet_row(batch_dry,batch_wet)-first)<=1,"MultiMesh instance transforms preserve the world wet band")
	check(report.captures.all(func(c):return c.draws==1 and c.triangles==2),"palette / wetness / MultiMesh add no draw or geometry pass")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};check(report.renderer.method=="mobile","Mobile GPU probe")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open("res://../material-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("COAST_MATERIAL ",report.passed," ",report.checks.size()," checks ",report.metrics)
	quit(0 if report.passed else 1)
