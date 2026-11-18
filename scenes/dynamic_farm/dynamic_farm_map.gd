extends Control
## Separate farm-dev art entry. No account, claim, choose_home or old-farm state writes.
const Api := preload("res://modules/dynamic_farm/map/geo_api.gd")
const Selection := preload("res://modules/dynamic_farm/map/selection_controller.gd")
const CameraInput := preload("res://modules/dynamic_farm/map/geo_native_camera.gd")
const AndroidBridge := preload("res://scenes/map_poc/map_bridge_android.gd")
const CONFIG := "res://modules/dynamic_farm/map/config.json"
const HOST := "res://scenes/dynamic_farm/dynamic_farm_host.tscn"
var _selector: Node
var _camera: Control
var _bridge: MapBridge
var _hud: Control
var _message: Label
var _details: Label
var _open: Button
var _retry: Button
var _choices: OptionButton
var _candidate_ids: Array[String] = []
var _framed := false
var _leaving := false
var _opening := false
var _suspended := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# The isolated build must set this BEFORE Net's autoload _ready, not from this scene.
	if not bool(ProjectSettings.get_setting("sensen/network/online_qa", false)):
		_message.text = "Use the isolated Dynamic Farm preview build."; return
	var parser := JSON.new()
	if not FileAccess.file_exists(CONFIG) or parser.parse(FileAccess.get_file_as_string(CONFIG)) != OK or not parser.data is Dictionary:
		_message.text = "This preview service is not configured."; return
	var token := FileAccess.get_file_as_string("res://mapbox_token.txt").strip_edges() if FileAccess.file_exists("res://mapbox_token.txt") else ""
	if not Engine.has_singleton("GodotMap") or token.is_empty():
		_message.text = "This preview needs the Android parcel map."; return
	_bridge = AndroidBridge.new()
	_camera = CameraInput.new(); add_child(_camera); move_child(_camera, 0)
	_selector = Selection.new(); _selector.config = parser.data; _selector.bridge = _bridge
	var api := Api.new(); add_child(api); _selector.api = api; add_child(_selector)
	_selector.changed.connect(_render)
	_selector.candidates_found.connect(_show_candidates)
	_selector.farm_ready.connect(_open_host)
	_camera.tapped.connect(func(point: Vector2): _selector.tap(point, _camera.zoom))
	_camera.camera_changed.connect(_selector.camera_changed)
	_camera.setup_map(_bridge, token)
	_selector.activate()

func _build_ui() -> void:
	_hud = Control.new(); _hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_hud)
	var top := _panel(false)
	top.add_child(_label("Dynamic Farm", 20))
	_message = _label("Loading dynamic farm map…", 14); top.add_child(_message)
	var row := HBoxContainer.new(); top.add_child(row)
	_retry = _button("Retry", _retry_map); _retry.disabled = true; row.add_child(_retry)
	row.add_child(_button("San Francisco", _reset_area))
	row.add_child(_button("Back", _leave))
	var bottom := _panel(true)
	_details = _label("Choose a parcel to explore in 3D.", 16); bottom.add_child(_details)
	_choices = OptionButton.new(); _choices.custom_minimum_size.y = 44; _choices.hide()
	_choices.item_selected.connect(func(index: int):
		if index >= 0 and index < _candidate_ids.size():
			_selector.choose(_candidate_ids[index]); _choices.hide())
	bottom.add_child(_choices)
	_open = _button("Preview in 3D", _preview); _open.disabled = true; bottom.add_child(_open)
	bottom.add_child(_label("Explore and walk. Farming actions come later.", 12))
	var credits := HBoxContainer.new(); bottom.add_child(credits)
	for item in [["© Mapbox", "https://www.mapbox.com/about/maps/"], ["© OpenStreetMap", "https://www.openstreetmap.org/copyright"]]:
		var credit := _button(item[0], OS.shell_open.bind(item[1])); credit.flat = true; credits.add_child(credit)
	bottom.add_child(_label("Parcels: DataSF · PDDL / CC0", 10))

