extends Node
## Imported GLBs in the real room kits. Review-only; never edits room anchors.
const KIT="res://assets/props/warming_cabinet/"
var report={"checks":[],"assets":{},"captures":[],"placements":{}}
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var heading:Label
var footer:Label
var output:String
var contract:Dictionary
var fixture:Dictionary
var sun:DirectionalLight3D
var room:Node3D
var cabinet:Node3D
var rig:Node3D
var old_glow:OmniLight3D
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(p):return [p.x,p.y,p.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func meshes(node):return node.find_children("*","MeshInstance3D",true,false)
func audit(option):
	var model=load(KIT+"warming_cabinet_"+option+".glb").instantiate()
	var all=meshes(model);var box=AABB();var first=true;var triangles=0;var surfaces=0
	var groups={}
	for m in all:
		var transform=model.transform.affine_inverse()*m.transform
		var b=transform*m.mesh.get_aabb()
		box=b if first else box.merge(b);first=false
		var count=m.mesh.get_faces().size()/3;triangles+=count;surfaces+=m.mesh.get_surface_count()
		groups[m.name]={"triangles":count,"surfaces":m.mesh.get_surface_count(),"bounds":[xyz(b.position),xyz(b.end)]}
		check(m.transform.is_equal_approx(Transform3D.IDENTITY),option+" identity node transform: "+m.name)
		for s in m.mesh.get_surface_count():
			var mat=m.mesh.surface_get_material(s)
			check(mat!=null,option+" material exists: "+m.name+"/"+str(s))
			if mat.resource_name=="Warming_Glass_A":
				check(is_equal_approx(mat.albedo_color.a,.15) and mat.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA,BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS],"A imported alpha pane is 0.15")
			else:
				check(mat.albedo_texture!=null and not mat.emission_enabled,option+" imported opaque atlas / no emission: "+m.name+"/"+str(s))
	check(box.size.distance_to(Vector3(.56,1.32,.50))<.00001,option+" imported dimensions 0.56 x 1.32 x 0.50 m")
	check(box.position.distance_to(Vector3(-.28,0,0))<.00001,option+" grounded back-plane pivot, +Z front")
	check(triangles==contract.variants[option].triangles and triangles<=1500,option+" actual imported triangle budget")
	check(surfaces==contract.variants[option].surfaces,option+" actual imported surfaces match manifest")
	check(model.transform.is_equal_approx(Transform3D.IDENTITY),option+" root scale 1 / identity")
	for i in range(1,7):
		var d=model.find_child("dish_"+str(i),true,false)
		check(d is MeshInstance3D,option+" independent mesh dish_"+str(i))
		if d:
			var p=d.mesh.get_aabb().get_center()
			check((p.x<0 if i%2==1 else p.x>0),option+" dish left/right ordering "+str(i))
	for key in contract.sockets:
		var marker=model.find_child(key,true,false)
		check(marker!=null and not marker is MeshInstance3D,option+" empty socket "+key)
		if marker:check(marker.position.distance_to(vec(contract.sockets[key]))<.00001,option+" exact socket "+key)
	check(model.find_children("*","Light3D",true,false).is_empty(),option+" asset contains no realtime light")
	report.assets[option]={"bounds":[xyz(box.position),xyz(box.end)],"size":xyz(box.size),"triangles":triangles,"surfaces":surfaces,"groups":groups}
	model.free()
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
	footer=Label.new();footer.position=Vector2(12,size.y-65);footer.add_theme_font_size_override("font_size",11 if size.x==360 else 18);footer.add_theme_color_override("font_color",Color("394b42"));layer.add_child(footer)
func pose(focus,size,pitch,yaw):
	camera.size=size;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*20
