extends Control
## Dynamic farm map. Its only server write is the C-32 first-home claim (and, in internal test packages,
## giving that home up); no choose_home or old-farm state writes. Internal test packages and the invite-only
## release package (C-98) also open the player's own parcel for farming from "Enter my farm"
## (`sensen/dynamic_farm/own_farm`, C-34 Q-72); everywhere else that button opens the same read-only 3D preview.
## Two fixed entries, Market (Jasmine) and Carpenter (Scott), open over the map for a player with a home
## (C-59, C-30#29 question 1); they trade through that home's parcel save (parcel_town.gd). Like "Enter my farm"
## they are only in packages with `own_farm` (C-59#29): internal test packages and the release package (C-98).
## C-110: the map frames the player's home on entry and has a "My home" button; the account state and its
## Sign in / Sign out entry stay on the top panel whether or not a parcel is selected.
## The guide (C-35, C-61) says on the bottom card where the next step is, from the home's parcel save (ParcelGuide).
## C-112: farm-dev's camera feel (geo_native_camera.gd) and its round locate key, over the bottom card at the right;
## My home, San Francisco and the locate key fly there. Only buildings are coloured (ParcelMapController.kt).
## C-130: with the server's starter zone on, the map lands there for a player without a home (San Francisco and the
## locate key go there too), marks it with its own native layer and offers claiming only inside it.
## C-128 (0.4.4): a round profile key at the left, level with the locate key, opens the main farm's profile over the
## map, and from it Settings and the dressing room (parcel_profile.gd).
const Api := preload("res://modules/dynamic_farm/map/geo_api.gd")
const Selection := preload("res://modules/dynamic_farm/map/selection_controller.gd")
const CameraInput := preload("res://modules/dynamic_farm/map/geo_native_camera.gd")
const Claims := preload("res://modules/dynamic_farm/map/claim_controller.gd")
const ClaimApi := preload("res://modules/dynamic_farm/map/claim_api.gd")
const FakeParcelServer := preload("res://modules/dynamic_farm/map/fake_parcel_server.gd")
const Geo := preload("res://modules/dynamic_farm/map/geo_math.gd")
const AndroidBridge := preload("res://scenes/map_poc/map_bridge_android.gd")
const CONFIG := "res://modules/dynamic_farm/map/config.json"
const HOST := "res://scenes/dynamic_farm/dynamic_farm_host.tscn"
const ACCOUNT_PANEL := "res://scenes/account/account_panel.gd"
const TOWN := "res://scenes/dynamic_farm/parcel_town.gd"
const PROFILE := "res://scenes/dynamic_farm/parcel_profile.gd"
const LocalFarmStore := preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const RemoteFarmStore := preload("res://modules/dynamic_farm/parcel_farm_remote_store.gd")
const ParcelFarm := preload("res://modules/dynamic_farm/parcel_farm.gd")
const Guide := preload("res://modules/dynamic_farm/parcel_guide.gd")
const LOCAL_SAVE_SETTING := "sensen/dynamic_farm/local_farm_save"
const OCCLUSION_COLOR := "#E7F0DF" # Existing scene BG_COLOR(.906, .941, .875), opaque RGB.
const AREA_REFRESH_SECONDS := 0.8
## The bottom card's line with nothing selected (C-35: the next step in a package that enters one's own farm).
const PICK_PREVIEW := "Choose a parcel to explore in 3D."
const PICK_FIRST := "Tap a building to choose your first home."
const PICK_HOME := "Tap your green parcel, then Enter my farm."
## A Market / Carpenter entry while its town loads (C-61, C-59#135: a cold start's first open took ~10 s).
const TOWN_LOADING := "Loading…"
const TOWN_NAMES := {"market": "Market", "carpenter": "Carpenter"}
## Camera zoom when the map moves to the player's home (C-110); the parcel and its address labels show from 18.
const HOME_ZOOM := 18.0
const MY_HOME := "My home"
## The locate key: farm-dev's MapLocateButton (scenes/p0/p0_map.gd _style_locate, LOCK-24) as it is, in its place
## over the bottom card. It flies back to the player's home, or to the dataset's area without one.
const LOCATE_ICON := "res://assets/p0/icons/locate.svg"
const LOCATE_GAP := 12.0
## The profile key (C-128): the same round key at the left, with the account glyph; it opens the profile.
const PROFILE_ICON := "res://assets/ui/icons/lucide/user-round.svg"
## How long a profile tap waits for the saved outfit's parts at most (C-135), in seconds; then the profile opens all the
## same and its figure may show late or stay blank. 5 s: a cold start's load took ~3 s on the phone (C-133), and a
## stuck loader must not keep the profile and Settings out of reach. Overridden by the project setting below.
const PROFILE_WAIT_SECONDS := 5.0
const PROFILE_WAIT_SETTING := "sensen/dynamic_farm/profile_outfit_wait_seconds"
const CHECKING := "Checking your account…"
const SIGNED_IN := "Signed in as %s"
const SIGNED_IN_NO_NAME := "Signed in"
const NOT_SIGNED_IN := "Not signed in"
const SIGN_OUT_ASK := "Sign out on this phone?"
## The saved account was kept because the server could not confirm it (5xx, rate limit or no network).
const ACCOUNT_KEPT := "Can't reach the server. You're still signed in."
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
var _account_line: Label
var _account_button: Button # "Sign in" or "Sign out"
var _sign_out_confirm: Control
var _account_note: Label
var _places: Control
var _home: Button
var _locate: Button
var _bottom: Control
var _market: Button
var _carpenter: Button
var _town: Control
var _profile_button: Button
## The profile and the pages opened from it, over the map (parcel_profile.gd), else null.
var _profile: Control
## A tap on the profile key waiting for the saved outfit's parts to load (C-133); the key is held meanwhile.
var _profile_waiting := false
## The most a profile tap waits for the outfit (PROFILE_WAIT_SECONDS).
var profile_wait_seconds := float(ProjectSettings.get_setting(PROFILE_WAIT_SETTING, PROFILE_WAIT_SECONDS))
## The town that is loading after a tap on Market / Carpenter (C-61: the tap shows Loading… at once), else "".
var _town_loading := ""
## The home's parcel save as last read or seen (the guide's line) and the parcel it belongs to; read again after
## a visit to the parcel.
var home_farm := {}
var _farm_parcel := ""
var _farm_fresh := false
var _farm_reading := false
var _town_prepared := false
var _town_router: Node   # AppRouter when the preload was requested: it takes a preload the map leaves behind
var _town_script: GDScript
var _area_timer: Timer
var _area_generation := -1
var _retry: Button
var _choices: OptionButton
var _candidate_ids: Array[String] = []
var _entering := "" # Parcel whose load was started from "Enter my farm".
var _framed := false
var _leaving := false
var _opening := false
var _suspended := false
var _presentation_epoch := 0
var _surface_opaque_requested := false
var _restoring := false # Reloading the saved account before the first ownership read.
var _signing_out := false
var _framed_home := "" # Parcel the camera was moved to automatically; "" until the home is framed.
var _player_moved := false # The player moved the camera since the last account change.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_warm_outfit()
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
	_camera.user_moved.connect(func(): _player_moved = true)
	_selector = Selection.new(); _selector.config = parser.data; _selector.bridge = _bridge
	var api := Api.new(); add_child(api); _selector.api = api; add_child(_selector)
	_selector.changed.connect(_render)
	_claims = Claims.new(); _claims.bridge = _bridge; _claims.api = _claim_api()
	_claims.reselect = bool(ProjectSettings.get_setting("sensen/dynamic_farm/reselect", false))
	_claims.changed.connect(_render); add_child(_claims)
	_selector.candidates_found.connect(_show_candidates)
	_selector.farm_ready.connect(_open_host)
	_camera.tapped.connect(func(point: Vector2): _selector.tap(point, _camera.zoom))
	_camera.camera_changed.connect(func(): _selector.camera_changed(_camera.zoom))
	_camera.camera_changed.connect(func(): _area_timer.start(AREA_REFRESH_SECONDS))
	_camera.setup_map(_bridge, token)
	_selector.activate()
	_start_claims()

