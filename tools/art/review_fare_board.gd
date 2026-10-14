extends Node
## Isolated real Post Office art review, with one fixture prop at approved pose.
const KIT="res://assets/rooms/post_office/"
const AT=Vector3(-3.21,1.65,-1.65)
var report={"checks":[],"captures":[]}
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var title:Label
var note:Label
var output:String
var layout:Dictionary
var sun:DirectionalLight3D

func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(p):return [p.x,p.y,p.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func find_mesh(node):
	if node is MeshInstance3D:return node
	var list=node.find_children("*","MeshInstance3D",true,false)
	return list[0] if list.size()==1 else null

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	var contract=JSON.parse_string(FileAccess.get_file_as_string("res://review-data/asset-contract.json"))
	var swatches=JSON.parse_string(FileAccess.get_file_as_string("res://review-data/atlas-swatches.json"))
	var fare=load(KIT+"fare_board.glb").instantiate()
	var mesh_node=find_mesh(fare)
	check(mesh_node!=null,"One actual imported MeshInstance3D")
	var mesh=mesh_node.mesh;var box=mesh.get_aabb();var arrays=mesh.surface_get_arrays(0)
	check(mesh.get_surface_count()==1,"One imported surface")
	check(mesh.get_faces().size()/3==contract.triangles and contract.triangles<=800,"Actual imported triangles <= 800 and match contract")
	check(box.size.distance_to(Vector3(.90,.65,.07))<.0001,"Actual imported dimensions 0.90 x 0.65 x 0.07 m")
	check(absf(box.position.z)<.0001 and absf(box.get_center().x)<.0001 and absf(box.get_center().y)<.0001,"Back-centre pivot at zero and +Z front")
	check(fare.transform.is_equal_approx(Transform3D.IDENTITY) and mesh_node.transform.is_equal_approx(Transform3D.IDENTITY),"Root and mesh identity transforms")
	for key in ["board_center","mark"]:
		var marker=fare.find_child(key,true,false)
		check(marker!=null,"Empty imported: "+key)
		if marker:check(marker.position.distance_to(vec(contract.sockets[key]))<.0001 and marker.basis.is_equal_approx(Basis.IDENTITY),"Socket position and identity basis: "+key)
	var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	check(uvs.size()==arrays[Mesh.ARRAY_VERTEX].size(),"Every imported vertex has atlas UV")
	var all_valid=true;var worst=0.0
	for uv in uvs:
		var distance=INF
		for record in swatches.swatches.values():distance=minf(distance,uv.distance_to(Vector2(record.gltf_uv[0],record.gltf_uv[1])))
		worst=maxf(worst,distance);all_valid=all_valid and distance<.000001
	check(all_valid,"Actual imported UVs stay at the six verified existing atlas swatch centres")
	var material_name=mesh.surface_get_material(0).resource_name
	check(material_name=="RoomKit_SharedAtlas","RoomKit_SharedAtlas material name")
	report.asset={"bounds":[xyz(box.position),xyz(box.end)],"size":xyz(box.size),"triangles":mesh.get_faces().size()/3,"surfaces":mesh.get_surface_count(),"uv_max_error":worst,"sockets":contract.sockets}
	setup_world()
	var room=load("res://scenes/post_office/post_office_art.tscn").instantiate();world.add_child(room)
	var reference=find_mesh(room.get_node("sorting_cabinet"))
	check(reference!=null,"Actual Post Office sorting cabinet present")
	var mat=reference.material_override
	check(mat.albedo_texture.resource_path==KIT+"room_albedo_ao.png" and is_equal_approx(mat.roughness,.8),"Reuse actual room shared atlas material")
	world.add_child(fare);fare.position=AT;fare.rotation_degrees.y=90;mesh_node.material_override=mat
	check(mesh_node.material_override==reference.material_override,"Fare Board uses same runtime material object as room kit")
	var world_box=fare.transform*box
	check(absf(world_box.position.x+3.21)<.0001 and absf(world_box.position.y-1.325)<.0001 and absf(world_box.end.y-1.975)<.0001,"Approved wall pose and actual height extent")
	report.placement={"position":xyz(fare.position),"yaw":fare.rotation_degrees.y,"world_bounds":[xyz(world_box.position),xyz(world_box.end)]}
	var rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig)
	rig.position=Vector3(-2.2,.08,.35);rig.rotation.y=-PI/2
	rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Existing character assembled at public counter approach")
	rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
	var displacement=vec(layout.camera.position)-vec(layout.camera.target)
	var yaw=rad_to_deg(atan2(displacement.x,displacement.z))
	pose(vec(layout.camera.target),layout.camera.size,43,yaw)
	title.text="FARE BOARD / POST OFFICE / DEFAULT 43 DEG VIEW"
	note.text="SGODOT-275 / LIU BEI / AT (-3.21, 1.65, -1.65), YAW 90 / CHARACTER H 1.745 M\n0.90 x 0.65 x 0.07 M / SEVEN BLANK ROWS / EXISTING SHARED ROOM ATLAS"
	# Ray test the visible face against actual imported room triangles, including
	# shared plants. Flat diffuse material and renderer remain those of the kit.
	var obstacles=[]
	for node in room.find_children("*","MeshInstance3D",true,false):
		var tri=node.mesh.get_faces()
		for i in range(0,tri.size(),3):
			obstacles.append([node.global_transform*tri[i],node.global_transform*tri[i+1],node.global_transform*tri[i+2]])
	var occluded=0
	for x in [-.34,-.17,0,.17,.34]:
		for y in [-.20,-.10,0,.10,.20]:
			var target=fare.global_transform*Vector3(x,y,.059)
			for tri in obstacles:
				var hit=Geometry3D.ray_intersects_triangle(target,camera.basis.z,tri[0],tri[1],tri[2])
				if hit!=null and hit.distance_to(target)>.0005:occluded+=1;break
	check(occluded==0,"25 face samples unobstructed by actual room, counter, monitor and plants at default angles")
	report.visibility={"samples":25,"occluded":occluded,"pitch":43,"yaw":yaw}
	await capture("fare-board-room-43deg")
	room.visible=false;rig.visible=false;fare.position=Vector3.ZERO;fare.rotation=Vector3.ZERO
	# Orthographic details inspect geometry and atlas color without cast shadows.
	# The room capture above retains the kit's unchanged real shadow settings.
	sun.shadow_enabled=false
	report.detail_cast_shadows=false
	pose(Vector3(0,0,0),1.37,0,0,3)
	title.text="FARE BOARD / FRONT (+Z) / SEVEN ROWS"
	note.text="SEVEN IVORY BARS / RED, MUSTARD, TEAL, IVORY DOTS / TWO BRASS HEADS\nFRAME 0.05 M / RECESS 0.01 M / NO TEXT OR SYMBOLS / DETAIL LIGHTING: CAST SHADOWS OFF"
	await capture("fare-board-front")
	pose(Vector3(0,0,.035),1.30,0,90,3)
	title.text="FARE BOARD / RIGHT SIDE / BACK CENTRE PIVOT"
	note.text="MAXIMUM DEPTH 0.070 M / WALL CONTACT PLANE Z = 0 / FACE +Z / CAST SHADOWS OFF\nboard_center (0, 0, 0.05) / mark (0, 0.45, 0) / EMPTY NODES"
	var canvas=CanvasLayer.new();vp.add_child(canvas)
	var a=camera.unproject_position(Vector3(0,-.375,0));var b=camera.unproject_position(Vector3(0,-.375,.07))
	var line=Line2D.new();line.points=PackedVector2Array([a,b]);line.width=3;line.default_color=Color("765041");canvas.add_child(line)
	var label=Label.new();label.text="0.070 m";label.add_theme_color_override("font_color",Color("614539"));label.add_theme_font_size_override("font_size",25);label.position=(a+b)/2+Vector2(-48,8);canvas.add_child(label)
	await capture("fare-board-side")
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name()
	report.failures=report.checks.filter(func(c):return not c.passed)
	FileAccess.open(output+"/validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("FARE_QA ",report.checks.size()," checks; ",report.failures.size()," failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)

