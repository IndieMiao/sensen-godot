extends Node
const Art=preload("res://modules/farm/farm_art.gd")
const Old=preload("res://scenes/p0/zz_spot_art_old.gd")
var vp:SubViewport
var pond
var runtime
var output:String
var fixture={"energy":{"value":200,"cap":200},"coins":250,"bag":{"slots":[],"free":20},"fishing":{"cast_energy":5},"travel":{"here":"san_francisco"}}
var report={"checks":[],"captures":[],"assets":{},"intercepted_requests":[]}
func _ready():run.call_deferred()
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func xyz(p):return [p.x,p.y,p.z]
func meshes(root):
	var found=root.find_children("*","MeshInstance3D",true,false)
	if root is MeshInstance3D:found.push_front(root)
	return found
func bounds(root):
	var lo=Vector3.INF;var hi=-Vector3.INF;var triangles=0;var surfaces=0
	for node in meshes(root):
		for surface in node.mesh.get_surface_count():
			surfaces+=1;var a=node.mesh.surface_get_arrays(surface)
			triangles+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3
			for v in a[Mesh.ARRAY_VERTEX]:
				var p=root.global_transform.affine_inverse()*node.global_transform*v;lo=lo.min(p);hi=hi.max(p)
	return {"bounds":[xyz(lo),xyz(hi)],"size":xyz(hi-lo),"triangles":triangles,"surfaces":surfaces}
func screen_rect(root):
	var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
	for node in meshes(root):
		for surface in node.mesh.get_surface_count():
			for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p=pond.cam.unproject_position(node.to_global(vertex));lo=lo.min(p);hi=hi.max(p)
	return [lo.x,lo.y,hi.x-lo.x,hi.y-lo.y]
func circle_gap(root,control):
	var rect=control.get_global_rect();var center=rect.get_center();var radius=rect.size.x*.5;var distance=INF
	var closest=Vector2.ZERO
	for node in meshes(root):
		for surface in node.mesh.get_surface_count():
			var a=node.mesh.surface_get_arrays(surface);var indices=a[Mesh.ARRAY_INDEX];var vertices=a[Mesh.ARRAY_VERTEX]
			for i in range(0,indices.size(),3):
				var triangle=PackedVector2Array()
				for k in 3:triangle.append(pond.cam.unproject_position(node.to_global(vertices[indices[i+k]])))
				if Geometry2D.is_point_in_polygon(center,triangle):distance=0;closest=center
				for k in 3:
					var p=Geometry2D.get_closest_point_to_segment(center,triangle[k],triangle[(k+1)%3])
					if p.distance_to(center)<distance:distance=p.distance_to(center);closest=p
	return {"circle_center":[center.x,center.y],"radius_px":radius,"mesh_gap_px":distance-radius,
		"closest_mesh_point":[closest.x,closest.y]}
func load_pond(id):
	if is_instance_valid(pond):
		pond.queue_free();await get_tree().process_frame;await get_tree().process_frame
	pond=load("res://review_pond.gd").new();pond.setup({"pond_id":id});vp.add_child(pond)
	for i in 20:await get_tree().process_frame
	var ticks=0
	while pond.actor.rig.is_busy() and ticks<600:await get_tree().process_frame;ticks+=1
	check(not pond.actor.rig.is_busy(),id+": native player assembled")
	runtime.ui.set_view(fixture);runtime.ui.set_action(pond._action_state(fixture))
	for i in 20:await get_tree().process_frame
	pond._update_camera()
func capture(name,prop=null):
	for i in 12:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Saved "+name)
	var data={"name":name,"pixels":[vp.size.x,vp.size.y],"pond":pond.entry.id,"camera":str(pond.cam.global_transform),
		"pitch_degrees":pond.cam.rotation_degrees.x,"width_m":pond.cam.size,"player":xyz(pond.actor.position)}
	if prop!=null:data["prop_position"]=xyz(prop.position);data["prop_screen_rect"]=screen_rect(prop)
	report.captures.append(data);print("REED_CLAY_CAPTURE ",name)
