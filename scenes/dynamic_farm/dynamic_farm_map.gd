extends Control
## Dynamic farm map. Its only server write is the C-32 first-home claim (and, in internal test packages,
## giving that home up); no choose_home or old-farm state writes.
const Api := preload("res://modules/dynamic_farm/map/geo_api.gd")
const Selection := preload("res://modules/dynamic_farm/map/selection_controller.gd")
const CameraInput := preload("res://modules/dynamic_farm/map/geo_native_camera.gd")
const Claims := preload("res://modules/dynamic_farm/map/claim_controller.gd")
const ClaimApi := preload("res://modules/dynamic_farm/map/claim_api.gd")
const FakeParcelServer := preload("res://modules/dynamic_farm/map/fake_parcel_server.gd")
const AndroidBridge := preload("res://scenes/map_poc/map_bridge_android.gd")
const CONFIG := "res://modules/dynamic_farm/map/config.json"
const HOST := "res://scenes/dynamic_farm/dynamic_farm_host.tscn"
const ACCOUNT_PANEL := "res://scenes/account/account_panel.gd"
const OCCLUSION_COLOR := "#E7F0DF" # Existing scene BG_COLOR(.906, .941, .875), opaque RGB.
const AREA_REFRESH_SECONDS := 0.8
## Development stand-in for the C-31 server, shared by map visits in one run.
static var _fake_server: RefCounted
var _selector: Node
var _claims: Node
var _camera: Control
var _bridge: MapBridge
var _hud: Control
var _message: Label
var _details: Label
var _open: Button
var _claim: Button
var _confirm: Control
var _enter: Button
var _reselect: Button
var _sign_in: Button
var _area_timer: Timer
var _area_generation := -1
var _retry: Button
var _choices: OptionButton
var _candidate_ids: Array[String] = []
var _framed := false
var _leaving := false
var _opening := false
var _suspended := false
var _presentation_epoch := 0
var _surface_opaque_requested := false

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
	_bridge.set_godot_surface_opaque(false) # A fresh map scene always requests the transparent mode.
	_camera = CameraInput.new(); add_child(_camera); move_child(_camera, 0)
	_selector = Selection.new(); _selector.config = parser.data; _selector.bridge = _bridge
	var api := Api.new(); add_child(api); _selector.api = api; add_child(_selector)
	_selector.changed.connect(_render)
	_claims = Claims.new(); _claims.bridge = _bridge; _claims.api = _claim_api()
	_claims.reselect = bool(ProjectSettings.get_setting("sensen/dynamic_farm/reselect", false))
	_claims.changed.connect(_render); add_child(_claims)
	_selector.candidates_found.connect(_show_candidates)
	_selector.farm_ready.connect(_open_host)
	_camera.tapped.connect(func(point: Vector2): _selector.tap(point, _camera.zoom))
	_camera.camera_changed.connect(_selector.camera_changed)
	_camera.camera_changed.connect(func(): _area_timer.start(AREA_REFRESH_SECONDS))
	_camera.setup_map(_bridge, token)
	_selector.activate()
	_start_claims()

## Isolated test builds skip Net's boot. Internal packages may reload the saved account token only
## (`sensen/dynamic_farm/account_restore`); nothing here signs in anonymously.
func _start_claims() -> void:
	var net := get_node_or_null("/root/Net")
	if net != null and not _fake_claims() and bool(ProjectSettings.get_setting("sensen/dynamic_farm/account_restore", false)):
		await net.restore_saved_account()
	if is_inside_tree() and not _suspended: _claims.start()

func _fake_claims() -> bool:
	return bool(ProjectSettings.get_setting("sensen/dynamic_farm/fake_claims", false))