## Isolated test builds skip Net's boot. Internal and release packages may reload the saved account token
## (`sensen/dynamic_farm/account_restore`). Only a package with `sensen/dynamic_farm/guest_play` (install-and-play,
## C-100) then signs in anonymously with this installation's key when no account was restored; the server decides
## whether that guest may claim and farm (PARCEL_GUEST_WRITES), otherwise the map asks the player to sign in.
## Only an explicit 401 drops the saved account (Net._resume_account); a server error, rate limit or lost network
## keeps it and the top panel says so (C-110).
func _start_claims() -> void:
	if _restoring: return
	var net := get_node_or_null("/root/Net")
	if net != null and not _fake_claims():
		_restoring = true; _render()
		await net.dynamic_farm_sign_in(bool(ProjectSettings.get_setting("sensen/dynamic_farm/account_restore", false)),
			_guest_play())
		_restoring = false
		_sync_guest()
	if is_inside_tree() and not _suspended: _claims.start()
	if is_inside_tree(): _render()

## Install-and-play (C-100): this installation plays as a guest when no account is signed in.
func _guest_play() -> bool:
	return bool(ProjectSettings.get_setting("sensen/dynamic_farm/guest_play", false))

## Without an account the player is this installation's guest (or signed out): no give-up entry (Q-156).
func _sync_guest() -> void:
	var net := get_node_or_null("/root/Net")
	if _claims != null and net != null and not _fake_claims(): _claims.guest = not net.account.signed_in()

