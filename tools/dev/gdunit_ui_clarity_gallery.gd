extends Node
## High-density native proof from the isolated current farm fixture; no writes
## to a game service. Logical UI size remains 360 x 780 throughout.
var farm: Node3D
var model: FarmSession
var output := ""
var captures: Array = []

func _ready() -> void:
	assert(Net.is_test_process())
	output = str(ProjectSettings.get_setting("clarity/output", "/Volumes/ACASIS/projects/sensen-godot/output/ui-clarity-2026-09-21/native"))
	DirAccess.make_dir_recursive_absolute(output)
	Localization.select_language("zh_CN")
	get_tree().root.size = Vector2i(1080, 2340)
	get_tree().root.content_scale_size = Vector2i(360, 780)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var outfit := AvatarConfig.from_json_text(FileAccess.get_file_as_string("res://gallery_outfit.json"))
	assert(Avatar.save_outfit(outfit) == OK)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://gallery_farm.json"))
	model = FarmSession.new(ApiClient.new("https://presentation.invalid/v1", func(_m, _p, _h, _b): return ApiClient.Response.new(false, 503, {})))
	model.client.token = "presentation-only"
	model.player_id = "clarity-gallery"
	assert(model._adopt(raw))
	Net.session = model
	Net.online_available = false
	farm = load(AppRouter.FARM).instantiate()
	farm.setup({"session": model})
	add_child(farm)
	_run.call_deferred()

func settle(frames := 12) -> void:
	for frame in frames: await get_tree().process_frame

func shot(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	pixels.save_png(output.path_join(name + ".png"))
	captures.append({"name": name, "pixels": [pixels.get_width(), pixels.get_height()],
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"avatar_indicator": farm._focus_button.visible,
		"indicator_rect": [farm._focus_button.position.x, farm._focus_button.position.y, farm._focus_button.size.x, farm._focus_button.size.y]})

func _run() -> void:
	await settle(120)
	assert(not farm._focus_button.visible)
	await shot("farm-hd")
	var start: Vector3 = farm._camera_center
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1, -1), Vector2(1, 1)]:
		# Move the camera in its ground-projected axes, never move the saved player.
		var horizontal: Vector3 = farm.cam.global_basis.x
		horizontal.y = 0
		var vertical: Vector3 = farm.cam.global_basis.y
		vertical.y = 0
		farm._camera_center = start - horizontal.normalized() * direction.x * 17 + vertical.normalized() * direction.y * 17
		farm._update_camera()
		await settle(90)
		assert(farm._focus_button.visible)
		await shot("direction-%d-%d" % [direction.x, direction.y])
	farm.recenter_on_player()
	await get_tree().create_timer(0.5).timeout
	assert(not farm._focus_button.visible)
	farm._open_life()
	await settle()
	var bag := farm.life_sheet.active as BagPanel
	if bag == null:
		for node in farm.find_children("*", "Control", true, false):
			if node is BagPanel: bag = node
	assert(bag != null)
	bag.select_stack(str(model.state.bag.slots[0].id))
	await shot("bag-hd")
	bag.select_page("character")
	await settle(100)
	await shot("character-hd")
	FileAccess.open(output.path_join("captures.json"), FileAccess.WRITE).store_string(JSON.stringify({"passed": true, "captures": captures}, "\t"))
	get_tree().quit()
