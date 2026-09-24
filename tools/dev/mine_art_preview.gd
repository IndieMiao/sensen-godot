extends Node3D
## Isolated visual fixtures: never boots a network account or reads a Journey save.
const Mine = preload("res://scenes/mine/mine.gd")
var mine: Node3D
var floor_number := 1
var capture_mode := false
var _inspect_elapsed := 0.0
var _qa_bar: HBoxContainer
var commands: Array[String] = []

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-mine-art"):
		get_tree().quit(2)
		return
	Localization.select_language("zh_CN")
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func _session(number: int) -> FarmSession:
	var ss := FarmSession.new(ApiClient.new("https://example.test/v1", _request))
	ss.farm_id = "mine-art-fixture"
	ss.client.token = "fixture"
	ss.version = 1
	ss.state = {"inventory": {"produce": {}, "dishes": {}}, "journey": {"wood": 0, "materials": {"stone": 0, "copper_ore": 0, "rock_salt": 0}},
		"character": {"version": 1, "hp": 100, "buffs": []},
		"bag": {"version": 1, "capacity": 30, "slots": [], "overflow": [], "equipped": {"main_hand": {"id": "fixture-sword", "item_id": "copper_sword", "quantity": 1, "quality": "normal", "instance_id": "fixture-sword"}}},
		"mine": {"version": 1, "run": 0, "floor": number, "deepest_floor": 5, "cleared_floors": [], "broken": {}, "elevator_unlocked": false,
			"combat": {"version": 2, "sequence": 0, "monsters": {"1": [], "2": [], "3": [38], "4": [38, 38, 38], "5": [300]}}}}
	return ss

func _request(_method: String, _url: String, _headers: PackedStringArray, _body: String) -> ApiClient.Response:
	# Local command fixtures only, used to exercise model picking and scene refresh.
	# Production settlement is covered by the existing mine suites, not this viewer.
	if not is_instance_valid(mine): return ApiClient.Response.new(true,503,{})
	var state: Dictionary = mine.session.state.duplicate(true)
	var command: Variant = JSON.parse_string(_body)
	if not command is Dictionary: return ApiClient.Response.new(true,200,{"state":state,"version":mine.session.version})
	var kind := str(command.get("type",""))
	commands.append(kind)
	if kind == "mine_rock":
		var key := str(int(state.mine.floor))
		var broken: Array = state.mine.broken.get(key,[])
		var id := str(command.payload.node_id)
		if not broken.has(id): broken.append(id)
		state.mine.broken[key] = broken
		state.mine.last_drop = {"floor":int(state.mine.floor),"node_id":id,"materials":{"stone":1}}
		state.journey.materials.stone += 1
		if broken.size() == 6: state.mine.cleared_floors.append(int(state.mine.floor))
	elif kind == "descend_mine": state.mine.floor = mini(5,int(state.mine.floor)+1)
	elif kind == "ascend_mine": state.mine.floor = maxi(1,int(state.mine.floor)-1)
	else: return ApiClient.Response.new(true,422,{"code":"NOT_AVAILABLE"})
	return ApiClient.Response.new(true,200,{"state":state,"version":mine.session.version+1})

func show_floor(number: int) -> void:
	floor_number = clampi(number, 1, 5)
	if is_instance_valid(mine):
		remove_child(mine)
		mine.queue_free()
	mine = Mine.new()
	mine.setup({"session": _session(floor_number)})
	add_child(mine)
	mine.combat.grace = 99999

func _run() -> void:
	if not capture_mode:
		show_floor(1)
		_add_review_controls()
		return
	var folder := str(ProjectSettings.get_setting("mine_art/output", "user://captures"))
	DirAccess.make_dir_recursive_absolute(folder)
	for size in [Vector2i(390, 844), Vector2i(360, 640), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size * (2 if size.x < 600 else 1)
		for number in range(1, 6):
			show_floor(number)
			assert(is_instance_valid(mine.scenery) and mine.scenery.get_child_count() >= 5)
			for frame in 24: await get_tree().process_frame
			mine.set_process(false)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(folder.path_join("floor-%d-%dx%d.png" % [number, size.x, size.y]))
			if bool(ProjectSettings.get_setting("mine_art/camera_qa",false)) and size == Vector2i(390,844) and number == 1:
				var original: Vector3 = mine._camera_center
				mine._camera_center = Vector3(1.25,0.7,-6.75)
				mine._update_camera()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder.path_join("camera-panned-elevator.png"))
				mine._camera_center = original+Vector3(8,0,0)
				mine._update_camera()
				for frame in 30: await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder.path_join("camera-offscreen-portrait.png"))
				mine.recenter_on_player()
				await get_tree().create_timer(0.45).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder.path_join("camera-recentered.png"))
			if size.x == 960:
				mine.canvas.hide()
				mine.player.hide()
				for enemy in mine.combat.enemies.values():
					enemy.node.get_node("Health").hide()
					enemy.node.get_node("HealthFill").hide()
					enemy.node.get_node("HealthTrack").hide()
				mine.cam.size = 13.3
				var center := Vector3(4.75, 0, -3.85)
				mine.cam.position = center + Vector3(2.014, 7.502, 7.789)
				mine.cam.look_at(center)
				mine.cam.near = 0.05
				mine.cam.far = 60
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder.path_join("chamber-%d.png" % number))
	print("MINE_ART_CAPTURES ", folder)
	get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_5:
		show_floor(event.keycode - KEY_1 + 1)