func _own_farm_entry() -> bool:
	return bool(ProjectSettings.get_setting("sensen/dynamic_farm/own_farm", false))

func _fake_claims() -> bool:
	return bool(ProjectSettings.get_setting("sensen/dynamic_farm/fake_claims", false))

## Claims carry the configured release (config.json dataset_version), the same one the map and farms use.
func _claim_api() -> RefCounted:
	var dataset := str(_selector.config.get("dataset_version", ""))
	if _fake_claims():
		if _fake_server == null: _fake_server = FakeParcelServer.new()
		_fake_server.dataset = dataset
		return ClaimApi.new(_fake_server.client(str(ProjectSettings.get_setting("sensen/dynamic_farm/fake_player", "fake-a"))), dataset)
	var net := get_node_or_null("/root/Net")
	return ClaimApi.new(net.client if net != null else null, dataset)

func _build_ui() -> void:
	_hud = Control.new(); _hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_hud)
	var top := _panel(false)
	var heading := HBoxContainer.new(); top.add_child(heading)
	var titles := VBoxContainer.new(); titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0); heading.add_child(titles)
	titles.add_child(_label("Dynamic Farm", 20))
	_account_line = _label("", 12); titles.add_child(_account_line)
	_account_button = _button("Sign in", _account_action); _account_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_account_button.custom_minimum_size.x = 96; heading.add_child(_account_button)
	_sign_out_confirm = VBoxContainer.new(); _sign_out_confirm.hide(); top.add_child(_sign_out_confirm)
	_sign_out_confirm.add_child(_label(SIGN_OUT_ASK, 14))
	var sign_out_answer := HBoxContainer.new(); _sign_out_confirm.add_child(sign_out_answer)
	sign_out_answer.add_child(_button("Sign out", _sign_out))
	sign_out_answer.add_child(_button("Cancel", func(): _sign_out_confirm.hide(); _render()))
	_account_note = _label(ACCOUNT_KEPT, 12); _account_note.hide(); top.add_child(_account_note)
	_message = _label("Loading dynamic farm map…", 14); top.add_child(_message)
	var row := HBoxContainer.new(); top.add_child(row)
	_retry = _button("Retry", _retry_map); _retry.disabled = true; row.add_child(_retry)
	row.add_child(_button("San Francisco", _reset_area.bind(true)))
	row.add_child(_button("Back", _leave))
	_places = HBoxContainer.new(); _places.visible = _own_farm_entry(); top.add_child(_places)
	_home = _button(MY_HOME, _go_home); _home.hide(); _places.add_child(_home)
	_market = _button(TOWN_NAMES.market, _open_town.bind("market")); _market.disabled = true; _market.visible = _own_farm_entry(); _places.add_child(_market)
	_carpenter = _button(TOWN_NAMES.carpenter, _open_town.bind("carpenter")); _carpenter.disabled = true; _carpenter.visible = _own_farm_entry(); _places.add_child(_carpenter)
	var bottom := _panel(true)
	_bottom = bottom.get_parent()
	_details = _label(PICK_PREVIEW, 16); bottom.add_child(_details)
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
	_enter = _button("Enter my farm", _enter_farm); _enter.hide(); bottom.add_child(_enter)
	_open = _button("Preview in 3D", _preview); _open.disabled = true; bottom.add_child(_open)
	_reselect = _button("Give up and choose again", _abandon); _reselect.hide(); bottom.add_child(_reselect)
	_area_timer = Timer.new(); _area_timer.one_shot = true; _area_timer.timeout.connect(_refresh_area); add_child(_area_timer)
	# Only the preview package still cannot farm; one that enters one's own farm drops the line (C-35).
	if not _own_farm_entry(): bottom.add_child(_label("Explore and walk. Farming actions come later.", 12))
	var credits := HBoxContainer.new(); bottom.add_child(credits)
	for item in [["© Mapbox", "https://www.mapbox.com/about/maps/"], ["© OpenStreetMap", "https://www.openstreetmap.org/copyright"]]:
		var credit := _button(item[0], ExternalLink.open.bind(item[1])); credit.flat = true; credits.add_child(credit)
	bottom.add_child(_label("Parcels: DataSF · PDDL / CC0", 10))
	_locate = _round_key(LOCATE_ICON); _locate.name = "MapLocate"; _locate.disabled = true
	_locate.pressed.connect(_locate_player); _hud.add_child(_locate)
	_profile_button = _round_key(PROFILE_ICON, UiTokens.COLOR_TEXT); _profile_button.name = "MapProfile"
	_profile_button.pressed.connect(_open_profile); _hud.add_child(_profile_button)
	_bottom.item_rect_changed.connect(_place_locate); _hud.resized.connect(_place_locate)
	_render_account()

