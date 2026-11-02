extends SceneTree
var vp:SubViewport
func _init():run.call_deferred()
func run():
	vp=SubViewport.new();vp.size=Vector2i(2400,2000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var world=Node3D.new();vp.add_child(world)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color.BLACK;world.add_child(env)
	var pitch=deg_to_rad(43.);var yaw=deg_to_rad(14.5)
	var normal=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
	var right=Vector3(cos(yaw),0,-sin(yaw));var up=normal.cross(right)
	var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=24;camera.near=.1;camera.far=50;camera.basis=Basis(right,up,normal)
	camera.position=right*6+up*2+normal*14;world.add_child(camera);camera.current=true
	var material=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color.WHITE;material.vertex_color_use_as_albedo=false
	var output=ProjectSettings.globalize_path("res://../outline");DirAccess.make_dir_recursive_absolute(output)
	var hashes={}
	for entry in [["original","res://assets/mine/backdrop/mine_backdrop.glb"],["vein","res://assets/mine/types/vein/backdrop.glb"]]:
		hashes[entry[0]]=FileAccess.get_sha256(entry[1])
		var model=load(entry[1]).instantiate();world.add_child(model)
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			mesh.material_override=material;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in 6:await RenderingServer.frame_post_draw
		var image=vp.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		assert(image.save_png(output+"/"+entry[0]+".png")==OK)
		model.queue_free();await process_frame
	var file=FileAccess.open(output+"/render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"size":[2400,2000],"u_min":-6,"v_max":12,"pixels_per_m":100,
		"msaa":4,"renderer":RenderingServer.get_current_rendering_method(),"asset_sha256":hashes},"\t")+"\n");file.close()
	print("VEIN_OUTLINE_CAPTURE_COMPLETE")
	vp.queue_free();await process_frame;quit()
