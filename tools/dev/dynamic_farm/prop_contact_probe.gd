extends SceneTree
## Real selected farm, rendered model poses, player rig and movement signal. A
## review shot starts near the named prop (not a recorded trip from spawn).
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
var scene
var finished := false

func _initialize() -> void: _run.call_deferred()

func fail(message: String) -> void:
	finished = true
	push_error(message)
	quit(1)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=3:
		fail("Expected parcel.json output-directory role")
		return
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	debug_collisions_hint = true
	scene = load("res://scenes/dynamic_farm/dynamic_farm.tscn").instantiate()
	scene.setup({"farm":raw,"dataset":raw.dataset_version,"block_id":raw.block_id,"preview_only":true})
	scene.preview_error.connect(fail)
	scene.preview_ready.connect(func(_summary): _review.call_deferred(args[1],args[2]))
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 60000
	while not finished and Time.get_ticks_msec() < deadline:
		await create_timer(1).timeout
	if not finished: fail("Timed out waiting for the collision review")

func _input(world: Vector3) -> void:
	var right: Vector3 = scene._camera.global_basis.x
	var front: Vector3 = -scene._camera.global_basis.z
	right.y=0; front.y=0
	scene._controls.movement_changed.emit(Vector2(world.dot(right.normalized()),-world.dot(front.normalized())))

func _review(folder: String, role: String) -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	var profiles := {}
	for record: Dictionary in catalog.assets: profiles[record.id]=record.collision_proxy
	var walk: Walk = scene._walk
	var id: String = scene._data.block_id.replace("*","_star")
	for item: Dictionary in scene._plan.layout:
		if item.role!=role: continue
		var proxy := Scenery.Proxy.new(profiles[item.asset],item.transform,catalog.collision_fit_fraction)
		var center := proxy.pose.origin * Vector3(1,0,1)
		# Approach a capsule from its long side, where the model is flattest.
		var normal := proxy.pose.basis.z if proxy.shape is CapsuleShape3D else proxy.pose.basis.x
		var tangent := normal.cross(Vector3.UP)
		var contact := center+normal*(proxy.reach(normal)+Walk.BODY_RADIUS) if proxy.solid else center
		var start := contact+normal*1.5
		# Find a clear approach and exit on the genuine layout, never move a prop.
		if not walk.clear_position(start): continue
		walk.position=start
		walk.move(-normal*1.5)
		if walk.position.distance_to(contact)>0.01: continue
		walk.move(tangent*1.1)
		if walk.position.distance_to(contact+tangent*1.1)>0.02: continue
		walk.position=start; scene._actor.position=start
		scene._overview=true # Hold the review camera still while the player walks.
		scene._zoom=0.85; scene._focus=center; scene._place_camera()
		var draw := DisplayServer.get_name()!="headless"
		# Use --fixed-fps 30 (or Movie Maker at 30 fps).
		_input(-normal*0.4)
		for i in 38: await process_frame
		_input(Vector3.ZERO)
		var reached: Vector3=walk.position
		if proxy.solid and reached.distance_to(contact)>0.025:
			fail("Player did not reach the expected contact: "+str(reached.distance_to(contact))); return
		if not proxy.solid and (reached-center).dot(normal)>-0.2:
			fail("Player did not walk through the low cover"); return
		if draw:
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(folder.path_join(id+"-"+role+".png"))!=OK:
				fail("Could not write contact frame"); return
		for i in 12: await process_frame
		_input(tangent*0.4)
		for i in 22: await process_frame
		_input(Vector3.ZERO)
		if (walk.position-reached).dot(tangent)<0.9 or not walk.clear_position(walk.position):
			fail("Could not walk past the contact"); return
		print("PROP_CONTACT ",id," ",item.asset," contact_delta_m=",reached.distance_to(contact)," tangent_m=",(walk.position-reached).dot(tangent)," rendered=",draw)
		finished=true
		scene.queue_free(); await process_frame
		quit(0); return
	fail("No suitable real prop and approach on "+id+" for "+role)
