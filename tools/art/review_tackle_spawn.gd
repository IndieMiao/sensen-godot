extends "review_tackle_shop.gd"
## User-requested entry view: feet on the authored spawn; camera follows it.
## A local art fixture, not the gameplay room's opening-subject/clamp integration.

func actor(at, yaw, slots):
	var rig = Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity: child.free()
	rig.assembler = AvatarAssemblerMerged.new(); world.add_child(rig)
	rig.position = at; rig.rotation.y = deg_to_rad(yaw)
	var config = Avatar.slot_table.default_config()
	for slot in slots: config.slots[StringName(slot)] = slots[slot]
	rig.apply_config(config)
	var frames = 0
	while rig.is_busy() and frames < 900: await get_tree().process_frame; frames += 1
	check(not rig.is_busy(), "Entry-view actor assembled")
	for slot in slots: check(rig.current_config().slots[StringName(slot)] == slots[slot], "Existing Finn part: " + slots[slot])
	rig.play_motion("idle"); var animation = rig.get_node("AnimationPlayer"); animation.seek(.3,true); animation.pause()
	return rig

func screen_bounds(node):
	var bounds = Rect2(); var first = true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible or mesh.mesh == null: continue
		for i in 8:
			var point = camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_endpoint(i))
			bounds = Rect2(point,Vector2.ZERO) if first else bounds.expand(point); first = false
	return {"min": [bounds.position.x,bounds.position.y], "max": [bounds.end.x,bounds.end.y]}

func run():
	output = ProjectSettings.globalize_path("res://../spawn-captures"); DirAccess.make_dir_recursive_absolute(output)
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	var fixture_data = JSON.parse_string(FileAccess.get_file_as_string("res://spawn-review-fixture.json"))
	setup(); vp.size = Vector2i(360,800)
	var spawn = room.get_node("spawn").position
	var keeper = room.get_node("npc_keeper").position
	var player = await actor(spawn,180,{})
	var finn = await actor(keeper,0,fixture_data.finn.slots)
	var offset = vec(layout.camera.position) - vec(layout.camera.target)
	var yaw = rad_to_deg(atan2(offset.x,offset.z))
	pose(player.position,6.72,43,yaw)
	check(camera.unproject_position(spawn).distance_to(Vector2(180,400)) < .01, "Camera follows player feet at spawn, centered at 180/400")
	var layer = CanvasLayer.new(); vp.add_child(layer)
	var name_tag = Label.new(); name_tag.text = "Finn"; name_tag.add_theme_font_size_override("font_size",12)
	name_tag.add_theme_color_override("font_color",Color("514336"))
	name_tag.add_theme_color_override("font_outline_color",Color("fff6e9")); name_tag.add_theme_constant_override("outline_size",3)
	name_tag.position = camera.unproject_position(keeper + Vector3.UP * 1.9) + Vector2(-12,-10); layer.add_child(name_tag)
	await capture("game-spawn-follow-360")
	report.spawn = xyz(spawn); report.focus = xyz(player.position); report.keeper = xyz(keeper)
	report.finn = fixture_data.finn; report.finn_source_revision = fixture_data.source_revision
	report.finn_resource_sha256 = fixture_data.copied_resource_sha256
	report.player_screen = xyz(Vector3(camera.unproject_position(spawn).x,camera.unproject_position(spawn).y,0))
	report.finn_screen_bounds = screen_bounds(finn); report.counter_screen_bounds = screen_bounds(room.get_node("curved_counter"))
	report.player_screen_bounds = screen_bounds(player)
	report.renderer = RenderingServer.get_current_rendering_method(); report.adapter = RenderingServer.get_video_adapter_name()
	report.failures = report.checks.filter(func(c):return not c.passed)
	FileAccess.open(output + "/spawn-follow-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("SPAWN_FOLLOW_QA ",report.checks.size()," checks / ",report.failures.size()," failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)
