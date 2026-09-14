extends Node3D

var place_id := ""
var session: FarmSession
var cam: Camera3D
var world_env: WorldEnvironment
var canvas: CanvasLayer
var root: Control
var content: VBoxContainer
var scroll: ScrollContainer
var tabs: HBoxContainer
var status: Label
var feedback: Label
var body: PanelContainer
var scenery: Node3D
var _environment: Environment
var _args: Dictionary
var _exit: Button
var active_panel: SessionPanel
var selected_tab := L10n.text("people")
var _tab_buttons: Dictionary = {}
var _cast: Node3D
var _cast_key := ""
var _scenery_key := ""
var _decorations: Node3D
var _decoration_key := ""
var _navigation_target := ""
var _pointer_id := -2
var _pointer_start := Vector2.ZERO
var _pointer_dragged := false
var photo: WeekPhoto
var journey_scene: JourneyPlace

func setup(args: Dictionary) -> void:
	_args = args
	place_id = str(args.get("place_id", ""))
	session = args.get("session")
	selected_tab = str(args.get("tab", L10n.text("people")))

func _ready() -> void:
	if session == null or not PlaceCatalog.available(place_id, session.state):
		call_deferred("_leave")
		return
	if JourneyProgress.active(session.state):
		journey_scene = JourneyPlace.new()
		journey_scene.place_id = place_id
		journey_scene.session = session
		journey_scene.initial_target = str(_args.get("target", ""))
		add_child(journey_scene)
		return
	_build_world()
	_build_ui()
	session.state_changed.connect(_state_changed)
	_refresh()

func _build_world() -> void:
	get_viewport().transparent_bg = false
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("dcebd4")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("e7f2eb")
	_environment.ambient_light_energy = 0.65
	world_env = WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new()
	cam.position = Vector3(8, 10, 12)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 13
	add_child(cam)
	cam.look_at(Vector3(0, 0, 1))
	cam.make_current()
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)
	var safe := SafeAreaMargin.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.theme = GameUi.theme()
	canvas.add_child(safe)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)
	root.resized.connect(_layout)
	var head := HBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	_exit = GameUi.button("arrow-left", "", L10n.text("Back to map"))
	_exit.pressed.connect(_leave)
	head.add_child(_exit)
	var title := GameUi.label(L10n.text(str(PlaceCatalog.find(place_id).name)), 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title)
	body = PanelContainer.new()
	root.add_child(body)
	var col := VBoxContainer.new()
	body.add_child(col)
	tabs = HBoxContainer.new()
	col.add_child(tabs)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	feedback = GameUi.label("", 12, GameUi.INK)
	feedback.name = "PlaceFeedback"
	feedback.custom_minimum_size.y = 32
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(feedback)
	status = GameUi.label("", 12, GameUi.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)
	_build_tabs()
	call_deferred("_layout")

func _build_tabs() -> void:
	var specs: Array = [[L10n.text("people"), "users-round", L10n.text("Residents")], ["choices", "heart", L10n.text("Harvest uses")]]
	if place_id == "nursery": specs.append(["project", "shopping-basket", L10n.text("Nursery project")])
	if place_id == "courtyard":
		specs.append(["growth", "shovel", L10n.text("Growth choice")])
		specs.append(["decorations", "house", L10n.text("Courtyard pieces")])
	if place_id == "bistro": specs.append(["kitchen", "utensils", L10n.text("Kitchen")])
	specs.append(["events", "calendar-days", L10n.text("Neighbourhood stories")])
	specs.append(["journal", "book-open", L10n.text("Handbook")])
	for spec in specs:
		var button := GameUi.button(spec[1], "", spec[2])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): select_tab(spec[0]))
		tabs.add_child(button)
		_tab_buttons[spec[0]] = button
	select_tab(selected_tab)

func select_tab(id: String) -> void:
	if not _tab_buttons.has(id): return
	if id == selected_tab and active_panel != null: return
	if active_panel and active_panel.busy: return
	if active_panel is DecorationPanel:
		_navigation_target = id
		if (active_panel as DecorationPanel).request_leave(): return
	_navigation_target = ""
	_activate_tab(id)

