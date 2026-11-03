extends Node
const KIT="res://assets/rooms/poi_culture_hall/props/"
var vp:SubViewport
var camera:Camera3D
var floor_model:Node3D
var mosaic:Node3D
var report={"checks":[],"captures":[]}
var output:String
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func pose(width,pitch,yaw):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0)
	camera.position=mosaic.position+camera.basis.z*20
func capture(name):
	for i in 8:await RenderingServer.frame_post_draw
	var img=vp.get_texture().get_image()
	check(img.save_png(output+"/"+name+".png")==OK,"Capture "+name)
	var samples={}
	for spec in [{"id":"center","r":.07,"a":.26},{"id":"cream_inner","r":.22,"a":.45},
		{"id":"terracotta","r":.38,"a":.17},{"id":"cream_outer","r":.70,"a":.10},{"id":"rim","r":.935,"a":.075}]:
		var p=mosaic.position+Vector3(cos(spec.a)*spec.r,.008,sin(spec.a)*spec.r)
		var screen=camera.unproject_position(p);var channels=[[],[],[]]
		for dy in range(-2,3):
			for dx in range(-2,3):
				var color=img.get_pixel(roundi(screen.x)+dx,roundi(screen.y)+dy)
				channels[0].append(color.r);channels[1].append(color.g);channels[2].append(color.b)
		for values in channels:values.sort()
		var median=Color(channels[0][12],channels[1][12],channels[2][12])
		samples[spec.id]={"rendered_srgb":"#"+median.to_html(false),"pixel":[screen.x,screen.y]}
	report.captures.append({"file":name+".png","size":[vp.size.x,vp.size.y],"width_m":camera.size,
		"pitch_degrees":-camera.rotation_degrees.x,"yaw_degrees":camera.rotation_degrees.y,"samples":samples})
	print("MOSAIC_CAPTURE ",name)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	var layout=JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/poi_culture_hall/layout.json"))
	var light=layout.review_lighting
	vp=SubViewport.new();vp.size=Vector2i(1200,1200);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var world=Node3D.new();vp.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color.WHITE
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(light.ambient_color)
	env.ambient_light_energy=light.ambient;env.tonemap_mode=Environment.TONE_MAPPER_ACES
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=vec(light.sun_position);sun.look_at(vec(light.sun_target))
	sun.light_energy=light.sun;sun.light_color=Color(light.sun_color);sun.light_angular_distance=light.angular_distance
	sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=light.shadow_distance;sun.shadow_bias=light.shadow_bias;sun.shadow_normal_bias=light.shadow_normal_bias
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1;camera.far=40;camera.current=true;world.add_child(camera)
	floor_model=load("res://assets/rooms/_shared/shell_hall/hall_floor.glb").instantiate();world.add_child(floor_model)
	var shell=JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/_shared/shell_hall/layout.json"))
	var floor_spec=shell.assets.filter(func(s):return s.name=="hall_floor")[0]
	floor_model.position=vec(floor_spec.position);floor_model.rotation_degrees.y=floor_spec.yaw_degrees
	for node in floor_model.find_children("*","MeshInstance3D",true,false):
		for i in node.mesh.get_surface_count():
			var mat=node.get_active_material(i).duplicate();mat.albedo_texture=load(layout.shell_atlas)
			node.set_surface_override_material(i,mat)
	mosaic=load(KIT+"floor_mosaic.glb").instantiate();world.add_child(mosaic)
	var placement=layout.placements.filter(func(p):return p.name=="floor_mosaic")[0]
	mosaic.position=vec(placement.position);mosaic.rotation_degrees.y=placement.yaw_degrees
	var surfaces=0;var triangles=0;var lo=Vector3.INF;var hi=-Vector3.INF
	for node in mosaic.find_children("*","MeshInstance3D",true,false):
		check(node.mesh.resource_name=="floor_mosaic_mobile","Actual mesh name retained")
		check(node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Mosaic does not cast shadow")
		for i in node.mesh.get_surface_count():
			surfaces+=1;var arrays=node.mesh.surface_get_arrays(i);triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
			for v in arrays[Mesh.ARRAY_VERTEX]:
				var p=mosaic.global_transform.affine_inverse()*node.global_transform*v;lo=lo.min(p);hi=hi.max(p)
			var mat=node.get_active_material(i)
			check(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb,"Linear vertex colors used by actual imported material")
	check(triangles==524 and surfaces==1,"524 actual triangles / one surface")
	check((hi-lo).distance_to(Vector3(1.94,.008,1.94))<.00001,"Actual imported diameter and height unchanged")
	check(absf(lo.y)<.00001 and absf(lo.x+hi.x)<.00001 and absf(lo.z+hi.z)<.00001,"Bottom-center origin retained")
	var hit_y=-INF
	for node in floor_model.find_children("*","MeshInstance3D",true,false):
		for i in node.mesh.get_surface_count():
			var arrays=node.mesh.surface_get_arrays(i);var points=arrays[Mesh.ARRAY_VERTEX];var idx=arrays[Mesh.ARRAY_INDEX]
			for j in range(0,idx.size(),3):
				var hit=Geometry3D.segment_intersects_triangle(mosaic.position+Vector3.UP,mosaic.position-Vector3.UP,
					node.global_transform*points[idx[j]],node.global_transform*points[idx[j+1]],node.global_transform*points[idx[j+2]])
				if hit!=null:hit_y=maxf(hit_y,hit.y)
	check(absf(hit_y-layout.floor_y)<.00001,"Real terracotta floor supports mosaic at .08m")
	check(absf(mosaic.position.y-hit_y-.0005)<.00001,"Original .5mm placement clearance retained")
	report.geometry={"bounds":[[lo.x,lo.y,lo.z],[hi.x,hi.y,hi.z]],"triangles":triangles,"surfaces":surfaces}
	report.fixture={"source_art_commit":"a5ffdae184629cd12c082944e2019b5c79248afd","mosaic_position":placement.position,
		"real_floor_y":hit_y,"lighting":light,"tonemap":"ACES","scope":"Real N3 floor and atlas; isolated unoccluded detail, no room assembly changes"}
	floor_model.visible=false;pose(2.25,90,0);await capture("mosaic_topdown")
	floor_model.visible=true;env.background_color=Color(light.background);vp.size=Vector2i(1440,1100)
	pose(3.4,43,45);await capture("mosaic_terracotta_43deg")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Actual Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("MOSAIC_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
