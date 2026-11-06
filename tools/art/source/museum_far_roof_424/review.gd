extends Node
const KIT="res://assets/landmarks/alcatraz_island/"
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var near_mesh:MeshInstance3D
var far_mesh:MeshInstance3D
var output:String
var report={"checks":[],"views":{}}
func _ready():run.call_deferred()
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label,evidence=null):
	report.checks.append({"check":label,"passed":bool(ok),"evidence":evidence})
	if not ok:push_error(label)
func mesh_from(name):
	var root=load(KIT+name+".glb").instantiate();var mi=root.find_children("*","MeshInstance3D",true,false)[0];var m=mi.mesh;root.free();return m
func tri(m):
	var n=0
	for s in m.get_surface_count():n+=m.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3
	return n
func capture(name,dist,width,pitch,yaw,focus_offset=Vector3.ZERO):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0)
	# Range culling measures the global AABB centre, not the node origin.
	var center=near_mesh.get_aabb().get_center()+near_mesh.position
	camera.position=center+camera.basis.z*dist+focus_offset
	for i in 12:await RenderingServer.frame_post_draw
	var prim=vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	var draws=vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	check(prim==(tri(near_mesh.mesh) if dist<55 else tri(far_mesh.mesh)),name+" engine renders expected LOD only",prim)
	check(draws==1,name+" one visible surface",draws)
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,name+" capture")
	report.views[name]={"camera":xyz(camera.position),"aabb_center_distance":camera.position.distance_to(center),"width_m":width,"pitch":pitch,"yaw":yaw,"size":[vp.size.x,vp.size.y],"visible_triangles":prim,"draws":draws};print("MUSEUM_CAPTURE ",name," ",prim)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	vp=SubViewport.new();vp.size=Vector2i(720,620);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp);world=Node3D.new();vp.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("CEDCE0");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("D5E4EE");env.ambient_light_energy=.72
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-56,-34,0);sun.light_color=Color(1,.965,.88);sun.light_energy=.98;sun.shadow_enabled=false;world.add_child(sun)
	camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.near=.1;camera.far=200;world.add_child(camera)
	near_mesh=MeshInstance3D.new();near_mesh.name="Near";near_mesh.mesh=mesh_from("alc_museum");near_mesh.position=Vector3(0,10,-13);near_mesh.visibility_range_end=55;near_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;world.add_child(near_mesh)
	far_mesh=MeshInstance3D.new();far_mesh.name="Far";far_mesh.mesh=mesh_from("alc_museum_far");far_mesh.position=near_mesh.position;far_mesh.visibility_range_begin=55;far_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;world.add_child(far_mesh)
	var paint=StandardMaterial3D.new();paint.vertex_color_use_as_albedo=true;paint.roughness=.94;paint.metallic_specular=.15;near_mesh.material_override=paint;far_mesh.material_override=paint
	var m=JSON.parse_string(FileAccess.get_file_as_string(KIT+"alc_museum_far_manifest.json"))
	check(tri(near_mesh.mesh)==m.near_triangles and tri(far_mesh.mesh)==m.triangles,"Actual mesh triangles match manifest",[tri(near_mesh.mesh),tri(far_mesh.mesh)])
	check(far_mesh.mesh.get_surface_count()==1,"Far one surface")
	check(near_mesh.get_aabb().is_equal_approx(far_mesh.get_aabb()),"Same imported AABB/pivot",[xyz(near_mesh.get_aabb().position),xyz(far_mesh.get_aabb().position)])
	check(float(m.ratio)>=.18 and float(m.ratio)<=.30,"Far about quarter of near",m.ratio)
	var cfg=ConfigFile.new();check(cfg.load(KIT+"alc_museum_far.glb.import")==OK,"Import readable")
	check(cfg.has_section_key("remap","uid") and FileAccess.get_file_as_string(KIT+"alc_museum_far.glb.import").contains("nodes/root_script=null"),"Godot UID and root_script line")
	check(cfg.get_value("params","gltf/texture_map_mode",0)==1,"Texture map mode 1")
	for pair in [["full",720,620,43.0,43.0,14.5],["front",720,320,43.0,8.0,0.0],["mobile_wide",360,800,20.16,43.0,60.0],["mobile_default",360,800,6.72,43.0,14.5]]:
		vp.size=Vector2i(pair[1],pair[2])
		for dist in [54.0,56.0]:await capture(pair[0]+"_"+str(int(dist))+"m",dist,pair[3],pair[4],pair[5])
	# Pixel alignment control: force each LOD at exactly one camera transform.
	vp.size=Vector2i(720,620);near_mesh.visibility_range_end=0;far_mesh.visible=false
	await capture("fixed_near",54,43,43,14.5)
	near_mesh.visible=false;far_mesh.visible=true;far_mesh.visibility_range_begin=0
	# Request 56 for expected triangle accounting, then compensate along view axis
	# to keep exactly the same position as fixed_near at54.
	await capture("fixed_far",56,43,43,14.5,-camera.basis.z*2)
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n");print("MUSEUM_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
