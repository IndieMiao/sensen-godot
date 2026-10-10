extends Node
## Offline SGODOT-290 structural validation and rendered art delivery.
const Art = preload("res://modules/farm/farm_art.gd")
const IDS = ["deco_planter","deco_lantern","deco_path","deco_bench","deco_scarecrow","deco_fence","deco_birdbath","deco_windmill","deco_fountain","deco_pergola"]
const NAMES = ["01  FLOWER PLANTER","02  GARDEN LANTERN","03  STONE PATH","04  WOODEN BENCH","05  SCARECROW","06  FENCE SEGMENT","07  BIRDBATH","08  WINDMILL","09  FOUNTAIN","10  PERGOLA"]
var vp: SubViewport
var world: Node3D
var cam: Camera3D
var stage: Node3D
var rig: AvatarRig
var labels: Array[Label] = []
var origins: Array[Vector3] = []
var report = {"assets":[], "checks":[], "captures":[]}
var out: String
var manifest: Dictionary

func _ready(): _run.call_deferred()

func check(ok: bool, what: String):
	report.checks.append({"check":what,"passed":ok})
	if not ok: push_error(what)

func meshes(node: Node):
	var result = node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D: result.push_front(node)
	return result

func _run():
	out = ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(out)
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/art/manifest.json"))
	for id in IDS + ["deco_windmill_sails"]:
		var scene = load("res://assets/farm/art/"+id+".glb").instantiate()
		var nodes=meshes(scene)
		check(nodes.size()==1,id+": exactly one MeshInstance3D")
		var mesh: Mesh=Art.mesh_for(id)
		check(mesh!=null and mesh.get_surface_count()==1,id+": FarmArt mesh_for / one surface")
		var entry=manifest.assets[id]
		var tris=mesh.get_faces().size()/3
		var box=mesh.get_aabb()
		check(tris==int(entry.triangles) and tris<=int(entry.triangle_limit),id+": triangle budget / manifest")
		check((scene.transform if scene is Node3D else Transform3D.IDENTITY).is_equal_approx(Transform3D.IDENTITY),id+": scene root identity")
		check(nodes[0].transform.is_equal_approx(Transform3D.IDENTITY),id+": mesh baked at origin")
		check(absf(box.position.y)<.00001 if id!="deco_windmill_sails" else absf(box.get_center().x)<.00001 and absf(box.get_center().y)<.00001,id+": grounded or axle pivot")
		var arrays=mesh.surface_get_arrays(0)
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var opaque=not colors.is_empty()
		for c in colors: opaque = opaque and is_equal_approx(c.a,1.0)
		check(opaque,id+": opaque vertex colors")
		for socket_name in entry.sockets:
			var socket=scene.find_child(socket_name,true,false)
			var p=entry.sockets[socket_name].position
			check(socket!=null,id+": socket "+socket_name+" exists")
			if socket:
				check(socket.position.distance_to(Vector3(p[0],p[1],p[2]))<.00001,id+": socket "+socket_name+" position")
				check(socket.basis.is_equal_approx(Basis.IDENTITY),id+": socket "+socket_name+" +Z orientation")
		if id not in ["deco_scarecrow","deco_fence","deco_windmill_sails"]:
			var half=Vector2(entry.footprint_cells[0],entry.footprint_cells[1])*.65/2-Vector2(.03,.03)
			check(maxf(absf(box.position.x),absf(box.end.x))<=half.x+.0001 and maxf(absf(box.position.z),absf(box.end.z))<=half.y+.0001,id+": cell footprint with 3 cm margin")
		report.assets.append({"id":id,"triangles":tris,"surfaces":mesh.get_surface_count(),"bounds_min":[box.position.x,box.position.y,box.position.z],"bounds_max":[box.end.x,box.end.y,box.end.z],"sockets":entry.sockets})
		scene.free()
	check(Art.material().vertex_color_use_as_albedo and not Art.material().vertex_color_is_srgb and is_equal_approx(Art.material().roughness,.9),"Unmodified FarmArt shared vertex material")
	check(Art.mesh_for("deco_path").get_aabb().size.y<=.04,"Stone path thickness <= 4 cm")
	check(Art.mesh_for("deco_scarecrow").get_aabb().size.x<=.85,"Scarecrow hands <= 85 cm")
	check(is_equal_approx(Art.mesh_for("deco_fence").get_aabb().size.x,.65),"Fence repeats every 65 cm")
	check(manifest.assets.deco_pergola.colliders.size()==4,"Pergola four post colliders only")
	var basic_bench=load("res://assets/rooms/basic_room/bench.glb").instantiate()
	var basic_seat_height=meshes(basic_bench)[0].mesh.get_aabb().end.y
	check(absf(basic_seat_height-float(manifest.assets.deco_bench.seat_height))<.0001,"Seat height matches actual Basic Room bench mesh")
	report.basic_room_seat_height=basic_seat_height
	basic_bench.free()
	var bench_bounds=Art.mesh_for("deco_bench").get_aabb()
	var back_height=bench_bounds.end.y-basic_seat_height
	check(back_height>=.35 and back_height<=.40,"Bench back rises 0.35-0.40 m above the unchanged seat")
	check(bench_bounds.size.x<=1.24 and bench_bounds.size.z<=.59,"Reclining bench fits within 1.24 by 0.59 m")
	var bench_scene=load("res://assets/farm/art/deco_bench.glb").instantiate()
	for i in 2:
		var seat=bench_scene.find_child("seat_%d"%i,true,false)
		var expected=Transform3D(Basis.IDENTITY,Vector3(-.275 if i==0 else .275,.67,.035))
		check(seat.transform.is_equal_approx(expected),"Bench seat_%d remains at its R1 position and orientation"%i)
	bench_scene.free()
	var rotor=Art.mesh_for("deco_windmill_sails")
	var radius=0.0
	for v in rotor.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: radius=maxf(radius,Vector2(v.x,v.y).length())
	check(radius*2<=1.24,"Windmill full rotation swept diameter <= 1.24 m")
	report.rotor_swept_diameter=radius*2
	check(manifest.assets.deco_windmill.triangles+manifest.assets.deco_windmill_sails.triangles<=4000,"Windmill body + sails <= 4000 triangles")
	vp=SubViewport.new()
	vp.size=Vector2i(4400,1200)
	vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)
	world=Node3D.new()
	vp.add_child(world)
	var env=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("e7eddf")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(.79,.88,.94)
	env.environment.ambient_light_energy=.42
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	world.add_child(env)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-51,-38,0)
	sun.light_color=Color(1,.96,.87)
	sun.light_energy=1.1
	sun.shadow_enabled=true
	sun.shadow_opacity=.58
	sun.shadow_bias=.10
	sun.shadow_normal_bias=1.0
	sun.light_angular_distance=1.0
	sun.directional_shadow_max_distance=40
	world.add_child(sun)
	var ground=MeshInstance3D.new()
	var plane=PlaneMesh.new();plane.size=Vector2(100,100)
	ground.mesh=plane
	ground.position.y=-.007
	var mat=StandardMaterial3D.new();mat.albedo_color=Color("dbe3ce");mat.roughness=1.0
	ground.material_override=mat
	world.add_child(ground)
	stage=Node3D.new()
	world.add_child(stage)
	var x=-8.5
	for i in IDS.size():
		var id=IDS[i]
		var width=float(manifest.assets[id].footprint_cells[0])*.65
		x+=width/2
		var p=Vector3(x,0,0)
		origins.append(p)
		stage.add_child(Art.instance(id,p))
		if id=="deco_windmill": stage.add_child(Art.instance("deco_windmill_sails",p+Vector3(0,.985,.273)))
		x+=width/2+.80
	cam=Camera3D.new()
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect=Camera3D.KEEP_WIDTH
	cam.size=22.0
	cam.near=.1;cam.far=70
	world.add_child(cam)
	cam.current=true
	rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new()
	world.add_child(rig)
	rig.position=Vector3(-9.65,0,0)
	rig.rotation.y=0
	rig.apply_config(Avatar.slot_table.default_config())
	var wait=0
	while rig.is_busy() and wait<900:
		await get_tree().process_frame
		wait+=1
	check(not rig.is_busy(),"Scale avatar assembled")
	rig.play_motion("idle")
	var ap=rig.get_node("AnimationPlayer")
	ap.seek(.3,true);ap.pause()
	var canvas=CanvasLayer.new();vp.add_child(canvas)
	for i in IDS.size():
		var label=Label.new()
		label.text=NAMES[i]
		label.add_theme_font_size_override("font_size",25)
		label.add_theme_color_override("font_color",Color("4a503f"))
		canvas.add_child(label);labels.append(label)
	var title=Label.new()
	title.add_theme_font_size_override("font_size",38)
	title.add_theme_color_override("font_color",Color("394532"))
	title.position=Vector2(80,55);canvas.add_child(title)
	var note=Label.new()
	note.text="SGODOT-290  /  LIU BEI  /  1 CELL = 0.65 M  /  AVATAR H = 1.745 M  /  FARM SHARED MATERIAL"
	note.add_theme_font_size_override("font_size",23)
	note.add_theme_color_override("font_color",Color("626952"))
	note.position=Vector2(80,115);canvas.add_child(note)
	for view in ["43deg","top"]:
		var pitch=43 if view=="43deg" else 90
		var focus=Vector3(-.35,.62,0) if view=="43deg" else Vector3(-.35,0,0)
		cam.rotation_degrees=Vector3(-pitch,0,0)
		cam.position=focus+cam.basis.z*25
		title.text="FARM DECORATIONS  /  "+("43 DEGREE REVIEW" if view=="43deg" else "TOP DOWN PLACEMENT REVIEW")
		for i in labels.size():
			labels[i].position=cam.unproject_position(origins[i]+Vector3(0,0,.78))-Vector2(120,-15)
		await capture("overview-"+view)
	canvas.visible=false
	# Detail views are additional Godot captures, never replacements for the one-row overview.
	vp.size=Vector2i(1100,1000)
	for i in IDS.size():
		var id=IDS[i]
		for node in stage.get_children():
			node.visible=node.name==id.to_pascal_case() or (id=="deco_windmill" and node.name=="DecoWindmillSails")
		var aabb=Art.mesh_for(id).get_aabb()
		cam.size=maxf(maxf(aabb.size.x,aabb.size.z)*1.9,aabb.size.y*1.6)
		cam.size=maxf(cam.size,1.0)
		cam.rotation_degrees=Vector3(-43,25,0)
		cam.position=origins[i]+Vector3(0,aabb.size.y*.45,0)+cam.basis.z*15
		await capture(id+"-detail")
	# Independent field instances prove fence seams and the axle rotation contract.
	stage.visible=false;rig.visible=false
	var seam=Node3D.new();world.add_child(seam)
	for i in range(3):seam.add_child(Art.instance("deco_fence",Vector3((i-1)*.65,0,0)))
	cam.size=2.7;cam.rotation_degrees=Vector3(-30,15,0);cam.position=Vector3(0,.30,0)+cam.basis.z*15
	await capture("fence-three-segments")
	seam.free()
	report.renderer=RenderingServer.get_current_rendering_method()
	report.adapter=RenderingServer.get_video_adapter_name()
	report.failures=report.checks.filter(func(item):return not item.passed)
	FileAccess.open(out+"/validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("DECOR_QA ",report.checks.size()," checks; ",report.failures.size()," failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)

func capture(id: String):
	for i in 8:await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image()
	var result=image.save_png(out+"/"+id+".png")
	check(result==OK,"Capture saved: "+id)
	report.captures.append({"id":id,"size":[image.get_width(),image.get_height()]})
	print("DECOR_CAPTURE ",id)
