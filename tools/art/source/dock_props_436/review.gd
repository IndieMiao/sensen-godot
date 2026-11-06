extends Node
const KIT="res://assets/landmarks/_shared/dock_props/"
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
	env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("DDE8E7");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("FFF0DC");env.ambient_light_energy=.65
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.light_color=Color("FFF1D8");sun.light_energy=1.0;sun.shadow_enabled=true;sun.shadow_opacity=.50;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.shadow_bias=.05;sun.shadow_normal_bias=.25;world.add_child(sun)
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
	report.captures.append({"file":name+".png","size":[vp.size.x,vp.size.y],"camera_width":camera.size,"pitch":-camera.rotation_degrees.x});print("DOCK_CAPTURE ",name)
func catalogue():
	vp.size=Vector2i(360,250)
	for name in manifest.assets:
		clear();var row=manifest.assets[name];var low=v(row.bounds[0]);var high=v(row.bounds[1]);var n=piece(name,Vector3(0,-low.y,0));var w=high.x-low.x;var height=high.y-low.y
		move_player(Vector3(w*.5+.62,0,0));rig.rotation_degrees.y=180
		var focus=Vector3(.3,maxf(height,1.745)*.53,0);var width=maxf(w+2.1,maxf(height,1.745)*2.15)
		pose(width,focus,24,22);await capture("catalog_"+name)
		report.catalog[name]={"bounds":row.bounds,"triangles":row.triangles,"avatar_height":1.745,"pose_lift_m":-low.y}

func inspect():
	for name in manifest.assets:
		var n=piece(name,Vector3.ZERO);var meshes=n.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==1,name+" one mesh")
		var total=0;var surfaces=0
		for mi in meshes:
			total+=tri(mi.mesh);surfaces+=mi.mesh.get_surface_count()
			var mat=mi.mesh.surface_get_material(0)
			check(mat is StandardMaterial3D and mat.vertex_color_use_as_albedo,name+" matte vertex material")
			check(mat.albedo_texture==null and mat.roughness>=.88,name+" no texture; roughness")
		check(total==manifest.assets[name].triangles and total<=800,name+" triangle budget",total)
		check(surfaces==1,name+" single surface")
		n.free()
	check(manifest.assets.size()==12,"All twelve dock props")

func simple_box(at:Vector3,size:Vector3,material:Material,label:String):
	var mi=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=size;mi.mesh=mesh;mi.material_override=material;mi.position=at;mi.name=label;assembly.add_child(mi);return mi

const SHARED="res://assets/landmarks/_shared/"
var foam_nodes=[]
func external(folder:String,name:String,at:Vector3,yaw=0.0):
	var n=load(SHARED+folder+"/"+name+".glb").instantiate();assembly.add_child(n);n.position=at;n.rotation_degrees.y=yaw;n.set_meta("dependency",folder+"/"+name);return n
func apply_material(n,material):
	for mi in n.find_children("*","MeshInstance3D",true,false):mi.material_override=material
func freeze_shader(source:ShaderMaterial):
	var material=source.duplicate(true);var shader=Shader.new()
	shader.code=source.shader.code.replace("TIME","review_clock").replace("shader_type spatial;","shader_type spatial;\nuniform float review_clock=0.0;")
	material.shader=shader;material.set_shader_parameter("review_clock",1.5);return material
func coast(name:String,at:Vector3,yaw=0.0):
	var n=external("coast_kit",name,at,yaw)
	var mat=load(SHARED+"coast_kit/coast_warm_sand.tres").duplicate(true);mat.set_shader_parameter("water_level",.2)
	apply_material(n,mat);return n
func foam(name:String,at:Vector3,yaw=0.0,ends=Vector2.ZERO):
	var n=external("water_edge","water_edge_"+name,at+Vector3(0,.218,0),yaw)
	var mat=freeze_shader(load(SHARED+"water_edge/water_edge_material.tres"));mat.set_shader_parameter("end_fade_uv",ends);apply_material(n,mat)
	for mi in n.find_children("*","MeshInstance3D",true,false):mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;mi.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	foam_nodes.append(n);return n
func far_cards():
	# SGODOT-434's recommended three-card urban composition, at screen upper edge.
	var view_height=camera.size*vp.size.y/vp.size.x
	for row in [["far_hills_a",0.0,.84],["far_city_high",1.23,.82],["far_bridge",-2.1,1.0]]:
		var pos=camera.global_transform*Vector3(row[1],view_height*(.5-.16),-60)
		var n=external("far_backdrop",row[0],pos);n.scale=Vector3.ONE*row[2]
		for mi in n.find_children("*","MeshInstance3D",true,false):
			mi.extra_cull_margin=100;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;mi.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
