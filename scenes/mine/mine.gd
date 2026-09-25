extends Node3D

const Layout = preload("res://modules/mining/mine_layout.gd")
const Art = preload("res://modules/mining/mine_art.gd")
const Combat = preload("res://modules/mining/mine_combat.gd")
const CameraFit = preload("res://modules/farm/farm_camera.gd")
const AvatarFocus = preload("res://modules/ui/avatar_focus_button.gd")
const DIG_SECONDS := 1.0

var session: FarmSession
var cam: Camera3D
var world_env: WorldEnvironment
var environment: Environment
var canvas: CanvasLayer
var ui: Control
var header: VBoxContainer
var footer: VBoxContainer
var _header_backdrop: Panel
var _notice_backdrop: Panel
var title: Label
var status: Label
var feedback: Label
var inventory_label: Label
var effects_label: Label
var progress: ProgressBar
var marker_layer: Control
var primary: Button
var restart: Button
var reconnect: Button
var targets: Dictionary = {}
var scenery: Node3D
var objects: Node3D
var player: Node3D
var rig: AvatarRig
var mover: PlayerMover
var busy := false
var pending_target := ""
var camera_pan := preload("res://modules/farm/scene_pan.gd").new()
var _camera_center := Vector3.ZERO
var _camera_initialized := false
var _camera_context := ""
var _camera_recenter: Tween
var _focus_button: Button
var _world_key := ""
var _rendered_floor := -1
var _rendered_run := -1
var _rendered_farm := ""
var _dig_target := ""
var _dig_elapsed := 0.0
var _pressed_target: Variant = null
var _anim := ""
var _leaving := false
var _ready_for_input := false
var bag_sheet: BagSheet
var combat: Node3D
var health_label: Label
var health_bar: ProgressBar
var attack: Button
var attack_progress: ProgressBar
var stick: TouchStick
var pause_button: Button
var _paused := false
var _focused := true
var _attack_held := false
var _attack_touch_index := -1
var _pending_hurt := ""
var _rescued := false
var _weapon_id := ""
var _weapon_model: Node3D
var prediction := preload("res://modules/mining/combat_predictor.gd").new()
var _combat_view: Dictionary = {}
var _combat_draining := false
var _combat_sending := false
var _last_attack_sent_ms := -100000
var _last_hurt_sent_ms := -100000
var _exit_after_combat := false
var _rescue_scheduled := false
const MAX_PENDING_COMBAT := 8
const MAX_COMBAT_LAG_MS := 2500

func setup(args: Dictionary) -> void:
	session = args.get("session", Net.session if Net else null)

func _ready() -> void:
	if session == null: session = Net.session if Net else null
	_build_world()
	_build_ui()
	combat = Combat.new()
	combat.name = "MineCombat"
	combat.contact.connect(func(id): _pending_hurt = id)
	add_child(combat)
	camera_pan.free_pan = true
	camera_pan.tapped.connect(_tap_scene)
	if session:
		session.state_changed.connect(_state_changed)
		session.offline_changed.connect(func(_offline): _refresh())
	_refresh()
	_ready_for_input = true
	if session and current_floor() == 0: _enter.call_deferred()

func mine_state() -> Dictionary:
	return session.state.get("mine", {}) if session else {}

func _display_state() -> Dictionary:
	return prediction.view(session.state) if session else {}

func _floor_rocks(number: int, run: int, farm_id: String) -> Array:
	return Layout.rocks(number, run, farm_id)

func _floor_navigation(number: int, run: int, farm_id: String) -> FarmBlueprint:
	return Layout.navigation(number, broken(), run, farm_id)

func current_floor() -> int:
	return int(mine_state().get("floor", 0))

func completed() -> bool:
	return mine_state().get("cleared_floors", []).any(func(value): return int(value) == 5)

func fully_cleared() -> bool:
	var floors: Array = mine_state().get("cleared_floors", [])
	return range(1, int(Layout.data().floors) + 1).all(func(number):
		if not floors.any(func(value): return int(value) == number): return false
		var mined: Array = mine_state().get("broken", {}).get(str(number), [])
		if not Layout.rocks(number).all(func(rock): return mined.has(rock.id)): return false
		var health: Array = mine_state().get("combat", {}).get("monsters", {}).get(str(number), [])
		return health.all(func(hp): return int(hp) <= 0))

func cleared() -> bool:
	return mine_state().get("cleared_floors", []).any(func(value): return int(value) == current_floor())

func broken() -> Array:
	return mine_state().get("broken", {}).get(str(maxi(current_floor(), 1)), [])

