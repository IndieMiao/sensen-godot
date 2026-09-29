class_name FishingPondScene
extends Node3D

var session: FarmSession
var entry: Dictionary = {}
var site_spec: Dictionary = {}
var mover: PlayerMover
var player: Node3D
var _rig: AvatarRig
var cam: Camera3D
var environment: Environment
var world_env: WorldEnvironment
var online: OnlineSpace
var fishing_panel: FishingPanel
var fishing_view: FishingPresentation
var bag_sheet: BagSheet
var camera_pan := preload("res://modules/farm/scene_pan.gd").new()
var canvas: CanvasLayer
var ui: Control
var notice: Label
var _focus_button: AvatarFocusButton
var _focus := Vector3(6, 0, -6)
var _overview := false
var _recenter: Tween
var _plan: Dictionary = {}
var _animation := ""
var _join_args: Dictionary = {}
var _notice_left := 0.0
var _geometry_ready := false

func setup(args: Dictionary) -> void:
	session = args.get("session", Net.session)
	entry = SystemPonds.location(str(args.get("pond_id", "")))
	_join_args = args.get("online_join", {}).duplicate()

func _ready() -> void:
	if entry.is_empty():
		push_error("Missing registered pond")
		return
	site_spec = SystemPonds.site(entry)
	get_viewport().transparent_bg = false
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("d8e9ad")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e4f0ff")
	environment.ambient_light_energy = 0.65
	environment.sky = preload("res://assets/ponds/art/pond_daylight_sky.tres")
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "PondSun"
	sun.rotation_degrees = Vector3(-55, -137, 0)
	sun.light_color = Color("fff3dc")
	sun.light_energy = 1.15
	sun.light_specular = 0.13
	sun.shadow_enabled = true
	sun.shadow_blur = 3.0
	sun.shadow_opacity = 0.82
	sun.light_angular_distance = 1.0
	sun.directional_shadow_max_distance = 65
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.05
	cam.far = 80
	add_child(cam)
	cam.make_current()
	add_child(PondScenery.build(entry))
	var water := FishingWater.build(str(entry.id), site_spec)
	water.water_material.set_shader_parameter("sun_direction", sun.global_basis.z.normalized())
	add_child(water)
	var bp := SystemPonds.blueprint(entry)
	mover = PlayerMover.new(bp, BlueprintGrid.new(bp))
	player = Node3D.new()
	player.name = "PondPlayer"
	player.position = mover.position
	add_child(player)
	_rig = Avatar.create_rig()
	_rig.assembler = AvatarAssemblerMerged.new()
	# The orthographic pond camera sits 40m away even in the close view.
	# Match the other world scenes instead of using the dressing room's 8/16m LOD.
	for child in _rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 50
			child.sleep_distance = 80
	player.add_child(_rig)
	_rig.config_applied.connect(func(_config): _animation = ""; _play("idle"))
	Avatar.follow_saved_outfit(_rig)
	_build_ui()
	fishing_panel = FishingPanel.new()
	add_child(fishing_panel)
	fishing_panel.opened.connect(_begin_fishing)
	fishing_panel.closed.connect(_end_fishing)
	camera_pan.free_pan = true
	camera_pan.tapped.connect(_tap)
	_update_camera()
	if session and session.logged_in():
		_join_args.merge({"pond_id": entry.id, "catalog_revision": SystemPonds.revision()}, false)
		online = OnlineSpace.attach(self, session, "pond", _join_args, func(): return mover, func(): return _animation, party_travel_ready)
		online.world_changed.connect(_world_changed)
		online.connection_changed.connect(func():
			if not online.joined:
				_geometry_ready = false
				_plan = {}
				mover.stop()
				if fishing_panel.visible: fishing_panel.interrupt()
				if not online.error.is_empty(): _message(OnlineSpace.error_text(online.error)))

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	canvas.name = "PondHUD"
	add_child(canvas)
	var safe := SafeAreaMargin.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.theme = GameUi.theme()
	canvas.add_child(safe)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(ui)
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.add_theme_constant_override("separation", 8)
	ui.add_child(header)
	var back := GameUi.button("arrow-left", "", "Back")
	back.name = "PondBack"
	back.custom_minimum_size = Vector2(44, 44)
	back.pressed.connect(_leave)
	header.add_child(back)
	var title := GameUi.label(L10n.text(str(entry.name)), 16)
	title.name = "PondTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title)
	var overview := GameUi.button("map", "", "Overview")
	overview.name = "PondOverview"
	overview.custom_minimum_size = Vector2(44, 44)
	overview.pressed.connect(toggle_overview)
	header.add_child(overview)
	var bag := GameUi.button("backpack", "", "Bag")
	bag.name = "PondBag"
	bag.custom_minimum_size = Vector2(44, 44)
	bag.pressed.connect(_open_bag)
	header.add_child(bag)
	var fish := GameUi.button("fish", L10n.text("Go fishing"), "PondFish", true)
	fish.name = "PondFish"
	fish.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	fish.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fish.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# The English label is wider than 112px. Size before placing so its minimum
	# width grows into the safe area instead of extending past the screen edge.
	fish.size = fish.get_combined_minimum_size().max(Vector2(112, 44))
	fish.position = -fish.size - Vector2(0, 4)
	fish.pressed.connect(func(): _go_fishing(Vector3.INF))
	ui.add_child(fish)
	notice = GameUi.label("", 12)
	notice.name = "PondNotice"
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notice.offset_top = -104
	notice.offset_bottom = -54
	notice.add_theme_stylebox_override("normal", GameUi.card_style(false, 8))
	ui.add_child(notice)
	_focus_button = AvatarFocusButton.new()
	ui.add_child(_focus_button)
	_focus_button.pressed.connect(recenter_on_player)