func _panel(bottom: bool) -> VBoxContainer:
	var panel := PanelContainer.new(); _hud.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
	panel.offset_left = 12; panel.offset_right = -12
	if bottom: panel.offset_bottom = -24; panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else: panel.offset_top = 28
	var style := StyleBoxFlat.new(); style.bg_color = Color("FBF8F1")
	style.set_corner_radius_all(12); style.set_content_margin_all(12); panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 8); panel.add_child(column)
	return column

func _label(text: String, font_size: int) -> Label:
	var label := Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color", Color("263E31")); label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new(); button.text = text; button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; button.pressed.connect(action)
	return button

func _render() -> void:
	if _selector == null or _suspended or _leaving: return
	if not _framed and not _selector.manifest.is_empty():
		_framed = true; _reset_area()
	_message.text = _selector.message
	_retry.disabled = _selector.busy or _opening
	_open.disabled = _selector.busy or not _selector.map_ready or _selector.selection.is_empty() or _opening
	_camera.input_enabled = not _selector.busy and not _opening
	if _selector.selection.is_empty(): _details.text = "Choose a parcel to explore in 3D."
	else:
		var p: Dictionary = _selector.selection
		_details.text = "%s\n%d core · %d walk-only extension cells" % [p.name, p.core_cell_count, p.extension_cell_count]
	if _selector._options.is_empty(): _choices.hide()

func _show_candidates(rows: Array) -> void:
	_choices.clear(); _candidate_ids.clear()
	for row in rows.slice(0, 6):
		_candidate_ids.append(row.block_id); _choices.add_item(row.name)
	_choices.select(-1); _choices.show()

func _reset_area() -> void:
	if _selector == null or _selector.busy or _selector.manifest.is_empty() or _opening: return
	var native: Dictionary = _selector.manifest.native_map
	_camera.frame_center(float(native.center[0]), float(native.center[1]), clampf(float(native.get("initial_zoom", 17.5)), 13, 21))

func _retry_map() -> void:
	if _selector != null and not _selector.busy and not _opening: _selector.activate()

func _preview() -> void:
	if _selector != null and not _opening: _selector.open_farm()

func _open_host(farm: Dictionary) -> void:
	if _leaving or _suspended or _opening: return
	var router := get_node_or_null("/root/AppRouter")
	if router == null or not router.has_method("open_instance"):
		_message.text = "This preview is missing its scene router."; return
	_opening = true; _render()
	await router.open_instance(HOST, {"farm": farm, "dataset": farm.dataset_version, "block_id": farm.block_id,
		"preview_only": true, "return_context": {"center": Array(_camera.center), "zoom": _camera.zoom}})
	_opening = false
	if not _suspended: _render()

func suspend() -> void:
	_suspended = true
	if _selector != null: _selector.pause()
	_hud.hide(); process_mode = Node.PROCESS_MODE_DISABLED

func resume() -> void:
	if _leaving: return
	_suspended = false; process_mode = Node.PROCESS_MODE_INHERIT; _hud.show()
	if _bridge != null:
		get_viewport().transparent_bg = true; _bridge.set_map_visible(true); _camera._changed()
	if _selector != null: _selector.activate()

func _leave() -> void:
	if _leaving or _opening: return
	_leaving = true
	suspend()
	_finish_leave.call_deferred()

func _finish_leave() -> void:
	var router := get_node_or_null("/root/AppRouter")
	if router != null and router.top_instance() == self: router.pop_instance()
	elif _bridge != null and _bridge.move_task_to_back():
		_leaving = false
		# Remain paused until APPLICATION_RESUMED, rather than reloading behind the departing task.
	else: _quit_preview()

func _quit_preview() -> void:
	get_tree().quit()

func is_back_navigation_locked() -> bool:
	_leave(); return true

func _notification(what: int) -> void:
	if not is_node_ready() or _selector == null: return
	if what == NOTIFICATION_APPLICATION_PAUSED and not _suspended: suspend()
	elif what == NOTIFICATION_APPLICATION_RESUMED and _suspended:
		var router := get_node_or_null("/root/AppRouter")
		if router == null or router.top_instance() in [null, self]: resume()
