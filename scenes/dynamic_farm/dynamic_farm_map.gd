extends Control
## Dynamic farm map. Its only server write is the C-32 first-home claim (and, in internal test packages,
## giving that home up); no choose_home or old-farm state writes. Internal test packages and the invite-only
## release package (C-98) also open the player's own parcel for farming from "Enter my farm"
## (`sensen/dynamic_farm/own_farm`, C-34 Q-72); everywhere else that button opens the same read-only 3D preview.
## C-115 (C-103#17, replacing C-59's Market and Carpenter buttons): one fixed place pin in San Francisco, farm-dev's
## Washington Square Travel Post (town_entry.gd), opens its place card; Go opens the 3D room (parcel_outpost.tscn) where
## Jasmine (Market) and Scott (Carpenter) trade through the home's parcel save. Like "Enter my farm" it is only in
## packages with `own_farm` (C-59#29): internal test packages and the release package (C-98).
## C-110: the map frames the player's home on entry and has a "My home" key; the account chip (Sign in, or the name
## with Sign out behind it) stays at the top right whether or not a parcel is selected.
## The guide (C-35, C-61) gives the next step: in the hint under the top row with nothing selected, on the home's card.
## C-112: farm-dev's camera feel (geo_native_camera.gd) and its round locate key, over the bottom card at the right;
## My home, San Francisco and the locate key fly there. Only buildings are coloured (ParcelMapController.kt).
## C-130: with the server's starter zone on, the map lands there for a player without a home (San Francisco and the
## locate key go there too), marks it with its own native layer and offers claiming only inside it.
## C-128 (0.4.4): a round profile key at the left, level with the locate key, opens the main farm's profile over the
## map, and from it Settings and the dressing room (parcel_profile.gd).
## C-106: the UI v3 look of the owner-approved C-85 page ⑤ (map_ui.gd); states, actions and lines are unchanged.
## C-188 (owner on Q-283, after C-187's design D-437): the player's avatar stands on the map (map_travel.gd) and walks a
## curved route from home to the Washington Square pin on Go, and back home on Enter my farm; an iris closes on the place
## before its scene opens and opens from it on the way back. Preview in 3D keeps its plain cut (C-188#13).
## C-146 (owner 11-25: "移除游客模式, 必须要注册/有账号才能玩"): no guest entry. A package that signs in
## (`sensen/dynamic_farm/account_restore`: the internal and release packages) opens the map only with an account: without
## one the sign-in panel stands over an empty screen with no way past it (no ✕) until the player signs in or signs up;
## signing out puts it back and takes the map and its parcels away.
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
const LoadingLayer := preload("res://modules/ui/loading_overlay.gd")
const ACCOUNT_PANEL := "res://scenes/account/account_panel.gd"
## The 3D space the Washington Square pin opens (C-115).
const ROOM := "res://scenes/dynamic_farm/parcel_outpost.tscn"
const TownEntry := preload("res://scenes/dynamic_farm/town_entry.gd")
const MapTravel := preload("res://scenes/dynamic_farm/map_travel.gd")
## The Washington Square pin's place in the avatar's trips (C-188).
const TOWN := "town"
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
## Camera zoom when the map moves to the player's home (C-110); the parcel and its address labels show from 18.
const HOME_ZOOM := 18.0
const MY_HOME := "My home"
## The Washington Square pin stays above this fraction of the screen's height while its card is open (C-115).
const PIN_CLEAR_OF_CARD := 0.55
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
const SIGNED_IN_NO_NAME := "Signed in"
const SIGN_OUT_ASK := "Sign out on this phone?"
## The saved account was kept because the server could not confirm it (5xx, rate limit or no network).
const ACCOUNT_KEPT := "Can't reach the server. You're still signed in."
## UI v3 (C-106, C-85 ⑤ as approved in Q-124): the pieces, the board's copy and the art.
const MapUi := preload("res://scenes/dynamic_farm/map_ui.gd")
const CITY := "San Francisco"
const CITY_ICON := "res://assets/ui/icons/lucide/compass.svg"
const HOME_ICON := "res://assets/ui/icons/lucide/house.svg"
const ALERT_ICON := "res://assets/ui/icons/lucide/circle-alert.svg"
## The signed-in chip's avatar: the existing player portrait (the board's stand-in, C-85 README §5).
const AVATAR_IMAGE := "res://assets/ui/kit_images/player_portrait.png"
const ACCOUNT_AVATAR_LEFT := 4.0  # C-85 ⑤ .acct padding-left
const ACCOUNT_MAX_W := 160.0      # a long name cuts with … and leaves the city chip its room
const TOP_INSET := 28.0           # the map's top edge before C-106, kept as the least inset
const CREDIT_H := 24.0
const BUSY_DOTS := "• • •"
const PARCEL_TAG := "Parcel"
const HOME_TAG := "Your home"
const NOT_CLAIMED := "Not claimed"
const CLAIM_ASK := "Claim this parcel?"
const CLAIM_NOTE := "You can only have one home."
const CLAIMING := "Claiming…"
const PREVIEW_NOTE := "Explore and walk. Farming actions come later."
const READY_TO_PREVIEW := "Ready to preview this farm."
const CHOOSE_PREVIEW := "Choose a parcel to preview."
## Development stand-in for the C-31 server, shared by map visits in one run.
static var _fake_server: RefCounted
var _selector: Node
var _claims: Node
var _camera: Control
var _bridge: MapBridge
var _hud: Control
var _top: VBoxContainer
var _city: Button
var _hint: PanelContainer
## The hint line (map progress, the next step); `_preview_note` the preview package's second line.
var _message: Label
var _preview_note: Label
## The card's owner line ("Your home", "Claimed by …", "Not claimed", …).
var _details: Label
var _card: Control
var _card_hero: TextureRect
var _card_tag: UiTagPill
var _card_name: Label
var _card_cells: Label
var _owner_row: HBoxContainer
var _owner_dot: Panel
var _guide: Label
var _error_card: PanelContainer
var _error_line: Label
var _claim_toast: PanelContainer
var _claim_note: Label
var _open: Button
var _claim: Button
var _confirm: Control
var _enter: Button
var _reselect: Button
var _account_button: Button # The account chip: the name, "Sign in", or • • • while checking
var _avatar: Control
var _account_styled := false
var _sign_out_confirm: Control
var _account_toast: PanelContainer
var _account_note: Label
var _home: Button
var _locate: Button
var _bottom: VBoxContainer
var _entry: Control # The Washington Square pin and its place card (TownEntry).
## The avatar and its trips (C-188, map_travel.gd); the parcel card hidden while a trip has taken it away; the farm read
## for Enter my farm, opened once the iris has closed on home; a farm read whose trip was cancelled (Back), not opened;
## the place whose scene is open (the iris opens from it on the way back); the scene a trip preloads (T-02).
var _travel: Control
var _travel_card := false
var _farm_waiting := {}
var _drop_farm := false
var _inside := ""
var _preloading := ""
var _profile_button: Button
## The profile and the pages opened from it, over the map (parcel_profile.gd), else null.
var _profile: Control
## A tap on the profile key waiting for the saved outfit's parts to load (C-133); the key is held meanwhile.
var _profile_waiting := false
## The most a profile tap waits for the outfit (PROFILE_WAIT_SECONDS).
var profile_wait_seconds := float(ProjectSettings.get_setting(PROFILE_WAIT_SETTING, PROFILE_WAIT_SECONDS))
## The home's parcel save as last read or seen (the guide's line) and the parcel it belongs to; read again after
## a visit to the parcel.
var home_farm := {}
var _farm_parcel := ""
var _farm_fresh := false
var _farm_reading := false
var _area_timer: Timer
var _area_generation := -1
var _retry: Button
var _choices: VBoxContainer
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
var _gated := false # The sign-in panel stands over the map: no account yet (C-146).
var _player_moved := false # The player moved the camera since the last account change.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_warm_outfit()
	# The isolated build must set this BEFORE Net's autoload _ready, not from this scene.
	if not bool(ProjectSettings.get_setting("sensen/network/online_qa", false)):
		_set_hint("Use the isolated Dynamic Farm preview build."); return
	var parser := JSON.new()
	if not FileAccess.file_exists(CONFIG) or parser.parse(FileAccess.get_file_as_string(CONFIG)) != OK or not parser.data is Dictionary:
		_set_hint("This preview service is not configured."); return
	var token := FileAccess.get_file_as_string("res://mapbox_token.txt").strip_edges() if FileAccess.file_exists("res://mapbox_token.txt") else ""
	if not Engine.has_singleton("GodotMap") or token.is_empty():
		_set_hint("This preview needs the Android parcel map."); return
	_bridge = AndroidBridge.new()
	_bridge.set_godot_surface_opaque(false) # A fresh map scene always requests the transparent mode.
	# C-146: no account, no map. Nothing of the map (native view, parcels, claims) is created before the player is signed in.
	if not await signed_in_first(): return
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
	_camera.tapped.connect(_on_map_tap)
	_camera.camera_changed.connect(func(): _selector.camera_changed(_camera.zoom))
	_camera.camera_changed.connect(func(): _area_timer.start(AREA_REFRESH_SECONDS))
	_camera.setup_map(_bridge, token)
	_selector.activate()
	_start_claims()