func capture(id):
	for i in 12:await RenderingServer.frame_post_draw
	var img=vp.get_texture().get_image();check(img.save_png(output+"/"+id+".png")==OK,"Saved "+id)
	report.captures.append({"id":id,"width":img.get_width(),"height":img.get_height(),"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y,"camera_size":camera.size,"camera_position":xyz(camera.position)})
	print("WARMING_CAPTURE ",id)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	contract=JSON.parse_string(FileAccess.get_file_as_string(KIT+"manifest.json"));fixture=JSON.parse_string(FileAccess.get_file_as_string("res://review-fixture.json"))
	for option in ["a","b"]:audit(option)
	for slug in ["basic_room","standard_room_5"]:
		var layout=JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/"+slug+"/layout.json"))
		setup(layout,Vector2i(360,800))
		room=load("res://scenes/"+slug+"/"+slug+"_art.tscn").instantiate();world.add_child(room)
		# The actual Basic anchor adds the seasoning rack, absent from base art.
		for prop in fixture.anchors[slug].props:
			var original=room.get_node(prop.from);var copy=original.duplicate();copy.name=prop.name;room.add_child(copy)
			copy.position=vec(prop.position);copy.rotation_degrees=Vector3(0,prop.yaw_degrees,0);copy.scale=Vector3.ONE*prop.scale
		# Retain the already-programmed placeholder light at its present world
		# position and energy. The GLB itself contains no light or emission.
		var old=fixture.anchors[slug].old_cabinet
		old_glow=OmniLight3D.new();world.add_child(old_glow);old_glow.light_color=Color("ffb87a");old_glow.light_energy=.9;old_glow.omni_range=1.1
		old_glow.position=vec(old.position)+Basis(Vector3.UP,deg_to_rad(old.yaw_degrees))*(Vector3(0,1.1133,.795)*old.scale)
		rig=Avatar.create_rig()
		for child in rig.get_children():
			if child is RigActivity:child.free()
		rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.position=Vector3(-.85,.082,-.75);rig.rotation.y=-PI/2;rig.apply_config(Avatar.slot_table.default_config())
		var ticks=0
		while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
		check(not rig.is_busy(),slug+" actual character assembled")
		rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
		var offset=vec(layout.camera.position)-vec(layout.camera.target);var yaw=rad_to_deg(atan2(offset.x,offset.z))
		pose(Vector3(-1.1,1.25,-.45),6.72,43,yaw)
		var at=contract.placements[slug]
		for option in ["a","b"]:
			cabinet=load(KIT+"warming_cabinet_"+option+".glb").instantiate();world.add_child(cabinet);cabinet.position=vec(at.position);cabinet.rotation_degrees.y=at.yaw_degrees
			heading.text="WARMING CABINET / "+option.to_upper()+"\n"+("BASIC ROOM" if slug=="basic_room" else "STANDARD ROOM")+" / 43 DEG"
			footer.text="SGODOT-282 / LIU BEI\n0.56 W x 0.50 D x 1.32 H m\n"+("A: alpha 0.15 glass" if option=="a" else "B: diagonal glass cues; no pane")+" / 360 x 800 / view 6.72 m"
			await capture(slug+"_"+option+"_43deg")
			report.placements[slug]={"position":at.position,"yaw":at.yaw_degrees,"existing_glow_position":xyz(old_glow.position)}
			# Extra clearly identified close views aid inspection; never substitute
			# these for the four uncropped default-camera phone-size captures.
			if option=="b":
				pose(vec(at.position)+Vector3(.25,.75,0),3.5,43,yaw)
				heading.text="WARMING CABINET / B / DETAIL\n"+slug.to_upper();await capture(slug+"_b_detail")
				pose(Vector3(-1.1,1.25,-.45),6.72,43,yaw)
			cabinet.free()
		vp.free()
	setup({},Vector2i(1000,1000));sun.shadow_enabled=false
	for option in ["a","b"]:
		cabinet=load(KIT+"warming_cabinet_"+option+".glb").instantiate();world.add_child(cabinet)
		for view in [["front",0,0],["three_quarter",18,35],["side",0,90]]:
			pose(Vector3(0,.66,.25),1.72,view[1],view[2])
			heading.text="WARMING CABINET / "+option.to_upper()+" / "+view[0].replace("_"," ").to_upper()
			footer.text="SGODOT-282 / LIU BEI / 0.56 W x 0.50 D x 1.32 H m\n"+("Alpha 0.15 pane" if option=="a" else "No pane; two diagonal glass cues")+" / six independent dishes / detail shadows off"
			await capture(option+"_"+view[0])
		cabinet.free()
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name()
	report.failures=report.checks.filter(func(c):return not c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WARMING_QA ",report.checks.size()," checks, ",report.failures.size()," failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)