func _world_changed(world: Dictionary) -> void:
	_geometry_ready = world.get("pond_id") == entry.id and world.get("catalog_revision") == SystemPonds.revision() and world.get("template_id") == entry.template_id
	if not _geometry_ready:
		online.stop()
		_message(L10n.text("This pond needs an app update."))

func _process(delta: float) -> void:
	if mover == null: return
	_notice_left = maxf(0, _notice_left - delta)
	notice.visible = _notice_left > 0
	if fishing_panel.visible: return
	if session: mover.speed = CharacterModel.current(session.state, "move_speed")
	mover.step(delta)
	player.position = mover.position
	if mover.is_moving():
		_rig.rotation.y = atan2(mover.facing.x, mover.facing.z)
		_play("run")
	else:
		_play("idle")
		if not _plan.is_empty():
			var plan := _plan
			_plan = {}
			if player.position.distance_to(plan.origin) < 0.3 and _geometry_ready:
				camera_pan.cancel()
				fishing_panel.open(session, str(entry.id), plan.target, site_spec)
				return
	camera_pan.step(delta, cam)
	_update_camera()

func _play(animation: String) -> void:
	if _animation == animation: return
	_animation = animation
	_rig.play_motion(animation)

func _tap(position: Vector2) -> void:
	var origin := cam.project_ray_origin(position)
	var direction := cam.project_ray_normal(position)
	if absf(direction.y) < 0.001: return
	var point := origin + direction * (-origin.y / direction.y)
	if FishingModel.contains(str(entry.id), point, 0, site_spec):
		_go_fishing(point)
	else:
		_plan = {}
		mover.set_target_position(point)

func _go_fishing(point: Vector3) -> void:
	if not _geometry_ready or session == null or session.offline:
		_message(L10n.text("Connect to the pond before fishing."))
		if online and not online.active: online.start()
		return
	if session.has_unconfirmed_command(): return
	if not CharacterModel.has_fishing_rod(session.state):
		_message(L10n.text("Equip a fishing rod on the character page first."))
		return
	_plan = FishingModel.plan(str(entry.id), mover.position, point, mover.grid, site_spec)
	if _plan.is_empty() or not mover.set_target_position(_plan.origin):
		_plan = {}
		_message(L10n.text("Can't reach that spot"))