func _add_review_controls() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 60
	add_child(canvas)
	_qa_bar = HBoxContainer.new()
	_qa_bar.position = Vector2(12,144)
	_qa_bar.add_theme_constant_override("separation",4)
	canvas.add_child(_qa_bar)
	for number in range(1,6):
		var button := Button.new()
		button.name = "ReviewFloor%d" % number
		button.text = "B%d" % number
		button.custom_minimum_size = Vector2(46,36)
		button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover",StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed",StyleBoxEmpty.new())
		button.add_theme_color_override("font_color",Color("f2e8da"))
		button.add_theme_color_override("font_hover_color",Color.WHITE)
		button.pressed.connect(show_floor.bind(number))
		_qa_bar.add_child(button)
	var reset := Button.new()
	reset.name = "ReviewReset"
	reset.text = "Reset"
	reset.custom_minimum_size = Vector2(58,36)
	reset.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	reset.add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	reset.add_theme_stylebox_override("pressed",StyleBoxEmpty.new())
	reset.add_theme_color_override("font_color",Color("f2e8da"))
	reset.add_theme_color_override("font_hover_color",Color.WHITE)
	reset.pressed.connect(func(): show_floor(floor_number))
	_qa_bar.add_child(reset)

func _process(delta: float) -> void:
	if capture_mode or not is_instance_valid(mine): return
	_inspect_elapsed += delta
	if _inspect_elapsed < 0.15: return
	_inspect_elapsed = 0
	var transform := get_viewport().get_screen_transform()
	var controls := []
	for button in find_children("*","BaseButton",true,false):
		if button.is_visible_in_tree():
			var r: Rect2 = transform * button.get_global_rect()
			controls.append({"name":str(button.name),"text":button.text,"rect":[r.position.x,r.position.y,r.size.x,r.size.y],"disabled":button.disabled})
	var targets := []
	for id in mine.targets:
		var model: MeshInstance3D = mine.targets[id].model
		var point: Vector2 = mine.cam.unproject_position(model.global_transform*model.get_aabb().get_center())
		var center_pick: String = mine._pick_target(point)
		if center_pick != id:
			# Nearby bodies may legitimately occlude a model's centre in a diagonal
			# view. Use its exposed silhouette in the live scene tree, like a player.
			var rect: Rect2 = mine._project_model_rect(model)
			for sample in [Vector2(0.5,0.2),Vector2(0.25,0.45),Vector2(0.75,0.45),Vector2(0.5,0.8)]:
				var candidate: Vector2 = rect.position+rect.size*sample
				if mine._pick_target(candidate) == id:
					point = candidate
					break
		var p: Vector2 = transform * point
		targets.append({"id":id,"point":[p.x,p.y],"pick":mine._pick_target(point),"center_pick":center_pick})
	var stick_rect: Rect2 = transform * mine.stick.get_global_rect()
	var area: Rect2 = transform * mine.world_area()
	var screen: Vector2 = transform * mine.cam.unproject_position(mine.player.position)
	var state := {"floor":mine.current_floor(),"targets":targets,"controls":controls,"commands":commands,"moving":mine.mover.is_moving(),
		"busy":mine.busy,"digging":mine._dig_target,"feedback":mine.feedback.text,"player":[mine.player.position.x,mine.player.position.z],"player_screen":[screen.x,screen.y],
		"stick":[stick_rect.position.x,stick_rect.position.y,stick_rect.size.x,stick_rect.size.y],"bag":mine.bag_sheet!=null and mine.bag_sheet.visible,
		"zoom":mine.camera_pan.zoom,"pan":[mine.camera_pan.offset.x,mine.camera_pan.offset.z],"camera_size":mine.cam.size,
		"camera_center":[mine._camera_center.x,mine._camera_center.z],"focus_visible":mine._focus_button.visible,
		"world_area":[area.position.x,area.position.y,area.size.x,area.size.y],
		"avatar_meshes":mine.rig.find_children("*","MeshInstance3D",true,false).filter(func(mesh): return mesh.visible and mesh.mesh != null).size(),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	FileAccess.open("user://mine-art-state.tmp",FileAccess.WRITE).store_string(JSON.stringify(state))
	DirAccess.rename_absolute("user://mine-art-state.tmp","user://mine-art-state.json")