## farm-dev's round locate key, styled as P0 styles it (Close round, floating shadow, the glyph as drawn). `tint`
## colours a white glyph (lucide's) the text colour the locate glyph is drawn in.
func _round_key(glyph: String, tint := Color.WHITE) -> Button:
	var b := Button.new(); b.focus_mode = Control.FOCUS_NONE
	b.theme = UiKit.theme(); b.theme_type_variation = UiTokens.BUTTON_CLOSE_ROUND
	for state in [&"normal", &"hover", &"focus", &"disabled", &"pressed", &"hover_pressed"]:
		var sb := b.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if sb != null:
			sb.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
			sb.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
			sb.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_color_override(StringName("icon_%s_color" % state), tint)
	b.icon = load(glyph); b.expand_icon = true; b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override(&"icon_max_width", 22)
	b.custom_minimum_size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE); b.size = b.custom_minimum_size
	return b

func _place_locate() -> void:
	if _locate == null or _bottom == null: return
	_locate.position = Vector2(_hud.size.x - _locate.size.x - LOCATE_GAP, _bottom.position.y - _locate.size.y - LOCATE_GAP)
	_profile_button.position = Vector2(LOCATE_GAP, _locate.position.y)

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

## A disabled panel button that reads another text for a while (Loading…) keeps the width its `usual` text gives it,
## with no side margins and the text centred; `text == usual` puts it back. A longer text widened the top panel past
## the screen and cut off the buttons on the right (C-123, C-61#195).
func _text_in_place(button: Button, text: String, usual: String) -> void:
	if button.text == text: return
	if text == usual:
		button.text = usual
		button.remove_theme_stylebox_override("disabled"); button.clip_text = false; button.custom_minimum_size.x = 0
		return
	if button.text == usual:
		button.custom_minimum_size.x = button.get_combined_minimum_size().x
		button.clip_text = true
		var style := button.get_theme_stylebox("disabled").duplicate() as StyleBox
		style.content_margin_left = 0; style.content_margin_right = 0
		button.add_theme_stylebox_override("disabled", style)
	button.text = text

func _render() -> void:
	_render_account()
	if _selector == null or _suspended or _leaving: return
	_frame_on_entry()
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
	_camera.input_enabled = not _selector.busy and not _opening and not _claims.busy and _town == null
	if id.is_empty(): _details.text = _no_selection()
	else:
		var p: Dictionary = _selector.selection
		_details.text = "%s\n%d core · %d walk-only extension cells" % [p.name, p.core_cell_count, p.extension_cell_count]
		if state == "mine":
			_details.text += "\nYour home"
			if not guide_line().is_empty(): _details.text += "\n" + guide_line()
		elif state == "other":
			var owner: String = _claims.owner_name(id)
			_details.text += ("\nClaimed by %s" % owner) if not owner.is_empty() else "\n" + Claims.NO_NAME
		elif state == "none" and _claims.has_home(): _details.text += "\nYou already have a home."
		elif state != "other" and _claims.signed_out: _details.text += "\nSign in to claim a home."
		elif state == "none" and not _claims.in_zone(id): _details.text += "\n" + Claims.OUTSIDE_ZONE
	if not _claims.message.is_empty(): _details.text += "\n" + _claims.message
	var claimable: bool = state == "none" and _claims.mine_known and not _claims.has_home() and _claims.in_zone(id)
	if not claimable or not idle: _confirm.hide()
	_claim.visible = claimable and not _confirm.visible; _claim.disabled = not idle
	_enter.visible = state == "mine"; _enter.disabled = not idle
	_open.visible = state != "mine"
	_reselect.visible = state == "mine" and _claims.can_give_up(); _reselect.disabled = not idle
	var town_ready: bool = _claims.has_home() and not _opening and not _claims.busy and _town == null and _town_loading.is_empty()
	_market.disabled = not town_ready; _carpenter.disabled = not town_ready
	_text_in_place(_market, TOWN_LOADING if _town_loading == "market" else TOWN_NAMES.market, TOWN_NAMES.market)
	_text_in_place(_carpenter, TOWN_LOADING if _town_loading == "carpenter" else TOWN_NAMES.carpenter, TOWN_NAMES.carpenter)
	_home.visible = _claims.has_home()
	_home.disabled = _selector.manifest.is_empty() or _opening or _town != null
	_locate.disabled = _home.disabled
	_places.visible = _own_farm_entry() or _home.visible
	if _own_farm_entry() and _claims.has_home():
		_prepare_town()
		_read_farm()
	if _selector._options.is_empty(): _choices.hide()

