extends SceneTree
var elapsed = 0.0
func _initialize(): run.call_deferred()
func _process(delta):
	elapsed += delta
	return elapsed > 180.0
func run():
	if DisplayServer.get_name() == "headless": quit(2); return
	var kp_script = load("res://modules/p0/p0_keeper_portraits.gd")
	var appearance = load("res://modules/net/online_appearance.gd")
	var kp = kp_script.new(); root.add_child(kp)
	kp._stage(Vector2i(720,960)); kp._backdrop(true)
	var avatar = root.get_node("Avatar")
	var lou = OS.get_cmdline_user_args().has("--lou")
	var rig = avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity: rig.remove_child(child); child.free()
	kp._viewport.add_child(rig)
	var looks = JSON.parse_string(FileAccess.get_file_as_string("res://output/npc-batch3/looks-phase3.json" if lou else "res://output/npc-batch3/looks-phase2.json"))
	rig.apply_config(appearance.config({"version":1,"slots":looks.lou_new.slots if lou else looks.nadia_new.slots},true))
	var frames = 0
	while rig.is_busy() and frames < 900: await process_frame; frames += 1
	if rig.is_busy(): quit(1); return
	var output = "res://output/npc-batch3/nadia-motion"
	if lou: output = "res://output/npc-batch3/lou-motion"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var report = {"renderer":RenderingServer.get_current_rendering_method(),"captures":[]}
	for entry in [["idle",.3,.32],["walk",.0,.32],["walk",.2,.32],["walk",.4,.32],["walk",.6,.32],["idle",.3,1.57],["idle",.3,3.46]]:
		rig.rotation.y = entry[2]
		rig.play_motion(entry[0])
		var animation = rig.get_node("AnimationPlayer")
		animation.seek(entry[1],true); animation.pause()
		kp._aim(Vector3(0,1.02,0),2.35,.05)
		for i in 3: await process_frame
		var image: Image = await kp._render()
		var name_ = "%s_%03d_%03d.png" % [entry[0],int(entry[1]*100),int(entry[2]*100)]
		assert(image.save_png(output+"/"+name_)==OK)
		report.captures.append({"name":name_,"motion":entry[0],"time":entry[1],"yaw":entry[2]})
	rig.rotation.y = .32; rig.play_motion("idle")
	rig.get_node("AnimationPlayer").seek(.3,true); rig.get_node("AnimationPlayer").pause()
	kp._aim(Vector3(0,1.12,0),3.15,.05)
	var canvas = CanvasLayer.new(); kp._viewport.add_child(canvas)
	var logical = Node2D.new(); logical.scale = Vector2(2,2); canvas.add_child(logical)
	var tag = UiNpcNameTag.new("Lou" if lou else "Nadia"); logical.add_child(tag)
	tag.status = UiStatusBadge.State.REQUEST
	var name_anchor = load("res://scenes/p0/p0_outpost.gd").NAME_OVER_HEAD
	tag.place_over(kp._camera.unproject_position(rig.to_global(name_anchor))/2)
	for i in 5: await process_frame
	var badge_image: Image = await kp._render()
	assert(badge_image.save_png(output+"/native_badge_72px.png")==OK)
	report.badge = {"native_logical_px":UiTokens.SIZE_STATUS_BADGE_NPC,"canvas_scale":2,"physical_px":tag._badge.size.x*2,
		"name_anchor_m":[name_anchor.x,name_anchor.y,name_anchor.z],"image":"native_badge_72px.png"}
	assert(is_equal_approx(tag._badge.size.x*2,72))
	FileAccess.open(output+"/motion-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("NADIA_MOTION_QA ",report.captures.size()," poses; native badge ",tag._badge.size.x*2," px")
	kp._viewport.remove_child(rig); rig.free()
	quit()