func landing():
	clear();foam_nodes.clear();env.background_color=Color("67AFC2")
	var sea=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(512,512);sea.mesh=plane;sea.position.y=.2
	var bay=freeze_shader(load(SHARED+"sea_backdrop/bay.tres"));bay.render_priority=-100;sea.material_override=bay;sea.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;assembly.add_child(sea)
	var paving=load(SHARED+"ground_detail/ground_paving.tres")
	var grass=load(SHARED+"ground_detail/ground_grass.tres")
	simple_box(Vector3(-2,.60,0),Vector3(4,1.2,6),paving,"ReviewOnlyFourBySixQuay")
	simple_box(Vector3(-19,.56,0),Vector3(30,1.12,36),grass,"ReviewOnlyLandBackdrop")
	for z in [-2,2]:
		coast("coast_seawall",Vector3(0,0,z),90)
		foam("straight",Vector3(0,0,z),90,Vector2(.12,.12))
	coast("coast_dock_end",Vector3(1,0,0))
	coast("coast_dock_straight",Vector3(5.4,0,0))
	piece("boarding_gangplank",Vector3(3.2,1.1,0))
	# v1.2 piles are at localX=±.66/Z=±.72. Omit the shore-adjacent pair.
	for x in [1.66,4.74,6.06]:
		for z in [-.72,.72]:foam("pile_ring",Vector3(x,0,z))
	piece("ticket_booth",Vector3(-1.0,1.2,-2),-90)
	piece("waiting_shelter",Vector3(-1.0,1.2,1.8),-90)
	piece("fishing_net_rack",Vector3(-3.45,1.2,2.0),-90)
	piece("wood_crate_closed",Vector3(-3.2,1.2,-2.4),-90)
	piece("wood_crate_open",Vector3(-3.3,1.2,-1.2),-90)
	piece("rope_coil_bound",Vector3(-3.2,2.05,-2.4),-90)
	piece("wood_barrel_closed",Vector3(-2.65,1.2,.75))
	piece("wood_barrel_open",Vector3(-2.65,1.2,2.6))
	piece("lifebuoy_stand",Vector3(5.1,1.2,.60),-90)
	piece("rope_coil_flat",Vector3(5.7,1.2,0))
	piece("beacon_pole",Vector3(6.1,1.2,-.72))
	move_player(Vector3(-.55,1.2,.20));rig.rotation_degrees.y=90
	pose(6.72,Vector3(1.8,2.5,0),43,-90);far_cards()
	var count=0;var surfaces=0;var props={};var dependencies={}
	for n in assembly.get_children():
		if n.has_meta("kit_id"):
			var key=n.get_meta("kit_id");props[key]=props.get(key,0)+1
		if n.has_meta("dependency"):
			var key=n.get_meta("dependency");dependencies[key]=dependencies.get(key,0)+1
	for mi in assembly.find_children("*","MeshInstance3D",true,false):count+=tri(mi.mesh);surfaces+=mi.mesh.get_surface_count()
	report.example={"main_footprint_m":[10.4,6],"dock_deck_y":1.2,"water_y":.2,"foam_y":.218,"props":props,"dependencies":dependencies,"triangles_including_review_ground":count,"surfaces_including_review_ground":surfaces,"far_cards":3,"bay_priority":-100,"foam_instances":foam_nodes.size(),"layout_exported":false}
	check(props.size()==12,"All twelve new props used in landing")
	check(foam_nodes.size()==8,"Two shore ribbons and six separated pile rings")
	check((Vector3(3.2,1.1,0)+Vector3(-1.2,.1,0)).distance_to(Vector3(2,1.2,0))<.00001,"Gangplank dock connector matches426 terminal")
	check((Vector3(3.2,1.1,0)+Vector3(1.2,.1,0)).distance_to(Vector3(4.4,1.2,0))<.00001,"Gangplank far connector meets426 landing")

func gangplank_test():
	clear();var a=coast("coast_dock_end",Vector3.ZERO);piece("boarding_gangplank",Vector3(2.2,1.1,0))
	for mi in assembly.find_children("*","MeshInstance3D",true,false):mi.create_trimesh_collision()
	await get_tree().physics_frame
	var space=world.get_world_3d().direct_space_state
	for x in [.999,1.0,1.001,1.005]:
		for z in [-.45,0,.45]:
			var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,2,z),Vector3(x,.8,z)))
			check(not hit.is_empty() and abs(hit.position.y-1.2)<.00001,"Flush dock/gang top x="+str(x)+" z="+str(z),xyz(hit.get("position",Vector3.ZERO)))
	# End bumpers occupy|Z|0.73..0.91; the entire1.20m board lies between them.
	check(.73-manifest.assets.boarding_gangplank.deck_size_m[1]/2>=.1299,"13cm clearance to each terminal bumper")
	clear()

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"manifest.json"))
	setup();camera.far=180;inspect();await avatar();await gangplank_test();landing();await capture("example_360")
	report.default_view={"draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
	clear();env.background_color=Color("DDE8E7");await catalogue()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("DOCK_PROPS_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