func _claim_api() -> RefCounted:
	if _fake_claims():
		if _fake_server == null: _fake_server = FakeParcelServer.new()
		return ClaimApi.new(_fake_server.client(str(ProjectSettings.get_setting("sensen/dynamic_farm/fake_player", "fake-a"))))
	var net := get_node_or_null("/root/Net")
	return ClaimApi.new(net.client if net != null else null)

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
	_claim = _button("Make this my first home", func(): _confirm.show(); _render()); _claim.hide(); bottom.add_child(_claim)
	_confirm = VBoxContainer.new(); _confirm.hide(); bottom.add_child(_confirm)
	_confirm.add_child(_label("Claim this parcel? You can only have one home.", 14))
	var answer := HBoxContainer.new(); _confirm.add_child(answer)
	answer.add_child(_button("Claim", _claim_selection))
	answer.add_child(_button("Cancel", func(): _confirm.hide(); _render()))
	_enter = _button("Enter my farm", _preview); _enter.hide(); bottom.add_child(_enter)
	_open = _button("Preview in 3D", _preview); _open.disabled = true; bottom.add_child(_open)
	_reselect = _button("Give up and choose again", _abandon); _reselect.hide(); bottom.add_child(_reselect)
	_sign_in = _button("Sign in", _open_sign_in); _sign_in.hide(); bottom.add_child(_sign_in)
	_area_timer = Timer.new(); _area_timer.one_shot = true; _area_timer.timeout.connect(_refresh_area); add_child(_area_timer)
	bottom.add_child(_label("Explore and walk. Farming actions come later.", 12))
	var credits := HBoxContainer.new(); bottom.add_child(credits)
	for item in [["© Mapbox", "https://www.mapbox.com/about/maps/"], ["© OpenStreetMap", "https://www.openstreetmap.org/copyright"]]:
		var credit := _button(item[0], ExternalLink.open.bind(item[1])); credit.flat = true; credits.add_child(credit)
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
	var id := str(_selector.selection.get("block_id", ""))
	if _selector.map_ready and _selector.generation > 0:
		_claims.attach(_selector.generation, id)
		if _area_generation != _selector.generation:
			_area_generation = _selector.generation; _area_timer.start(0.1)
	var state: String = _claims.status(id)
	var idle: bool = not _selector.busy and _selector.map_ready and not _opening and not _claims.busy
	_open.disabled = not idle or id.is_empty()
	_camera.input_enabled = not _selector.busy and not _opening and not _claims.busy
	if id.is_empty(): _details.text = "Choose a parcel to explore in 3D."
	else:
		var p: Dictionary = _selector.selection
		_details.text = "%s\n%d core · %d walk-only extension cells" % [p.name, p.core_cell_count, p.extension_cell_count]
		if state == "mine": _details.text += "\nYour home"
		elif state == "other":
			var owner: String = _claims.owner_name(id)
			_details.text += ("\nClaimed by %s" % owner) if not owner.is_empty() else "\n" + Claims.NO_NAME
		elif state == "none" and _claims.has_home(): _details.text += "\nYou already have a home."
		elif state != "other" and _claims.signed_out: _details.text += "\nSign in to claim a home."
	if not _claims.message.is_empty(): _details.text += "\n" + _claims.message
	var claimable: bool = state == "none" and _claims.mine_known and not _claims.has_home()
	if not claimable or not idle: _confirm.hide()
	_claim.visible = claimable and not _confirm.visible; _claim.disabled = not idle
	_enter.visible = state == "mine"; _enter.disabled = not idle
	_open.visible = state != "mine"
	_reselect.visible = state == "mine" and _claims.reselect; _reselect.disabled = not idle
	_sign_in.visible = _claims.signed_out and not id.is_empty() and not _fake_claims(); _sign_in.disabled = not idle
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
	if _selector != null and not _selector.busy and not _opening: _selector.retry()

func _preview() -> void:
	if _selector != null and not _opening: _selector.open_farm()

func _claim_selection() -> void:
	_confirm.hide()
	if _selector != null and not _selector.selection.is_empty(): _claims.claim(_selector.selection)

func _open_sign_in() -> void:
	if _claims == null or find_children("*", "AccountPanel", true, false).size() > 0: return
	# Loaded at run time: the panel uses the Net autoload, which scripts preloading this scene may not have yet.
	var panel: CanvasLayer = load(ACCOUNT_PANEL).open(self, "sign_in")
	_camera.input_enabled = false
	var signed_in: bool = await panel.closed
	if not is_inside_tree(): return
	if signed_in: _claims.forget()
	_render()

func _abandon() -> void:
	if _claims != null: _claims.abandon()

