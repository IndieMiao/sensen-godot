extends Node
## Actual imported geometry and prescribed neighbour placement; isolated art QA.
const Art = preload("res://modules/farm/farm_art.gd")
const NEIGHBOURS = {"storage":Vector3(-.65,0,0), "well":Vector3(0,0,1.30)}
var report = {"assets":[], "checks":[], "captures":[], "neighbours":[]}
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

func vector(a): return Vector3(a[0],a[1],a[2])
func triple(p): return [p.x,p.y,p.z]
func bounds_record(a): return [triple(a.position),triple(a.end)]

func bounds(points):
	var result=AABB(points[0],Vector3.ZERO)
	for p in points: result=result.expand(p)
	return result

func triangle_boxes(mesh, offset):
	var faces=mesh.get_faces();var result=[]
	for i in range(0,faces.size(),3):
		result.append(bounds([faces[i]+offset,faces[i+1]+offset,faces[i+2]+offset]))
	return result

func _run():
	out=ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(out)
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/art/manifest.json"))
	var entry=manifest.assets.notice_board
	var scene=load("res://assets/farm/art/notice_board.glb").instantiate()
	var meshes=scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D: meshes.push_front(scene)
	check(meshes.size()==1,"One merged mesh in imported PackedScene")
	var mesh=Art.mesh_for("notice_board");var arrays=mesh.surface_get_arrays(0)
	var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var aabb=mesh.get_aabb()
	check(mesh.get_surface_count()==1,"One surface")
	check(mesh.get_faces().size()/3==int(entry.triangles) and entry.triangles<=1200,"Actual triangle count matches manifest and <= 1200")
	check(aabb.position.distance_to(vector(entry.bounds[0]))<.0001 and aabb.end.distance_to(vector(entry.bounds[1]))<.0001,"Actual bounds match manifest")
	check(absf(aabb.position.y)<.0001 and aabb.end.y>=1.55 and aabb.end.y<=1.6001,"Ground pivot and roof total height 1.55-1.60 m (mark empty excluded)")
	check(scene.transform.is_equal_approx(Transform3D.IDENTITY) and meshes[0].transform.is_equal_approx(Transform3D.IDENTITY),"Identity root and mesh transforms")
	check(arrays[Mesh.ARRAY_TEX_UV]==null or arrays[Mesh.ARRAY_TEX_UV].is_empty(),"No UV/texture payload")
	var opaque=colors.size()==positions.size()
	for c in colors: opaque=opaque and is_equal_approx(c.a,1)
	check(opaque,"Opaque vertex colors")
	for socket in ["board_center","mark"]:
		var marker=scene.find_child(socket,true,false)
		check(marker!=null,"Empty retained: "+socket)
		if marker:
			check(marker.position.distance_to(vector(entry.sockets[socket].position))<.0001 and marker.basis.is_equal_approx(Basis.IDENTITY),"Socket position and +Z basis: "+socket)
	var frame_points=[];var structure=[];var roof_points=[];var cork_points=[];var paper_points=[]
	var dark=Color("675139").srgb_to_linear();var wood=Color("a87948").srgb_to_linear()
	var cork=Color("cba067").srgb_to_linear()
	var paper_colors=[Color("fff4d2").srgb_to_linear(),Color("fff3dd").srgb_to_linear(),Color("f1ce58").srgb_to_linear()]
	for i in positions.size():
		var p=positions[i];var c=colors[i]
		if near_color(c,dark): frame_points.append(p)
		if near_color(c,wood): structure.append(p)
		if near_color(c,cork): cork_points.append(p)
		if p.y>=1.46: roof_points.append(p)
		for pc in paper_colors:
			if near_color(c,pc): paper_points.append(p);break
	var frame=bounds(frame_points);var legs=bounds(structure);var roof=bounds(roof_points)
	var cork_box=bounds(cork_points);var paper_box=bounds(paper_points)
	check(frame.size.distance_to(Vector3(.56,.44,.05))<.0001,"Actual solid frame 0.56 x 0.44 x 0.05 m")
	check(absf(frame.position.y-.95)<.0001 and absf(frame.end.y-1.39)<.0001,"Actual frame bottom 0.95 and top 1.39 m")
	check(absf(frame.end.z-cork_box.end.z-.01)<.0001,"Cork face recessed 0.01 m")
	check(legs.position.x>=-.3101 and legs.end.x<=.3101 and legs.position.z>=-.0701 and legs.end.z<=.0701,"Actual post/foot projection within X +/-0.31 and Z +/-0.07")
	check(absf(legs.get_center().x)<.0001 and absf(legs.get_center().z)<.0001,"Structure centred at ground midpoint")
	for side in [-1,1]:
		var pts=[]
		for p in structure:
			if p.y>.90 and p.x*side>0:pts.append(p)
		var post=bounds(pts)
		check(absf(post.size.x-.07)<.0001 and absf(post.size.z-.07)<.0001 and absf(post.get_center().x-side*.25)<.0001,"Post section/centre side "+str(side))
	check(roof.size.x<=.7001 and absf(roof.size.z-.26)<.0001,"Canopy width <= 0.70 and depth 0.26 m")
	check(roof.position.y>=1.4599 and roof.end.z-cork_box.end.z<=.1001,"Eave >= 1.46 m and overhang <= 0.10 m")
	check(paper_box.end.z-cork_box.end.z<=.0121,"Paper relief inside 0.012 m limit")
	check(vector(entry.collider.size).distance_to(Vector3(.62,1.60,.14))<.0001 and vector(entry.collider.at).distance_to(Vector3(0,.80,0))<.0001,"Collider contract: 0.62 x 1.60 x 0.14 m")
	check(entry.footprint_cells==[1.0,1.0] and is_equal_approx(entry.footprint,.65),"One 0.65 m anchor cell")
	report.assets.append({"id":"notice_board","bounds":bounds_record(aabb),"triangles":mesh.get_faces().size()/3,"surfaces":mesh.get_surface_count(),"board_bounds":bounds_record(frame),"structure_bounds":bounds_record(legs),"roof_bounds":bounds_record(roof),"cork_face_z":cork_box.end.z,"sockets":entry.sockets,"collider":entry.collider})
	# Every actual imported triangle is tested against the neighbour triangles.
	# Zero overlapping triangle bounding-box pairs proves no surface intersection;
	# additionally, separated lower/upper volumes exclude enclosed components.
	var own_boxes=triangle_boxes(mesh,Vector3.ZERO)
	for id in NEIGHBOURS:
		var neighbour=Art.mesh_for(id);var offset=NEIGHBOURS[id]
		var neighbour_box=neighbour.get_aabb();neighbour_box.position+=offset
		var candidates=0
		var other_boxes=triangle_boxes(neighbour,offset)
		for own in own_boxes:
			for other in other_boxes:
				if own.grow(.000001).intersects(other.grow(.000001)):candidates+=1
		check(candidates==0,"No triangle intersections with actual "+id+" at prescribed cell (zero candidate pairs)")
		var lower=[];var upper=[]
		for p in positions:
			if p.y<=neighbour_box.end.y+.0001:lower.append(p)
			else:upper.append(p)
		var lower_box=bounds(lower);var upper_box=bounds(upper)
		var x_gap=lower_box.position.x-neighbour_box.end.x
		var z_gap=neighbour_box.position.z-aabb.end.z
		check((id=="storage" and x_gap>.029 and upper_box.position.y>neighbour_box.end.y) or (id=="well" and z_gap>0),"Separated occupied volumes exclude containment: "+id)
		report.neighbours.append({"id":id,"relative_position":triple(offset),"actual_bounds":bounds_record(neighbour_box),"triangles":neighbour.get_faces().size()/3,"triangle_aabb_candidate_pairs":candidates,"clearance_axis":"X below neighbour top" if id=="storage" else "Z entire mesh","clearance_m":x_gap if id=="storage" else z_gap})
	scene.free()
	check(Art.material().vertex_color_use_as_albedo and not Art.material().vertex_color_is_srgb and is_equal_approx(Art.material().roughness,.9),"Unmodified FarmArt.material()")
	setup_world()
	var notice=Art.instance("notice_board");world.add_child(notice)
	var neighbours=[]
	for id in NEIGHBOURS:
		var n=Art.instance(id,NEIGHBOURS[id]);world.add_child(n);neighbours.append(n)
	var grid=Node3D.new();world.add_child(grid)
	for ix in range(-3,4):
		for iz in range(-2,5):
			var col=Color("bdcca9") if (ix+iz)%2==0 else Color("c8d3b6")
			if ix==0 and iz==0:col=Color("e8d89c")
			box(grid,Vector3(ix*.65,-.004,iz*.65),Vector3(.643,.006,.643),col)
	var rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig)
	rig.position=Vector3(.92,0,0);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Existing scale avatar assembled")
	rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
	pose(Vector3(.10,.60,.70),3.85,43,14.5)
	title.text="NOTICE BOARD / 43 DEG / EXISTING STORAGE + WELL"
	note.text="SGODOT-284 / LIU BEI / BOARD (15,15) / STORAGE (14,15) / WELL (15,13) / CELL 0.65 M\nH 1.595 M / BOARD BOTTOM 0.95 M / AVATAR H 1.745 M / PITCH 43 DEG / YAW 14.5 DEG"
	# Actual roof triangles cannot obstruct a grid covering the cork interior.
	var roof_faces=[];var faces=mesh.get_faces()
	for i in range(0,faces.size(),3):
		if minf(faces[i].y,minf(faces[i+1].y,faces[i+2].y))>=1.46:roof_faces.append([faces[i],faces[i+1],faces[i+2]])
	var obstructed=0
	for x in [-.23,-.115,0,.115,.23]:
		for y in [1.00,1.17,1.34,1.35]:
			var target=Vector3(x,y,cork_box.end.z)
			for tri in roof_faces:
				if Geometry3D.ray_intersects_triangle(target,cam.basis.z,tri[0],tri[1],tri[2])!=null:obstructed+=1;break
	check(obstructed==0,"43 degree roof visibility: 20 cork samples unobstructed by actual roof triangles")
	await capture("notice-board-43deg")
	for n in neighbours:n.visible=false
	rig.visible=false;grid.visible=false
	pose(Vector3(0,1.255,0),1.06,0,0)
	title.text="NOTICE BOARD / FRONT (+Z)";title.add_theme_font_size_override("font_size",28)
	note.text="FOUR BLANK PAPERS / SMALL ROUND PINS / EXACT EXISTING ASSET VERTEX COLORS\nFRAME 0.56 x 0.44 x 0.05 M / CORK FACE RECESSED 0.01 M / NO LETTERING OR MARKS"
	await capture("notice-board-front")
	for n in neighbours:n.visible=true
	grid.visible=true
	pose(Vector3(-.13,0,.75),3.40,90,0)
	title.text="NOTICE BOARD / TRUE TOP VIEW / 0.65 M GRID"
	note.text="NOTICE BOARD (15,15) / STORAGE (14,15) / WELL (15,13) / NO GEOMETRY INTERSECTIONS\nPOST + FOOT X +/-0.30 M / CANOPY X +/-0.35 M (ABOVE NEIGHBOURS) / STORAGE FOOT GAP 0.03 M"
	var labels=CanvasLayer.new();vp.add_child(labels)
	label_at(labels,"(15,15) NOTICE",Vector3(0,0,-.25))
	label_at(labels,"(14,15) STORAGE",Vector3(-.65,0,-.29))
	label_at(labels,"(15,14) GAP",Vector3(0,0,.65))
	label_at(labels,"(15,13) WELL",Vector3(0,0,1.72))
	for cx in [-.25,.25]:
		for side in [-1,1]:
			line_at(labels,Vector3(cx+side*.05,0,-.05),Vector3(cx+side*.05,0,.05),Color("84b8d4"))
			line_at(labels,Vector3(cx-.05,0,side*.05),Vector3(cx+.05,0,side*.05),Color("84b8d4"))
	label_at(labels,"BLUE: FOOT PROJECTION",Vector3(.86,0,.20))
	await capture("notice-board-top-grid")
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name()
	report.failures=report.checks.filter(func(item):return not item.passed)
	FileAccess.open(out+"/validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("NOTICE_BOARD_QA ",report.checks.size()," checks; ",report.failures.size()," failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)