## Isolated test builds skip Net's boot. Internal and release packages reload the saved account token
## (`sensen/dynamic_farm/account_restore`); there is no guest sign-in any more (C-146).
## Only an explicit 401 drops the saved account (Net._resume_account); a server error, rate limit or lost network
## keeps it and the top panel says so (C-110).
func _start_claims() -> void:
	if _restoring: return
	var net := get_node_or_null("/root/Net")
	if net != null and not _fake_claims():
		_restoring = true; _render()
		await net.dynamic_farm_sign_in(_account_restore())
		_restoring = false
		_sync_guest()
	if is_inside_tree() and not _suspended and not _gated: _claims.start()
	if is_inside_tree(): _render()

func _account_restore() -> bool:
	return bool(ProjectSettings.get_setting("sensen/dynamic_farm/account_restore", false))

## C-146: a package that signs in (account_restore, with Net and the real server) needs an account for the map.
func account_required() -> bool:
	return get_node_or_null("/root/Net") != null and not _fake_claims() and _account_restore()

## Entry (C-146): the saved account, else the sign-in panel until the player signs in or signs up. True once signed in
## (or when the package needs no account); false if the map left meanwhile.
func signed_in_first() -> bool:
	if not account_required(): return true
	var net := get_node("/root/Net")
	_restoring = true; _render()
	var signed_in: bool = await net.dynamic_farm_sign_in(true)
	_restoring = false
	if not is_inside_tree(): return false
	_render()
	if signed_in: return true
	return await _sign_in_gate()

## The sign-in panel with no ✕ (AccountPanel.set_gate) over the map's empty screen; the map's own keys are hidden. It closes
## only once signed in (sign-up signs in too).
func _sign_in_gate() -> bool:
	_gated = true
	_hud.hide()
	if _camera != null: _camera.input_enabled = false
	var panel: CanvasLayer = load(ACCOUNT_PANEL).open(self, "sign_in", "", true, true) # the v3 look (C-85 ④), in English (C-144)
	panel.set_gate(true)
	var signed_in: bool = await panel.closed
	_gated = false
	if not is_inside_tree(): return false
	_hud.show()
	_render()
	return signed_in

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

