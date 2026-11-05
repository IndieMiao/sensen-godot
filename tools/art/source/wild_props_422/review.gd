extends Node
const Art=preload("res://modules/farm/farm_art.gd")
const Old=preload("res://zz_spot_art_old.gd")
var vp: SubViewport
var pond
var runtime
var report:={"checks":[],"captures":[],"assets":{},"intercepted_requests":[]}
var fixture={"energy":{"value":200,"cap":200},"coins":180,"bag":{"slots":[],"free":22},"fishing":{"cast_energy":5},"travel":{"here":"san_francisco"}}
var out:="res://../"
func _ready() -> void: run.call_deferred()
func check(ok: bool,text: String) -> void:
	report.checks.append({"check":text,"passed":ok})
	if not ok:push_error(text)
func frames(n: int) -> void:
	for i in n:await get_tree().process_frame
func meshes(node) -> Array:
	var found=node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D:found.push_front(node)
	return found
func screen_rect(node) -> Array:
	var lo:=Vector2(INF,INF);var hi:=-lo
	for mesh in meshes(node):
		for surface in mesh.mesh.get_surface_count():
			for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p: Vector2=pond.cam.unproject_position(mesh.to_global(vertex));lo=lo.min(p);hi=hi.max(p)
	return [lo.x,lo.y,hi.x,hi.y]
func capture(name: String) -> void:
	await frames(10);RenderingServer.force_draw(true)
	var image:=vp.get_texture().get_image()
	check(image.save_png(out+name+".png")==OK,"capture "+name)
	report.captures.append({"name":name,"size":[image.get_width(),image.get_height()],"camera":str(pond.cam.global_transform),"width_m":pond.cam.size,"pitch":pond.cam.rotation_degrees.x,"player":str(pond.actor.position)})
func validate(node: MeshInstance3D, name: String) -> void:
	var tris:=0
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://wild_asset_stats.json")).assets[name]
	check(node.mesh.get_surface_count()==1,name+": one surface")
	for s in node.mesh.get_surface_count():tris+=node.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3
	check(tris<=300,name+": <=300 triangles")
	check(tris==int(expected.triangles),name+": imported triangle count matches current GLB")
	var box:=node.mesh.get_aabb()
	check(box.position.is_equal_approx(Vector3(expected.bounds[0][0],expected.bounds[0][1],expected.bounds[0][2])) and box.end.is_equal_approx(Vector3(expected.bounds[1][0],expected.bounds[1][1],expected.bounds[1][2])),name+": imported bounds match current GLB")
	check(node.scale==Vector3.ONE,name+": comparison runtime scale 1.0")
	var mat:=node.get_active_material(0) as StandardMaterial3D
	check(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb and mat.metallic==0 and is_equal_approx(mat.roughness,.9),name+": matte linear farm vertex colours")
	var imp:=ConfigFile.new();assert(imp.load("res://assets/farm/art/"+name+".glb.import")==OK)
	check(str(imp.get_value("remap","uid","")).begins_with("uid://") and imp.get_value("params","gltf/texture_map_mode")==1,name+": Godot UID / texture_map_mode 1")
	var md5_path: String=str(imp.get_value("remap","path")).trim_suffix(".scn")+".md5"
	check(FileAccess.get_file_as_string(md5_path).contains('source_md5="'+FileAccess.get_md5("res://assets/farm/art/"+name+".glb")+'"'),name+": imported cache source hash is current")
	report.assets[name]={"triangles":tris,"surfaces":node.mesh.get_surface_count(),"uid":imp.get_value("remap","uid"),"sha256":FileAccess.get_sha256("res://assets/farm/art/"+name+".glb")}
