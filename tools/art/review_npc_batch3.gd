extends SceneTree
## Part closeups on the game's resident portrait stage; fixed camera per pair.
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
	var avatar = root.get_node("Avatar")
	var hat_revision = OS.get_cmdline_user_args().has("--nadia-hat-v11")
	var nadia = OS.get_cmdline_user_args().has("--nadia") or hat_revision
	var lou = OS.get_cmdline_user_args().has("--lou")
	var looks_path = "res://output/npc-batch3/looks-phase3.json" if lou else ("res://output/npc-batch3/looks-phase2.json" if nadia else "res://output/npc-batch3/looks-phase1.json")
	var looks = JSON.parse_string(FileAccess.get_file_as_string(looks_path))
	var output = "res://output/npc-batch3/nadia-closeups" if nadia else "res://output/npc-batch3/closeups"
	if lou: output = "res://output/npc-batch3/lou-closeups"
	if hat_revision: output = "res://output/npc-batch3/nadia-v11-closeups"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var report = {"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "captures": []}
	var pairs = [["lena_a", "lena_new", "lena_hat"], ["rafa_r1", "rafa_hat_only", "rafa_hat"], ["rafa_hat_only", "rafa_new", "rafa_cloth"]]
	if nadia: pairs = [["nadia_now", "nadia_hat_only", "nadia_hat"], ["nadia_hat_only", "nadia_new", "nadia_apron"]]
	if hat_revision: pairs = [["nadia_now", "nadia_hat_only", "nadia_hat"]]
	if lou: pairs = [["lou_now", "lou_new", "lou_cloth"]]
	for pair in pairs:
		for index in 2:
			var id = pair[index]
			kp._stage(Vector2i(640, 640)); kp._backdrop(true)
			var rig = avatar.create_rig()
			for child in rig.get_children():
				if child is RigActivity: rig.remove_child(child); child.free()
			kp._viewport.add_child(rig)
			rig.apply_config(appearance.config({"version": 1, "slots": looks[id].slots}, true))
			var frames = 0
			while rig.is_busy() and frames < 900: await process_frame; frames += 1
			if rig.is_busy(): push_error("Assembly timed out"); quit(1); return
			rig.play_motion("idle")
			var animation = rig.get_node("AnimationPlayer"); animation.seek(.3, true); animation.pause()
			for side in ["front", "back"]:
				rig.rotation.y = kp_script.TURN + (PI if side == "back" else 0)
				var cloth = pair[2] in ["rafa_cloth", "nadia_apron", "lou_cloth"]
				kp._aim(Vector3(0, 1.0 if cloth else 1.46, 0), 1.0 if cloth else .91, .05)
				for i in 3: await process_frame
				var image: Image = await kp._render()
				var name_ = "%s_%s_%s.png" % [pair[2], "before" if index == 0 else "after", side]
				if image.save_png(output + "/" + name_) != OK: quit(1); return
				report.captures.append({"name": name_, "look": id, "resolution": [640, 640], "camera_size": kp._camera.size})
				print("BATCH3_CLOSEUP ", name_)
			kp._viewport.remove_child(rig); rig.free()
	FileAccess.open(output + "/render-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	quit()