func _build_world() -> void:
	get_viewport().transparent_bg = false
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("242125")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e8dfea")
	environment.ambient_light_energy = 0.48
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-51, -38, 0)
	sun.light_color = Color("ffe8ce")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.58
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.45
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(cam)
	cam.make_current()
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())
	player = Node3D.new()
	player.name = "Player"
	add_child(player)
	rig = Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	rig.rotation.y = PI
	for child in rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 50
			child.sleep_distance = 80
	player.add_child(rig)
	rig.config_applied.connect(func(_config): _play("idle"))
	Avatar.follow_saved_outfit(rig)

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	var safe := SafeAreaMargin.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.theme = GameUi.theme()
	canvas.add_child(safe)
	ui = Control.new()
	ui.name = "MineUI"
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(ui)
	ui.resized.connect(_layout)
	marker_layer = Control.new()
	marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(marker_layer)
	_header_backdrop = Panel.new()
	_header_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_backdrop.add_theme_stylebox_override("panel", GameUi.card_style(false, 8))
	ui.add_child(_header_backdrop)
	_notice_backdrop = Panel.new()
	_notice_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_backdrop.add_theme_stylebox_override("panel", GameUi.card_style(false, 8))
	ui.add_child(_notice_backdrop)
	header = VBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	header.add_theme_constant_override("separation", 4)
	ui.add_child(header)
	header.minimum_size_changed.connect(_layout.call_deferred)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	header.add_child(top)
	var back := GameUi.button("arrow-left", "", L10n.text("Return to farm"))
	back.pressed.connect(_leave)
	top.add_child(back)
	title = GameUi.label(L10n.text("Starter mine"), 14, GameUi.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(title)
	reconnect = GameUi.button("refresh-cw", "", L10n.text("Reconnect"))
	reconnect.pressed.connect(_recover)
	top.add_child(reconnect)
	var bag := GameUi.button("backpack", "", L10n.text("Your bag"))
	bag.name = "OpenBag"
	bag.pressed.connect(_open_bag)
	top.add_child(bag)
	pause_button = GameUi.button("pause", "", L10n.text("Pause"))
	pause_button.name = "PauseCombat"
	pause_button.toggle_mode = true
	pause_button.toggled.connect(func(value):
		_paused = value
		pause_button.icon = GameUi.icon("play" if value else "pause")
		pause_button.tooltip_text = L10n.text("Resume" if value else "Pause")
		_attack_held = false
		if mover: mover.stop()
		camera_pan.cancel()
		feedback.text = L10n.text("Paused") if value else ""
		_refresh())
	top.add_child(pause_button)
	status = GameUi.label("", 12, GameUi.MUTED)
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.custom_minimum_size.y = 22
	header.add_child(status)
	effects_label = GameUi.label("", 12, GameUi.GREEN)
	effects_label.name = "MineEffects"
	effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(effects_label)
	health_label = GameUi.label("", 13, GameUi.INK)
	health_label.name = "MineHealth"
	health_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(health_label)
	health_bar = ProgressBar.new()
	health_bar.name = "MineHealthBar"
	health_bar.custom_minimum_size.y = 8
	health_bar.show_percentage = false
	var fill := GameUi.surface(GameUi.CORAL, 0, 5)
	fill.set_border_width_all(0)
	fill.shadow_size = 0
	health_bar.add_theme_stylebox_override("fill", fill)
	header.add_child(health_bar)
	footer = VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	ui.add_child(footer)
	feedback = GameUi.label("", 14, GameUi.INK)
	feedback.name = "MineFeedback"
	feedback.custom_minimum_size.y = 38
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.max_lines_visible = 2
	footer.add_child(feedback)
	inventory_label = GameUi.label("", 12, GameUi.MUTED)
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_label.max_lines_visible = 2
	footer.add_child(inventory_label)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 6
	progress.show_percentage = false
	progress.max_value = DIG_SECONDS
	footer.add_child(progress)
	var commands := HBoxContainer.new()
	commands.add_theme_constant_override("separation", 8)
	footer.add_child(commands)
	stick = TouchStick.new()
	stick.name = "MineMoveStick"
	stick.custom_minimum_size = Vector2(112, 112)
	stick.radius = 44
	stick.changed.connect(_stick_changed)
	commands.add_child(stick)
	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.add_child(actions)
	primary = GameUi.button("pickaxe", "", "", true)
	primary.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	primary.name = "MinePrimary"
	primary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary.pressed.connect(_primary_action)
	actions.add_child(primary)
	attack = GameUi.button("sword", "", L10n.text("Attack"), true)
	attack.name = "MineAttack"
	attack.custom_minimum_size.y = 54
	attack.button_down.connect(func():
		_attack_held = true
		_attack())
	attack.button_up.connect(func(): _attack_held = false)
	actions.add_child(attack)
	attack_progress = ProgressBar.new()
	attack_progress.custom_minimum_size.y = 4
	attack_progress.max_value = 1
	attack_progress.show_percentage = false
	actions.add_child(attack_progress)
	restart = GameUi.button("refresh-cw", L10n.text("Start new expedition"), L10n.text("Start new expedition"))
	restart.name = "MineRestart"
	restart.pressed.connect(_restart)
	footer.add_child(restart)
	_focus_button = AvatarFocus.new()
	ui.add_child(_focus_button)
	_focus_button.pressed.connect(recenter_on_player)
	_layout.call_deferred()

func _layout() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or footer == null: return
	var width := maxf(48, ui.size.x)
	header.size = Vector2(minf(480, maxf(48, width - 60)), header.get_combined_minimum_size().y)
	_header_backdrop.position = Vector2(-4, -4)
	_header_backdrop.size = header.size + Vector2(8, 12)
	feedback.size.x = width
	inventory_label.size.x = width
	footer.size.x = width
	var height := footer.get_combined_minimum_size().y
	footer.position = Vector2(0, maxf(0, ui.size.y - height))
	footer.size = Vector2(width, height)
	_notice_backdrop.position = footer.position + Vector2(-4, -4)
	_notice_backdrop.size = Vector2(width + 8, inventory_label.position.y + inventory_label.size.y + 12)
	_update_camera()

func world_area() -> Rect2:
	if not is_inside_tree() or ui == null or footer == null: return Rect2()
	var top := header.get_global_rect().end.y + 12
	var bottom := footer.global_position.y - 8
	return Rect2(ui.global_position.x + 12, top, maxf(0, ui.size.x - 24), maxf(0, bottom - top))

func _update_camera() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or cam == null or ui == null: return
	if not cam.is_inside_tree(): return
	cam.size = CameraFit.close_view_size(get_viewport().get_visible_rect().size) / camera_pan.zoom
	if not _camera_initialized:
		_camera_center = player.position + Vector3.UP * 0.7
		_camera_initialized = true
	# Keep the released view, including the point under a pinch. Walking and
	# same-floor snapshots never take camera ownership away from the player.
	if not camera_pan.active():
		_camera_center += camera_pan.offset
		camera_pan.offset = Vector3.ZERO
		camera_pan._raw_offset = Vector3.ZERO
	CameraFit.place(cam, _camera_center)
	cam.position += camera_pan.offset
	CameraFit.fit_ground_depth(cam)
	_sync_markers()
	_update_focus_indicator()

func _camera_modal_open() -> bool:
	return (bag_sheet != null and bag_sheet.visible) or GameUi.modal_is_open(self)

func _update_focus_indicator() -> void:
	if _focus_button == null or player == null or cam == null: return
	var viewport_rect := get_viewport().get_visible_rect()
	var point := player.position + Vector3.UP * 0.7
	var behind := cam.is_position_behind(point)
	var projected := cam.unproject_position(point)
	if behind or not projected.is_finite():
		var local := cam.to_local(point)
		var direction := Vector2(local.x, -local.y)
		if direction.is_zero_approx(): direction = Vector2.DOWN
		projected = viewport_rect.get_center() + direction.normalized() * viewport_rect.size.length()
	_focus_button.update_indicator(projected, viewport_rect, world_area(), behind,
		_camera_modal_open() or _rescued or current_floor() <= 0)

func _stop_camera_recenter() -> void:
	if _camera_recenter:
		_camera_recenter.kill()
		_camera_recenter = null

func recenter_on_player() -> void:
	if player == null or _camera_modal_open() or _rescued or current_floor() <= 0: return
	_stop_camera_recenter()
	camera_pan.cancel()
	_camera_center += camera_pan.offset
	camera_pan.offset = Vector3.ZERO
	camera_pan._raw_offset = Vector3.ZERO
	var start := _camera_center
	_camera_recenter = create_tween()
	_camera_recenter.tween_method(func(weight: float):
		_camera_center = start.lerp(player.position + Vector3.UP * 0.7, weight)
		_update_camera(), 0.0, 1.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_recenter.finished.connect(func(): _camera_recenter = null)

func _exit_tree() -> void:
	_stop_camera_recenter()

func _state_changed(_state: Dictionary, _version: int) -> void:
	if _combat_sending: return
	_refresh()

func _refresh() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or ui == null: return
	_combat_view = _display_state()
	var active := current_floor() > 0
	title.text = L10n.format_text("Mine - floor %d / 5", current_floor()) if active else L10n.text("Starter mine")
	status.text = L10n.format_text("Rocks cleared: %d / %d", [mini(broken().size(), Layout.rock_count(current_floor())), Layout.rock_count(current_floor())]) if active else L10n.text("Five floors explored" if fully_cleared() else "Enter mine")
	if active and Layout.rock_count(current_floor()) == 0: status.text = L10n.text("Elite challenge")
	if active and current_floor() in [1, 5]:
		status.text += "  |  " + L10n.text("Elevator ready" if mine_state().get("elevator_unlocked", false) else "Elevator locked")
	effects_label.text = CharacterModel.action_status(session.state, "mining_bonus") if session else ""
	effects_label.visible = not effects_label.text.is_empty()
	var stocks: Array[String] = []
	for item in ["stone", "copper_ore", "rock_salt"]:
		stocks.append(L10n.format_text("%s %d", [L10n.item_name(item), JourneyProgress.material(session.state, item) if session else 0]))
	inventory_label.text = " / ".join(stocks)
	var blocked := _connection_blocked()
	reconnect.visible = blocked and session != null and not busy
	reconnect.disabled = busy
	primary.disabled = busy or _has_combat_pending() or not _dig_target.is_empty() or blocked or _paused
	restart.visible = current_floor() in [0, 1] and completed()
	restart.disabled = primary.disabled
	if not active:
		primary.text = L10n.text("Start new expedition" if fully_cleared() else "Enter mine")
		primary.icon = GameUi.icon("arrow-down")
	elif cleared():
		primary.text = L10n.text("Return to farm") if current_floor() == 5 else L10n.format_text("Descend to floor %d", current_floor() + 1)
		primary.icon = GameUi.icon("arrow-left") if current_floor() == 5 else null
	else:
		primary.text = L10n.text("Mining...") if not _dig_target.is_empty() else L10n.text("Mine rock")
		primary.icon = GameUi.icon("pickaxe")
	primary.tooltip_text = primary.text
	if session == null: feedback.text = L10n.text("Offline - farm not connected")
	elif session.offline or session.has_unconfirmed_command(): feedback.text = L10n.text("Check the connection to continue mining")
	var key := JSON.stringify([session.farm_id if session else "", current_floor(), mine_state().get("run", 0), broken(), mine_state().get("elevator_unlocked", false), cleared()])
	if key != _world_key:
		_world_key = key
		_rebuild_floor()
		primary.disabled = busy or _has_combat_pending() or not _dig_target.is_empty() or blocked or _paused
	if combat and mover:
		var weapon_id := str(CharacterModel.equipped(session.state if session else {}, "main_hand").get("item_id", ""))
		if weapon_id != _weapon_id:
			_weapon_id = weapon_id
			if is_instance_valid(_weapon_model):
				_weapon_model.hide()
				_weapon_model.queue_free()
			_weapon_model = null
			if not weapon_id.is_empty():
				_weapon_model = preload("res://modules/mining/combat_art.gd").model(weapon_id)
				_weapon_model.name = "HeldWeapon"
				_weapon_model.hide()
				_weapon_model.position = Vector3(-0.26, 0.6, 0.05)
				_weapon_model.rotation_degrees.x = -65
				_weapon_model.scale = Vector3.ONE * 0.65
				player.add_child(_weapon_model)
		combat.sync(_combat_view, mover, session.farm_id if session else "")
		_sync_weapon_visibility()
		_sync_combat_targets()
		var count: int = combat.enemies.size()
		health_label.text = L10n.format_text("HP %d / %d", [CharacterModel.hp(_combat_view), int(CharacterModel.current(session.state, "max_hp"))]) if session else ""
		if count > 0: health_label.text += "   /   " + L10n.format_text("Monsters remaining: %d", count)
		health_bar.max_value = CharacterModel.current(session.state, "max_hp") if session else 100
		health_bar.value = CharacterModel.hp(_combat_view) if session else 100
		# Disabling a held BaseButton emits button_up and breaks continuous attacks.
		attack.disabled = blocked or _paused or _combat_stalled() or _predicted_defeat() or not active or combat.weapon(session.state if session else {}).is_empty()
		attack.tooltip_text = L10n.text("Equip a weapon first") if combat.weapon(session.state if session else {}).is_empty() else L10n.text("Attack")
		stick.mouse_filter = Control.MOUSE_FILTER_IGNORE if blocked or _paused or not active else Control.MOUSE_FILTER_STOP
	if _rescued:
		primary.text = L10n.text("Return to farm")
		primary.disabled = false
		primary.icon = GameUi.icon("arrow-left")
		restart.visible = false
	elif active and Layout.rock_count(current_floor()) == 0 and not cleared():
		primary.text = L10n.text("Clear monsters")
		primary.disabled = true
	primary.tooltip_text = primary.text
	_layout.call_deferred()

func _floor_spawn() -> Vector3:
	return Layout.SPAWN

func _camera_context_key() -> String:
	if current_floor() <= 0: return ""
	return "%s:%d:%d" % [session.farm_id if session else "", int(mine_state().get("run", 0)), current_floor()]

func _rebuild_floor() -> void:
	var number := maxi(1, current_floor())
	var run := int(mine_state().get("run", 0))
	var farm_id := session.farm_id if session else ""
	var changed_floor := _rendered_floor != current_floor() or _rendered_run != run or _rendered_farm != farm_id
	var previous := mover.position if mover and not changed_floor else _floor_spawn()
	var camera_context := _camera_context_key()
	# A temporary empty world during reconnect is not a new destination. Keep
	# its view; only an authoritative new floor/run/instance reframes arrival.
	if not camera_context.is_empty() and camera_context != _camera_context:
		_stop_camera_recenter()
		camera_pan.reset(camera_pan.min_zoom)
		_camera_initialized = false
		_camera_context = camera_context
	if changed_floor:
		_dig_target = ""
		_dig_elapsed = 0
		progress.value = 0
		_play("idle")
	_rendered_floor = current_floor()
	_rendered_run = run
	_rendered_farm = farm_id
	pending_target = ""
	for node in [scenery, objects]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	for child in marker_layer.get_children():
		marker_layer.remove_child(child)
		child.queue_free()
	targets.clear()
	var nav := _floor_navigation(number, run, farm_id)
	mover = PlayerMover.new(nav, BlueprintGrid.new(nav))
	if nav.is_walkable(nav.world_to_cell(previous)): mover.position = previous
	player.position = mover.position
	scenery = Art.floor_scenery(number, bool(mine_state().get("elevator_unlocked", false)))
	add_child(scenery)
	objects = Node3D.new()
	objects.name = "MineObjects"
	add_child(objects)
	if current_floor() == 0: return
	var index := 0
	for rock in _floor_rocks(number, run, farm_id):
		if not broken().has(rock.id):
			var object := Art.rock(rock.position, index, number)
			object.name = str(rock.id)
			objects.add_child(object)
			_add_target(rock.id, L10n.text("Mine rock"), "", rock.position + Vector3(0, 0.95, 0), rock.position, object.get_node("Rock"))
		index += 1
	_add_target("up", L10n.text("Return to farm") if number == 1 else L10n.format_text("Ascend to floor %d", number - 1), "", Layout.UP + Vector3(0, 0.8, 0), Layout.UP, scenery.get_node("UpLadder"))
	if cleared() and number < 5:
		var ladder := Art.ladder(Layout.DOWN, false)
		objects.add_child(ladder)
		_add_target("down", L10n.format_text("Descend to floor %d", number + 1), "", Layout.DOWN + Vector3(0, 0.55, 0), Layout.DOWN, ladder)
	if number in [1, 5]:
		var unlocked := bool(mine_state().get("elevator_unlocked", false))
		_add_target("elevator", L10n.format_text("Elevator to floor %d", 5 if number == 1 else 1) if unlocked else L10n.text("Clear floor 5 to unlock the elevator"), "", Layout.ELEVATOR + Vector3(0, 1.75, 0), Layout.ELEVATOR, scenery.get_node("MineElevator"))
	_sync_markers()

func _add_target(id: String, caption: String, icon: String, world: Vector3, body: Vector3, model: MeshInstance3D = null) -> void:
	var button := GameUi.button(icon, "", caption)
	button.name = "Target_" + id
	button.size = Vector2(44, 44)
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_layer.add_child(button)
	targets[id] = {"world": world, "body": body + Vector3(0, 0.28, 0), "approach": Layout.approach(mover, body),
		"button": button, "marker_visible": not icon.is_empty(), "model": model}

func _sync_markers() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or cam == null or marker_layer == null: return
	if not cam.is_inside_tree(): return
	var area := world_area()
	_sync_combat_targets()
	for target in targets.values():
		var button: Button = target.button
		var point := cam.unproject_position(target.world)
		button.position = point - marker_layer.global_position - Vector2(22, 22)
		button.visible = target.marker_visible and not cam.is_position_behind(target.world) and area.encloses(Rect2(point - Vector2(22, 22), Vector2(44, 44)))
		button.disabled = busy or not _dig_target.is_empty()

func _project_model_rect(model: MeshInstance3D) -> Rect2:
	if not is_instance_valid(model) or not model.is_visible_in_tree(): return Rect2()
	var bounds := model.get_aabb()
	var rect := Rect2()
	for corner in 8:
		var world := model.global_transform * bounds.get_endpoint(corner)
		if cam.is_position_behind(world): return Rect2()
		var point := cam.unproject_position(world)
		rect = Rect2(point, Vector2.ZERO) if corner == 0 else rect.expand(point)
	return rect

func _model_pick_rect(model: MeshInstance3D) -> Rect2:
	var rect := _project_model_rect(model)
	if not rect.has_area(): return rect
	# Keep small models comfortable to tap without letting padding hide a nearer model.
	var size := Vector2(maxf(44, rect.size.x + 12), maxf(44, rect.size.y + 12))
	return Rect2(rect.get_center() - size * 0.5, size).intersection(world_area())

func _pick_target(point: Vector2) -> String:
	var picked := ""
	var nearest := INF
	var padded := ""
	var padding_distance := INF
	var center_distance := INF
	var origin := cam.project_ray_origin(point)
	var direction := cam.project_ray_normal(point)
	for id in targets:
		var target: Dictionary = targets[id]
		var button: Button = target.button
		if button.disabled: continue
		var candidate: Variant = target.model
		if not is_instance_valid(candidate): continue
		var model := candidate as MeshInstance3D
		if not _model_pick_rect(model).has_point(point): continue
		var inverse := model.global_transform.affine_inverse()
		var hit: Variant = model.get_aabb().intersects_ray(inverse * origin, (inverse.basis * direction).normalized())
		if hit is Vector3:
			var distance := origin.distance_squared_to(model.global_transform * hit)
			if distance < nearest:
				nearest = distance
				picked = id
		else:
			var rect := _project_model_rect(model)
			var closest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
			var distance := point.distance_squared_to(closest)
			var center := point.distance_squared_to(rect.get_center())
			if distance < padding_distance or (is_equal_approx(distance, padding_distance) and center < center_distance):
				padding_distance = distance
				center_distance = center
				padded = id
	return picked if not picked.is_empty() else padded

func _input(event: InputEvent) -> void:
	if bag_sheet and bag_sheet.visible: return
	if not _ready_for_input: return
	if event is InputEventScreenTouch:
		if event.pressed and attack.get_global_rect().has_point(event.position):
			_attack_touch_index = event.index
			return
		if not event.pressed and event.index == _attack_touch_index:
			_attack_touch_index = -1
			_attack_held = false
			return
		if event.pressed and not world_area().has_point(event.position): return
	if event is InputEventScreenDrag and event.index == _attack_touch_index: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: _attack_held = false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		_attack()
		get_viewport().set_input_as_handled()
		return
	if camera_pan.handle(event, cam):
		_stop_camera_recenter()
		if not camera_pan.active(): _pressed_target = null
		_update_camera()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if bag_sheet and bag_sheet.visible: return
	if not _ready_for_input: return
	var point: Variant = null
	if event is InputEventScreenTouch and event.pressed: point = event.position
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: point = event.position
	if point is Vector2 and world_area().has_point(point): _pressed_target = _pick_target(point)
	var allow := point is Vector2 and world_area().has_point(point)
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: allow = world_area().has_point(event.position)
	if camera_pan.handle(event, cam, allow):
		_stop_camera_recenter()
		_update_camera()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop_camera_recenter()
		_focused = false
		_attack_held = false
		if mover: mover.stop()
		if stick: stick._release_stick()
		camera_pan.cancel()
		_pressed_target = null
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true

func _tap_scene(point: Vector2) -> void:
	if not _can_act() or not world_area().has_point(point): return
	var id := _pick_target(point) if _pressed_target == null else str(_pressed_target)
	if not id.is_empty():
		select_target(id)
		return
	var world = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(point), cam.project_ray_normal(point))
	if world is Vector3:
		pending_target = ""
		if not mover.set_target_position(world): feedback.text = L10n.text("Can't reach that spot")

func _can_act() -> bool:
	return current_floor() > 0 and not busy and not _paused and _focused and not _connection_blocked() and not _combat_stalled() and not _predicted_defeat() and _dig_target.is_empty() and not (bag_sheet and bag_sheet.visible)

func select_target(id: String) -> void:
	if not _can_act() or not targets.has(id): return
	if id.begins_with("slime_"):
		_attack(id)
		return
	if _has_combat_pending():
		feedback.text = L10n.text("Syncing combat...")
		return
	if id == "elevator" and not mine_state().get("elevator_unlocked", false):
		feedback.text = L10n.text("Clear floor 5 to unlock the elevator")
		return
	var destination := Layout.approach(mover, targets[id].body - Vector3(0, 0.28, 0))
	if not mover.set_target_position(destination):
		feedback.text = L10n.text("Can't reach that spot")
		return
	pending_target = id
	feedback.text = L10n.text("Walking...")

func _process(delta: float) -> void:
	if mover == null: return
	if _focused and not _camera_modal_open() and not _rescued:
		camera_pan.step(delta, cam)
	var frozen := _paused or not _focused or (bag_sheet and bag_sheet.visible) or busy or _connection_blocked() or _combat_stalled() or _predicted_defeat() or _rescued or _exit_after_combat
	combat.step(delta, mover, frozen)
	_sync_weapon_visibility()
	attack_progress.value = 1.0 - clampf(combat.cooldown * float(combat.weapon(session.state if session else {}).get("speed", 1)), 0, 1)
	player.visible = _rescued or combat.invulnerability <= 0 or int(Time.get_ticks_msec() / 90) % 2 == 0
	if frozen:
		if _combat_stalled(): feedback.text = L10n.text("Syncing combat...")
		_update_camera()
		return
	mover.speed = CharacterModel.current(session.state, "move_speed")
	var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if keyboard != Vector2.ZERO:
		_cancel_dig()
		mover.set_joystick(_camera_direction(keyboard.limit_length()))
	elif stick.vector != Vector2.ZERO:
		mover.set_joystick(_camera_direction(stick.vector))
	elif mover.joystick != Vector2.ZERO:
		mover.set_joystick(Vector2.ZERO)
	if (_attack_held or Input.is_physical_key_pressed(KEY_SPACE)) and combat.cooldown <= 0: _attack()
	if busy: return
	if not _pending_hurt.is_empty() and not busy:
		_resolve_combat([])
	var arrived_this_frame := false
	mover.step(delta)
	player.position = mover.position
	if mover.is_moving():
		player.look_at(player.position + mover.facing, Vector3.UP)
		_play("run")
	elif not pending_target.is_empty() and not busy:
		var target := pending_target
		pending_target = ""
		_arrived(target)
		arrived_this_frame = true
	elif _dig_target.is_empty():
		_play("idle")
	if not _dig_target.is_empty() and not busy and not arrived_this_frame:
		_dig_elapsed += maxf(0, delta)
		var duration := CharacterModel.gather_seconds(session.state if session else {}, "ore", DIG_SECONDS)
		progress.max_value = duration
		progress.value = _dig_elapsed
		if _dig_elapsed >= duration:
			var target := _dig_target
			_dig_target = ""
			_mine_rock(target)
	_update_camera()

func _arrived(id: String) -> void:
	if not targets.has(id): return
	if id.begins_with("rock_"):
		_dig_target = id
		_dig_elapsed = 0.0
		var point: Vector3 = targets[id].body
		player.look_at(Vector3(point.x, player.position.y, point.z), Vector3.UP)
		_play(AnimPlaceholders.clip_for("till"))
		feedback.text = L10n.text("Mining...")
		_refresh()
	elif id == "up":
		if current_floor() == 1: _leave()
		else: _command("ascend_mine", _payload())
	elif id == "down": _command("descend_mine", _payload())
	elif id == "elevator": _command("use_mine_elevator", _payload())

func _play(animation: String) -> void:
	if rig == null or _anim == animation: return
	_anim = animation
	rig.play_motion(animation)

func _payload() -> Dictionary:
	return {"run": int(mine_state().get("run", 0)), "floor": current_floor()}

func _command(type: String, payload: Dictionary) -> bool:
	if session == null or busy or _has_combat_pending(): return false
	busy = true
	pending_target = ""
	mover.stop()
	_refresh()
	var accepted := await session.send(type, payload)
	busy = false
	progress.value = 0
	feedback.text = "" if accepted else error_text(session.last_error_code)
	_refresh()
	return accepted

func _mine_rock(id: String) -> void:
	var payload := _payload()
	payload.node_id = id
	var was_unlocked := bool(mine_state().get("elevator_unlocked", false))
	if await _command("mine_rock", payload):
		var drop: Dictionary = mine_state().get("last_drop", {})
		var parts: Array[String] = []
		for item in drop.get("materials", {}):
			parts.append(L10n.format_text("+%d %s", [int(drop.materials[item]), L10n.item_name(str(item))]))
		feedback.text = " / ".join(parts)
		if not was_unlocked and mine_state().get("elevator_unlocked", false):
			feedback.text += "\n" + L10n.text("Five floors cleared. Elevator unlocked!")
		elif cleared() and current_floor() < 5:
			feedback.text += "\n" + L10n.text("The ladder is clear")

func _primary_action() -> void:
	if _rescued:
		_finish_rescue()
		return
	if current_floor() == 0:
		_enter()
		return
	if not _can_act() or _has_combat_pending(): return
	if cleared():
		if current_floor() == 5: _leave()
		else: select_target("down")
		return
	var nearest := INF
	var id := ""
	for target in targets:
		if not str(target).begins_with("rock_"): continue
		var distance := mover.position.distance_to(targets[target].body)
		if distance < nearest:
			nearest = distance
			id = target
	if not id.is_empty(): select_target(id)

func _enter() -> void:
	if not is_inside_tree() or session == null or busy or _leaving or current_floor() > 0: return
	if session.offline or session.has_unconfirmed_command(): return
	# Only an exhausted mine rolls over automatically; an elevator-only trip keeps its other rocks.
	if fully_cleared():
		if not await _command("restart_mine", {"run": int(mine_state().get("run", 0))}): return
	if not is_inside_tree() or _leaving or current_floor() > 0: return
	if await _command("enter_mine", {"run": int(mine_state().get("run", 0))}):
		feedback.text = L10n.text("The mine is quiet")

func _restart() -> void:
	if session == null or busy or _leaving or current_floor() not in [0, 1] or not completed(): return
	if session.offline or session.has_unconfirmed_command(): return
	if current_floor() == 1:
		if not await _command("leave_mine", _payload()): return
	if await _command("restart_mine", {"run": int(mine_state().get("run", 0))}):
		await _enter()

func _recover() -> void:
	if session == null or busy or _combat_draining: return
	var recovering_combat: bool = session.has_unconfirmed_command() and session._unconfirmed_command.get("type") == "mine_combat"
	busy = true
	_refresh()
	var accepted := await session.refresh()
	busy = false
	if recovering_combat and current_floor() == 0 and mine_state().get("combat", {}).get("last_result", {}).get("rescued", false):
		_rescued = true
		_schedule_rescue()
	feedback.text = L10n.text("Farm synced") if accepted else L10n.text("Could not connect. Try again.")
	if _rescued: feedback.text = L10n.text("Rescued to the farm. Your items are safe.")
	_refresh()
	if accepted and current_floor() == 0 and not _leaving and not _rescued: await _enter()

func _leave() -> void:
	if bag_sheet and bag_sheet.visible:
		bag_sheet.close()
		return
	if busy or _leaving: return
	if _has_combat_pending():
		_exit_after_combat = true
		_attack_held = false
		mover.stop()
		feedback.text = L10n.text("Syncing combat...")
		return
	_leaving = true
	_dig_target = ""
	pending_target = ""
	if mover: mover.stop()
	# The command journal and mine state belong to the shared session, so local exit can preserve both.
	if session and (session.offline or session.has_unconfirmed_command()):
		AppRouter.pop_instance()
		return
	if current_floor() > 0:
		if not await _command("leave_mine", _payload()):
			if session.offline or session.has_unconfirmed_command():
				AppRouter.pop_instance()
				return
			_leaving = false
			return
	AppRouter.pop_instance()

func is_back_navigation_locked() -> bool:
	if bag_sheet and bag_sheet.consume_back(): return true
	if not busy and not _leaving: _leave.call_deferred()
	return true

func _open_bag() -> void:
	if busy or _leaving or not _dig_target.is_empty() or session == null: return
	if _has_combat_pending():
		feedback.text = L10n.text("Syncing combat...")
		return
	pending_target = ""
	_stop_camera_recenter()
	if mover: mover.stop()
	_attack_held = false
	_attack_touch_index = -1
	stick._release_stick()
	camera_pan.cancel()
	_pressed_target = null
	if bag_sheet == null:
		bag_sheet = BagSheet.new()
		bag_sheet.setup(session)
		ui.add_child(bag_sheet)
	bag_sheet.open()
	_update_focus_indicator()

func suspend() -> void:
	_stop_camera_recenter()
	_attack_held = false
	if stick: stick._release_stick()
	camera_pan.cancel()
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	canvas.visible = false
	cam.current = false
	world_env.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	canvas.visible = true
	get_viewport().transparent_bg = false
	world_env.environment = environment
	cam.make_current()
	_refresh()

static func error_text(code: String) -> String:
	var messages := {"ALREADY_CLAIMED": "This rock has already been mined", "NOT_AVAILABLE": "The mine floor changed. Reconnect to continue."}
	return L10n.text(messages[code]) if messages.has(code) else SessionPanel.error_text(code)

func _cancel_dig() -> void:
	pending_target = ""
	_dig_target = ""
	_dig_elapsed = 0
	progress.value = 0

func _stick_changed(vector: Vector2) -> void:
	if mover == null: return
	if vector == Vector2.ZERO:
		mover.set_joystick(vector)
		return
	if busy or _paused or not _focused or _connection_blocked() or _combat_stalled() or _predicted_defeat(): return
	var was_digging := not _dig_target.is_empty()
	_cancel_dig()
	mover.set_joystick(_camera_direction(vector))
	if was_digging: _refresh()

func _camera_direction(vector: Vector2) -> Vector2:
	# Preserve screen-relative controls after adopting the farm's diagonal view.
	var right := cam.global_basis.x
	var down := cam.global_basis.z
	right.y = 0
	down.y = 0
	var direction := right.normalized() * vector.x + down.normalized() * vector.y
	return Vector2(direction.x, direction.z)

func _attack(target_id := "") -> void:
	if combat == null or busy or _paused or not _focused or _rescued or current_floor() <= 0 or _connection_blocked() or _combat_stalled() or _predicted_defeat() or _exit_after_combat or (bag_sheet and bag_sheet.visible): return
	if combat.cooldown > 0: return
	if combat.weapon(session.state).is_empty():
		feedback.text = L10n.text("Equip a weapon first")
		return
	_cancel_dig()
	var hit: Array[String] = combat.swing(session.state, mover, target_id)
	_sync_weapon_visibility()
	player.look_at(player.position + mover.facing, Vector3.UP)
	if not hit.is_empty() or not _pending_hurt.is_empty(): _resolve_combat(hit)

func _sync_weapon_visibility() -> void:
	if is_instance_valid(_weapon_model):
		_weapon_model.visible = combat._swing_left > 0 and _can_act() and not _exit_after_combat and not _leaving

func _resolve_combat(hit: Array) -> void:
	if busy or session == null: return
	var payload := _payload()
	payload.targets = hit
	var hurt_by := _pending_hurt
	_pending_hurt = ""
	if not hurt_by.is_empty(): payload.hurt_by = hurt_by
	payload.created_ms = Time.get_ticks_msec()
	_cancel_dig()
	var before_hp := CharacterModel.hp(_combat_view)
	prediction.pending.append(payload)
	_refresh()
	var hurt := before_hp - CharacterModel.hp(_combat_view)
	if hurt > 0: combat.hurt(mover, hurt_by, hurt)
	_drain_combat()

func _connection_blocked() -> bool:
	return session == null or session.offline or (session.has_unconfirmed_command() and not _combat_sending)

func _has_combat_pending() -> bool:
	return _combat_draining or not prediction.pending.is_empty()

func _combat_stalled() -> bool:
	return not prediction.pending.is_empty() and (prediction.pending.size() >= MAX_PENDING_COMBAT or Time.get_ticks_msec() - int(prediction.pending[0].created_ms) > MAX_COMBAT_LAG_MS)

func _predicted_defeat() -> bool:
	return not prediction.pending.is_empty() and CharacterModel.hp(_combat_view) <= 0

func _drain_combat() -> void:
	if _combat_draining: return
	_combat_draining = true
	while not prediction.pending.is_empty() and is_inside_tree():
		var payload := prediction.payload(session.state)
		if payload.is_empty():
			prediction.pending.pop_front()
			_refresh()
			continue
		var interval := ceili(1000.0 / float(combat.weapon(session.state).get("speed", 1))) + 30
		var deadline := _last_attack_sent_ms + interval if not payload.targets.is_empty() else 0
		if payload.has("hurt_by"): deadline = maxi(deadline, _last_hurt_sent_ms + int(Layout.data().combat.invulnerability_ms) + 30)
		var wait_ms := deadline - Time.get_ticks_msec()
		if wait_ms > 0:
			await get_tree().create_timer(wait_ms / 1000.0).timeout
			if not is_inside_tree(): return
		var accepted := false
		for attempt in 2:
			_combat_sending = true
			if not payload.targets.is_empty(): _last_attack_sent_ms = Time.get_ticks_msec()
			if payload.has("hurt_by"): _last_hurt_sent_ms = Time.get_ticks_msec()
			accepted = await session.send("mine_combat", payload)
			_combat_sending = false
			if not is_inside_tree(): return
			if accepted or session.offline or session.has_unconfirmed_command(): break
			if session.last_error_code != "NOT_AVAILABLE" or attempt > 0: break
			# Receipt-time cooldowns can race under network jitter; refresh before one bounded retry.
			_combat_sending = true
			var refreshed := await session.refresh()
			_combat_sending = false
			if not is_inside_tree(): return
			if not refreshed: break
			payload = prediction.payload(session.state)
			if payload.is_empty(): break
			await get_tree().create_timer(maxi(interval, int(Layout.data().combat.invulnerability_ms)) / 1000.0).timeout
			if not is_inside_tree(): return
		if not accepted:
			prediction.pending.clear()
			feedback.text = error_text(session.last_error_code)
			if not session.offline and not session.has_unconfirmed_command(): await session.refresh()
			if not is_inside_tree(): return
			if current_floor() == 0 and mine_state().get("combat", {}).get("last_result", {}).get("rescued", false):
				_rescued = true
				_schedule_rescue()
			break
		prediction.pending.pop_front()
		var result: Dictionary = mine_state().get("combat", {}).get("last_result", {})
		var rewards: Array[String] = []
		var loot: Dictionary = result.get("loot", result.get("materials", {}))
		for item in loot: rewards.append(L10n.format_text("+%d %s", [int(loot[item]), L10n.item_name(str(item))]))
		if not rewards.is_empty(): feedback.text = " / ".join(rewards)
		if result.get("rescued", false):
			prediction.pending.clear()
			_rescued = true
			_schedule_rescue()
			break
		_refresh()
		if cleared():
			var opened := L10n.text("Five floors cleared. Elevator unlocked!" if current_floor() == 5 else "The ladder is clear")
			feedback.text = (" / ".join(rewards) + "\n" if not rewards.is_empty() else "") + opened
	_combat_draining = false
	if not is_inside_tree(): return
	if _rescued: return
	_refresh()
	if _exit_after_combat:
		_exit_after_combat = false
		_leave.call_deferred()

func _schedule_rescue() -> void:
	_stop_camera_recenter()
	_attack_held = false
	_attack_touch_index = -1
	_pending_hurt = ""
	_cancel_dig()
	mover.stop()
	stick._release_stick()
	camera_pan.cancel()
	if _rescue_scheduled: return
	_rescue_scheduled = true
	_finish_rescue.call_deferred()

func _finish_rescue() -> void:
	if not is_inside_tree() or not _rescued or current_floor() != 0: return
	if AppRouter._navigation_pending:
		await get_tree().process_frame
		_finish_rescue.call_deferred()
		return
	if AppRouter.top_instance() != self: return
	var router := AppRouter
	router.pop_instance()
	var farm := router.top_instance()
	if farm and farm.has_method("show_mine_rescue"): farm.show_mine_rescue()

func _sync_combat_targets() -> void:
	if combat == null: return
	for id in targets.keys():
		if str(id).begins_with("slime_") and not combat.enemies.has(id):
			targets[id].button.queue_free()
			targets.erase(id)
	for id in combat.enemies:
		var enemy: Dictionary = combat.enemies[id]
		var point: Vector3 = enemy.node.position
		if not targets.has(id):
			_add_target(id, L10n.text(str(enemy.spec.name)), "", point + Vector3.UP, point, enemy.node.get_node("Body"))
		targets[id].body = point + Vector3(0, 0.3, 0)
		targets[id].world = point + Vector3.UP
		targets[id].model = enemy.node.get_node("Body")