## The v3 map UI (C-106, after the owner-approved C-85 page ⑤, D-201 / Q-124): a top row of glass keys (Back, the city
## chip, the account chip), one hint capsule under it, the parcel card at the bottom and keys on the sides (farm-dev's
## round locate and profile keys, a glass My home). The states, actions and lines are the ones the map had; only where
## they are drawn changed (map_ui.gd).
func _build_ui() -> void:
	_hud = Control.new(); _hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; _hud.theme = MapUi.theme(); add_child(_hud)
	var safe := _safe_margins()
	_top = VBoxContainer.new(); _top.name = "Top"; _top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_left = UiTokens.SIZE_SCREEN_EDGE - (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5
	_top.offset_right = -UiTokens.SIZE_SCREEN_EDGE; _top.offset_top = maxf(TOP_INSET, safe.y + UiTokens.SIZE_SCREEN_SAFE_INSET)
	_top.add_theme_constant_override("separation", int(UiTokens.SPACE_S4)); _hud.add_child(_top)
	var row := HBoxContainer.new(); row.name = "TopRow"; row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(UiTokens.SPACE_S3)); _top.add_child(row)
	var back := UiGlassButton.new(null, UiGlassButton.Glyph.BACK); back.name = "Back"; back.tooltip_text = "Back"
	back.pressed.connect(_leave); row.add_child(back)
	_city = MapUi.glass_pill(CITY, load(CITY_ICON)); _city.name = "City"; _city.pressed.connect(_reset_area.bind(true))
	row.add_child(_city)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(spacer)
	_account_button = MapUi.glass_pill("Sign in"); _account_button.name = "Account"
	_account_button.clip_text = true; _account_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_account_button.pressed.connect(_account_action); row.add_child(_account_button)
	_avatar = MapUi.avatar(load(AVATAR_IMAGE)); _avatar.name = "Avatar"
	_avatar.position = Vector2(ACCOUNT_AVATAR_LEFT, (UiTokens.SIZE_TOUCH_MIN - MapUi.AVATAR) * 0.5); _account_button.add_child(_avatar)
	# The saved account was kept although the server could not confirm it (C-110): an amber toast with Retry.
	_account_toast = PanelContainer.new(); _account_toast.name = "AccountKept"; _account_toast.hide()
	_account_toast.add_theme_stylebox_override("panel", MapUi.toast_box(UiTokens.COLOR_AMBER)); _top.add_child(_account_toast)
	var kept := HBoxContainer.new(); kept.add_theme_constant_override("separation", int(UiTokens.SPACE_S4)); _account_toast.add_child(kept)
	_account_note = MapUi.wrap(MapUi.label(ACCOUNT_KEPT, UiTokens.STYLE_TYPE_CAPTION)); _account_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_account_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; kept.add_child(_account_note)
	var kept_retry := MapUi.command("Retry", UiTokens.BUTTON_CMD_SECONDARY, true); kept_retry.name = "AccountRetry"
	kept_retry.size_flags_horizontal = Control.SIZE_SHRINK_END; kept_retry.custom_minimum_size.x = 72
	kept_retry.pressed.connect(_retry_map); kept.add_child(kept_retry)
	# One line for where to go next or what the map is doing; it replaces the old top panel's status line and the bottom
	# card's empty-state line, which said the same thing twice with no home (C-88#5).
	_hint = PanelContainer.new(); _hint.name = "Hint"; _hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint.add_theme_stylebox_override("panel", MapUi.hint_box()); _top.add_child(_hint)
	var lines := VBoxContainer.new(); lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 0); _hint.add_child(lines)
	_message = MapUi.wrap(MapUi.label("Loading dynamic farm map…", UiTokens.STYLE_TYPE_LABEL_ON_DARK))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lines.add_child(_message)
	# Only the preview package still cannot farm; one that enters one's own farm drops the line (C-35).
	if not _own_farm_entry():
		_preview_note = MapUi.wrap(MapUi.label(PREVIEW_NOTE, UiTokens.STYLE_TYPE_CAPTION_ON_DARK, UiTokens.COLOR_TEXT_ON_DARK_MUTED))
		_preview_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lines.add_child(_preview_note)
	_bottom = VBoxContainer.new(); _bottom.name = "Bottom"; _bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE); _bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.offset_left = UiTokens.SIZE_SCREEN_EDGE; _bottom.offset_right = -UiTokens.SIZE_SCREEN_EDGE
	_bottom.offset_bottom = -maxf(UiTokens.SPACE_S2, safe.w)
	_bottom.add_theme_constant_override("separation", int(UiTokens.SPACE_S4)); _hud.add_child(_bottom)
	# Claiming… on glass while the claim is sent (the card steps aside), a claim or give-up failure on white with a red bar.
	_claim_toast = PanelContainer.new(); _claim_toast.name = "ClaimToast"; _claim_toast.hide()
	_claim_toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; _bottom.add_child(_claim_toast)
	_claim_note = MapUi.wrap(MapUi.label("", UiTokens.STYLE_TYPE_CAPTION)); _claim_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_claim_toast.add_child(_claim_note)
	# A map or parcel read that failed: the line and Retry on a white card, as the board's load-failure state.
	_error_card = PanelContainer.new(); _error_card.name = "LoadFailed"; _error_card.hide()
	_error_card.add_theme_stylebox_override("panel", MapUi.card_box(UiTokens.SPACE_S6)); _bottom.add_child(_error_card)
	var failed := VBoxContainer.new(); failed.alignment = BoxContainer.ALIGNMENT_CENTER
	failed.add_theme_constant_override("separation", int(UiTokens.SPACE_S4)); _error_card.add_child(failed)
	var alert := UiKit.icon(load(ALERT_ICON), 24); alert.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	alert.modulate = UiTokens.COLOR_AMBER; failed.add_child(alert)
	_error_line = MapUi.wrap(MapUi.label("", UiTokens.STYLE_TYPE_BODY_BOLD)); _error_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	failed.add_child(_error_line)
	_retry = MapUi.command("Retry", UiTokens.BUTTON_CMD_SECONDARY, true); _retry.name = "Retry"
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; _retry.custom_minimum_size.x = 88
	_retry.pressed.connect(_retry_map); _retry.disabled = true; failed.add_child(_retry)
	_build_card()
	var credits := HBoxContainer.new(); credits.name = "Credits"; credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits.add_theme_constant_override("separation", int(UiTokens.SPACE_S3)); _bottom.add_child(credits)
	for item in [["© Mapbox", "https://www.mapbox.com/about/maps/"], ["© OpenStreetMap", "https://www.openstreetmap.org/copyright"]]:
		var credit := MapUi.link(item[0], UiTokens.COLOR_TEXT_SECONDARY); credit.custom_minimum_size.y = CREDIT_H
		credit.add_theme_font_size_override("font_size", MapUi.theme().get_font_size("font_size", UiTokens.STYLE_TYPE_MICRO))
		credit.pressed.connect(ExternalLink.open.bind(item[1])); credits.add_child(credit)
	# r8 fills buildings DataSF lacks from OpenStreetMap (C-113): ODbL asks for "© OpenStreetMap contributors" on the map.
	# The longer line wraps beside the two links instead of widening the row past a portrait screen.
	var data := MapUi.wrap(MapUi.label("Parcels: DataSF · PDDL / CC0 · Buildings: DataSF, © OpenStreetMap contributors · ODbL",
		UiTokens.STYLE_TYPE_MICRO, UiTokens.COLOR_TEXT_SECONDARY))
	data.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; data.custom_minimum_size.y = CREDIT_H; credits.add_child(data)
	# Side keys over the card: farm-dev's round locate key (C-112, LOCK-24) at the right with My home (C-110) above it;
	# the same round profile key (C-128) at the left, level with locate. Market and Carpenter are in the Washington
	# Square room now (C-115).
	_locate = _round_key(LOCATE_ICON); _locate.name = "MapLocate"; _locate.tooltip_text = "Locate"
	_locate.disabled = true; _locate.pressed.connect(_locate_player); _hud.add_child(_locate)
	_home = UiGlassButton.new(UiArt.sys("home")); _home.name = "MyHome"; _home.tooltip_text = MY_HOME
	_home.hide(); _home.pressed.connect(_go_home); _hud.add_child(_home)
	_profile_button = _round_key(PROFILE_ICON, UiTokens.COLOR_TEXT); _profile_button.name = "MapProfile"; _profile_button.tooltip_text = "Profile"
	_profile_button.pressed.connect(_open_profile); _hud.add_child(_profile_button)
	_entry = TownEntry.new(); _entry.visible = false; _hud.add_child(_entry); _hud.move_child(_entry, 0)
	_entry.go_requested.connect(_open_town)
	_entry.card_changed.connect(_on_entry_card)
	# Over the pins, under the panels and keys; its iris over everything (added last below).
	_travel = MapTravel.new(); _hud.add_child(_travel); _hud.move_child(_travel, 1)
	_travel.fade_in.assign([_top])
	_travel.closed.connect(_travel_closed)
	_travel.cancelled.connect(_travel_cancelled)
	_travel.card_gone.connect(_travel_card_gone)
	_travel.settled.connect(_render)
	_confirm = _dialog("ClaimConfirm", CLAIM_ASK, CLAIM_NOTE, UiArt.hero("parcel"),
		[["Claim", UiTokens.BUTTON_CMD_PRIMARY, _claim_selection], ["Cancel", UiTokens.BUTTON_CMD_SECONDARY, _cancel_claim]], _cancel_claim)
	_sign_out_confirm = _dialog("SignOutConfirm", SIGN_OUT_ASK, "", null,
		[["Sign out", UiTokens.BUTTON_CMD_DESTRUCTIVE, _sign_out], ["Cancel", UiTokens.BUTTON_CMD_SECONDARY, _cancel_sign_out]], _cancel_sign_out)
	_hud.add_child(_travel.make_iris())
	_area_timer = Timer.new(); _area_timer.one_shot = true; _area_timer.timeout.connect(_refresh_area); add_child(_area_timer)
	for node in [_bottom, _hud]: node.item_rect_changed.connect(_place_locate)
	_hud.resized.connect(_place_locate)
	_home.visibility_changed.connect(_place_locate)
	_render_account()