func _activate_tab(id: String) -> void:
	selected_tab = id
	_pointer_id = -2
	scroll.scroll_vertical = 0
	feedback.text = ""
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	active_panel = null
	var path := "res://scenes/place/resident_panel.gd" if id == L10n.text("people") else "res://scenes/place/economy_panel.gd"
	if id in ["kitchen", "journal"]: path = "res://scenes/place/kitchen_panel.gd"
	if id == "decorations": path = "res://scenes/place/decoration_panel.gd"
	if id == "events": path = "res://scenes/place/events_panel.gd"
	if ResourceLoader.exists(path):
		active_panel = load(path).new()
		active_panel.message = feedback
		if id in [L10n.text("people"), "events"]: active_panel.place_id = place_id
		elif id != "decorations": active_panel.section = id
		if id == "people": active_panel.selected_resident = str(_args.get("resident_id", ""))
		active_panel.setup(session)
		if active_panel.has_signal("gift_requested"):
			active_panel.connect("gift_requested", _visit_resident)
		if id == "events":
			active_panel.connect("navigation_requested", _event_navigate)
			active_panel.connect("photo_requested", _open_photo)
		if active_panel is DecorationPanel:
			var decorations := active_panel as DecorationPanel
			decorations.preview_changed.connect(_preview_decorations)
			decorations.navigation_confirmed.connect(_finish_decoration_navigation)
			decorations.navigation_cancelled.connect(func(): _navigation_target = "")
		content.add_child(active_panel)
	else:
		var intro := GameUi.label(str(PlaceCatalog.find(place_id).intro), 15)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(intro)
	for key in _tab_buttons:
		_tab_buttons[key].theme_type_variation = &"TabSelectedButton" if key == id else &"TabButton"
	_refresh_decorations()

func _finish_decoration_navigation() -> void:
	var target := _navigation_target
	_navigation_target = ""
	if target == "back": AppRouter.pop_instance()
	elif _tab_buttons.has(target): _activate_tab(target)

func _preview_decorations(props: Array) -> void:
	var selected := (active_panel as DecorationPanel).selected_prop if active_panel is DecorationPanel else ""
	_render_decorations(props, selected)

func _refresh_decorations() -> void:
	if place_id != "courtyard" or session == null: return
	if active_panel is DecorationPanel:
		_preview_decorations((active_panel as DecorationPanel).preview())
	else:
		_render_decorations(DecorationLayout.saved(session.state))

func _render_decorations(props: Array, selected := "") -> void:
	if place_id != "courtyard": return
	var key := JSON.stringify([props, selected])
	if key == _decoration_key: return
	_decoration_key = key
	if _decorations:
		remove_child(_decorations)
		_decorations.queue_free()
	_decorations = DecorationLayout.build(props, selected)
	add_child(_decorations)

func _unhandled_input(event: InputEvent) -> void:
	if not active_panel is DecorationPanel: return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_id == -2 and _decoration_world_area().has_point(event.position):
				_pointer_id = event.index
				_pointer_start = event.position
				_pointer_dragged = false
		elif _pointer_id == event.index:
			if not event.canceled and not _pointer_dragged and _pointer_start.distance_to(event.position) < 14:
				decoration_tap(event.position)
			_pointer_id = -2
		else: return
	elif event is InputEventScreenDrag:
		if _pointer_id != event.index: return
		_pointer_dragged = _pointer_dragged or _pointer_start.distance_to(event.position) >= 14
	elif event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION or event.button_index != MOUSE_BUTTON_LEFT: return
		if event.pressed:
			if not _decoration_world_area().has_point(event.position): return
			_pointer_id = -1
			_pointer_start = event.position
			_pointer_dragged = false
		elif _pointer_id == -1:
			if not _pointer_dragged and _pointer_start.distance_to(event.position) < 14:
				decoration_tap(event.position)
			_pointer_id = -2
		else: return
	elif event is InputEventMouseMotion:
		if _pointer_id != -1: return
		_pointer_dragged = _pointer_dragged or _pointer_start.distance_to(event.position) >= 14
	else: return
	get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _pointer_id == -2: return
	# A release over GUI never reaches _unhandled_input; clear its world gesture here.
	if event is InputEventScreenTouch and not event.pressed and event.index == _pointer_id:
		if event.canceled or not _decoration_world_area().has_point(event.position): _pointer_id = -2
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _decoration_world_area().has_point(event.position): _pointer_id = -2

func _decoration_world_area() -> Rect2:
	if body == null: return Rect2()
	return Rect2(12, 72, get_viewport().get_visible_rect().size.x - 24, maxf(0, body.global_position.y - 84))

func decoration_tap(screen: Vector2) -> bool:
	if not active_panel is DecorationPanel or cam == null or not _decoration_world_area().has_point(screen): return false
	var point = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if not point is Vector3: return false
	var panel := active_panel as DecorationPanel
	return panel.pick_at(point) or panel.place_at(point)

