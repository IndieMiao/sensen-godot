extends "res://static_review.gd"
const MineArt=preload("res://modules/mining/mine_art.gd")
const MineCamera=preload("res://modules/farm/farm_camera.gd")

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output);setup()
	var assets=[]
	for directory in ["assets/mine/rocks","assets/mine/props"]:
		assets.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://"+directory+"/manifest.json")).assets)
	for spec in assets:
		var model=load("res://"+spec.file).instantiate();world.add_child(model)
		report.assets[spec.name]=validate(model,spec)
		if spec.name=="elevator_station":
			for anchor in spec.anchors:
				var node=model.find_child(anchor.name,true,false)
				var expected=Vector3(anchor.position[0],anchor.position[1],anchor.position[2])
				check(node!=null and node.position.distance_to(expected)<.00001,spec.name+": "+anchor.name+" position")
				check(node.basis.is_equal_approx(Basis.IDENTITY),spec.name+": "+anchor.name+" front +Z")
			pose(20,25,2.7,Vector3(0,1.1,0));await capture("elevator_detail")
		model.queue_free();await get_tree().process_frame
	mine_lighting()
	for floor_number in [1,3]:
		var fixture=Node3D.new();world.add_child(fixture);var mine=MineArt.floor_scenery(floor_number,false);fixture.add_child(mine)
		var old=mine.get_node_or_null("MineElevator")
		if old!=null:old.free()
		fixture.add_child(MineArt.ladder(Vector3(8.25,0,-6.75),false))
		await reference_player(fixture)
		for spec in assets:
			if spec.name.begins_with("rock_"):continue
			var model=load("res://"+spec.file).instantiate();fixture.add_child(model)
			model.position=Vector3(spec.placement_world[0],spec.placement_world[1],spec.placement_world[2])
		var prefix="red" if floor_number==1 else "purple"
		vp.size=Vector2i(900,800);pose(0,43,11.4,Vector3(4.75,.35,-3.85));await capture(prefix+"_both_props_43deg")
		vp.size=Vector2i(360,800);camera.size=MineCamera.close_view_size(Vector2(360,800))/.8
		MineCamera.place(camera,Vector3(4.9,.4,-3.8));await capture(prefix+"_arena_default_43deg")
		MineCamera.place(camera,Vector3(2.2,.6,-5.6));await capture(prefix+"_elevator_default_43deg")
		var rocks=Node3D.new();fixture.add_child(rocks);var index=0
		for spec in assets:
			if not spec.name.begins_with("rock_"):continue
			var model=load("res://"+spec.file).instantiate();rocks.add_child(model)
			model.position=Vector3(2.4+index*1.55,0,-2.8);BlobShadow.attach(model,.52);index+=1
		vp.size=Vector2i(900,500);pose(0,43,7.4,Vector3(4.75,.3,-2.8));await capture(prefix+"_four_ores_43deg")
		fixture.queue_free();await get_tree().process_frame
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	check(report.renderer.method=="mobile","Actual Mobile renderer")
	report.passed=report.checks.all(func(c):return c.passed)
	var f=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t")+"\n");f.close()
	print("KIT_VALIDATION ",report.passed)
	vp.queue_free();await get_tree().process_frame;await get_tree().process_frame
	get_tree().quit(0 if report.passed else 1)