## The parcel card (C-85 ⑤ A / C): the band with the hero and its tag, the address, the cell counts, whose it is, the
## guide's next step at home, the overlapping parcels to pick from, and the actions the map had.
func _build_card() -> void:
	_card = Control.new(); _card.name = "Card"; _card.hide(); _card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_card)
	var box := PanelContainer.new(); box.name = "Surface"; box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_STOP; box.add_theme_stylebox_override("panel", MapUi.card_box()); _card.add_child(box)
	box.minimum_size_changed.connect(func(): _card.custom_minimum_size.y = box.get_combined_minimum_size().y)
	_card.add_child(MapUi.band())
	_card_hero = UiKit.icon(UiArt.hero("parcel"), MapUi.HERO); _card_hero.name = "Hero"
	_card_hero.position = Vector2(UiTokens.SPACE_S5, -MapUi.HERO * 0.5); _card.add_child(_card_hero)
	_card_tag = UiTagPill.new(PARCEL_TAG); _card_tag.name = "Tag"
	_card_tag.position = Vector2(MapUi.TAG_LEFT, (MapUi.BAND_H - UiTokens.SIZE_TAG_H) * 0.5); _card.add_child(_card_tag)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", int(UiTokens.SPACE_S2)); box.add_child(column)
	_card_name = MapUi.wrap(MapUi.label("", UiTokens.STYLE_TYPE_HEADLINE)); _card_name.name = "Name"; column.add_child(_card_name)
	_card_cells = MapUi.label("", UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_TEXT_MUTED); _card_cells.name = "Cells"; column.add_child(_card_cells)
	_owner_row = HBoxContainer.new(); _owner_row.name = "Owner"; _owner_row.add_theme_constant_override("separation", int(UiTokens.SPACE_S3))
	column.add_child(_owner_row)
	_owner_dot = MapUi.dot(); _owner_dot.name = "Dot"; _owner_row.add_child(_owner_dot)
	_details = MapUi.wrap(MapUi.label("", UiTokens.STYLE_TYPE_LABEL)); _details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owner_row.add_child(_details)
	_guide = MapUi.wrap(MapUi.label("", UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_TEXT_SECONDARY)); _guide.name = "Guide"
	column.add_child(_guide)
	_choices = VBoxContainer.new(); _choices.name = "Choices"; _choices.hide()
	_choices.add_theme_constant_override("separation", 1); column.add_child(_choices)
	var actions := VBoxContainer.new(); actions.add_theme_constant_override("separation", int(UiTokens.SPACE_S4))
	column.add_child(_gap(UiTokens.SPACE_S4)); column.add_child(actions)
	_claim = MapUi.command("Make this my first home", UiTokens.BUTTON_CMD_PRIMARY); _claim.name = "MakeHome"
	MapUi.set_icon(_claim, load(HOME_ICON), 18); _claim.hide(); _claim.pressed.connect(_ask_claim); actions.add_child(_claim)
	_enter = MapUi.command("Enter my farm", UiTokens.BUTTON_CMD_PRIMARY); _enter.name = "EnterFarm"
	_enter.hide(); _enter.pressed.connect(_enter_farm); actions.add_child(_enter)
	_open = MapUi.command("Preview in 3D", UiTokens.BUTTON_CMD_SECONDARY); _open.name = "Preview"
	_open.disabled = true; _open.pressed.connect(_preview); actions.add_child(_open)
	_reselect = MapUi.link("Give up and choose again", UiTokens.COLOR_ACTION_DANGER); _reselect.name = "GiveUp"
	_reselect.hide(); _reselect.pressed.connect(_abandon); actions.add_child(_reselect)

static func _gap(height: float) -> Control:
	var gap := Control.new(); gap.custom_minimum_size.y = height; gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

## A centred confirm dialog over a modal scrim (the claim confirm of ⑤ B, the sign-out confirm of C-110): an optional
## hero over the top edge, the question, an optional second line and full-width keys. A scrim tap is `cancel`.
func _dialog(node_name: String, title: String, line: String, hero: Texture2D, keys: Array, cancel: Callable) -> Control:
	var overlay := Control.new(); overlay.name = node_name; overlay.hide()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _hud.add_child(overlay)
	var scrim := ColorRect.new(); scrim.name = "Scrim"; scrim.color = UiTokens.COLOR_SCRIM_MODAL
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			scrim.accept_event(); cancel.call())
	overlay.add_child(scrim)
	var center := CenterContainer.new(); center.name = "Center"; center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE; overlay.add_child(center)
	var frame := Control.new(); frame.name = "Panel"; frame.custom_minimum_size.x = MapUi.DIALOG_W; center.add_child(frame)
	var box := PanelContainer.new(); box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_stylebox_override("panel", MapUi.card_box(MapUi.HERO * 0.5 + UiTokens.SPACE_S5 if hero != null else UiTokens.SPACE_S7, UiTokens.SPACE_S7))
	frame.add_child(box)
	box.minimum_size_changed.connect(func(): frame.custom_minimum_size.y = box.get_combined_minimum_size().y)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", int(UiTokens.SPACE_S4)); box.add_child(column)
	var heading := MapUi.wrap(MapUi.label(title, UiTokens.STYLE_TYPE_HEADLINE)); heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	if not line.is_empty():
		var second := MapUi.wrap(MapUi.label(line, UiTokens.STYLE_TYPE_BODY, UiTokens.COLOR_TEXT_SECONDARY))
		second.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; column.add_child(second)
	column.add_child(_gap(UiTokens.SPACE_S2))
	for key in keys:
		var b := MapUi.command(key[0], key[1]); b.pressed.connect(key[2]); column.add_child(b)
	if hero != null:
		var art := UiKit.icon(hero, MapUi.HERO); art.name = "Hero"
		art.position = Vector2((MapUi.DIALOG_W - MapUi.HERO) * 0.5, -MapUi.HERO * 0.5); frame.add_child(art)
	return overlay

func _show_dialog(dialog: Control) -> void:
	if dialog.visible: return
	dialog.show()
	UiMotion.panel_in(dialog.get_node("Center/Panel"), dialog.get_node("Scrim"))

