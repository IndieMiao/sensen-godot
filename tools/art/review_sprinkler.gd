extends Node
## Offline fixture using the game's farm materials, crop meshes and pinned camera.
const Art = preload("res://modules/farm/farm_art.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const Plant = preload("res://modules/farm/crop_plant_mesh.gd")
const BED_H = .15
const PITCH = 1.30
const HEAD_POSITION = Vector3(0,.42,0)
var report = {"checks": [], "captures": [], "crops": [], "rotations": []}
var vp: SubViewport
var world: Node3D
var cam: Camera3D
var environment: Environment
var sprinkler: Node3D
var head: MeshInstance3D
var rig
var beds: Array = []
var crops: Array = []
var floor_node: MeshInstance3D
var output: String
var sun: DirectionalLight3D
var entry: Dictionary

func _ready(): run.call_deferred()

func check(ok, label):
	report.checks.append({"check": label, "passed": bool(ok)})
	if not ok: push_error(label)

func xyz(v): return [v.x, v.y, v.z]

func create_world():
	vp = SubViewport.new()
	vp.size = Vector2i(360, 800)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	world = Node3D.new(); vp.add_child(world)
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.906,.941,.875)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.79,.88,.94)
	environment.ambient_light_energy = .42
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var env = WorldEnvironment.new(); env.environment = environment; world.add_child(env)
	sun = DirectionalLight3D.new(); world.add_child(sun)
	sun.rotation_degrees = Vector3(-51,-38,0)
	sun.light_color = Color(1,.96,.87); sun.light_energy = 1.1
	sun.shadow_enabled = true; sun.shadow_opacity = .58
	sun.shadow_bias = .1; sun.shadow_normal_bias = 1.0; sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 0
	var floor_mesh = PlaneMesh.new(); floor_mesh.size = Vector2(40,40)
	floor_node = MeshInstance3D.new(); floor_node.mesh = floor_mesh; world.add_child(floor_node)
	floor_node.position.y = -.005
	var mat = StandardMaterial3D.new(); mat.albedo_color = Color("dbe3ce"); mat.roughness = 1
	floor_node.material_override = mat
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam = Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH; cam.current = true; world.add_child(cam)

func game_camera(zoom=1.0):
	cam.size = FarmCamera.close_view_size(Vector2(360,800))*FarmCamera.P0_VIEW_K/zoom
	FarmCamera.place(cam,Vector3(0,.7,0)); FarmCamera.fit_ground_depth(cam)

func inspect_mesh(node):
	var points = PackedVector3Array()
	for m in node.find_children("*", "MeshInstance3D", true, false):
		for i in m.mesh.get_surface_count():
			for v in m.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				points.append(node.global_transform.affine_inverse()*m.global_transform*v)
	return points