func validate_asset(node,name,limit,height_min,height_max):
	var stats=bounds(node);report.assets[name]=stats
	check(stats.triangles<=900 and stats.surfaces==1,name+": <=900 triangles / one surface")
	check(stats.size[0]<=limit+.00001 and stats.size[2]<=limit+.00001,name+": entire mesh including leaves within footprint")
	check(stats.size[1]>=height_min and stats.size[1]<=height_max+.00001,name+": height within brief")
	check(absf(stats.bounds[0][1])<.00001,name+": bottom Y=0")
	check(absf(stats.bounds[0][0]+stats.bounds[1][0])<.00001 and absf(stats.bounds[0][2]+stats.bounds[1][2])<.00001,name+": footprint-centre origin")
	check(node.scale==Vector3.ONE,name+": unit instance scale")
	var m=node.get_active_material(0)
	check(m==Art.material() and m.vertex_color_use_as_albedo and not m.vertex_color_is_srgb,name+": shared FarmArt linear vertex colours")
	check(is_equal_approx(m.roughness,.9) and m.albedo_texture==null,name+": matte .9, no texture")
	var cfg=ConfigFile.new();cfg.load("res://assets/farm/art/"+name+".glb.import")
	check(cfg.get_value("params","meshes/light_baking")==1 and cfg.get_value("params","meshes/ensure_tangents")==true and cfg.get_value("params","meshes/generate_lods")==true,name+": sign-compatible importer")
	check(str(cfg.get_value("remap","uid","")).begins_with("uid://"),name+": import UID")
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	runtime=P0Runtime.new();P0Runtime._instance=runtime
	runtime.session.transport=func(method,path,_body,meta):report.intercepted_requests.append({"method":method,"path":path,"type":meta.get("type","")})
	vp.add_child(runtime);runtime.set_process(false);runtime.session.set_process(false)
	await load_pond("pond_san_francisco_03")
	pond.actor.teleport(Vector3(.88,0,-6.62));pond.actor.set_process(false);pond.actor.set_physics_process(false)
	pond._opening=false;pond.p0_recenter();pond._update_camera()
	var reed=pond.get_node("Scenery/ReedBank")
	validate_asset(reed,"reed_bank",1.4,.8,1)
	check(reed.position.is_equal_approx(Vector3(-.3,0,-6.6)),"Reed occupies L1 (-.3, -6.6)")
	check(pond.actor.position.is_equal_approx(Vector3(.88,0,-6.62)),"Reed player at supplied L1 stand (.88, -6.62)")
	check(absf(pond.cam.rotation_degrees.x+43)<.001,"Reed native 43-degree camera")
	await capture("reed_L1_43deg",reed)
	await load_pond("pond_san_francisco_01")
	check(pond._opening and not pond._parked,"Clay uses untouched native opening camera")
	check(pond.actor.position.is_equal_approx(Vector3(6.125,0,-1.625)),"Clay uses original spawn")
	var clay=pond.get_node("Scenery/ClayPit")
	validate_asset(clay,"clay_pit",1.2,0,.5)
	check(clay.position.is_equal_approx(Vector3(7.6,0,-1.4)),"Clay occupies revised F2 (7.6, -1.4)")
	report.clay_clearance={"switch_key":circle_gap(clay,runtime.ui._keys.switch_button()),"main_key":circle_gap(clay,runtime.ui._keys.key())}
	check(report.clay_clearance.switch_key.mesh_gap_px>=12,"Clay projected triangles >=12px from switch outer circle")
	var sr=screen_rect(clay);check(sr[0]>=0 and sr[0]+sr[2]<=360 and sr[1]>=0 and sr[1]+sr[3]<=800,"Complete clay model inside screen")
	await capture("clay_F2_43deg",clay)
	runtime.ui.root.visible=false
	var names=["reed_bank","clay_pit","spot_grove","spot_rock_pile","spot_herb_patch","flax_patch","hardwood_grove"]
	report.comparison=[]
	for i in names.size():
		var name=names[i];var at=Vector3(6+(i-3)*2.7,0,12);var item
		if name.begins_with("spot_"):item=Old.build(name,at)
		elif name=="hardwood_grove":
			item=load("res://assets/farm/art/hardwood_grove.glb").instantiate();item.position=at
		else:item=Art.instance(name,at)
		pond.add_child(item);var stats=bounds(item);stats["name"]=name;stats["position"]=xyz(at);report.comparison.append(stats)
	vp.size=Vector2i(2800,850);pond.cam.size=20.3;pond.cam.position=Vector3(6,.8,12)+pond.cam.basis.z*24
	await capture("seven_resources_43deg")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Godot Mobile renderer")
	check(report.intercepted_requests.all(func(r):return r.type=="telemetry" or r.method==HTTPClient.METHOD_GET),"Only startup calls intercepted; no gameplay mutations or network dispatch")
	report.passed=report.checks.all(func(c):return c.passed)
	var file=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("REED_CLAY_VERIFY ",report.passed," ",report.checks.size()," checks")
	get_tree().quit(0 if report.passed else 1)
