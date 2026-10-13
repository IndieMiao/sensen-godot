extends Node
## SGODOT-282 actual Godot Mobile assets, dimensions, sockets and review media.
const Art = preload("res://modules/farm/farm_art.gd")
const IDS = ["chef_sign_a", "chef_sign_b"]
var report = {"assets":[], "checks":[], "captures":[]}
var vp: SubViewport
var world: Node3D
var cam: Camera3D
var out: String
var title: Label
var note: Label

func _ready(): _run.call_deferred()

func check(ok: bool, what: String):
	report.checks.append({"check":what,"passed":ok})
	if not ok: push_error(what)

func vector(values): return Vector3(values[0],values[1],values[2])

func _run():
	out=ProjectSettings.globalize_path("res://../v1.3/captures")
	DirAccess.make_dir_recursive_absolute(out)
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/art/manifest.json"))
	for id in IDS:
		var scene=load("res://assets/farm/art/"+id+".glb").instantiate()
		var meshes=scene.find_children("*","MeshInstance3D",true,false)
		if scene is MeshInstance3D: meshes.push_front(scene)
		var entry=manifest.assets[id]
		check(meshes.size()==1,id+": one merged mesh")
		var mesh=Art.mesh_for(id)
		check(mesh.get_surface_count()==1,id+": one surface via FarmArt")
		var box=mesh.get_aabb()
		check(mesh.get_faces().size()/3==int(entry.triangles) and int(entry.triangles)<=1500,id+": triangle budget / manifest")
		check(box.position.distance_to(vector(entry.bounds[0]))<.00001 and box.end.distance_to(vector(entry.bounds[1]))<.00001,id+": actual bounds match manifest")
		check(box.size.y>=1.6 and box.size.y<=1.8,id+": total height 1.6-1.8 m")
		check(absf(box.position.y)<.00001,id+": foot at ground")
		check(scene.transform.is_equal_approx(Transform3D.IDENTITY) and meshes[0].transform.is_equal_approx(Transform3D.IDENTITY),id+": baked identity transforms")
		var arrays=mesh.surface_get_arrays(0)
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var opaque=not colors.is_empty()
		for c in colors: opaque=opaque and is_equal_approx(c.a,1)
		check(opaque,id+": opaque vertex colors")
		check(arrays[Mesh.ARRAY_TEX_UV]==null or arrays[Mesh.ARRAY_TEX_UV].is_empty(),id+": no UV payload")
		var marker=scene.find_child("board_center",true,false)
		check(marker!=null,id+": board_center empty retained")
		if marker:
			check(marker.position.distance_to(vector(entry.board_center))<.00001,id+": marker at board centre")
			check(marker.basis.is_equal_approx(Basis.IDENTITY),id+": marker +Z facing")
		check(is_equal_approx(entry.board_bottom,1.06) and entry.board_bottom>=1.0,id+": board bottom >= 1.0 m")
		# Measure the exported gold frame region, independently of metadata.
		var frame=AABB();var have_frame=false
		for index in arrays[Mesh.ARRAY_VERTEX].size():
			var p=arrays[Mesh.ARRAY_VERTEX][index]
			var c=colors[index]
			var gold=Color("e6b954").srgb_to_linear()
			var edge=Color("bb8b3e").srgb_to_linear()
			# Godot packs colours into 8-bit channels; sqrt(3)/255 < .007.
			var gold_vertex=(Vector3(c.r,c.g,c.b).distance_to(Vector3(gold.r,gold.g,gold.b))<.007 or Vector3(c.r,c.g,c.b).distance_to(Vector3(edge.r,edge.g,edge.b))<.007)
			if gold_vertex:
				if not have_frame: frame=AABB(p,Vector3.ZERO);have_frame=true
				else: frame=frame.expand(p)
		check(absf(frame.position.y-entry.board_bottom)<.0001 and absf(frame.size.x-.50)<.0001 and absf(frame.size.y-.45)<.0001,id+": v1.3 exported board 0.50 x 0.45 m / bottom (0.1 mm tolerance)")
		check(frame.size.z>=.0499 and frame.size.z<=.064,id+": solid frame depth including relief")
		check(absf(frame.position.x+.582)<.0001 and absf(frame.end.x+.082)<.0001 and scene.scale==Vector3.ONE,id+": v1.3 left board edges, positive scale")
		var intrusion=-.325-(frame.position.x+.18)
		check(absf(intrusion-.077)<.0001,id+": +0.18 m fixture shift leaves 77 mm path intrusion")
		var feet=AABB();var have_feet=false
		for p in arrays[Mesh.ARRAY_VERTEX]:
			if p.y<=.21:
				if not have_feet: feet=AABB(p,Vector3.ZERO);have_feet=true
				else: feet=feet.expand(p)
		check(feet.size.x<=.30001 and feet.size.z<=.30001,id+": foot projection <= 0.30 m square")
		check(absf(feet.get_center().x)<.00001 and absf(feet.get_center().z)<.00001,id+": pivot at foot centre")
		check(feet.end.x+.18<=.32501,id+": shifted foot remains inside anchor cell")
		var collider=entry.collider
		check(vector(collider.size).x<=.30 and vector(collider.size).z<=.30 and vector(collider.at).x==0 and vector(collider.at).z==0,id+": only post collider, no suspended board box")
		check(is_equal_approx(entry.footprint,.65) and entry.footprint_cells==[1.0,1.0],id+": one 0.65 m anchor cell")
		report.assets.append({"id":id,"triangles":entry.triangles,"bounds":entry.bounds,"board_bounds":[[frame.position.x,frame.position.y,frame.position.z],[frame.end.x,frame.end.y,frame.end.z]],"foot_size":[feet.size.x,feet.size.y,feet.size.z],"collider":collider,"fixture_right_shift":.18,"path_intrusion":intrusion,"foot_right_clearance":.325-(feet.end.x+.18)})
		scene.free()
	check(Art.material().vertex_color_use_as_albedo and not Art.material().vertex_color_is_srgb and is_equal_approx(Art.material().roughness,.9),"Unmodified shared FarmArt.material()")
	vp=SubViewport.new();vp.size=Vector2i(1800,1400);vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp);world=Node3D.new();vp.add_child(world)
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e7eddf")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(.79,.88,.94);env.environment.ambient_light_energy=.42
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;world.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-51,-38,0)
	sun.light_color=Color(1,.96,.87);sun.light_energy=1.1;sun.shadow_enabled=true
	sun.shadow_opacity=.58;sun.shadow_bias=.10;sun.shadow_normal_bias=1.0
	sun.light_angular_distance=1;sun.directional_shadow_max_distance=30;world.add_child(sun)
	box(world,Vector3(0,-.025,0),Vector3(50,.04,50),Color("dbe3ce"))
	var signs=[]
	for id in IDS:
		var node=Art.instance(id);world.add_child(node);signs.append(node)
		node.visible=false
	var rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity: child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig)
	rig.position=Vector3(1.20,0,0);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900: await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Existing scale avatar assembled")
	rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
	cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH
	cam.near=.1;cam.far=70;cam.current=true;world.add_child(cam)
	var canvas=CanvasLayer.new();vp.add_child(canvas)
	var footer=ColorRect.new();footer.position=Vector2(0,1280);footer.size=Vector2(1800,120)
	footer.color=Color("e7eddf");canvas.add_child(footer)
	title=Label.new();title.position=Vector2(60,45);title.add_theme_font_size_override("font_size",32)
	title.add_theme_color_override("font_color",Color("394532"));canvas.add_child(title)
	note=Label.new();note.position=Vector2(60,1300);note.add_theme_font_size_override("font_size",23)
	note.add_theme_color_override("font_color",Color("4a503f"));canvas.add_child(note)
	signs[0].position.x=-.95;signs[1].position.x=.45
	signs[0].visible=true;signs[1].visible=true
	pose(Vector3(-.10,.86,0),4.05,43,14.5)
	title.text="CHEF'S SIGN / V1.3 / TIMBER + STONE / 43 DEG"
	note.text="SGODOT-282 / LIU BEI / 43 DEG PITCH + 14.5 DEG YAW / AVATAR H = 1.745 M\nBOARD 0.50 x 0.45 x 0.05 M / BOTTOM 1.06 M / ICONS UNIFORMLY SCALED 5/6"
	await capture("chef-sign-v1.3-43deg")
	rig.visible=false;signs[0].visible=false
	signs[1].position=Vector3(.18,0,0)
	# Fixture only: (5,14) is the origin cell; (4,14) is directly left.
	# The actual GLB pivot remains at its own foot. No shift is baked into it.
	var grid=Node3D.new();world.add_child(grid)
	for ix in range(-3,3):
		for iz in range(-2,3):
			var col=Color("bdcca9") if (ix+iz)%2==0 else Color("c8d3b6")
			if ix==0 and iz==0: col=Color("e8d89c")
			if ix==-1: col=Color("cabda2")
			box(grid,Vector3(ix*.65,-.004,iz*.65),Vector3(.643,.006,.643),col)
	# Footprint/collider outline at ground level; it does not enclose the hanging board.
	for side in [-1,1]:
		box(grid,Vector3(.18+side*.14,.003,0),Vector3(.008,.007,.28),Color("6689a1"))
		box(grid,Vector3(.18,.003,side*.14),Vector3(.28,.007,.008),Color("6689a1"))
	pose(Vector3(-.28,0,0),2.20,90,0)
	title.text="CHEF'S SIGN / V1.3 / TRUE TOP VIEW / 0.65 M GRID"
	note.text="B (LARGEST FOOT) / POST SHIFT +0.18 M IS IN THIS FIXTURE ONLY; GLB PIVOT UNCHANGED\nBOARD ENTERS (4,14) BY 0.077 M / FOOT RIGHT MARGIN 0.005 M / FINAL BENCH + HIT TEST: INTEGRATION"
	label_at(canvas,"(4,14) MINE PATH",Vector3(-.65,0,-.26),Color("5e4535"))
	label_at(canvas,"(5,14) SIGN ANCHOR",Vector3(0,0,-.26),Color("5e4535"))
	line_at(canvas,Vector3(-.325,0,-.325),Vector3(-.325,0,.325),Color("a6573d"),4)
	# Dimension overlays come from actual world positions in the unrotated fixture.
	line_at(canvas,Vector3(-.402,0,.16),Vector3(-.325,0,.16),Color("9b382d"),3)
	for x in [-.402,-.325]: line_at(canvas,Vector3(x,0,.145),Vector3(x,0,.175),Color("9b382d"),3)
	label_at(canvas,"77 mm into path",Vector3(-.50,0,.21),Color("9b382d"))
	line_at(canvas,Vector3(0,0,.22),Vector3(.18,0,.22),Color("456880"),3)
	for x in [0,.18]: line_at(canvas,Vector3(x,0,.205),Vector3(x,0,.235),Color("456880"),3)
	label_at(canvas,"post +0.18 m",Vector3(.09,0,.28),Color("456880"))
	await capture("chef-sign-v1.3-top-grid")
	report.renderer=RenderingServer.get_current_rendering_method()
	report.adapter=RenderingServer.get_video_adapter_name()
	report.failures=report.checks.filter(func(item):return not item.passed)
	FileAccess.open(out+"/validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("CHEF_SIGN_QA ",report.checks.size()," checks; ",report.failures.size()," failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)

func box(parent, at, size, color):
	var node=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=size;node.mesh=mesh
	var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=1
	node.material_override=mat;node.position=at;parent.add_child(node)
	return node

func pose(focus, size, pitch, yaw):
	cam.size=size;cam.rotation_degrees=Vector3(-pitch,yaw,0);cam.position=focus+cam.basis.z*20

func label_at(parent, text, at, color):
	var label=Label.new();label.text=text;label.size=Vector2(410,38)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",26);label.add_theme_color_override("font_color",color)
	label.position=cam.unproject_position(at)-Vector2(205,19);parent.add_child(label)

func line_at(parent, a, b, color, width):
	var line=Line2D.new();line.points=PackedVector2Array([cam.unproject_position(a),cam.unproject_position(b)])
	line.default_color=color;line.width=width;parent.add_child(line)

func capture(id):
	for i in 8: await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image()
	check(image.save_png(out+"/"+id+".png")==OK,"Capture saved: "+id)
	report.captures.append({"id":id,"size":[image.get_width(),image.get_height()],"pitch":-cam.rotation_degrees.x,"yaw":cam.rotation_degrees.y,"camera_size":cam.size})
	print("CHEF_SIGN_CAPTURE ",id)
