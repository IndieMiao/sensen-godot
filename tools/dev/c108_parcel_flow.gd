extends SceneTree
## C-108 review captures on the real parcel scene (the r4 fixture parcel, saved on this machine only, as the scene
## tests open it): the top bar, then — where the revision has the HUD avatar — the avatar → the profile → Edit look →
## another outfit → Done → `Look saved` → back on the parcel, wearing it. Each step is a PNG in <out_dir>:
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/dev/c108_parcel_flow.gd -- <out_dir>
## The outfit and the parcel save go to scratch user directories, never the player's.

const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")

var out := ""
var step := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://c108_parcel_flow"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	step += 1
	root.get_texture().get_image().save_png(out.path_join("%02d_%s.png" % [step, name]))
	print("SHOT ", name)

func _frames(n: int) -> void:
	for i in n: await process_frame

func _idle(rig: Node) -> void:
	for i in 900:
		if not rig.is_busy(): return
		await process_frame

func _run() -> void:
	var avatar: Node = root.get_node("Avatar")
	avatar.store.base_dir = "user://c108_flow_store"
	avatar.user_id = "c108"
	avatar.save_outfit(avatar.slot_table.default_config())
	var router: Node = root.get_node("AppRouter")
	var raw: Dictionary = Fixture.farm()
	var dir := "user://c108_flow_parcel"
	var args := {"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true,
		"farm_store": LocalStore.new(raw.block_id, dir)}
	var scene: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup(args)
	var ready := [false]
	scene.preview_ready.connect(func(_s): ready[0] = true)
	root.add_child(scene)
	current_scene = scene
	while not ready[0]: await process_frame
	await _frames(180)
	var farming: Node = scene.get_node("ParcelFarming")
	if farming.has_method("close_tip"): farming.close_tip()
	await _shot("parcel_topbar")
	if not scene.has_method("open_profile"):
		quit()
		return
	var avatar_button: Button = scene._header.get_node("Avatar")
	await _frames(60)   # the head portrait renders
	await _shot("parcel_avatar_ready")
	avatar_button.pressed.emit()
	await _frames(4)
	await _shot("profile_entering")
	await _frames(60)
	await _shot("profile")
	var host: Control = scene._profile
	var room: Node = host.edit_look()
	await _idle(room.rig)
	await _frames(60)
	await _shot("dressing")
	room.parts_panel._show_slot(&"cloth", true)
	await _frames(40)
	await _shot("dressing_outfits")
	var current: String = room.rig.desired_part(&"cloth")
	var target := ""
	for meta in avatar.catalog.parts_for_slot(&"cloth"):
		if meta.id != current and target == "": target = meta.id
	room.parts_panel._select_part(&"cloth", target)
	await _frames(2)
	await _shot("dressing_trying")
	await _idle(room.rig)
	await _frames(30)
	await _shot("dressing_new_outfit")
	room._on_done()
	for i in 240:
		if router.top_instance() == null: break
		await process_frame
	await _frames(8)
	await _shot("profile_look_saved")
	await _frames(60)
	await _shot("profile_new_look")
	host.back()
	await _frames(90)
	await _shot("parcel_wearing_it")
	print("SAVED ", avatar.load_outfit().slots[&"cloth"], " target ", target)
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	quit()