func _ask_claim() -> void:
	_show_dialog(_confirm); _render()

func _cancel_claim() -> void:
	_confirm.hide(); _render()

func _cancel_sign_out() -> void:
	_sign_out_confirm.hide(); _render()

## Top system inset (status bar, notch) and bottom (gesture bar) in UI units; zero on desktop (as dynamic_farm.gd).
func _safe_margins() -> Vector4:
	if not is_inside_tree() or not (OS.has_feature("android") or OS.has_feature("ios")): return Vector4.ZERO
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0)

## Side keys sit LOCATE_GAP over whatever the bottom column shows (the card, a toast, the credits): locate at the right
## with My home above it, the profile key at the left level with locate. The round keys (locate, profile) fill their
## 44 px; the glass My home key draws a smaller disc in its 44 px, so its disc's outer edge lines up with locate's.
func _place_locate() -> void:
	if _locate == null or _bottom == null: return
	var nudge := (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5 # the glass disc's edge on the margin
	var right := _hud.size.x - UiTokens.SIZE_SCREEN_EDGE
	var y := _bottom.position.y - LOCATE_GAP - _locate.size.y
	_locate.position = Vector2(right - _locate.size.x, y)
	_profile_button.position = Vector2(UiTokens.SIZE_SCREEN_EDGE, y)
	if _home.visible: _home.position = Vector2(right + nudge - _home.size.x, y - _home.size.y - UiTokens.SPACE_S2)

## farm-dev's round locate key, styled as P0 styles it (Close round, floating shadow, the glyph as drawn): LOCK-24's
## MapLocateButton as it is, kept on the v3 map (C-106); the profile key is the same key (C-128). `tint` colours a white
## glyph (lucide's) the text colour the locate glyph is drawn in.
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

func _render() -> void:
	_render_account()
	if _selector == null or _suspended or _leaving: return
	_frame_on_entry()
	_retry.disabled = _selector.busy or _opening
	var id := str(_selector.selection.get("block_id", ""))
	if _selector.generation > 0: _claims.show_zone(_selector.generation) # Before the parcel layers load (C-130 V-362).
	if _selector.map_ready and _selector.generation > 0:
		_claims.attach(_selector.generation, id)
		if _area_generation != _selector.generation:
			_area_generation = _selector.generation; _area_timer.start(0.1)
	var state: String = _claims.status(id)
	var idle: bool = not _selector.busy and _selector.map_ready and not _opening and not _claims.busy and not _traveling()
	_open.disabled = not idle or id.is_empty()
	# A trip keeps the map draggable (D-437 §5) while its farm loads: a tap skips the walk instead of picking.
	_camera.input_enabled = (not _selector.busy or _traveling()) and not _opening and not _claims.busy and _profile == null and not _gated
	_render_card(id, state)
	var claimable: bool = state == "none" and _claims.mine_known and not _claims.has_home() and _claims.in_zone(id)
	if not claimable or not idle: _confirm.hide()
	_claim.visible = claimable and not _confirm.visible; _claim.disabled = not idle
	_enter.visible = state == "mine"; _enter.disabled = not idle
	_open.visible = state != "mine"
	_reselect.visible = state == "mine" and _claims.can_give_up(); _reselect.disabled = not idle
	_home.visible = _claims.has_home() and not (_entry != null and _entry.is_open())
	_home.disabled = _selector.manifest.is_empty() or _opening or _traveling()
	_locate.disabled = _home.disabled
	_render_entry()
	_render_travel()
	if not _selector.busy:
		_drop_farm = false
		# Enter my farm's read failed (its card says so): the trip home is called off.
		if _travel != null and _travel.heading(MapTravel.HOME) and _travel.phase != MapTravel.Phase.CLOSED and _farm_waiting.is_empty():
			_travel.cancel.call_deferred(false)
	if _own_farm_entry() and _claims.has_home(): _read_farm()
	if _selector._options.is_empty(): _choices.hide()
	_render_feedback(id)
	_place_locate.call_deferred()

## The card for the selected parcel (or the list of overlapping ones): name, counts, whose it is and the next step.
func _render_card(id: String, state: String) -> void:
	var claiming: bool = _claims.busy and _claims.message == CLAIMING
	_card.visible = (not id.is_empty() or _choices.visible) and not claiming and not _travel_card
	var mine := state == "mine"
	_card_tag.text = HOME_TAG if mine else PARCEL_TAG
	_card_hero.texture = UiArt.hero("home" if mine else "parcel")
	for node in [_card_name, _card_cells]: node.visible = not id.is_empty()
	_guide.text = guide_line() if mine else ""
	_guide.visible = not _guide.text.is_empty()
	if id.is_empty():
		_details.text = ""; _owner_row.hide(); return
	var p: Dictionary = _selector.selection
	_card_name.text = str(p.name)
	_card_cells.text = "%d core · %d walk-only extension cells" % [p.core_cell_count, p.extension_cell_count]
	var line := ""
	var color := UiTokens.COLOR_ACTION_DISABLED_INK
	if mine: line = "Your home"; color = UiTokens.COLOR_ACTION_PRIMARY
	elif state == "other":
		var owner: String = _claims.owner_name(id)
		line = ("Claimed by %s" % owner) if not owner.is_empty() else Claims.NO_NAME
		color = UiTokens.COLOR_BADGE_UNREAD
	elif state == "none" and _claims.has_home(): line = "You already have a home."
	elif _claims.signed_out: line = "Sign in to claim a home."
	elif state == "none" and not _claims.in_zone(id): line = Claims.OUTSIDE_ZONE
	elif state == "none": line = NOT_CLAIMED
	_details.text = line; MapUi.set_dot(_owner_dot, color); _owner_row.visible = not line.is_empty()

## The hint line, the load-failure card and the claim toast.
func _render_feedback(id: String) -> void:
	var failed := _failed()
	_error_card.visible = failed
	_error_line.text = _selector.message if failed else ""
	_set_hint(hint_line())
	var note: String = _claims.message
	_claim_toast.visible = not note.is_empty()
	if note == CLAIMING:
		_claim_note.text = "• • •  " + CLAIMING
		_claim_note.theme_type_variation = UiTokens.STYLE_TYPE_LABEL_ON_DARK
		_claim_toast.add_theme_stylebox_override("panel", MapUi.hint_box())
	elif not note.is_empty():
		_claim_note.text = note
		_claim_note.theme_type_variation = UiTokens.STYLE_TYPE_CAPTION
		_claim_toast.add_theme_stylebox_override("panel", MapUi.toast_box(UiTokens.COLOR_ACTION_DANGER))
	_claim_note.custom_minimum_size.x = _line_width(_claim_note)

## A selector line that failed and has Retry (map, parcel or farm read); shown on the load-failure card.
func _failed() -> bool:
	if _selector == null or _selector.busy: return false
	var text: String = _selector.message
	return text.contains("Retry") or text.to_lower().contains("try again")

## The one hint line under the top row: with nothing selected the next step (C-35) in place of the idle "Tap a building"
## prompt, so a player without a home reads it once (C-88#5); while busy or after a tap that found nothing, what the map
## says; over a selected parcel nothing but its load ("Loading dynamic farm…"); a failure goes on its card instead.
func hint_line() -> String:
	if _selector == null: return _message.text
	if _failed(): return ""
	var text: String = _selector.message
	if not _selector.selection.is_empty(): return text if _selector.busy else ""
	if _choices.visible: return text
	if text in ["", Selection.PROMPT, READY_TO_PREVIEW, CHOOSE_PREVIEW]: return _no_selection()
	return text

func _set_hint(text: String) -> void:
	_message.text = text
	if _hint == null: return
	_hint.visible = not text.is_empty()
	_message.custom_minimum_size.x = _line_width(_message)
	if _preview_note != null:
		_preview_note.custom_minimum_size.x = _line_width(_preview_note)
		_message.custom_minimum_size.x = maxf(_message.custom_minimum_size.x, _preview_note.custom_minimum_size.x)

## A label's one-line width, held to the screen less its margins (the label wraps beyond that).
func _line_width(l: Label) -> float:
	var font := l.get_theme_font("font")
	var size := l.get_theme_font_size("font_size")
	var widest := maxf(_hud.size.x, 360.0) - 2.0 * UiTokens.SIZE_SCREEN_EDGE - 2.0 * UiTokens.SPACE_S6 - MapUi.TOAST_BAR
	if font == null: return widest
	return minf(ceilf(font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x) + 1.0, widest)

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
	if _selector == null or _selector.manifest.is_empty() or _opening or _traveling(): return
	if not _frame_home(true): return
	# A home claimed on an earlier release opens in that release's farm (Q-172), which the map's release may not draw.
	if not _own_farm_entry(): return
	var release := _home_release()
	if release != str(_selector.manifest.get("dataset_version", "")): _selector.select_home(str(_claims.mine.parcel_id), release)

## The release the player's own farm opens in: the one the home was claimed on while it still serves its farms.
func _home_release() -> String:
	return _selector.home_release(str(_claims.mine.get("dataset_version", ""))) if _claims.has_home() else str(_selector.manifest.get("dataset_version", ""))

## The locate key: back to the player, who lives at their home; without a home, back to the starter zone (C-130) or the
## dataset's area.
func _locate_player() -> void:
	if _selector == null or _selector.manifest.is_empty() or _opening or _traveling(): return
	if not _frame_home(true): _reset_area(true)

## The account chip at the top right (C-110, C-85 ⑤ D): signed in, the avatar and the name (a tap asks to sign out);
## signed out, "Sign in" in the action colour; while the saved account is checked or signed out, the avatar and • • •.
## Development builds on the in-memory claim stand-in have no account and hide it.
func _render_account() -> void:
	if _account_button == null: return
	_profile_button.disabled = _opening or _profile != null or _profile_waiting or (_selector != null and _selector.busy) or _traveling()
	var net := get_node_or_null("/root/Net")
	var shown := net != null and not _fake_claims()
	_account_button.visible = shown
	if not shown:
		_sign_out_confirm.hide(); _account_toast.hide(); return
	var signed_in: bool = net.account.signed_in()
	var waiting := _restoring or _signing_out
	var text := BUSY_DOTS if waiting else _account_name(net.account) if signed_in else "Sign in"
	_style_account(signed_in or waiting, text)
	_account_button.disabled = waiting or _opening or (_claims != null and _claims.busy) or _traveling()
	if not signed_in or waiting: _sign_out_confirm.hide()
	_account_toast.visible = signed_in and not _restoring and not str(net.restore_error).is_empty()

func _style_account(with_avatar: bool, text: String) -> void:
	if _account_button.text == text and _avatar.visible == with_avatar and _account_styled: return
	_account_styled = true
	_account_button.text = text
	_avatar.visible = with_avatar
	if with_avatar:
		MapUi.glass_look(_account_button); _account_button.icon = null
	else:
		MapUi.primary_pill(_account_button); MapUi.set_icon(_account_button, load(PROFILE_ICON), 16)
	for state in ["normal", "hover", "focus", "disabled", "pressed", "hover_pressed"]:
		var box := _account_button.get_theme_stylebox(state).duplicate() as UiStyleBox
		box.content_margin_left = ACCOUNT_AVATAR_LEFT + MapUi.AVATAR + UiTokens.SPACE_S3 if with_avatar else UiTokens.SPACE_S5
		box.content_margin_right = UiTokens.SPACE_S5
		_account_button.add_theme_stylebox_override(state, box)
	var font := _account_button.get_theme_font("font")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _account_button.get_theme_font_size("font_size")).x
	width += (ACCOUNT_AVATAR_LEFT + MapUi.AVATAR + UiTokens.SPACE_S3 if with_avatar else UiTokens.SPACE_S5 + 16 + UiTokens.SPACE_S3) + UiTokens.SPACE_S5
	_account_button.custom_minimum_size.x = minf(ceilf(width) + 1.0, ACCOUNT_MAX_W)

