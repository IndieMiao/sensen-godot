extends Node
const KIT="res://assets/rooms/basic_room/"
var report={"checks":[],"assets":{},"captures":[],"sockets":{}}
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var heading:Label
var footer:Label
var output:String
var contract:Dictionary
var sun:DirectionalLight3D
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(p):return [p.x,p.y,p.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func audit():
	for id in contract.assets:
		var m=load(KIT+id+".glb").instantiate();add_child(m)
		var box=AABB();var first=true;var tris=0;var surfaces=0
		for mesh in m.find_children("*","MeshInstance3D",true,false):
			for si in mesh.mesh.get_surface_count():
				var a=mesh.mesh.surface_get_arrays(si);surfaces+=1;tris+=a[Mesh.ARRAY_INDEX].size()/3
				for v in a[Mesh.ARRAY_VERTEX]:
					var p=m.global_transform.affine_inverse()*mesh.global_transform*v
					if first:box=AABB(p,Vector3.ZERO);first=false
					else:box=box.expand(p)
		check(m.transform.is_equal_approx(Transform3D.IDENTITY),id+" imported identity root")
		check(tris==contract.assets[id].triangles,id+" imported triangles")
		check(surfaces==contract.assets[id].surfaces,id+" imported surfaces")
		if id=="kitchen_range_3":
			for key in contract.sockets_local:
				var socket=m.find_child(key,true,false)
				check(socket!=null and not socket is MeshInstance3D,"empty socket "+key)
				if socket:check(socket.position.distance_to(vec(contract.sockets_local[key]))<.000001,"socket transform "+key)
			for key in ["lid_2","lid_3"]:check(m.find_child(key,true,false) is MeshInstance3D,"independent cap "+key)
		report.assets[id]={"bounds":[xyz(box.position),xyz(box.end)],"size_xyz":xyz(box.size),"triangles":tris,"surfaces":surfaces};m.free()
func pot(variant,at):
	var model=load("res://assets/props/stove_pot/stove_pot.glb").instantiate();world.add_child(model);model.position=at
	for child in model.get_children():child.visible=child.name==variant
	return model
func setup(layout,size):
	vp=SubViewport.new();vp.size=size;vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;get_tree().root.add_child(vp)
	world=Node3D.new();vp.add_child(world)
	var lighting=layout.get("review_lighting",{})
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(lighting.get("background","e9e7d4"))
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(lighting.get("ambient_color","fff0dc"));env.ambient_light_energy=lighting.get("ambient",.70)
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	sun=DirectionalLight3D.new();world.add_child(sun);sun.position=vec(lighting.get("sun_position",[-6,7,1.5]));sun.look_at(Vector3.ZERO)
	sun.light_color=Color(lighting.get("sun_color","ffe6c2"));sun.light_energy=lighting.get("sun",1.05);sun.shadow_enabled=true
	sun.shadow_bias=lighting.get("shadow_bias",.045);sun.shadow_normal_bias=lighting.get("shadow_normal_bias",.4)
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.directional_shadow_max_distance=lighting.get("shadow_distance",30);sun.light_angular_distance=1.4
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1 if lighting.is_empty() else .05;camera.far=70 if lighting.is_empty() else 4000
	camera.current=true;world.add_child(camera)
	var layer=CanvasLayer.new();vp.add_child(layer)
	heading=Label.new();heading.position=Vector2(12,16);heading.add_theme_font_size_override("font_size",13 if size.x==360 else 24);heading.add_theme_color_override("font_color",Color("394b42"));layer.add_child(heading)
	footer=Label.new();footer.position=Vector2(12,size.y-90);footer.add_theme_font_size_override("font_size",11 if size.x==360 else 18);footer.add_theme_color_override("font_color",Color("394b42"));layer.add_child(footer)
func pose(focus,size,pitch,yaw):
	camera.size=size;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*20
func capture(id):
	for i in 12:await RenderingServer.frame_post_draw
	var img=vp.get_texture().get_image();check(img.save_png(output+"/"+id+".png")==OK,"Saved "+id)
	report.captures.append({"id":id,"width":img.get_width(),"height":img.get_height(),"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y,"camera_size":camera.size,"camera_position":xyz(camera.position)})
	print("KITCHEN_213_CAPTURE ",id)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	contract=JSON.parse_string(FileAccess.get_file_as_string("res://contract.json"));audit()
	setup({},Vector2i(960,960));sun.shadow_enabled=true
	var stove=load(KIT+"kitchen_range_3.glb").instantiate();world.add_child(stove)
	for view in [["range_front",0,0],["range_three_quarter",25,35],["range_side",0,90]]:
		pose(Vector3(0,.75,-.055),2.30,view[1],view[2]);heading.text="BASIC KITCHEN / "+view[0].replace("_"," ").to_upper()
		footer.text="SGODOT-213 / LIU BEI / 1.35 W x 0.60 D m body\nStove top: 0.980 m world / 0.45 m burner pitch\nIndependent lid_2 + lid_3; arched fireboxes remain open"
		await capture(view[0])
	vp.free()
	var layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	setup(layout,Vector2i(360,800))
	var room=load("res://scenes/basic_room/basic_room_art.tscn").instantiate();world.add_child(room)
	stove=room.get_node("kitchen_range_3")
	for key in contract.sockets_world:
		var socket=stove.find_child(key,true,false);check(socket.global_position.distance_to(vec(contract.sockets_world[key]))<.000001,"world socket "+key);report.sockets[key]=xyz(socket.global_position)
	var cabinet=load("res://assets/props/warming_cabinet/warming_cabinet_b.glb").instantiate();world.add_child(cabinet);cabinet.position=Vector3(-2.85,.082,-1.69);cabinet.rotation_degrees.y=90
	var fire=OmniLight3D.new();world.add_child(fire);fire.position=vec(layout.fire_position);fire.light_color=Color("ffb041");fire.light_energy=.7;fire.omni_range=1.1;fire.shadow_enabled=false
	var normal=pot("pot_normal",vec(contract.sockets_world.stove_1_top));var big=pot("pot_big",vec(contract.sockets_world.stove_2_top))
	stove.find_child("lid_2",true,false).hide()
	var rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.position=Vector3(-.95,.082,-1.35);rig.rotation_degrees.y=0;rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"real avatar assembled");rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
	var off=vec(layout.camera.position)-vec(layout.camera.target);var yaw=rad_to_deg(atan2(off.x,off.z))
	pose(Vector3(0,1.5,0),10.75,43,yaw);heading.text="BASIC ROOM / COMPLETE ROOM\n43 DEG / NORMAL + BIG POT"
	footer.text="SGODOT-213 / LIU BEI\n360 x 800 / full-room view 10.75 m\n#434 pots / warming cabinet B unchanged"
	await capture("basic_room_43deg_360")
	pose(Vector3(-1.65,1.16,-1.95),3.45,43,yaw);heading.text="BASIC ROOM / KITCHEN CORNER\n43 DEG / DETAIL"
	footer.text="SGODOT-213 / LIU BEI\n360 x 800 / detail view 3.45 m\nNormal + Big on exact stove sockets"
	await capture("kitchen_corner_360")
	# Additional default gameplay framing; complete-room evidence stays above.
	pose(Vector3(-.65,1.25,-.55),6.72,43,yaw);heading.text="BASIC ROOM / GAMEPLAY FRAMING\n43 DEG / 6.72 M VIEW";footer.text="SGODOT-213 / LIU BEI\n360 x 800 / additional framing\nFull room supplied separately"
	await capture("basic_gameplay_43deg_360")
	big.hide();stove.find_child("lid_2",true,false).show();pose(Vector3(-1.85,.95,-2.25),2.25,30,25);rig.hide();heading.text="KITCHEN / LEVEL 1 CAPS\nSTOVE 1 LIT / 2 + 3 COVERED";footer.text="SGODOT-213 / LIU BEI\nCaps are independent top meshes\nReview state only; runtime owns unlocks"
	await capture("level1_caps_360")
	vp.free()
	setup({},Vector2i(960,960));sun.shadow_enabled=false
	for id in ["spice_rack","cookbook_wall"]:
		var model=load(KIT+id+".glb").instantiate();world.add_child(model);pose(Vector3(0,.07,0),.82,14,20);heading.text="BASIC KITCHEN / "+id.replace("_"," ").to_upper();footer.text="SGODOT-213 / LIU BEI\nShared Basic Room atlas / plain surfaces / no text";await capture(id+"_detail");model.free()
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name();report.failures=report.checks.filter(func(c):return not c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("KITCHEN_213_GODOT_QA ",report.checks.size()," checks, ",report.failures.size()," failures");get_tree().quit(0 if report.failures.is_empty() else 1)