func _visit_resident(resident: String) -> void:
	var destination := {"nursery_keeper": "nursery", "bistro_owner": "bistro", "restorer": "courtyard"}
	if str(destination.get(resident, "")) == place_id:
		select_tab(L10n.text("people"))
		if active_panel is ResidentPanel: active_panel._select(resident)
	else:
		AppRouter.open_instance(AppRouter.PLACE, {"place_id": destination.get(resident, "nursery"), "session": session, "resident_id": resident})

func _event_navigate(destination: String, tab: String) -> void:
	if destination == place_id:
		select_tab(tab)
	elif destination == "map":
		while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	elif destination == "farm":
		AppRouter.open_instance(AppRouter.FARM, {"session": session})
	else:
		AppRouter.open_instance(AppRouter.PLACE, {"place_id": destination, "tab": tab, "session": session})

func _open_photo(summary: Dictionary) -> void:
	if photo != null or summary.is_empty(): return
	canvas.hide()
	if _cast: _cast.hide()
	if scenery: scenery.hide()
	if _decorations: _decorations.hide()
	photo = WeekPhoto.new()
	photo.farm_state = session.state.duplicate(true)
	photo.closed.connect(_close_photo)
	add_child(photo)

func _close_photo() -> void:
	if photo == null: return
	remove_child(photo)
	photo.queue_free()
	photo = null
	canvas.show()
	if _cast: _cast.show()
	if scenery: scenery.show()
	if _decorations: _decorations.show()
	cam.make_current()

func _layout() -> void:
	if body == null: return
	var height := minf(310, root.size.y * 0.46)
	body.position = Vector2(0, root.size.y - height)
	body.size = Vector2(root.size.x, height)
	_frame_world()

func _frame_world() -> void:
	if cam == null or not is_inside_tree(): return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x < 1 or body.global_position.y < 100: return
	var area := Rect2(12, 72, viewport_size.x - 24, body.global_position.y - 84)
	cam.position = Vector3(8, 10, 12)
	cam.look_at(Vector3.ZERO)
	cam.size = 14
	var corners: Array[Vector3] = []
	for x in [-4.6, 4.6]:
		for y in [0.0, 3.3]:
			for z in [-3.8, 3.8]: corners.append(Vector3(x, y, z))
	var bounds := Rect2(cam.unproject_position(corners[0]), Vector2.ZERO)
	for corner in corners: bounds = bounds.expand(cam.unproject_position(corner))
	cam.size *= maxf(bounds.size.x / area.size.x, bounds.size.y / area.size.y)
	bounds = Rect2(cam.unproject_position(corners[0]), Vector2.ZERO)
	for corner in corners: bounds = bounds.expand(cam.unproject_position(corner))
	var error := bounds.get_center() - area.get_center()
	var units := cam.size / viewport_size.x
	cam.position += cam.basis.x * error.x * units - cam.basis.y * error.y * units

func _state_changed(_state: Dictionary, _version: int) -> void:
	call_deferred("_refresh")

func _refresh() -> void:
	if not is_inside_tree() or session == null: return
	status.text = L10n.text("Offline") if session.offline else L10n.format_text("Chapter %d", (int(session.state.clock.chapter_index) + 1))
	var scenery_key := JSON.stringify(session.state.get("nursery", {}))
	if scenery_key != _scenery_key:
		_scenery_key = scenery_key
		if scenery:
			remove_child(scenery)
			scenery.queue_free()
		scenery = PlaceScenery.build(place_id, session.state)
		add_child(scenery)
	var cast_key := str(session.state.clock.chapter_index)
	if cast_key != _cast_key and ResourceLoader.exists("res://modules/farm/resident_cast.gd"):
		_cast_key = cast_key
		if _cast:
			remove_child(_cast)
			_cast.queue_free()
		_cast = load("res://modules/farm/resident_cast.gd").build(place_id, session.state)
		add_child(_cast)
	_refresh_decorations()

func _leave() -> void:
	if is_back_navigation_locked(): return
	AppRouter.pop_instance()

func is_back_navigation_locked() -> bool:
	if journey_scene: return journey_scene.is_back_navigation_locked()
	if photo: return photo.consume_back()
	if active_panel == null: return false
	if active_panel.busy: return true
	if active_panel is DecorationPanel: _navigation_target = "back"
	return active_panel.consume_back()

func suspend() -> void:
	if journey_scene:
		journey_scene.suspend()
		return
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	canvas.visible = false
	cam.current = false
	world_env.environment = null

func resume() -> void:
	if journey_scene:
		journey_scene.resume()
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	canvas.visible = true
	get_viewport().transparent_bg = false
	world_env.environment = _environment
	cam.make_current()
	_refresh()