func _begin_fishing(_id: String) -> void:
	_stop_recenter()
	fishing_view = FishingPresentation.new()
	add_child(fishing_view)
	fishing_view.configure(fishing_panel, player, _rig, cam, [ui, online.hud if online else null])

func _end_fishing() -> void:
	if is_instance_valid(fishing_view): fishing_view.finish()
	fishing_view = null

func _update_camera() -> void:
	if not camera_pan.active():
		_focus += camera_pan.offset
		camera_pan.offset = Vector3.ZERO
		camera_pan._raw_offset = Vector3.ZERO
	cam.size = (15.0 if _overview else 7.5) / camera_pan.zoom
	var target := _focus + camera_pan.offset
	cam.position = target + Vector3(0, 1, 1).normalized() * 40
	cam.look_at(target, Vector3.UP)
	var area := ui.get_global_rect()
	area.position.y += 52
	area.size.y = maxf(0, area.size.y - 108)
	_focus_button.update_indicator(cam.unproject_position(player.position + Vector3.UP * .7), get_viewport().get_visible_rect(), area, cam.is_position_behind(player.position))

func _input(event: InputEvent) -> void:
	_handle_input(event, false)

func _unhandled_input(event: InputEvent) -> void:
	_handle_input(event, true)

func _handle_input(event: InputEvent, allow_start: bool) -> void:
	if mover == null or fishing_panel.visible or (bag_sheet and bag_sheet.visible) or (online and (online.travel_busy or is_instance_valid(online.panel))): return
	if camera_pan.handle(event, cam, allow_start):
		_stop_recenter()
		_update_camera()
		get_viewport().set_input_as_handled()

func _stop_recenter() -> void:
	if _recenter: _recenter.kill(); _recenter = null

func recenter_on_player() -> void:
	_stop_recenter()
	camera_pan.cancel()
	_focus += camera_pan.offset
	camera_pan.offset = Vector3.ZERO
	camera_pan._raw_offset = Vector3.ZERO
	_overview = false
	var start := _focus
	_recenter = create_tween()
	_recenter.tween_method(func(t: float): _focus = start.lerp(player.position, t); _update_camera(), 0.0, 1.0, .34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func toggle_overview() -> void:
	_stop_recenter()
	camera_pan.reset()
	_overview = not _overview
	_focus = Vector3(6, 0, -8) if _overview else player.position
	_update_camera()

func _open_bag() -> void:
	if session == null or fishing_panel.visible: return
	mover.stop()
	_plan = {}
	camera_pan.cancel()
	if bag_sheet == null:
		bag_sheet = BagSheet.new()
		bag_sheet.setup(session)
		ui.add_child(bag_sheet)
	bag_sheet.open()

func _message(text: String) -> void:
	notice.text = text
	_notice_left = 5
	notice.show()

func is_back_navigation_locked() -> bool:
	if fishing_panel and fishing_panel.visible: fishing_panel.close(); return true
	if online and online.consume_back(): return true
	if bag_sheet and bag_sheet.consume_back(): return true
	return session != null and session.has_unconfirmed_command()

func _leave() -> void:
	if AppRouter.top_instance() == self: AppRouter.handle_back()

func party_travel_ready() -> bool:
	return not (fishing_panel and fishing_panel.visible) and not (session and session.has_unconfirmed_command()) and not (bag_sheet and bag_sheet.visible)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		camera_pan.cancel()
		_stop_recenter()
		_plan = {}
		if mover: mover.stop()

func suspend() -> void:
	_stop_recenter()
	camera_pan.cancel()
	_plan = {}
	mover.stop()
	_end_fishing()
	fishing_panel.interrupt()
	fishing_panel.hide()
	if online: online.suspend()
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	canvas.hide()
	cam.current = false
	world_env.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	show()
	canvas.show()
	get_viewport().transparent_bg = false
	world_env.environment = environment
	cam.make_current()
	if online: online.resume()

func _exit_tree() -> void:
	_stop_recenter()
	_end_fishing()
