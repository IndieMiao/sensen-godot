extends Node
const KIT="res://assets/rooms/market_plaza/"
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var assembly:Node3D
var rig
var env:Environment
var output:String
var manifest:Dictionary
var report={"checks":[],"captures":[],"catalog":{}}
func _ready():run.call_deferred()
func xyz(v):return [v.x,v.y,v.z]
func v(a):return Vector3(a[0],a[1],a[2])
func check(ok,label,evidence=null):
	report.checks.append({"check":label,"passed":bool(ok),"evidence":evidence})
	if not ok:push_error(label)
func setup():
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	world=Node3D.new();vp.add_child(world);assembly=Node3D.new();world.add_child(assembly)
	env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("F5F1E9");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("FFF8EF");env.ambient_light_energy=.45
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.light_color=Color("FFF8EF");sun.light_energy=.70;sun.shadow_enabled=true;sun.shadow_opacity=.50;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.shadow_bias=.05;sun.shadow_normal_bias=.25;world.add_child(sun)
	camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.near=.1;camera.far=120;world.add_child(camera)
func pose(width:float,focus:Vector3,pitch=43.0,yaw=45.0):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*42
func piece(name:String,at:Vector3,yaw=0.0):
	var n=load(KIT+name+".glb").instantiate();n.name=name+"_"+str(assembly.get_child_count());assembly.add_child(n);n.position=at;n.rotation_degrees.y=yaw;n.set_meta("kit_id",name)
	return n
func clear():
	for n in assembly.get_children():n.free()
func tri(mesh):
	var total=0
	for s in mesh.get_surface_count():total+=mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3
	return total
func avatar():
	rig=Avatar.create_rig()
	for c in rig.get_children():
		if c is RigActivity:c.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	for i in 900:
		if not rig.is_busy():break
		await get_tree().process_frame
	check(not rig.is_busy(),"Default avatar assembled")
	rig.play_motion("idle");var player=rig.get_node("AnimationPlayer");player.seek(.3,true);player.pause()
	var lo=INF;var hi=-INF
	for mi in rig.find_children("*","MeshInstance3D",true,false):
		if not mi.is_visible_in_tree() or mi.mesh==null:continue
		var mesh=mi.bake_mesh_from_current_skeleton_pose() if mi.skin!=null else mi.mesh
		for s in mesh.get_surface_count():
			for p in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var q=rig.global_transform.affine_inverse()*mi.global_transform*p;lo=minf(lo,q.y);hi=maxf(hi,q.y)
	rig.scale=Vector3.ONE*1.745/(hi-lo);rig.set_meta("floor_lift",-lo*rig.scale.y);rig.rotation_degrees.y=200
	report.avatar={"height_m":1.745,"source_height_m":hi-lo}
func move_player(at:Vector3):rig.position=at+Vector3.UP*float(rig.get_meta("floor_lift",0))
func capture(name:String):
	for i in 6:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"file":name+".png","size":[vp.size.x,vp.size.y],"camera_width":camera.size,"pitch":-camera.rotation_degrees.x});print("MARKET_CAPTURE ",name)
func floor_pad(size:Vector3):
	var mi=MeshInstance3D.new();var m=BoxMesh.new();m.size=size;mi.mesh=m;mi.position.y=-size.y*.5-.005
	var mat=StandardMaterial3D.new();mat.albedo_color=Color("E9E1D2");mat.roughness=1.0;mi.material_override=mat;assembly.add_child(mi)
func bounds_points(row:Dictionary,offset=Vector3.ZERO):
	var lo=v(row.bounds[0]);var hi=v(row.bounds[1]);var points=[]
	for x in [lo.x,hi.x]:
		for y in [lo.y,hi.y]:
			for z in [lo.z,hi.z]:points.append(Vector3(x,y,z)+offset)
	return points
func fit(points:Array,pitch=43.0,yaw=45.0):
	camera.rotation_degrees=Vector3(-pitch,yaw,0)
	var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
	for q in points:
		var xy=Vector2(camera.basis.x.dot(q),camera.basis.y.dot(q));lo=lo.min(xy);hi=hi.max(xy)
	var centre=(hi+lo)*.5;var span=hi-lo
	camera.size=maxf(span.x,span.y*float(vp.size.x)/vp.size.y)*1.18
	camera.position=camera.basis.x*centre.x+camera.basis.y*centre.y+camera.basis.z*40
func inspect():
	for row in manifest.assets:
		var n=piece(row.name,Vector3.ZERO);var surfaces=0;var triangles=0
		for mi in n.find_children("*","MeshInstance3D",true,false):
			surfaces+=mi.mesh.get_surface_count();triangles+=tri(mi.mesh)
			var material=mi.mesh.surface_get_material(0)
			check(material is StandardMaterial3D and material.vertex_color_use_as_albedo,row.name+" vertex colour")
			check(material.roughness>=.85 and material.albedo_texture==null,row.name+" matte, no image dependency")
		check(surfaces==1,row.name+" single surface")
		check(triangles==int(row.triangles) and triangles<=int(row.triangle_limit),row.name+" triangle budget",triangles)
		n.free()
func catalogue():
	for row in manifest.assets:
		clear();piece(row.name,Vector3.ZERO);floor_pad(Vector3(16,.08,16));rig.visible=false
		vp.size=Vector2i(640,640);fit(bounds_points(row),43,45);await capture("detail_"+row.name)
		var w=float(row.dimensions_m[0]);var d=float(row.dimensions_m[2]);var at=Vector3(w*.5+.80,0,-d*.5)
		move_player(at);rig.visible=true;rig.rotation_degrees.y=180
		var points=bounds_points(row)
		for x in [-.32,.32]:
			for y in [0,1.745]:
				for z in [-.22,.22]:points.append(at+Vector3(x,y,z))
		vp.size=Vector2i(720,800);fit(points,43,45);await capture("scale_"+row.name)
		if row.name in ["stall_keeper","stall_fish","flower_cart"]:
			rig.visible=false;vp.size=Vector2i(720,640);fit(bounds_points(row),20,225);await capture("back20_"+row.name)
func family():
	clear();vp.size=Vector2i(1500,1100);var points=[];var i=0
	for row in manifest.assets:
		var at=Vector3((i%4-1.5)*4.0,0,(i/4-1)*4.2)
		piece(row.name,at);points.append_array(bounds_points(row,at));i+=1
	floor_pad(Vector3(20,.08,18));rig.visible=true;move_player(Vector3(5.8,0,6.2));rig.rotation_degrees.y=180
	points.append(Vector3(5.8,1.745,6.2));fit(points,43,35);await capture("family")
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"))
	setup();inspect();await avatar();await catalogue();await family()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	report.stage=manifest.stage;report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("MARKET_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
