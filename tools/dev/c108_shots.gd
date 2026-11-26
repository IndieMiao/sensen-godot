extends SceneTree
## C-108 review captures: the dynamic farm's profile (from parcel_profile.gd, with a home) and the dressing room's
## states (A main, B trying a part on, C leaving with changes, D the failure toasts). Runs on any revision that has
## parcel_profile.gd (C-128 and later), so the same script shoots the before and the after:
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/dev/c108_shots.gd -- <out_dir>
## The outfit is saved under a scratch user directory, never the player's.

var out := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://c108_shots"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("SHOT ", name)

func _frames(n: int) -> void:
	for i in n: await process_frame

func _idle(rig: Node) -> void:
	for i in 900:
		if not rig.is_busy(): return
		await process_frame

func _run() -> void:
	var avatar: Node = root.get_node("Avatar")
	avatar.store.base_dir = "user://c108_shots_store"
	avatar.user_id = "c108"
	TranslationServer.set_locale("en")
	# The profile over a plain backdrop (the map is native and does not draw here).
	var backdrop := ColorRect.new()
	backdrop.color = Color("9FB98A")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var Host: GDScript = load("res://scenes/dynamic_farm/parcel_profile.gd")
	var home := {"name": "1340 Valencia St", "status": "Carrots ready in 3h 32m", "ready": false, "pressed": func(): pass}
	var host: Control = Host.open(backdrop, Vector3.ZERO, home) if Host.get_script_method_list().any(func(m): return m.name == "open" and m.args.size() >= 3) else Host.open(backdrop)
	await _frames(90)
	await _shot("profile_A")
	if host.top().has_method("show_look_saved"):
		host.top().show_look_saved()
		await _frames(20)
		await _shot("profile_D_look_saved")
	host.close()
	await _frames(2)
	backdrop.queue_free()
	# The dressing room.
	var room: Node = load("res://scenes/dressing_room/dressing_room.tscn").instantiate()
	root.add_child(room)
	await _idle(room.rig)
	await _frames(120)
	await _shot("dressing_A")
	var panel = room.parts_panel
	var current: String = room.rig.desired_part(&"hairHat")
	var other := ""
	for meta in avatar.catalog.parts_for_slot(&"hairHat"):
		if meta.id != current: other = meta.id
	panel._select_part(&"hairHat", other)
	await _frames(1)
	await _shot("dressing_B_trying")
	await _idle(room.rig)
	await _frames(30)
	if room.has_method("has_changes"):
		room._on_back()
		await _frames(30)
		await _shot("dressing_C_leave")
		room.is_back_navigation_locked()
		await _frames(20)
		room._show_feedback("Couldn't save. Try again.", 1)
		await _frames(4)
		room._show_feedback("Couldn't load Straw Bucket. Previous look kept.", 2)
		await _frames(30)
		await _shot("dressing_D_failed")
	else:
		room._show_feedback("Couldn't save. Try again.")
		await _frames(20)
		await _shot("dressing_D_failed")
	quit()