## First framing after the map loads: the player's home if they have one, else the starter zone (C-130), else the
## dataset's area. It waits while the saved account, the home and the zone are still being read, and never moves a
## camera the player has already moved. A home that only becomes known later (sign-in, a retried read) is framed once,
## the same way.
func _frame_on_entry() -> void:
	if _selector.manifest.is_empty() or _claims == null: return
	if not _framed:
		if _restoring or _claims._reading_mine or _claims._reading_zone or _selector.busy: return
		_framed = true
		if _player_moved: return
		if not _frame_home(): _reset_area()
	elif _framed_home.is_empty() and not _player_moved and _claims.has_home():
		_frame_home()

## Moves the camera to the player's home (the centre the server stored at claim time); `fly` for the buttons.
func _frame_home(fly := false) -> bool:
	if _camera == null or _claims == null or not _claims.has_home() or _opening: return false
	var center = _claims.mine.get("center")
	if not Geo.valid_point(center): return false
	_framed_home = str(_claims.mine.get("parcel_id", ""))
	if fly: _camera.fly_to(float(center[0]), float(center[1]), HOME_ZOOM)
	else: _camera.frame_center(float(center[0]), float(center[1]), HOME_ZOOM)
	return true

func _go_home() -> void:
	if _selector == null or _selector.manifest.is_empty() or _town != null: return
	_frame_home(true)

## The locate key: back to the player, who lives at their home; without a home, back to the starter zone (C-130) or the
## dataset's area.
func _locate_player() -> void:
	if _selector == null or _selector.manifest.is_empty() or _town != null or _opening: return
	if not _frame_home(true): _reset_area(true)

## Top panel: who is signed in on this phone, with Sign in / Sign out, shown whether or not a parcel is selected.
## Development builds on the in-memory claim stand-in have no account and hide it.
func _render_account() -> void:
	if _account_line == null: return
	_profile_button.disabled = _opening or _profile != null or _profile_waiting or (_selector != null and _selector.busy)
	var net := get_node_or_null("/root/Net")
	var shown := net != null and not _fake_claims()
	_account_line.visible = shown
	if not shown:
		_account_button.hide(); _sign_out_confirm.hide(); _account_note.hide(); return
	var signed_in: bool = net.account.signed_in()
	if _restoring: _account_line.text = CHECKING
	elif signed_in: _account_line.text = _account_name(net.account)
	else: _account_line.text = NOT_SIGNED_IN
	_account_button.text = "Sign out" if signed_in else "Sign in"
	_account_button.disabled = _opening or _town != null or not _town_loading.is_empty() or (_claims != null and _claims.busy)
	if not signed_in or _restoring or _signing_out: _sign_out_confirm.hide()
	_account_button.visible = not _restoring and not _signing_out and not _sign_out_confirm.visible
	_account_note.visible = signed_in and not _restoring and not str(net.restore_error).is_empty()

static func _account_name(account: AccountSession) -> String:
	var name := account.display_name if not account.display_name.is_empty() else account.email
	return SIGNED_IN % name.left(40) if not name.is_empty() else SIGNED_IN_NO_NAME

func _account_action() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null or _restoring or _signing_out: return
	if net.account.signed_in(): _sign_out_confirm.show(); _render()
	else: _open_sign_in()

## Revokes this phone's token and clears the saved account. Only an install-and-play package
## (`sensen/dynamic_farm/guest_play`, C-100) then continues as this installation's guest; others stay signed out.
func _sign_out() -> void:
	_sign_out_confirm.hide()
	var net := get_node_or_null("/root/Net")
	if net == null or _signing_out or _restoring: return
	_signing_out = true; _render()
	await net.sign_out(_guest_play())
	_signing_out = false
	if not is_inside_tree(): return
	_account_changed()

## Ownership and the framed home were relative to the previous account.
func _account_changed() -> void:
	_framed_home = ""; _player_moved = false
	_sync_guest()
	if _claims != null: _claims.forget()
	_render()