func make_fixture():
	var plot = Art.mesh_for("plot")
	check(plot.get_aabb().size.x > .9399 and plot.get_aabb().size.x < .9401,"actual plot 0.94m wide")
	var size = Vector3(.54,.48,.54)*.94
	var crop_mat = StandardMaterial3D.new()
	crop_mat.vertex_color_use_as_albedo = true; crop_mat.vertex_color_is_srgb = true
	crop_mat.roughness = .95; crop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var kinds = ["R","L","C","B","R","L","C","B"]
	var tints = {"R":Color(.97,.96,.85),"L":Color(.46,.76,.4),"C":Color(.93,.6,.24),"B":Color(.55,.8,.38)}
	for z in [-1,0,1]:
		for x in [-1,0,1]:
			var bed = Art.instance("plot",Vector3(x*PITCH,0,z*PITCH)); world.add_child(bed); beds.append(bed)
			check(bed.mesh == plot and bed.scale == Vector3.ONE,"real unscaled plot at %d,%d"%[x,z])
			if x == 0 and z == 0: continue
			var kind = kinds[crops.size()]
			var node = MultiMeshInstance3D.new()
			var mm = MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
			mm.mesh = Plant.build(kind,tints[kind]); mm.instance_count = 1
			var cell = Vector2i(4+x*2,3+z*2)
			var yaw = float(posmod(cell.x*7+cell.y*11,16))*TAU/16.0
			var transform = Transform3D(Basis(Vector3.UP,yaw)*Basis.from_scale(size),Vector3(x*PITCH,BED_H+size.y*.5,z*PITCH))
			mm.set_instance_transform(0,transform)
			mm.set_instance_color(0,Color(.72,.93,.52).lerp(Color.WHITE,1.0/3))
			node.multimesh = mm; node.material_override = crop_mat; world.add_child(node); crops.append(node)
			var aabb = transform*mm.mesh.get_aabb()
			check(aabb.end.y-BED_H >= .30 and aabb.end.y-BED_H <= .50,"mid-stage crop height 0.3-0.5m "+kind)
			report.crops.append({"kind":kind,"stage":1,"plot_xz":[x,z],"height_above_bed_m":aabb.end.y-BED_H,
				"scale":xyz(size),"source":"modules/farm/crop_plant_mesh.gd"})
	sprinkler = load("res://assets/farm/art/sprinkler.glb").instantiate(); world.add_child(sprinkler)
	sprinkler.position.y = BED_H
	head = sprinkler.find_child("head",true,false)
	var actual_triangles = 0
	var nodes = sprinkler.find_children("*","MeshInstance3D",true,false)
	check(nodes.size()==2,"two actual mesh nodes")
	for node in nodes:
		node.material_override = Art.material()
		check(node.mesh.get_surface_count()==1,str(node.name)+" one surface")
		# Godot prefixes the file stem to the glTF mesh's authored name.
		check(node.mesh.resource_name=="sprinkler_sprinkler_"+str(node.name)+"_mobile",str(node.name)+" imported mesh resource name")
		var data = node.mesh.surface_get_arrays(0)
		actual_triangles += data[Mesh.ARRAY_INDEX].size()/3
		check(data[Mesh.ARRAY_TEX_UV]==null,str(node.name)+" no UV")
	check(actual_triangles==entry.triangles and actual_triangles<=800,"actual imported triangle budget")
	check(Art.material().vertex_color_use_as_albedo and not Art.material().vertex_color_is_srgb,"unmodified shared linear FarmArt material")
	check(head.position.distance_to(HEAD_POSITION)<.00001,"head pivot at local 0,.42,0")
	var marker = sprinkler.find_child("spray_origin",true,false)
	check(marker.position.distance_to(HEAD_POSITION)<.00001,"spray_origin at head centre")
	for angle in [0,45,90]:
		head.rotation_degrees.y = angle
		var points = inspect_mesh(sprinkler)
		var maximum = 0.0
		for p in points: maximum = maxf(maximum,Vector2(p.x,p.z).length())
		check(maximum<=.20001,"actual imported radial extent at %d degrees"%angle)
		check(head.global_position.distance_to(HEAD_POSITION+Vector3.UP*BED_H)<.00001,"head pivot stays fixed at %d degrees"%angle)
		check(marker.global_position.distance_to(head.global_position)<.00001,"spray origin fixed at %d degrees"%angle)
		report.rotations.append({"angle":angle,"head_world_pivot":xyz(head.global_position),"max_radius_m":maximum})
	head.rotation_degrees.y = 0

func avatar():
	rig = Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity: child.free()
	rig.assembler = AvatarAssemblerMerged.new(); world.add_child(rig)
	rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:
		await get_tree().process_frame; ticks+=1
	check(not rig.is_busy(),"fixture avatar assembled")
	rig.play_motion("idle")
	var anim=rig.get_node("AnimationPlayer"); anim.seek(.3,true); anim.pause()
	var lo=INF; var hi=-INF
	for mesh in rig.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null or not mesh.is_visible_in_tree(): continue
		var posed=mesh.bake_mesh_from_current_skeleton_pose() if mesh.skin!=null else mesh.mesh
		if posed==null: continue
		for i in posed.get_surface_count():
			for v in posed.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				var p=rig.global_transform.affine_inverse()*mesh.global_transform*v
				lo=minf(lo,p.y); hi=maxf(hi,p.y)
	var scale_factor=1.745/(hi-lo)
	rig.scale=Vector3.ONE*scale_factor
	rig.position=Vector3(2.28,-lo*scale_factor,.55)
	report.avatar={"measured_source_height_m":hi-lo,"uniform_scale":scale_factor,"height_m":1.745}

func pose(focus,width,pitch,yaw):
	cam.size=width; cam.rotation_degrees=Vector3(-pitch,yaw,0)
	cam.position=focus+cam.basis.z*12; FarmCamera.fit_ground_depth(cam)

func capture(id):
	for i in 8: await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image()
	check(image.save_png(output+"/"+id+".png")==OK,"saved "+id)
	var low=Vector2(INF,INF); var high=Vector2(-INF,-INF)
	for p in inspect_mesh(sprinkler):
		var screen=cam.unproject_position(sprinkler.global_transform*p)
		low=low.min(screen); high=high.max(screen)
	report.captures.append({"id":id,"size":[image.get_width(),image.get_height()],"camera_width_m":cam.size,
		"pitch":-cam.rotation_degrees.x,"yaw":cam.rotation_degrees.y,"sprinkler_bounds_px":[[low.x,low.y],[high.x,high.y]],
		"head_angle":head.rotation_degrees.y})
	print("SPRINKLER_CAPTURE ",id)

