extends Node
var folder:String
func _ready():
	folder=OS.get_environment("MARKET_REVIEW")
	await overview()
	get_tree().quit()
func overview() -> void:
	var vp:=SubViewport.new();vp.size=Vector2i(1000,1000);vp.own_world_3d=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var art:Node3D=load("res://scenes/market_plaza/market_plaza_art.tscn").instantiate();vp.add_child(art)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("DDE8E7")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("FFF0DC");env.environment.ambient_light_energy=.7;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.light_energy=1;sun.light_color=Color("FFF1D8");sun.shadow_enabled=true;vp.add_child(sun);sun.position=Vector3(-6,9,3);sun.look_at(Vector3.ZERO)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=30;cam.far=120;vp.add_child(cam);cam.position=Vector3(22,29,22);cam.look_at(Vector3(0,1,0));cam.current=true
	for variant in ["san_francisco","generic"]:
		art.city_variant=variant
		for f in 10:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(folder.path_join("overview_"+variant+".png"))
	art.city_variant="san_francisco"
	art.get_node("CityBackdrop").visible=false
	cam.size=22;cam.position=Vector3(0,40,0);cam.look_at(Vector3.ZERO,Vector3.FORWARD)
	for f in 10:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(folder.path_join("topdown.png"))
	vp.queue_free()
