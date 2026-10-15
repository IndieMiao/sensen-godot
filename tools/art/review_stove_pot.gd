extends Node
## SGODOT-282. Imported pots with real room kits; review fixture only.
const KIT="res://assets/props/stove_pot/"
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
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(p):return [p.x,p.y,p.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func each_mesh(node):return node.find_children("*","MeshInstance3D",true,false)
func audit():
	var model=load(KIT+"stove_pot.glb").instantiate();add_child(model)
	check(model.get_child_count()==2,"exactly two imported variant nodes")
	check(model.transform.is_equal_approx(Transform3D.IDENTITY),"imported root scale 1 / identity")
	for id in ["pot_normal","pot_big"]:
		var variant=model.get_node(id);var box=AABB();var first=true;var triangles=0;var surfaces=0
		for m in each_mesh(variant):
			var transform=variant.global_transform.affine_inverse()*m.global_transform
			# Read actual imported vertex arrays, not a compressed metadata AABB.
			for s in m.mesh.get_surface_count():
				var arrays=m.mesh.surface_get_arrays(s)
				for p in arrays[Mesh.ARRAY_VERTEX]:
					var point=transform*p
					if first:box=AABB(point,Vector3.ZERO);first=false
					else:box=box.expand(point)
				triangles+=arrays[Mesh.ARRAY_INDEX].size()/3;surfaces+=1
				var mat=m.mesh.surface_get_material(s)
				check(mat.albedo_texture!=null and not mat.emission_enabled and mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,id+" opaque textured material / no emission")
		check(triangles==contract.variants[id].triangles,id+" imported triangle count")
		check(box.size.x<=(.24001 if id=="pot_normal" else .28001),id+" width including handles")
		check(abs(box.position.y)<.000001,id+" bottom on Y=0")
		check(variant.get_node("mouth").position.distance_to(vec(contract.variants[id].mouth))<.000001,id+" mouth path and position")
		check(not variant.get_node("mouth") is MeshInstance3D,id+" mouth is empty")
		report.assets[id]={"bounds":[xyz(box.position),xyz(box.end)],"size_xyz":xyz(box.size),"triangles":triangles,"surfaces":surfaces}
	var big=model.get_node("pot_big")
	check(big.get_node("lid").position.distance_to(vec(contract.variants.pot_big.lid_pivot))<.000001,"lid rear-edge local pivot")
	check(big.get_node("vent").position.distance_to(vec(contract.variants.pot_big.vent))<.000001,"direct child vent at outlet")
	check(model.find_children("*","Light3D",true,false).is_empty(),"no light nodes")
	model.free()
func pot(id,at=Vector3.ZERO,yaw=0):
	var model=load(KIT+"stove_pot.glb").instantiate();world.add_child(model);model.position=at;model.rotation_degrees.y=yaw
	for child in model.get_children():child.visible=child.name==id
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
	footer=Label.new();footer.position=Vector2(12,size.y-65);footer.add_theme_font_size_override("font_size",11 if size.x==360 else 18);footer.add_theme_color_override("font_color",Color("394b42"));layer.add_child(footer)
func pose(focus,size,pitch,yaw):
	camera.size=size;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*20
func capture(id):
	for i in 12:await RenderingServer.frame_post_draw
	var img=vp.get_texture().get_image();check(img.save_png(output+"/"+id+".png")==OK,"Saved "+id)
	report.captures.append({"id":id,"width":img.get_width(),"height":img.get_height(),"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y,"camera_size":camera.size,"camera_position":xyz(camera.position)})
	print("STOVE_POT_CAPTURE ",id)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	contract=JSON.parse_string(FileAccess.get_file_as_string(KIT+"manifest.json"));fixture=JSON.parse_string(FileAccess.get_file_as_string("res://review-fixture.json"))
	audit()
	setup({},Vector2i(900,900));sun.shadow_enabled=false
	for id in ["pot_normal","pot_big"]:
		var model=pot(id)
		for view in [["front",0,0],["three_quarter",25,35],["side",0,90]]:
			pose(Vector3(0,.12,0),.42,view[1],view[2])
			heading.text="STOVE POT / "+id.replace("pot_", "").to_upper()+" / "+view[0].replace("_"," ").to_upper()
			footer.text="SGODOT-282 / LIU BEI / "+str(contract.variants[id].triangles)+" triangles\n"+("Open / hollow / 0.14 m high" if id=="pot_normal" else "Hollow stockpot / hinged lid / 0.242 m high")
			await capture(id+"_"+view[0])
		if id=="pot_big":
			var lid=model.get_node("pot_big/lid");lid.position.y+=.06;lid.rotation_degrees.x=-20
			pose(Vector3(0,.16,0),.47,30,35);heading.text="BIG POT / OPEN LID"
			footer.text="SGODOT-282 / LIU BEI\nLid +0.06 m / local X -20 deg / empty interior"
			await capture("pot_big_open_lid")
		model.free()
	vp.free()
	for slug in ["basic_room","standard_room_5","deluxe_room_10"]:
		var layout=JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/"+slug+"/layout.json"))
		setup(layout,Vector2i(360,800));var room=load("res://scenes/"+slug+"/"+slug+"_art.tscn").instantiate();world.add_child(room)
		for prop in fixture.anchors[slug].props:
			var copy:Node3D
			if prop.has("from"):copy=room.get_node(prop.from).duplicate()
			else:copy=load(prop.scene.replace("/warming_cabinet.glb","/warming_cabinet_b.glb")).instantiate()
			copy.name=prop.name;room.add_child(copy);copy.position=vec(prop.position);copy.rotation_degrees.y=prop.yaw_degrees;copy.scale=Vector3.ONE*prop.scale
		var at=contract.placements[slug]
		for hidden in at.hide:room.get_node(hidden).hide()
		report.placements[slug]={"y":at.y,"xz":at.xz,"yaw_degrees":[0,0,45] if slug=="standard_room_5" else [0,0,0],"basic_kettle_hidden":slug=="basic_room","deluxe_old_kettle_removed_in_fixture":slug=="deluxe_room_10"}
		var models=[]
		for i in 3:
			var xy=at.xz[i];models.append(pot("pot_big" if i==1 else "pot_normal",Vector3(xy[0],at.y,xy[1]),45 if slug=="standard_room_5" and i==2 else 0))
		var rig=Avatar.create_rig()
		for child in rig.get_children():
			if child is RigActivity:child.free()
		rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig)
		rig.position=Vector3(-1.05,.082,-1.55) if slug=="basic_room" else Vector3(1.1,.082,-1.75) if slug=="standard_room_5" else Vector3(-3.15,.082,-.65)
		rig.rotation.y=0;rig.apply_config(Avatar.slot_table.default_config());var ticks=0
		while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
		check(not rig.is_busy(),slug+" real avatar assembled");rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
		var offset=vec(layout.camera.position)-vec(layout.camera.target);var yaw=rad_to_deg(atan2(offset.x,offset.z))
		var focus=Vector3(-.7,1.2,-.7) if slug=="basic_room" else Vector3(.6,1.3,-.9) if slug=="standard_room_5" else Vector3(-2.2,1.6,-.4)
		pose(focus,6.72,43,yaw)
		heading.text="STOVE POT / "+slug.replace("_room_10", "").replace("_room_5", "").replace("_room", "").to_upper()+" ROOM\nNORMAL + BIG / 43 DEG"
		footer.text="SGODOT-282 / LIU BEI\n360 x 800 / default view 6.72 m\n"+("Old kettle removed in review only" if slug=="deluxe_room_10" else "Actual stove positions / empty pots")
		await capture(slug+"_43deg")
		if slug=="standard_room_5":
			models[0].get_node("pot_normal").hide();models[0].get_node("pot_big").show()
			heading.text="STOVE POT / STANDARD ROOM\nTWO BIG POTS / 43 DEG";await capture("standard_two_big_43deg")
			models[0].get_node("pot_normal").show();models[0].get_node("pot_big").hide()
		# Extra inspection image preserves pitch/yaw; clearly labeled zoom.
		var xy=at.xz[0];pose(Vector3(xy[0],at.y+.1,xy[1]),1.25,43,yaw);rig.hide()
		heading.text="STOVE POT / KITCHEN DETAIL\n"+slug.replace("_room_10", "").replace("_room_5", "").replace("_room", "").to_upper()+" / 43 DEG"
		footer.text="SGODOT-282 / LIU BEI\nExtra detail / view 1.25 m\n"+("Old kettle removed in review only" if slug=="deluxe_room_10" else "Not the default-camera capture")
		await capture(slug+"_detail")
		vp.free()
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name();report.failures=report.checks.filter(func(c):return not c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("STOVE_POT_GODOT_QA ",report.checks.size()," checks, ",report.failures.size()," failures");get_tree().quit(0 if report.failures.is_empty() else 1)
