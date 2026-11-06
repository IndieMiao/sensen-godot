extends Node
const AlcatrazIsland = preload("res://scenes/landmark/alcatraz_island.gd")
const KIT="res://assets/landmarks/alcatraz_island/"
const NAMES=["alc_lighthouse_far","alc_watertower_far","alc_lighthouse","alc_watertower"]
var vp:SubViewport
var scene:AlcatrazIsland
var output:String
var before={}
var after={}
var report={"checks":[],"captures":{},"tower_rects":{}}
func _ready():run.call_deferred()
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label,evidence=null):
	report.checks.append({"check":label,"passed":bool(ok),"evidence":evidence})
	if not ok:push_error(label)
func asset_key(n):
	for name in NAMES:
		if n.name.begins_with(name.to_pascal_case()):return name
	return ""
func mesh_at(path):
	var source=load(path).instantiate();var m=source.find_children("*","MeshInstance3D",true,false)[0].mesh;source.free();return m
func tri(mesh):
	var t=0
	for s in mesh.get_surface_count():t+=mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3
	return t
func swap(old:bool):
	for n in scene.mesh_nodes:
		var key=asset_key(n)
		if key!="":n.mesh=before[key] if old else after[key]
func capture(name):
	for i in 8:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures[name]={"size":[vp.size.x,vp.size.y],"camera":xyz(scene._camera.position),"width":scene._camera.size,"visible_triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	print("TOWER_CAPTURE ",name)
func fit_summit():
	var cam=scene._camera;cam.rotation_degrees=Vector3(-43,14.5,0)
	var lo=Vector2(INF,INF);var hi=-lo
	for n in scene.mesh_nodes:
		if asset_key(n)=="" and not n.name.begins_with("AlcMuseum"):continue
		var b=n.global_transform*n.get_aabb()
		for i in 8:
			var v=b.get_endpoint(i);var p=Vector2(v.dot(cam.basis.x),v.dot(cam.basis.y));lo=lo.min(p);hi=hi.max(p)
	var mid=(lo+hi)*.5;var focus=Vector3(0,16,-12)
	focus+=cam.basis.x*(mid.x-focus.dot(cam.basis.x))+cam.basis.y*(mid.y-focus.dot(cam.basis.y))
	cam.size=maxf((hi.x-lo.x)*1.12,(hi.y-lo.y)*float(vp.size.x)/vp.size.y*1.14);cam.position=focus+cam.basis.z*100;cam.near=.1;cam.far=250
	for n in scene.mesh_nodes:
		if asset_key(n)=="":continue
		var b=n.global_transform*n.get_aabb();var low=Vector2(INF,INF);var high=-low
		for i in 8:
			var p=cam.unproject_position(b.get_endpoint(i));low=low.min(p);high=high.max(p)
		check(Rect2(0,0,vp.size.x,vp.size.y).encloses(Rect2(low,high-low)),n.name+" whole tower inside review wide view")
		report.tower_rects[str(n.name)]=[low.x,low.y,high.x,high.y]
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	vp=SubViewport.new();vp.size=Vector2i(720,460);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	scene=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(scene)
	for i in 300:
		await get_tree().physics_frame
		if scene.navigation_ready() and not scene._rig.is_busy():break
	check(scene.navigation_ready(),"bf0c31b1 scene navigation initialized")
	for name in NAMES:
		before[name]=mesh_at("res://before/"+name+".glb");after[name]=mesh_at(KIT+name+".glb")
		check(tri(before[name])==tri(after[name]),name+" triangle count unchanged")
		check(before[name].get_aabb().is_equal_approx(after[name].get_aabb()),name+" bounds unchanged")
	scene.set_process(false);scene._rig.get_node("AnimationPlayer").pause();scene._hud.visible=false
	# Expand the existing island review view once so all summit batches are
	# populated. No runtime layout or default/max camera parameters are edited.
	scene._overview=true;scene._focus=Vector3(0,16,-12);scene.camera_pan.reset(1.0);scene._update_camera();fit_summit()
	# Native Shader TIME follows Engine.time_scale; freeze the paired water control.
	Engine.time_scale=0
	swap(true);await capture("summit_before")
	swap(false);await capture("summit_after")
	report.wide_view_note="Supplementary landscape review fit for both towers and museum; original player zoom limits unchanged. All three cannot fit the native20.16m portrait width at original positions."
	# Supplementary native widest portrait after colour, with the same host controls.
	Engine.time_scale=1;vp.size=Vector2i(360,800);scene._overview=false;scene._hud.visible=true;scene._player.position=Vector3(0,10,-6);scene._focus=scene._follow_target();scene.camera_pan.reset(1.0/3.0);scene._update_camera()
	check(abs(scene._camera.size-20.16)<.01,"Native maximum width still20.16m")
	await capture("native_summit_after")
	# Separate LOD comparisons use the exact island light and shared matte material.
	for zone in scene.zones.values():zone.visible=false
	scene.get_node("Sea").visible=false;scene._set_backdrop_visible(false);scene._player.visible=false;scene._hud.visible=false
	scene._environment.environment.background_color=Color("DCE7E5")
	var paint=StandardMaterial3D.new();paint.vertex_color_use_as_albedo=true;paint.roughness=.94;paint.metallic_specular=.15
	var studio=Node3D.new();vp.add_child(studio)
	for name in ["alc_lighthouse","alc_watertower"]:
		var near=MeshInstance3D.new();near.mesh=after[name];near.material_override=paint;near.visibility_range_end=55;near.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;studio.add_child(near)
		var far=MeshInstance3D.new();far.mesh=after[name+"_far"];far.material_override=paint;far.visibility_range_begin=55;far.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;studio.add_child(far)
		var cam=scene._camera;cam.size=8.5;cam.rotation_degrees=Vector3(-20,25,0);cam.near=.1;cam.far=160
		var center=(near.get_aabb().get_center()+far.get_aabb().get_center())*.5
		for distance in [54,56]:
			cam.position=center+cam.basis.z*distance;await capture(name+"_"+str(distance)+"m")
			var expected=tri(near.mesh) if distance==54 else tri(far.mesh)
			check(report.captures[name+"_"+str(distance)+"m"].visible_triangles==expected,name+" engine LOD selects at "+str(distance),[report.captures[name+"_"+str(distance)+"m"].visible_triangles,expected])
		near.free();far.free()
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()};report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n");print("TOWER_COLOUR_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
