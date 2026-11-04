extends Node
const Art=preload("res://modules/farm/farm_art.gd")
const Old=preload("res://zz_spot_art_old.gd")
var vp:SubViewport
var pond
var runtime
var output:String
var report={"checks":[],"captures":[],"intercepted_requests":[]}
func _ready(): run.call_deferred()
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok: push_error(label)
func xyz(p):return [p.x,p.y,p.z]
func meshes(root):
	var found=root.find_children("*","MeshInstance3D",true,false)
	if root is MeshInstance3D: found.push_front(root)
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
	var rect=control.get_global_rect();var center=rect.get_center();var radius=rect.size.x*.5
	var distance=INF
	for node in meshes(root):
		for surface in node.mesh.get_surface_count():
			var a=node.mesh.surface_get_arrays(surface);var indices=a[Mesh.ARRAY_INDEX];var vertices=a[Mesh.ARRAY_VERTEX]
			for i in range(0,indices.size(),3):
				var triangle=PackedVector2Array()
				for k in 3:triangle.append(pond.cam.unproject_position(node.to_global(vertices[indices[i+k]])))
				if Geometry2D.is_point_in_polygon(center,triangle):distance=0
				for k in 3:distance=minf(distance,center.distance_to(Geometry2D.get_closest_point_to_segment(center,triangle[k],triangle[(k+1)%3])))
	return {"circle_center":[center.x,center.y],"radius_px":radius,"mesh_gap_px":distance-radius}
func capture(name):
	for i in 12: await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Saved "+name)
	report.captures.append({"name":name,"pixels":[vp.size.x,vp.size.y],"camera":str(pond.cam.global_transform),
		"pitch_degrees":pond.cam.rotation_degrees.x,"width_m":pond.cam.size})
	print("FLAX_CAPTURE ",name)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	runtime=P0Runtime.new();P0Runtime._instance=runtime
	runtime.session.transport=func(method,path,_body,meta):report.intercepted_requests.append({"method":method,"path":path,"type":meta.get("type","")})
	vp.add_child(runtime);runtime.set_process(false);runtime.session.set_process(false)
	var requested=OS.get_environment("P0_SCENE")
	check(requested=="pond:pond_san_francisco_01","Requested actual SF pond 01")
	pond=load("res://review_pond.gd").new();pond.setup({"pond_id":requested.trim_prefix("pond:")});vp.add_child(pond)
	for i in 30:await get_tree().process_frame
	var ticks=0
	while pond.actor.rig.is_busy() and ticks<600:await get_tree().process_frame;ticks+=1
	check(not pond.actor.rig.is_busy(),"Native player assembled")
	var fixture={"energy":{"value":200,"cap":200},"coins":250,"bag":{"slots":[],"free":20},
		"fishing":{"cast_energy":5},"travel":{"here":"san_francisco"}}
	runtime.ui.set_view(fixture);runtime.ui.set_action(pond._action_state(fixture))
	for i in 30:await get_tree().process_frame
	pond._update_camera()
	check(pond._opening and not pond._parked,"Native opening camera; no pan, park, zoom or teleport")
	check(pond.actor.position.is_equal_approx(Vector3(6.125,0,-1.625)),"Original entry spawn (6.125, 0, -1.625)")
	check(absf(pond.cam.rotation_degrees.x+43)<.001,"Native camera pitch 43 degrees")
	var flax=pond.get_node("Scenery/FlaxF2")
	check(flax.position.is_equal_approx(Vector3(7.9,0,-1.1)) and flax.scale==Vector3.ONE,"F2 coordinates and unit scale")
	report.model=bounds(flax);report.slot={"name":"F2","position":xyz(flax.position),"player":xyz(pond.actor.position),"screen_rect":screen_rect(flax)}
	check(report.model.triangles<=900 and report.model.surfaces==1,"Actual imported flax <=900 triangles / one surface")
	check(report.model.size[0]>=1.2 and report.model.size[0]<=1.4 and report.model.size[2]>=1.2 and report.model.size[2]<=1.4,"Footprint in 1.2–1.4 m range")
	check(report.model.size[1]>=.6 and report.model.size[1]<=.7,"Height in 0.6–0.7 m range")
	check(absf(report.model.bounds[0][1])<.0001,"Bottom origin Y=0")
	var sr=report.slot.screen_rect
	check(sr[0]>=16 and sr[0]+sr[2]<=344 and sr[1]>=0 and sr[1]+sr[3]<800,"Entire F2 model in screen, >=16px side margin")
	report.slot["switch_key"]=circle_gap(flax,runtime.ui._keys.switch_button())
	report.slot["main_key"]=circle_gap(flax,runtime.ui._keys.key())
	check(report.slot.switch_key.mesh_gap_px>0 and report.slot.main_key.mesh_gap_px>0,"Projected triangles clear actual circular switch and main-key shapes")
	var mat=flax.get_active_material(0)
	check(mat==Art.material() and mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb,"Exact FarmArt shared linear vertex-colour material")
	check(is_equal_approx(mat.roughness,.9) and mat.albedo_texture==null,"Matte .9, no texture")
	var config=ConfigFile.new();config.load("res://assets/farm/art/flax_patch.glb.import")
	check(config.get_value("params","meshes/light_baking")==1,"light_baking=1")
	check(str(config.get_value("remap","uid","")).begins_with("uid://"),"Godot import UID present")
	await capture("F2_default_43deg")
	runtime.ui.root.visible=false
	await capture("F2_default_art_only")
	# Comparison: original farm resource factories, equal unit scale, same pond sun and ambient.
	var items=[]
	var specs=[["spot_grove",-3.75],["spot_reed_bank",-1.25],["spot_herb_patch",1.25],["flax_patch",3.75]]
	report.comparison=[]
	for spec in specs:
		var at=Vector3(6+spec[1],0,12)
		var item=Art.instance("flax_patch",at) if spec[0]=="flax_patch" else Old.build(spec[0],at)
		pond.add_child(item);items.append(item)
		var stats=bounds(item);stats["name"]=spec[0];stats["position"]=xyz(at);report.comparison.append(stats)
	vp.size=Vector2i(1600,700);pond.cam.size=11.5
	pond.cam.position=Vector3(6,.7,12)+pond.cam.basis.z*20
	await capture("resources_comparison_43deg")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Godot Mobile renderer")
	check(report.intercepted_requests.all(func(r):return r.type=="telemetry" or r.method==HTTPClient.METHOD_GET),"Transport stub intercepted startup only; no network dispatch or gameplay actions")
	var file=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	var failed=report.checks.filter(func(c):return not c.passed)
	print("FLAX_VERIFY ",report.checks.size()," checks; failed=",failed.size())
	get_tree().quit(0 if failed.is_empty() else 1)