func run() -> void:
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	runtime=P0Runtime.new();P0Runtime._instance=runtime
	runtime.session.transport=func(method,path,_body,meta):report.intercepted_requests.append({"method":method,"path":path,"type":meta.get("type","")})
	vp.add_child(runtime);runtime.set_process(false);runtime.session.set_process(false)
	pond=load("res://review_pond.gd").new();pond.setup({"pond_id":"pond_san_francisco_01"});vp.add_child(pond)
	await frames(30)
	var ticks:=0
	while pond.actor.rig.is_busy() and ticks<600:await frames(1);ticks+=1
	runtime.ui.set_view(fixture);runtime.ui.set_action(pond._action_state(fixture));await frames(15);pond._update_camera()
	check(not pond.actor.rig.is_busy(),"native player assembled")
	check(pond.entry.template_id=="gourd" and pond._opening and not pond._parked,"gourd native opening camera")
	check(pond.actor.position.is_equal_approx(Vector3(6.125,0,-1.625)),"native spawn unchanged")
	check(absf(pond.cam.rotation_degrees.x+43)<.001,"native 43 degree pitch")
	var slots: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://pond_slots_v2.json")).shapes.gourd
	var active:=[]
	var resources:=[]
	for spec in [["F1","spot_grove"],["F2","flax_patch"],["L2","reed_bank"],["B1","spot_rock_pile"]]:
		var slot: Dictionary=slots[spec[0]].duplicate(true);slot["slot"]=spec[0];slot["resource"]=spec[1];active.append(slot)
		var at:=Vector3(slot.x,0,slot.z)
		var item: Node3D=Old.build(spec[1],at) if str(spec[1]).begins_with("spot_") else Art.instance(spec[1],at)
		pond.add_child(item);resources.append(item)
	await capture("opening_before")
	var scatter=load("res://scatter.gd").new(pond,active)
	report.scatter=scatter.build()
	check(report.scatter.foreground_group_placed,"left foreground log/mushroom/fern group fully inside screen above y720")
	check(report.scatter.corner_groups>=2 and report.scatter.corner_groups<=3,"2-3 corner groups")
	check(report.scatter.placements.all(func(p):return p.slot_gap_m>=1.5),"all decoration footprints clear active resource slots by >=1.5m")
	report.scatter.counts={}
	for row in report.scatter.placements:report.scatter.counts[row.asset]=report.scatter.counts.get(row.asset,0)+1
	check(report.scatter.counts.get("wild_cattail_water",0)>=4 and report.scatter.counts.get("wild_cattail_water",0)<=7,"4-7 sparse water-only cattail clumps")
	FileAccess.open(out+"placements.json",FileAccess.WRITE).store_string(JSON.stringify(report.scatter,"\t")+"\n")
	await capture("gourd_default_43")
	# Optional audit view: same exact placements, wider camera only, to expose far-corner groups.
	var old_transform: Transform3D=pond.cam.global_transform;var old_size: float=pond.cam.size
	runtime.ui.root.visible=false;vp.size=Vector2i(1200,1200);pond.cam.size=20;pond.cam.position=Vector3(6,0,-8)+pond.cam.basis.z*40
	await capture("whole_pond_density")
	# All 12 new pieces and 4 existing resources, unit scale in one unchanged pond light setup.
	scatter.root.visible=false;pond.actor.visible=false
	for item in resources:item.visible=false
	vp.size=Vector2i(1500,1260);pond.cam.size=12.2;pond.cam.position=Vector3(6,.5,10.5)+pond.cam.basis.z*40
	report.gallery=[]
	for i in 4:
		var id: String=["spot_grove","spot_rock_pile","flax_patch","reed_bank"][i]
		var at:=Vector3(2.4+i*2.4,0,7.2)
		var item: Node3D=Old.build(id,at) if id.begins_with("spot_") else Art.instance(id,at)
		pond.add_child(item);report.gallery.append({"asset":id,"resource":true,"screen_rect":screen_rect(item),"label_at":pond.cam.unproject_position(at+Vector3(0,0,.7))})
	var names: Array=JSON.parse_string(FileAccess.get_file_as_string("res://wild_asset_stats.json")).assets.keys()
	for i in names.size():
		var at:=Vector3(1.5+(i%6)*1.8,0,10.7+(i/6)*2.5)
		var item:=Art.instance(names[i],at);pond.add_child(item)
		if names[i]=="wild_log_moss":item.rotation.y=.45
		validate(item,names[i])
		report.gallery.append({"asset":names[i],"resource":false,"screen_rect":screen_rect(item),"label_at":pond.cam.unproject_position(at+Vector3(0,0,.62))})
	await capture("all_props_resources")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(out+"render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WILD_RENDER ",report.passed," ",report.checks.size()," checks; ",report.scatter.counts)
	get_tree().quit(0 if report.passed else 1)
