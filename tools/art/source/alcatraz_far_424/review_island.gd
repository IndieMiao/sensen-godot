extends Node
const AlcatrazIsland = preload("res://scenes/landmark/alcatraz_island.gd")
var scene:AlcatrazIsland
var viewport:SubViewport
var output:String
var report={"checks":[],"views":{}}
func _ready():run.call_deferred()
func check(ok,label,evidence=null):
	report.checks.append({"check":label,"passed":bool(ok),"evidence":evidence})
	if not ok:push_error(label)
func xyz(p):return [p.x,p.y,p.z]
func nodes_for(asset):
	return scene.mesh_nodes.filter(func(n):return n.name.begins_with(asset.to_pascal_case()))
func tri_count(mesh):
	var tri=0
	for s in mesh.get_surface_count():
		var a=mesh.surface_get_arrays(s);tri+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3
	return tri
func stats():
	return {"triangles":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"visible_draws":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_draws":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
func shot(name):
	var peak={"triangles":0,"visible_draws":0,"shadow_draws":0}
	for i in 12:
		await get_tree().process_frame;await RenderingServer.frame_post_draw
		var sample=stats()
		for key in peak:peak[key]=maxi(peak[key],sample[key])
	peak["total_draws"]=peak.visible_draws+peak.shadow_draws
	check(peak.triangles<=80000,name+" visible triangle budget",peak.triangles)
	check(peak.total_draws<=60,name+" visible+shadow draw budget",peak.total_draws)
	check(viewport.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	peak["camera_position"]=xyz(scene._camera.position);peak["camera_size"]=scene._camera.size
	peak["player_position"]=xyz(scene._player.position);report.views[name]=peak
	print("ISLAND_CAPTURE ",name," ",JSON.stringify(peak))
func run():
	output=ProjectSettings.globalize_path("res://../island-captures");DirAccess.make_dir_recursive_absolute(output)
	viewport=SubViewport.new();viewport.size=Vector2i(360,800);viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	scene=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();viewport.add_child(scene)
	for i in 240:
		await get_tree().physics_frame
		if scene.navigation_ready() and not scene._rig.is_busy():break
	check(scene.navigation_ready(),"Pinned blockout navigation ready")
	check(scene._player.position.distance_to(Vector3(-22,1,19))<.001,"Native dock spawn",xyz(scene._player.position))
	check(abs(scene._camera.rotation_degrees.x+43)<.01 and abs(scene._camera.rotation_degrees.y-14.5)<.01,"Native default camera 43 / 14.5",xyz(scene._camera.rotation_degrees))
	check(abs(scene._camera.size-6.72)<.001,"Native default width 6.72")
	scene.set_process(false)
	scene._rig.get_node("AnimationPlayer").pause()
	for name in ["alc_far_city","alc_far_bridge","alc_far_hills"]:
		var n=nodes_for(name);check(n.size()==1,name+" single card, no duplicate far LOD",n.size())
		check(n[0].visibility_range_begin==0 and n[0].visibility_range_end==0,name+" not culled by distance")
	for pair in [["alc_lighthouse",Vector3(-25,10,-11.5)],["alc_watertower",Vector3(25,10,-14)]]:
		var n=nodes_for(pair[0]);check(n.size()==2,pair[0]+" near/far pair")
		for item in n:check(item.position.distance_to(pair[1])<.001,pair[0]+" layout placement",xyz(item.position))
		check(n[0].visibility_range_end==55 and n[1].visibility_range_begin==55,pair[0]+" 55 m switch")
	var resident_triangles=0;var resident_surfaces=0
	for n in scene.find_children("*","MeshInstance3D",true,false):
		if n.mesh:resident_triangles+=tri_count(n.mesh);resident_surfaces+=n.mesh.get_surface_count()
	for n in scene.batch_nodes:
		resident_triangles+=tri_count(n.multimesh.mesh)*n.multimesh.instance_count;resident_surfaces+=n.multimesh.mesh.get_surface_count()
	check(resident_triangles<=300000 and resident_surfaces<=80,"Combined blockout resident budgets including both LODs",[resident_triangles,resident_surfaces])
	report.resident={"triangles":resident_triangles,"surfaces":resident_surfaces}
	await shot("SGODOT-424_far_v1.1_opening_360")
	# Actual host shader projects local XY into a false depth, so compare rendered
	# bridge-on and bridge-off images rather than unprojecting its world AABB.
	var on=viewport.get_texture().get_image();var bridge=nodes_for("alc_far_bridge")[0]
	bridge.visible=false
	for i in 6:await RenderingServer.frame_post_draw
	var off=viewport.get_texture().get_image();bridge.visible=true
	off.save_png(output+"/bridge_off_control.png")
	var count=0;var orange=0;var low=Vector2i(360,800);var high=Vector2i.ZERO
	for y in 800:
		for x in 360:
			var a=on.get_pixel(x,y);var b=off.get_pixel(x,y)
			if maxf(abs(a.r-b.r),maxf(abs(a.g-b.g),abs(a.b-b.b)))>.01:
				count+=1;low=low.min(Vector2i(x,y));high=high.max(Vector2i(x,y))
				if y>=55 and y<=180 and a.r>a.g*1.15 and a.g>a.b*1.1:orange+=1
	check(count>100 and orange>40,"Orange bridge visible near upper edge below HUD allowance",{"changed_pixels":count,"orange_pixels_y55_180":orange,"min":[low.x,low.y],"max":[high.x,high.y]})
	report.bridge_pixels={"count":count,"orange_below_hud":orange,"min":[low.x,low.y],"max":[high.x,high.y]}
	# Supplementary combined views at native review points and widest allowed view.
	scene.set_process(false)
	for pair in [["mid_hill",Vector3(8,5.5,3)],["summit",Vector3(0,10,-6)]]:
		scene._player.position=pair[1];scene._focus=scene._follow_target();scene._update_camera()
		await shot("SGODOT-424_far_v1.1_"+pair[0])
	scene.camera_pan.reset(1.0/3.0);scene._update_camera();check(abs(scene._camera.size-20.16)<.01,"Native maximum width 20.16")
	await shot("SGODOT-424_far_v1.1_summit_wide")
	report.passed=report.checks.all(func(c):return c.passed);report.renderer=RenderingServer.get_current_rendering_method()
	FileAccess.open(output+"/validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("ISLAND_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)
