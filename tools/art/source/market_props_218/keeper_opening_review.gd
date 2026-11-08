extends Node
class LocalMarket extends "res://scenes/p0/p0_outpost.gd":
	func _go_online(_session:P0Session) -> void:pass
var scene:LocalMarket
var rt:P0Runtime
var folder:String
var report={"views":{},"rays":{},"scope":"Only keeper model swapped; layout, camera, anchors, all other objects identical"}
var keeper:Node3D
func _ready():run.call_deferred()
func v(a):return Vector3(a[0],a[1],a[2])
func xyz(a):return [a.x,a.y,a.z]
func rect(r):return [r.position.x,r.position.y,r.size.x,r.size.y]
func run():
	folder=OS.get_environment("MARKET_REVIEW");DirAccess.make_dir_recursive_absolute(folder)
	Net.use_transport(FakeTransport.new([]).callable());rt=P0Runtime.ensure();rt.session.transport=func(_m,_p,_b,_c):pass
	await get_tree().process_frame
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
	fixture.energy.value=200;fixture.coins=200;rt.session.view=fixture;rt.session.busy=false;rt.session.state_changed.emit(rt.session.view,[])
	scene=LocalMarket.new();scene.setup({"outpost_id":"sh_market_1"});add_child(scene)
	for f in 130:await get_tree().process_frame
	scene.actor.stand_still();keeper=scene.art.get_node("stall_keeper")
	# Lock both pictures to one assembled runtime, camera, idle pose and UI state.
	for ap in scene.find_children("*","AnimationPlayer",true,false):ap.seek(.30,true);ap.pause()
	report.layout_sha256=FileAccess.get_sha256("res://assets/rooms/market_plaza/layout.json")
	report.camera={"size":scene.cam.size,"position":xyz(scene.cam.global_position),"rotation_degrees":xyz(scene.cam.global_rotation_degrees)}
	report.keeper_transform={"position":xyz(keeper.position),"rotation":xyz(keeper.rotation_degrees)}
	report.mei_anchor=xyz(scene.anchor("npc_keeper").position);report.renderer=RenderingServer.get_current_rendering_method()
	for version in ["before","after"]:
		for child in keeper.get_children():
			if not child is StaticBody3D:child.free()
		keeper.add_child(load("res://assets/review_keeper/"+version+".glb").instantiate())
		for f in 12:await get_tree().process_frame
		report.rays[version]=rays()
		await capture(version)
	var all_clear=true
	for row in report.rays.after:
		if row.hits>0:all_clear=false
	report.passed=all_clear and abs(-scene.cam.global_rotation_degrees.x-33.0)<.01 and abs(scene.cam.size-6.72)<.001
	FileAccess.open(folder+"/opening-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("KEEPER_REVIEW ",report.passed);get_tree().quit(0 if report.passed else 1)
func rays():
	var rows=[]
	for height in [1.6,1.8,1.9,1.95,2.0]:
		for lateral in [-.18,0.0,.18]:
			var origin=scene.anchor("npc_keeper").global_position+Vector3.UP*(height-.05)+scene.cam.global_basis.x*lateral
			var hits=[]
			for mi in keeper.find_children("*","MeshInstance3D",true,false):
				var faces=mi.mesh.get_faces()
				for i in range(0,faces.size(),3):
					var a=mi.global_transform*faces[i];var b=mi.global_transform*faces[i+1];var c=mi.global_transform*faces[i+2]
					var hit=Geometry3D.ray_intersects_triangle(origin,scene.cam.global_basis.z,a,b,c)
					if hit!=null:hits.append(xyz(hit-scene.room.position))
			rows.append({"height_m":height,"lateral_m":lateral,"origin":xyz(origin-scene.room.position),"hits":hits.size(),"points":hits})
	return rows
func capture(label):
	await RenderingServer.frame_post_draw
	var im=get_viewport().get_texture().get_image();assert(im.get_size()==Vector2i(360,800));im.save_png(folder+"/"+label+".png")
	var mei=scene.anchor("npc_keeper").global_position+Vector3.UP*1.85
	var screen=scene.cam.unproject_position(mei)
	report.views[label]={"camera_position":xyz(scene.cam.global_position),"camera_size":scene.cam.size,"mei_head_pixel":[screen.x,screen.y],"actor_position":xyz(scene.actor.position-scene.room.position),"player_box":rect(scene.actor.screen_box(scene.cam))}
	print("KEEPER_CAPTURE ",label)