## The chip's name: the account's display name, else its email, else "Signed in".
static func _account_name(account: AccountSession) -> String:
	var name := account.display_name if not account.display_name.is_empty() else account.email
	return name.left(40) if not name.is_empty() else SIGNED_IN_NO_NAME

func _account_action() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null or _restoring or _signing_out: return
	if net.account.signed_in(): _show_dialog(_sign_out_confirm); _render()
	else: _open_sign_in()

## Revokes this phone's token and clears the saved account; nothing signs in as a guest (C-146). Where the map needs an
## account, it goes away with the account: the parcels are cleared and the native map hidden, and the sign-in panel comes
## back until someone signs in, then the map loads again for that account.
func _sign_out() -> void:
	_sign_out_confirm.hide()
	var net := get_node_or_null("/root/Net")
	if net == null or _signing_out or _restoring: return
	_signing_out = true; _render()
	await net.sign_out(false)
	_signing_out = false
	if not is_inside_tree(): return
	_account_changed()
	if account_required() and not net.account.signed_in(): await _gate_map()

## Takes the map away for the sign-in panel and brings it back for the account that signs in.
func _gate_map() -> void:
	_gated = true # before the parcels are cleared, so nothing redrawn meanwhile lets the map move
	if _camera != null: _camera.stop()
	if _selector != null: _selector.pause() # clears the parcel layers and hides the native map
	if _claims != null: _claims.pause(); _claims.forget()
	if _entry != null: _entry.close_card()
	if not await _sign_in_gate(): return
	_account_changed()
	if _suspended or _leaving: return # resume() loads the map again
	# Google's account picker leaves the app while the panel is up: that pause made the Godot viewport opaque and
	# resume() kept it so behind the panel. Undone here, or the map stays grey until the next trip to the background (C-175).
	_presentation_epoch += 1
	if _bridge != null:
		get_viewport().transparent_bg = true
		_restore_surface_mode()
		_bridge.set_map_visible(true)
	if _camera != null: _camera._changed()
	if _selector != null: _selector.activate()
	if _claims != null: _claims.start()
	_render()
	_record_presentation("map", _presentation_epoch)

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