## With nothing selected: where to go next (C-35) in a package that enters one's own farm, once the player's own
## parcel is known; otherwise the preview's line.
func _no_selection() -> String:
	if not _own_farm_entry() or not _claims.mine_known: return PICK_PREVIEW
	if not _claims.has_home(): return PICK_FIRST
	return PICK_HOME if guide_line().is_empty() else guide_line()

## The guide's step done off the parcel (C-61: Market, Carpenter, back to gather) for the home's save, or "".
func guide_line() -> String:
	if not _own_farm_entry() or _claims == null or not _claims.has_home(): return ""
	if str(_claims.mine.get("parcel_id", "")) != _farm_parcel: return ""
	return Guide.map_text(Guide.step(home_farm, int(Time.get_unix_time_from_system() * 1000.0)))

## Reads the home's parcel save for the guide's line (no welcome gift), once per return to the map. Only with the
## native map running (tests set `home_farm` themselves).
func _read_farm() -> void:
	if _farm_reading or _bridge == null or not _own_farm_entry() or _claims == null or not _claims.has_home(): return
	var parcel := str(_claims.mine.parcel_id)
	if _farm_fresh and parcel == _farm_parcel: return
	_farm_reading = true
	var result: Dictionary = await _farm_store(parcel, str(_claims.mine.get("dataset_version", ""))).read()
	_farm_reading = false
	if not is_inside_tree() or not _claims.has_home() or str(_claims.mine.parcel_id) != parcel: return
	_farm_fresh = true # A failed read keeps the line it had; the next return to the map reads again.
	var read := ParcelFarm.normalize(result.get("farm"))
	if read.is_empty(): return
	home_farm = read; _farm_parcel = parcel
	_render()

func _show_candidates(rows: Array) -> void:
	_choices.clear(); _candidate_ids.clear()
	for row in rows.slice(0, 6):
		_candidate_ids.append(row.block_id); _choices.add_item(row.name)
	_choices.select(-1); _choices.show()

## The default area: the server's starter zone when it has one on (C-130), else the dataset's centre.
func _reset_area(fly := false) -> void:
	if _selector == null or _selector.busy or _selector.manifest.is_empty() or _opening: return
	var native: Dictionary = _selector.manifest.native_map
	var center: Array = native.center
	var level := clampf(float(native.get("initial_zoom", 17.5)), 13, 21)
	if _claims != null and not _claims.zone.is_empty():
		center = _claims.zone.center; level = _claims.zone.zoom
	if fly: _camera.fly_to(float(center[0]), float(center[1]), level)
	else: _camera.frame_center(float(center[0]), float(center[1]), level)

func _retry_map() -> void:
	if _selector != null and not _selector.busy and not _opening: _selector.retry()
	# The saved account could not be confirmed, or the home could not be read: ask the server again.
	var net := get_node_or_null("/root/Net")
	if _claims == null or _restoring or _signing_out: return
	if net != null and not _fake_claims() and net.account.signed_in() and not str(net.restore_error).is_empty(): _start_claims()
	elif not _claims.mine_known and not _claims.signed_out and not _claims._reading_mine: _claims.start()

func _preview() -> void:
	if _selector != null and not _opening:
		_entering = ""; _selector.open_farm()

func _enter_farm() -> void:
	if _selector != null and not _opening:
		_entering = str(_selector.selection.get("block_id", "")); _selector.open_farm()

func _claim_selection() -> void:
	_confirm.hide()
	if _selector != null and not _selector.selection.is_empty():
		_framed_home = str(_selector.selection.block_id) # The player is already looking at the parcel they claim.
		_claims.claim(_selector.selection)

func _open_sign_in() -> void:
	if _claims == null or find_children("*", "AccountPanel", true, false).size() > 0: return
	# Loaded at run time: the panel uses the Net autoload, which scripts preloading this scene may not have yet.
	var panel: CanvasLayer = load(ACCOUNT_PANEL).open(self, "sign_in")
	_camera.input_enabled = false
	var signed_in: bool = await panel.closed
	if not is_inside_tree(): return
	if signed_in: _account_changed()
	else: _render()