func setup_world():
	vp=SubViewport.new();vp.size=Vector2i(1800,1400);vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp);world=Node3D.new();vp.add_child(world)
	var lighting=layout.review_lighting
	var env=Environment.new();env.background_mode=Environment.BG_COLOR
	env.background_color=Color(lighting.background);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(lighting.ambient_color);env.ambient_light_energy=lighting.ambient
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	sun=DirectionalLight3D.new();world.add_child(sun);sun.position=vec(lighting.sun_position);sun.look_at(vec(lighting.sun_target))
	sun.light_color=Color(lighting.sun_color);sun.light_energy=lighting.sun;sun.shadow_enabled=true
	sun.shadow_bias=lighting.shadow_bias;sun.shadow_normal_bias=lighting.shadow_normal_bias
	sun.directional_shadow_max_distance=lighting.shadow_distance;sun.light_angular_distance=1.4
	for row in lighting.points:
		var light=OmniLight3D.new();world.add_child(light);light.position=vec(row.position)
		light.light_color=Color(row.color);light.light_energy=row.energy;light.omni_range=row.range
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1;camera.far=70;camera.current=true;world.add_child(camera)
	var canvas=CanvasLayer.new();vp.add_child(canvas)
	var footer=ColorRect.new();footer.position=Vector2(0,1280);footer.size=Vector2(1800,120);footer.color=Color("e3e9de");canvas.add_child(footer)
	title=Label.new();title.position=Vector2(40,35);title.add_theme_font_size_override("font_size",28);title.add_theme_color_override("font_color",Color("394b42"));canvas.add_child(title)
	note=Label.new();note.position=Vector2(40,1300);note.add_theme_font_size_override("font_size",22);note.add_theme_color_override("font_color",Color("394b42"));canvas.add_child(note)

func pose(focus,size,pitch,yaw,distance=20):
	camera.size=size;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*distance
func capture(id):
	for i in 8:await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image()
	check(image.save_png(output+"/"+id+".png")==OK,"Capture saved: "+id)
	report.captures.append({"id":id,"size":[image.get_width(),image.get_height()],"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y,"camera_size":camera.size})
	print("FARE_CAPTURE ",id)