func _refresh_area() -> void:
	if _selector == null or _suspended or not _selector.map_ready or _selector.manifest.is_empty(): return
	if _camera.zoom < float(_selector.manifest.native_map.get("minzoom", 16)): return
	var corner: PackedFloat64Array = _camera.screen_geo(Vector2.ZERO)
	var opposite: PackedFloat64Array = _camera.screen_geo(_camera.size)
	var bbox := [minf(corner[0], opposite[0]), minf(corner[1], opposite[1]), maxf(corner[0], opposite[0]), maxf(corner[1], opposite[1])]
	if bbox[2] - bbox[0] <= ClaimApi.MAX_BBOX_SPAN and bbox[3] - bbox[1] <= ClaimApi.MAX_BBOX_SPAN: _claims.refresh_area(bbox)

func _open_host(farm: Dictionary) -> void:
	if _leaving or _suspended or _opening: return
	if _bridge == null or not _bridge.supports_surface_opacity() or not _bridge.set_map_occlusion_color(OCCLUSION_COLOR):
		_render()
		_message.text = "Use the latest Dynamic Farm preview build."; return
	var router := get_node_or_null("/root/AppRouter")
	if router == null or not router.has_method("open_instance"):
		_message.text = "This preview is missing its scene router."; return
	_opening = true; _render()
	await router.open_instance(HOST, {"farm": farm, "dataset": farm.dataset_version, "block_id": farm.block_id,
		"preview_only": true, "return_context": {"center": Array(_camera.center), "zoom": _camera.zoom}})
	_opening = false
	if not _suspended:
		# Loading cancelled/failed before a host became top, or Back already returned here.
		_restore_surface_mode()
		_render()

func suspend() -> void:
	# AppRouter invokes this when it actually pushes another scene.
	_suspend_map(_opening)

func _suspend_map(committing_preview: bool) -> void:
	_suspended = true
	_presentation_epoch += 1
	get_viewport().transparent_bg = false
	if _bridge != null: _bridge.set_map_occlusion_color(OCCLUSION_COLOR)
	if committing_preview and _bridge != null:
		_surface_opaque_requested = _bridge.set_godot_surface_opaque(true)
	if _selector != null: _selector.pause()
	if _claims != null: _claims.pause()
	_hud.hide(); process_mode = Node.PROCESS_MODE_DISABLED
	_record_presentation("covered", _presentation_epoch)

func resume() -> void:
	if _leaving: return
	_suspended = false; process_mode = Node.PROCESS_MODE_INHERIT; _hud.show()
	_presentation_epoch += 1
	if _bridge != null:
		get_viewport().transparent_bg = true
		_restore_surface_mode()
		_bridge.set_map_visible(true); _camera._changed()
	if _selector != null: _selector.activate()
	if _claims != null: _claims.start()
	_record_presentation("map", _presentation_epoch)

func _restore_surface_mode() -> void:
	if _surface_opaque_requested and _bridge != null:
		_bridge.set_godot_surface_opaque(false)
	_surface_opaque_requested = false

func _record_presentation(stage: String, epoch: int) -> void:
	if _bridge == null: return
	_bridge.map_visibility_state() # Ask UI thread to refresh; its old return value is not an ACK.
	await get_tree().create_timer(0.2).timeout
	if not is_inside_tree() or epoch != _presentation_epoch: return
	var parser := JSON.new()
	var native: Dictionary = {}
	if parser.parse(_bridge.map_visibility_state()) == OK and parser.data is Dictionary: native = parser.data
	var state := {"stage": stage, "viewport_transparent": get_viewport().transparent_bg, "surface_opaque_requested": _surface_opaque_requested, "native": native}
	var router := get_node_or_null("/root/AppRouter")
	var top = router.top_instance() if router != null else null
	if is_instance_valid(top) and top.has_method("presentation_state"): state["host"] = top.presentation_state()
	# No parcel, player, credential or coordinates. Snapshot freshness is sample_uptime_ms, not a frame guarantee.
	print("DYNAMIC_MAP_PRESENTATION ", JSON.stringify(state))

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
	if what == NOTIFICATION_APPLICATION_PAUSED and not _suspended: _suspend_map(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED and _suspended:
		var router := get_node_or_null("/root/AppRouter")
		if router == null or router.top_instance() in [null, self]: resume()
		else: _record_presentation("covered_foreground", _presentation_epoch)