## The market or the carpenter over the map, trading through the player's own parcel save. The tapped entry reads
## Loading… and is on screen before anything loads: on a cold start the town's first open took seconds with no sign
## of the tap (C-59#135). A tap is handled before the frame's process step, so waiting for process_frame alone opened
## the town before Loading… was ever drawn (C-61 V-243 on the emulator).
func _open_town(who: String) -> void:
	if not _own_farm_entry() or _claims == null or not _claims.has_home() or _town != null or _opening or not _town_loading.is_empty(): return
	var tapped := Time.get_ticks_msec()
	_town_loading = who
	_render()
	await _on_screen()
	var drawn := Time.get_ticks_msec()
	if _town_cancelled(): return
	await _town_ready()
	var loaded := Time.get_ticks_msec()
	if _town_cancelled(): return
	var home: Dictionary = _claims.mine
	_town = _town_script.open(self, who, _farm_store(str(home.parcel_id), str(home.get("dataset_version", ""))), str(home.parcel_id))
	_town_loading = ""
	_town.closed.connect(_town_closed.bind(_town, str(home.parcel_id)))
	_hud.hide(); _camera.input_enabled = false
	var opened := Time.get_ticks_msec()
	await _on_screen()
	print("DYNAMIC_TOWN_OPEN ", JSON.stringify({"who": who, "loading_ms": drawn - tapped, "ready_ms": loaded - tapped,
		"open_ms": opened - tapped, "shown_ms": Time.get_ticks_msec() - tapped}))

## Waits until what the map shows now has been drawn, then for the next frame (headless draws nothing: a frame).
func _on_screen() -> void:
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	else: await get_tree().process_frame
	if is_inside_tree(): await get_tree().process_frame

## A tap given up while its town loads (the map left, went to the parcel, or lost its home); the entries come back.
func _town_cancelled() -> bool:
	if is_inside_tree() and not _suspended and not _leaving and not _opening and _claims.has_home(): return false
	_town_loading = ""
	if is_inside_tree(): _render()
	return true

## The town's script: the thread's preload, waited for frame by frame so Loading… stays drawn, else loaded here.
func _town_ready() -> void:
	if _town_script != null: return
	if _town_prepared:
		while is_inside_tree() and ResourceLoader.load_threaded_get_status(TOWN) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if not is_inside_tree(): return
		_town_prepared = false
		_town_script = ResourceLoader.load_threaded_get(TOWN)
	if _town_script == null: _town_script = load(TOWN)

## The town's script and what it preloads load on a thread once the player has a home, so the first tap opens sooner.
## Not under Compatibility, where threaded loads never finished (AppRouter.sync_loads): the tap loads it there.
func _prepare_town() -> void:
	var router := get_node_or_null("/root/AppRouter")
	if router != null and router.sync_loads: return
	if not _town_prepared and _town_script == null:
		_town_prepared = ResourceLoader.load_threaded_request(TOWN) == OK
		if _town_prepared: _town_router = router

## A map freed with that load still running hands it to AppRouter, which takes it once done (and waits for it only
## when Godot quits): a load left on its thread kept a quitting Godot from exiting (C-61, Q-139), and waiting here
## held Back on the main thread until the town had loaded (C-125). Without AppRouter the map still waits for it.
func _finish_town_load() -> void:
	if not _town_prepared: return
	_town_prepared = false
	if is_instance_valid(_town_router): _town_router.adopt_threaded_load(TOWN)
	else: ResourceLoader.load_threaded_get(TOWN)

func _town_closed(town: Control, parcel: String) -> void:
	_town = null
	if not town.farm.is_empty() and _claims != null and _claims.has_home() and str(_claims.mine.parcel_id) == parcel:
		home_farm = town.farm; _farm_parcel = parcel; _farm_fresh = true
	if _suspended or _leaving: return
	_hud.show(); _render()

## The map has no player of its own, so after a cold start nothing had loaded the saved outfit and the profile's figure
## stayed blank ~3 s on its first open (C-133): its parts start loading on the loader's threads as the map opens.
func _warm_outfit() -> void:
	var avatar := get_node_or_null("/root/Avatar")
	if avatar != null: avatar.warm_saved_outfit()

## The profile over the map (C-128), as the town is: the map's panels hide and its camera holds still until it closes.
## A tap while the saved outfit is still loading (just after a cold start) holds the key until it has loaded, frame
## by frame, so the profile opens with its figure, never with an empty frame for it (C-133). It waits
## profile_wait_seconds at most: a load that never ends opens the profile all the same (C-135).
func _open_profile() -> void:
	if _profile != null or _opening or _leaving or _suspended or _profile_waiting: return
	var avatar := get_node_or_null("/root/Avatar")
	if avatar != null and avatar.warming():
		_profile_waiting = true; _render()
		var start := Time.get_ticks_msec()
		var limit := int(profile_wait_seconds * 1000.0)
		while is_inside_tree() and avatar.warming() and Time.get_ticks_msec() - start < limit: await get_tree().process_frame
		_profile_waiting = false
		var timed_out: bool = is_inside_tree() and avatar.warming()
		print("PARCEL_PROFILE_WAIT ", JSON.stringify({"ms": Time.get_ticks_msec() - start, "timed_out": timed_out}))
		if not is_inside_tree(): return
		_render()
		if _profile != null or _opening or _leaving or _suspended: return
	var view := Vector3.ZERO
	if _camera != null: view = Vector3(float(_camera.center[1]), float(_camera.center[0]), float(_camera.zoom))
	_profile = load(PROFILE).open(self, view)
	_profile.closed.connect(_profile_closed)
	_hud.hide()
	if _camera != null: _camera.input_enabled = false