func near_color(a,b):return Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b))<.007

func setup_world():
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
	cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH
	cam.near=.1;cam.far=70;cam.current=true;world.add_child(cam)
	var canvas=CanvasLayer.new();vp.add_child(canvas)
	var footer=ColorRect.new();footer.position=Vector2(0,1280);footer.size=Vector2(1800,120)
	footer.color=Color("e7eddf");canvas.add_child(footer)
	title=Label.new();title.position=Vector2(50,40);title.add_theme_font_size_override("font_size",30)
	title.add_theme_color_override("font_color",Color("394532"));canvas.add_child(title)
	note=Label.new();note.position=Vector2(50,1300);note.add_theme_font_size_override("font_size",22)
	note.add_theme_color_override("font_color",Color("4a503f"));canvas.add_child(note)

func box(parent,at,size,color):
	var node=MeshInstance3D.new();var m=BoxMesh.new();m.size=size;node.mesh=m
	var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=1
	node.material_override=mat;node.position=at;parent.add_child(node);return node

func pose(focus,size,pitch,yaw):
	cam.size=size;cam.rotation_degrees=Vector3(-pitch,yaw,0);cam.position=focus+cam.basis.z*20

func label_at(parent,text,at):
	var label=Label.new();label.text=text;label.size=Vector2(380,38)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",23);label.add_theme_color_override("font_color",Color("5e4535"))
	label.position=cam.unproject_position(at)-Vector2(190,19);parent.add_child(label)

func line_at(parent,a,b,color):
	var line=Line2D.new();line.points=PackedVector2Array([cam.unproject_position(a),cam.unproject_position(b)])
	line.default_color=color;line.width=3;parent.add_child(line)

func capture(id):
	for i in 8:await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image()
	check(image.save_png(out+"/"+id+".png")==OK,"Capture saved: "+id)
	report.captures.append({"id":id,"size":[image.get_width(),image.get_height()],"pitch":-cam.rotation_degrees.x,"yaw":cam.rotation_degrees.y,"camera_size":cam.size})
	print("NOTICE_BOARD_CAPTURE ",id)