func palette_plate(colour, x):
	var st=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(colour)
	for p in [Vector3(-.25,0,-.25),Vector3(.25,0,-.25),Vector3(.25,0,.25),Vector3(-.25,0,-.25),Vector3(.25,0,.25),Vector3(-.25,0,.25)]:
		st.set_normal(Vector3.UP); st.add_vertex(p)
	var node=MeshInstance3D.new(); node.mesh=st.commit(); node.material_override=Art.material()
	world.add_child(node); node.position=Vector3(x,.17,.70)
	return node

func occlusion_controls():
	for bed in beds: bed.visible=false
	for crop in crops: crop.visible=false
	rig.visible=false; floor_node.visible=false; sun.visible=false
	environment.background_color=Color.BLACK
	var white=StandardMaterial3D.new(); white.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color=Color.WHITE; white.cull_mode=BaseMaterial3D.CULL_DISABLED
	var black=white.duplicate(); black.albedo_color=Color.BLACK
	for m in sprinkler.find_children("*","MeshInstance3D",true,false): m.material_override=black
	var rear=crops[1]; rear.visible=true; rear.material_override=white
	vp.size=Vector2i(1080,2400); game_camera()
	sprinkler.visible=false; await capture("rear_crop_without_sprinkler_mask")
	sprinkler.visible=true; await capture("rear_crop_with_sprinkler_mask")

func run():
	output=ProjectSettings.globalize_path("res://../captures"); DirAccess.make_dir_recursive_absolute(output)
	entry=JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/art/manifest.json")).assets.sprinkler
	report.asset_sha256=entry.sha256
	report.art_revision=entry.art_revision
	create_world(); make_fixture(); await avatar()
	game_camera(); check(is_equal_approx(cam.size,6.72),"default game camera width 6.72m")
	await capture("default_43deg_360")
	game_camera(.8); check(is_equal_approx(cam.size,8.4),"actual minimum zoom 0.8 width 8.4m")
	await capture("minimum_zoom_360")
	var revision_only = "--proportion-revision" in OS.get_cmdline_user_args()
	if not revision_only:
		vp.size=Vector2i(1080,2400); game_camera(); await capture("default_43deg_hd")
	rig.visible=false; vp.size=Vector2i(1000,1000)
	pose(Vector3.ZERO,4.2,90,0); await capture("top")
	if not revision_only:
		await supplemental_views()
	if "--compare-revisions" in OS.get_cmdline_user_args():
		await revision_comparison()
	await occlusion_controls()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","actual Mobile renderer")
	report.passed=report.checks.all(func(c): return c.passed)
	report.failures=report.checks.filter(func(c): return not c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("SPRINKLER_GODOT ",report.passed," checks=",report.checks.size())
	get_tree().quit(0 if report.passed else 1)

func revision_comparison():
	var current=sprinkler
	current.visible=false
	for crop in crops: crop.visible=false
	for bed in beds: bed.visible=bed.position.length()<.01
	rig.visible=false
	vp.size=Vector2i(600,600)
	pose(Vector3(0,.40,0),1.08,43,14.5)
	report.comparison_sources=JSON.parse_string(FileAccess.get_file_as_string("res://references/manifest.json"))
	for version in ["v1","v1_1","v1_2"]:
		if version=="v1_2":
			sprinkler=current
		else:
			sprinkler=load("res://references/sprinkler_"+version+".glb").instantiate()
			world.add_child(sprinkler)
			sprinkler.position=Vector3(0,BED_H,0)
			for mesh in sprinkler.find_children("*","MeshInstance3D",true,false):
				mesh.material_override=Art.material()
		sprinkler.visible=true
		head=sprinkler.find_child("head",true,false)
		check(sprinkler.scale==Vector3.ONE,"comparison "+version+" unit scale")
		await capture("comparison_"+version)
		if version!="v1_2": sprinkler.free()
	sprinkler=current
	head=current.find_child("head",true,false)

func supplemental_views():
	for crop in crops: crop.visible=false
	for bed in beds: bed.visible=bed.position.length()<.01
	vp.size=Vector2i(600,600); pose(Vector3(0,.46,0),1.08,43,14.5)
	for angle in [0,45,90]:
		head.rotation_degrees.y=angle; await capture("head_%03d"%angle)
	head.rotation_degrees.y=0
	var comparison=JSON.parse_string(FileAccess.get_file_as_string("res://../geometry-validation.json")).colour_comparison
	var wood=comparison.wood_linear
	var rim=comparison.plot_rim_linear
	var plate_a=palette_plate(Color(entry.palette_srgb.brass).srgb_to_linear(),-.59)
	var plate_b=palette_plate(Color(wood[0],wood[1],wood[2]),0)
	var plate_c=palette_plate(Color(rim[0],rim[1],rim[2]),.59)
	vp.size=Vector2i(1000,1000); pose(Vector3(0,.28,.25),2.10,62,0)
	await capture("brass_wood")
	plate_a.free(); plate_b.free(); plate_c.free()
