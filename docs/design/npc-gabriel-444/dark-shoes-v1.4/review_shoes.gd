extends SceneTree
## Run windowed in the isolated Gabriel runtime fixture, with current part imports.
const BASE_SLOTS = {"hairHat":"hairhat0_npc_gabriel","cloth":"cloth36_npc_gabriel","glass":"glass0"}
var elapsed = 0.0

func _initialize():
	run.call_deferred()

func _process(delta):
	elapsed += delta
	return elapsed > 180

func run():
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	var KP = load("res://modules/p0/p0_keeper_portraits.gd")
	var OA = load("res://modules/net/online_appearance.gd")
	var avatar = root.get_node("Avatar")
	var kp = KP.new()
	root.add_child(kp)
	var out = "res://output/gabriel-dark-shoes-444"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var report = {"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"scale":1.0,"captures":[]}
	for shoes in ["shoes3", "shoes3_npc_gabriel"]:
		var slots = BASE_SLOTS.duplicate()
		slots.shoes = shoes
		for close in [false, true]:
			kp._stage(Vector2i(360,320) if close else Vector2i(360,800))
			kp._backdrop(true)
			var rig = avatar.create_rig()
			for c in rig.get_children():
				if c is RigActivity:
					rig.remove_child(c)
					c.free()
			kp._viewport.add_child(rig)
			rig.apply_config(OA.config({"version":1,"slots":slots},true))
			var waited = 0
			while rig.is_busy() and waited < 900:
				await process_frame
				waited += 1
			assert(not rig.is_busy())
			rig.play_motion("idle")
			var ap = rig.get_node("AnimationPlayer")
			ap.seek(0,true)
			ap.pause()
			rig.rotation.y = PI / 4 if close else 0.0
			kp._aim(Vector3(0,0.18,0),0.58,0.12) if close else kp._aim(Vector3(0,0.88,0),2.02,0.05)
			for frame in 3:
				await process_frame
			var image: Image = await kp._render()
			var filename = shoes + ("-feet.png" if close else "-full.png")
			assert(image.save_png(out + "/" + filename) == OK)
			report.captures.append({"file":filename,"slots":slots,"size":[image.get_width(),image.get_height()],"camera_size":0.58 if close else 2.02,"yaw_deg":45 if close else 0})
			kp._viewport.remove_child(rig)
			rig.free()
	var thumbnailer = PartThumbnailer.new()
	thumbnailer.catalog = avatar.catalog
	root.add_child(thumbnailer)
	var thumb = await thumbnailer.thumbnail("shoes3_npc_gabriel")
	assert(thumb != null)
	assert(thumb.get_image().save_png("res://assets/avatar/thumbs/shoes3_npc_gabriel.png") == OK)
	thumbnailer.free()
	FileAccess.open(out + "/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t") + "\n")
	print("GABRIEL_SHOES_REVIEW ",JSON.stringify(report))
	kp.free()
	quit()