## Overlapping parcels (up to six) as a one-pick list in the card (C-85 ⑤ "多个地块重叠"); a row picks that parcel.
func _show_candidates(rows: Array) -> void:
	for child in _choices.get_children(): _choices.remove_child(child); child.queue_free()
	_candidate_ids.clear()
	for row in rows.slice(0, 6):
		_candidate_ids.append(str(row.block_id))
		var pick := MapUi.command(str(row.name), UiTokens.BUTTON_NAV_ROW); pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.pressed.connect(func(): _selector.choose(str(row.block_id)); _choices.hide(); _render())
		_choices.add_child(pick)
	_choices.show(); _render()

## The default area: the server's starter zone when it has one on (C-130), else the dataset's centre.
func _reset_area(fly := false) -> void:
	if _selector == null or _selector.busy or _selector.manifest.is_empty() or _opening or (fly and _traveling()): return
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
	if _selector != null and not _opening and not _traveling():
		_entering = str(_selector.selection.get("block_id", ""))
		var mine: bool = _claims != null and _claims.status(_entering) == "mine"
		_selector.open_farm(_home_release() if mine else "")
		# C-188: the avatar walks home meanwhile (or stays there) and the iris closes on it once the farm is read.
		if mine and _selector.busy and _travel != null and _own_farm_entry() and _travel.depart(MapTravel.HOME, _card):
			_travel.hold = true; _preload_scene(HOST); _render()

func _claim_selection() -> void:
	_confirm.hide()
	if _selector != null and not _selector.selection.is_empty():
		_framed_home = str(_selector.selection.block_id) # The player is already looking at the parcel they claim.
		_claims.claim(_selector.selection)

func _open_sign_in() -> void:
	if _claims == null or find_children("*", "AccountPanel", true, false).size() > 0: return
	# Loaded at run time: the panel uses the Net autoload, which scripts preloading this scene may not have yet.
	var panel: CanvasLayer = load(ACCOUNT_PANEL).open(self, "sign_in", "", true, true) # the v3 look (C-85 ④), in English (C-144)
	_camera.input_enabled = false
	var signed_in: bool = await panel.closed
	if not is_inside_tree(): return
	if signed_in: _account_changed()
	else: _render()

## The Washington Square pin (C-115): in packages that enter one's own farm, once the map shows; the card's Distance and Go
## need the home. Its card stands over the map's panels while it is open.
func _render_entry() -> void:
	if _entry == null: return
	_entry.camera = _camera
	_entry.visible = _own_farm_entry() and not _selector.manifest.is_empty() and not _suspended and not _leaving
	var center = _claims.mine.get("center") if _claims != null and _claims.has_home() else null
	_entry.home_center = center if Geo.valid_point(center) else []
	if not _entry.visible: _entry.close_card()

## A tap on the map: the Washington Square pin first (farm-dev's city map takes a pin's tap before the ground), else the
## building under it.
func _on_map_tap(point: Vector2) -> void:
	if _traveling(): # a tap while walking skips to the end (C-188, D-437 ④); nothing is picked meanwhile
		if _travel.walking(): _travel.skip()
		return
	if _entry != null and _entry.visible and not _opening and _entry.hit(point * _camera.size):
		_entry.open_card(); return
	_selector.tap(point, _camera.zoom)

## While the card is open it stands over the map's panels and side keys; a pin low on the screen, where the card would
## cover it, flies to the middle first.
func _on_entry_card(open: bool) -> void:
	_hud.move_child(_entry, -1 if open else 0)
	_bottom.visible = not open; _locate.visible = not open; _profile_button.visible = not open
	_home.visible = not open and _claims != null and _claims.has_home()
	if not open: return
	_camera.stop()
	var at: Vector2 = _entry.screen_point()
	if at == Vector2.INF or at.y > _camera.size.y * PIN_CLEAR_OF_CARD:
		_camera.fly_to(TownEntry.LON, TownEntry.LAT, _camera.zoom)

## Go on the Washington Square card: the 3D room above the map (AppRouter, as "Enter my farm"), trading through the home's
## parcel save. Back or the room's door returns here; the map then reads the save again for the guide's line.
## C-188: the avatar walks there first (map_travel.gd) while the room loads; the room opens once the iris has closed.
func _open_town() -> void:
	if not _own_farm_entry() or _claims == null or not _claims.has_home() or _opening or _profile != null or _traveling(): return
	var card: Control = _entry.card if _entry.is_open() else null
	if _travel != null and _travel.depart(TOWN, card, card.get_node_or_null("Sheet") if card != null else null):
		_preload_scene(ROOM); _render(); return
	_entry.close_card()
	await _enter_town()

func _enter_town() -> void:
	if _claims == null or not _claims.has_home(): _travel_back(); return
	var home: Dictionary = _claims.mine
	await _open_scene(ROOM, {"store": _farm_store(str(home.parcel_id), str(home.get("dataset_version", ""))),
		"parcel_id": str(home.parcel_id), "return_context": {"center": Array(_camera.center), "zoom": _camera.zoom}})

func _traveling() -> bool:
	return _travel != null and _travel.busy()

## The avatar's places (home's point, the Washington Square pin) and whether it shows: a package that enters its own farm,
## with a home. A new home (or none) puts it at home.
func _render_travel() -> void:
	if _travel == null: return
	_travel.camera = _camera
	var places := {}
	var center = _claims.mine.get("center") if _claims != null and _claims.has_home() else null
	if Geo.valid_point(center): places[MapTravel.HOME] = {"geo": center, "pin": null}
	if _entry != null and _entry.visible: places[TOWN] = {"geo": [TownEntry.LON, TownEntry.LAT], "pin": _entry}
	_travel.places = places
	var parcel := str(_claims.mine.get("parcel_id", "")) if places.has(MapTravel.HOME) else ""
	if parcel != MapTravel.home_parcel:
		MapTravel.home_parcel = parcel; MapTravel.at = MapTravel.HOME
	_travel.shown = _own_farm_entry() and places.has(MapTravel.HOME)

## The card faded out as the trip set off: the place card closes, the parcel card steps aside until the trip is over.
func _travel_card_gone() -> void:
	if _travel.destination() == TOWN: _entry.close_card()
	else: _travel_card = true; _render()

## The iris has closed on the place: its scene opens (the farm once read).
func _travel_closed(place: String) -> void:
	if place == TOWN: await _enter_town()
	elif not _farm_waiting.is_empty():
		var farm := _farm_waiting; _farm_waiting = {}
		await _open_farm_scene(farm)

## Back while walking, or the farm read failed: the avatar is back where it left; the scene's preload is dropped.
func _travel_cancelled(_place: String) -> void:
	_drop_preload()
	if _travel.destination() == MapTravel.HOME and _farm_waiting.is_empty() and _selector != null and _selector.busy: _drop_farm = true
	_farm_waiting = {}; _entering = ""
	_show_card()