func _profile_closed() -> void:
	_profile = null
	if _suspended or _leaving: return
	_hud.show(); _render()

## The same save the parcel scene uses: the server, or the device stand-in with the development setting.
func _farm_store(block_id: String, dataset: String) -> RefCounted:
	if bool(ProjectSettings.get_setting(LOCAL_SAVE_SETTING, false)): return LocalFarmStore.new(block_id)
	var net := get_node_or_null("/root/Net")
	return RemoteFarmStore.new(net.client if net != null else null, block_id, dataset)

func _abandon() -> void:
	if _claims != null: _claims.abandon()

func _refresh_area() -> void:
	if _selector == null or _suspended or not _selector.map_ready or _selector.manifest.is_empty(): return
	if _camera.zoom < float(_selector.manifest.native_map.get("minzoom", 16)): return
	_claims.refresh_area(area_bbox(_camera))

## The ground the camera sees as [west, south, east, north]. Tilted, the far edge reaches towards the horizon, so the
## box is held to the claim API's span around the centre (the near parcels, where the buildings are drawn).
static func area_bbox(camera: Control) -> Array:
	var west := INF; var south := INF; var east := -INF; var north := -INF
	for corner in [Vector2.ZERO, Vector2(camera.size.x, 0), Vector2(0, camera.size.y), camera.size]:
		var point: PackedFloat64Array = camera.screen_geo(corner)
		west = minf(west, point[0]); east = maxf(east, point[0]); south = minf(south, point[1]); north = maxf(north, point[1])
	var half := ClaimApi.MAX_BBOX_SPAN * 0.49 # Under the span after rounding.
	return [maxf(west, camera.center[0] - half), maxf(south, camera.center[1] - half), minf(east, camera.center[0] + half), minf(north, camera.center[1] + half)]

func _open_host(farm: Dictionary) -> void:
	if _leaving or _suspended or _opening: return
	# Only the player's own parcel, opened from "Enter my farm", in a package with `own_farm` is farmable.
	var own: bool = _own_farm_entry() and _entering == str(farm.block_id) and _claims != null and _claims.status(_entering) == "mine"
	_entering = ""
	if _bridge == null or not _bridge.supports_surface_opacity() or not _bridge.set_map_occlusion_color(OCCLUSION_COLOR):
		_render()
		_message.text = "Use the latest Dynamic Farm preview build."; return
	var router := get_node_or_null("/root/AppRouter")
	if router == null or not router.has_method("open_instance"):
		_message.text = "This preview is missing its scene router."; return
	_opening = true; _render()
	await router.open_instance(HOST, {"farm": farm, "dataset": farm.dataset_version, "block_id": farm.block_id,
		"own_parcel" if own else "preview_only": true, "return_context": {"center": Array(_camera.center), "zoom": _camera.zoom}})
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
	if _camera != null: _camera.stop()
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
	_suspended = false; process_mode = Node.PROCESS_MODE_INHERIT
	_hud.visible = _profile == null # Back from the dressing room: the profile is still over the map.
	_farm_fresh = false # Back from the parcel: its save has moved on.
	_presentation_epoch += 1
	if _bridge != null:
		get_viewport().transparent_bg = true
		_restore_surface_mode()
		_bridge.set_map_visible(true); _camera._changed()
	if _selector != null: _selector.activate()
	# Re-reads the player's parcel; a guest sign-in that failed earlier (offline, rate limited) is retried here.
	if _claims != null: _start_claims()
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
	if is_instance_valid(_profile):
		_profile.back()
		return true
	if is_instance_valid(_town):
		if not _town.stack.back(): _town.close()
		return true
	_leave(); return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: _finish_town_load()
	if not is_node_ready() or _selector == null: return
	if what == NOTIFICATION_APPLICATION_PAUSED and not _suspended: _suspend_map(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED and _suspended:
		var router := get_node_or_null("/root/AppRouter")
		if router == null or router.top_instance() in [null, self]: resume()
		else: _record_presentation("covered_foreground", _presentation_epoch)
