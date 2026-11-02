extends Node
const MineCombat=preload("res://modules/mining/mine_combat.gd")
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var report={"checks":[],"assets":{},"captures":[]}
var output:String

func _ready():run.call_deferred()
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)

func setup():
	vp=SubViewport.new();vp.size=Vector2i(512,512);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	world=Node3D.new();vp.add_child(world)
	var environment=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("DCE4E2")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("F0F0F2")
	environment.ambient_light_energy=.65;environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var env=WorldEnvironment.new();env.environment=environment;world.add_child(env)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_energy=.9;sun.light_color=Color("FFF6EA");sun.shadow_enabled=true;sun.shadow_opacity=.5
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1;camera.far=60;camera.current=true;world.add_child(camera)

func pose(yaw,pitch,width,focus):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*12

func capture(name):
	for i in 5:await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image();check(image.save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"id":name,"pixels":[vp.size.x,vp.size.y],"width_m":camera.size,
		"pitch":-camera.rotation_degrees.x,"yaw":camera.rotation_degrees.y})
	print("KIT_CAPTURE ",name)

func collision_proxy(body_mesh):
	var faces:PackedVector3Array=body_mesh.get_faces()
	# Close only the real code mesh's 4 cm top opening for downward contact rays.
	for i in 32:
		var a=TAU*i/32;var b=TAU*(i+1)/32
		faces.append(Vector3(0,1.43,0));faces.append(Vector3(cos(b)*.04,1.43,sin(b)*.04));faces.append(Vector3(cos(a)*.04,1.43,sin(a)*.04))
	var proxy=StaticBody3D.new();var shape=CollisionShape3D.new();var concave=ConcavePolygonShape3D.new()
	concave.set_faces(faces);concave.backface_collision=true;shape.shape=concave;proxy.add_child(shape);world.add_child(proxy)
	return proxy

func validate(model,spec):
	var id:String=spec.name
	var meshes=model.find_children("*","MeshInstance3D",true,false)
	check(meshes.size()==1,id+": one mesh node")
	check(model.find_children("*","Skeleton3D",true,false).is_empty() and model.find_children("*","AnimationPlayer",true,false).is_empty(),id+": no rig or animations")
	check(model.find_children("*","CollisionObject3D",true,false).is_empty(),id+": no runtime collision")
	var mesh:MeshInstance3D=meshes[0];var arrays=mesh.mesh.surface_get_arrays(0)
	check(mesh.mesh.get_surface_count()==1,id+": one surface")
	check(arrays[Mesh.ARRAY_INDEX].size()/3==spec.triangles and spec.triangles<=800,id+": measured triangles and budget")
	check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,id+": imported shadows off")
	var mat=mesh.get_active_material(0)
	check(mat is StandardMaterial3D and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb and mat.albedo_texture==null,id+": linear vertex paint, no texture")
	check(arrays[Mesh.ARRAY_COLOR].size()==arrays[Mesh.ARRAY_VERTEX].size(),id+": vertex paint retained")
	var lo=Vector3.INF;var hi=-Vector3.INF
	for v in arrays[Mesh.ARRAY_VERTEX]:
		var p=model.global_transform.affine_inverse()*mesh.global_transform*v;lo=lo.min(p);hi=hi.max(p)
	for axis in 3:
		check(absf(lo[axis]-spec.bounds[0][axis])<.00001 and absf(hi[axis]-spec.bounds[1][axis])<.00001,id+": measured bound axis "+str(axis))
	var config=ConfigFile.new();config.load("res://"+spec.file+".import")
	check(str(config.get_value("remap","uid","")).begins_with("uid://"),id+": Godot-generated UID")
	var result={"bounds":[xyz(lo),xyz(hi)],"triangles":arrays[Mesh.ARRAY_INDEX].size()/3,"surfaces":1,"uid":config.get_value("remap","uid","")}
	return result

func contact(model):
	var mesh:MeshInstance3D=model.find_children("*","MeshInstance3D",true,false)[0]
	var faces:PackedVector3Array=mesh.mesh.get_faces();var minimum=INF;var samples=0;var penetrating=0
	var space=world.get_world_3d().direct_space_state
	for i in range(0,faces.size(),3):
		for u in 7:
			for v in range(7-u):
				var p=mesh.global_transform*(faces[i]+(faces[i+1]-faces[i])*u/6.+(faces[i+2]-faces[i])*v/6.)
				var query=PhysicsRayQueryParameters3D.create(Vector3(p.x,3,p.z),Vector3(p.x,.05,p.z))
				query.hit_back_faces=true;var hit=space.intersect_ray(query)
				if hit.is_empty():continue
				var gap=p.y-hit.position.y;minimum=minf(minimum,gap);samples+=1
				if gap<-.001:penetrating+=1
	return {"minimum_gap_m":minimum,"samples":samples,"penetrating_samples":penetrating,
		"method":"Downward physics rays on actual unmodified _slime_body(1.0); only 0.04 m radius top opening capped"}

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output);setup()
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/monsters/slime_king/manifest.json"))
	var combat=MineCombat.new();var slime=combat._slime({"radius":1.0},false);world.add_child(slime)
	for name in ["HealthFill","HealthTrack","Health"]:slime.get_node(name).visible=false
	var proxy=collision_proxy(combat._slime_body(1.0));combat.free()
	await get_tree().physics_frame;await get_tree().physics_frame
	for spec in manifest.assets:
		var model=load("res://"+spec.file).instantiate();world.add_child(model)
		var row=validate(model,spec);slime.visible=false
		var lo=Vector3(spec.bounds[0][0],spec.bounds[0][1],spec.bounds[0][2]);var hi=Vector3(spec.bounds[1][0],spec.bounds[1][1],spec.bounds[1][2])
		var width=maxf(maxf(hi.x-lo.x,hi.y-lo.y),hi.z-lo.z)*1.35
		for view in [["front",0],["side",90],["back",180]]:
			pose(view[1],0,width,(lo+hi)/2);await capture(spec.name+"_"+view[0])
		model.position.y=1.43;slime.visible=true
		(slime.get_node("Body").material_override as StandardMaterial3D).albedo_color=Color(spec.preview_body_tint)
		row.contact=contact(model);check(row.contact.penetrating_samples==0 and row.contact.minimum_gap_m<.01,spec.name+": sampled fit against actual slime triangles")
		pose(0,43,2.8,Vector3(0,.93,0));await capture(spec.name+"_mounted_43deg")
		if spec.name=="ironback_plates":
			pose(145,43,2.8,Vector3(0,.93,0));await capture(spec.name+"_mounted_rear")
		report.assets[spec.name]=row;model.queue_free();await get_tree().process_frame
	proxy.queue_free();slime.queue_free()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Actual Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	var f=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t")+"\n");f.close()
	print("KIT_VALIDATION ",report.passed)
	vp.queue_free();await get_tree().process_frame;await get_tree().process_frame
	get_tree().quit(0 if report.passed else 1)