## The place could not open (or the map came back): the iris opens from it and the avatar goes back where it left.
func _travel_back() -> void:
	if _travel == null or _travel.phase != MapTravel.Phase.CLOSED: return
	_drop_preload()
	_travel.come_back(_travel.destination(), _travel.origin())
	_show_card()

func _show_card() -> void:
	_travel_card = false
	if _card != null: _card.modulate.a = 1.0
	_render()

## T-02: the scene a trip goes to starts loading on the loader's thread as it sets off. Not where AppRouter loads on the
## main thread (sync_loads: the Compatibility renderer, whose threaded loads never finish).
func _preload_scene(path: String) -> void:
	var router := get_node_or_null("/root/AppRouter")
	if router == null or router.get("sync_loads") == true or not _preloading.is_empty(): return
	if ResourceLoader.load_threaded_request(path, "PackedScene") == OK: _preloading = path

## The preloaded scene when it is ready, else null; one still loading (or failed) is left to AppRouter to take (C-125).
func _take_preload(path: String) -> PackedScene:
	if _preloading.is_empty() or _preloading != path: return null
	_preloading = ""
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		return ResourceLoader.load_threaded_get(path) as PackedScene
	var router := get_node_or_null("/root/AppRouter")
	if router != null and router.has_method("adopt_threaded_load"): router.adopt_threaded_load(path)
	return null

func _drop_preload() -> void:
	if not _preloading.is_empty(): _take_preload(_preloading)

func _exit_tree() -> void:
	_drop_preload()

## The map has no player of its own, so after a cold start nothing had loaded the saved outfit and the profile's figure
## stayed blank ~3 s on its first open (C-133): its parts start loading on the loader's threads as the map opens.
func _warm_outfit() -> void:
	var avatar := get_node_or_null("/root/Avatar")
	if avatar != null: avatar.warm_saved_outfit()

## The profile over the map (C-128): the map's panels hide and its camera holds still until it closes.
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
	_profile = load(PROFILE).open(self, view, _profile_home())
	_profile.closed.connect(_profile_closed)
	_hud.hide()
	if _camera != null: _camera.input_enabled = false

## The profile's `My farm` (C-108, ①): the player's home once there is one; its card flies the map home (My home).
func _profile_home() -> Dictionary:
	if _claims == null or not _claims.has_home(): return {}
	return {"name": "Your Home", "pressed": _go_home}

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
	if _drop_farm: _drop_farm = false; _render(); return # its trip was cancelled with Back (C-188)
	# C-188: on the way home the farm opens once the iris has closed on it.
	if _travel != null and _travel.heading(MapTravel.HOME) and _travel.phase != MapTravel.Phase.CLOSED:
		_farm_waiting = farm; _travel.hold = false; return
	await _open_farm_scene(farm)

func _open_farm_scene(farm: Dictionary) -> void:
	if _leaving or _suspended or _opening: _travel_back(); return
	# Only the player's own parcel, opened from "Enter my farm", in a package with `own_farm` is farmable.
	var own: bool = _own_farm_entry() and _entering == str(farm.block_id) and _claims != null and _claims.status(_entering) == "mine"
	_entering = ""
	await _open_scene(HOST, {"farm": farm, "dataset": farm.dataset_version, "block_id": farm.block_id,
		"own_parcel" if own else "preview_only": true, "return_context": {"center": Array(_camera.center), "zoom": _camera.zoom}})

## Opens a 3D scene above the map through AppRouter: the parcel (dynamic_farm_host) or the Washington Square room. The map's
## occlusion colour is set first; the map goes opaque only once the router really pushes the scene (suspend).
## C-188: after a trip (the iris closed on `place`) a scene preloaded in time is pushed at once; else its loading layer
## stands on the iris's colour. Back on the map the iris opens from the place (resume); a scene that never opened sends
## the avatar back where it left.
func _open_scene(path: String, args: Dictionary) -> void:
	var place: String = _travel.destination() if _travel != null and _travel.phase == MapTravel.Phase.CLOSED else ""
	if _bridge == null or not _bridge.supports_surface_opacity() or not _bridge.set_map_occlusion_color(OCCLUSION_COLOR):
		_travel_back(); _render()
		_set_hint("Use the latest Dynamic Farm preview build."); return
	var router := get_node_or_null("/root/AppRouter")
	if router == null or not router.has_method("open_instance"):
		_travel_back()
		_set_hint("This preview is missing its scene router."); return
	_opening = true; _render()
	var english_args := args.duplicate()
	english_args[LoadingLayer.ENGLISH_UI] = true # its loading layer in English as well (C-144)
	_inside = place
	var packed := _take_preload(path) if not place.is_empty() else null
	if packed != null and router.has_method("push_packed") and router.push_packed(packed, english_args) != null: pass
	else:
		if not place.is_empty(): english_args[LoadingLayer.BACKDROP] = Color(OCCLUSION_COLOR)
		await router.open_instance(path, english_args)
	_opening = false
	if not _suspended:
		# Loading cancelled/failed before a host became top, or Back already returned here.
		_restore_surface_mode()
		_inside = ""; _travel_back()
		_render()

func suspend() -> void:
	# AppRouter invokes this when it actually pushes another scene.
	_suspend_map(_opening)

func _suspend_map(committing_preview: bool) -> void:
	_suspended = true
	_presentation_epoch += 1
	if _travel != null and not committing_preview: _travel.reset() # a walk (or its arrival) left for the background is called off
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
	if _gated: return # Back to the sign-in panel; the map loads once someone signs in (C-146).
	_hud.visible = _profile == null # Back from the dressing room: the profile is still over the map.
	_farm_fresh = false # Back from the parcel: its save has moved on.
	# C-188 (R-01..R-03): back from a trip's scene the iris opens from its place, where the avatar now stands.
	if _travel != null and not _inside.is_empty():
		_travel.come_back(_inside, _inside); _inside = ""; _show_card()
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
	if _traveling(): _travel.cancel(); return # Back while walking calls the trip off (C-188); later it waits
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
	if _gated: # Back on the sign-in panel leaves the app (C-146); the map behind it never opened.
		if _bridge == null or not _bridge.move_task_to_back(): _quit_preview()
		return true
	if is_instance_valid(_profile):
		_profile.back()
		return true
	if _traveling(): # Back while walking calls the trip off (C-188); past the arrival it waits for the scene
		_travel.cancel(); return true
	if _entry != null and _entry.is_open():
		_entry.close_card(); return true
	_leave(); return true

func _notification(what: int) -> void:
	if not is_node_ready() or _selector == null: return
	if what == NOTIFICATION_APPLICATION_PAUSED and not _suspended: _suspend_map(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED and _suspended:
		var router := get_node_or_null("/root/AppRouter")
		if router == null or router.top_instance() in [null, self]: resume()
		else: _record_presentation("covered_foreground", _presentation_epoch)
