extends Control
## The home pick (SGODOT-303): Choose your home city, then Pick your farm spot, one full-screen layer over no world
## (a new player's first pages, from p0_boot). The city page stays under the spot page, so `‹ Change city` comes back to
## it as it was (the search, the city picked). Reads through P0HomePick on the session; the choice goes out as
## choose_home by the host (P0Runtime.pick_home), which hears `chose` and answers with sent(ok).
## CHANGE (SGODOT-303 PR-4: change_from, the home now): from Settings — HOME-CHANGE-PICK, the spot page titled `Change
## home city`, and a spot asks HOME-CHANGE-CONFIRM first; its Move farm is the `chose` (change_home), Cancel leaves the
## spot page as it was. ‹ Settings (and Back on the city page) emits `left`.
## WELCOME (SGODOT-340 §4, 338 S0): a first pick whose address is near an open city opens on HOME-WELCOME, not the list:
## `Start here` goes straight to that city's spot page (its `‹ Change city` back to the card), `Choose another city`
## to the list with `‹ Back` to the card and nothing picked. No city near (or the read failed): the list, as before.
## Till that first read is in, the card's outline holds its place (不知火舞 342 8c4168ab); failed or timed out, the list's
## PICK-ERR-LIST, not a failure on the outline.
## PIN (SGODOT-342 PR-2, q(216)): the spot page is HOME-PIN, a free pin on the city's map; Build here asks
## HOME-PIN-CONFIRM on a first pick (Build farm is the `chose`) and HOME-CHANGE-CONFIRM on a change, for another city or
## the home city itself (q(216) ⑨: the pin starts on the farm as it stands).
## Emits chose(cluster, lat, lng), say(text) for a toast, left (CHANGE).

signal chose(cluster: String, lat: float, lng: float)
signal say(text: String)
signal left
signal map_shown(on: bool)   # the pin page's real map is under it: the flow and its scrim let the drags through

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const PickPage := preload("res://scenes/p0/panels/p0_home_pick_page.gd")
const PinPage := preload("res://scenes/p0/panels/p0_home_pin_page.gd")
const P0HomePin := preload("res://modules/p0/p0_home_pin.gd")
const MoveConfirm := preload("res://scenes/p0/panels/p0_home_move_confirm.gd")
const Welcome := preload("res://scenes/p0/panels/p0_home_welcome.gd")

var session: Node
var cities: Control
var spots: Control
var _safe := Vector2.ZERO    # top, bottom
var _sending := false
var _spot_read := 0
var change_from := ""
var confirm: Control
var _spots_read := {}        # the spot page's read (its resets_day for the confirm card)
var welcome: Control         # HOME-WELCOME, a first pick near an open city
var _under: Control          # the page the spot page covers: the list or HOME-WELCOME
var loading: Control         # a first pick's card outline till its first read is in
var pick_map: Object         # the map in its pick mode the pin page reads (null: the page's own flat map)
## The host's (P0Runtime): open_map(cluster) pushes the P0 map in its pick mode and returns it (null: none, the page's
## own flat map); close_map() pops it. Unset (the tests), the pin page keeps its flat map.
var _land: ColorRect        # a first pick's ground under its pages: off while the real map is under them
var _map_city := ""         # the city pick_map is over: HOME-WELCOME's map goes on under its pin page
## HOME-WELCOME's map (340 §4, PR-2b; 不知火舞 342 bce34a87): the city view it flies to from the globe (every city
## alike), and how long the flight takes.
const WELCOME_ZOOM := 11.0
const WELCOME_FLY_S := 1.0
var _glide := false         # the next pin page comes on HOME-WELCOME's map: its start glides in (motion.recenterMs)
var open_map := Callable()
var close_map := Callable()

func _init(session_: Node = null, safe_top := 0.0, safe_bottom := 0.0, change_from_ := "") -> void:
	session = session_
	change_from = change_from_
	_safe = Vector2(safe_top, safe_bottom)
	name = "HomeFlow"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if change_from != "": _make_cities()
	else:   # the first read decides: HOME-WELCOME or the list; the map's land meanwhile (HOME-WELCOME's ground)
		var land := ColorRect.new()
		_land = land
		land.name = "Land"
		land.color = Welcome.LAND
		land.mouse_filter = Control.MOUSE_FILTER_IGNORE
		land.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(land)
		loading = Welcome.placeholder(_safe.y)
		add_child(loading)

## The list (HOME-PICK-1): back_to "Back" when it opens from HOME-WELCOME.
func _make_cities(back_to := "") -> void:
	cities = PickPage.new(_safe.x, _safe.y, change_from, back_to)
	cities.back_pressed.connect(func(): if welcome != null: back_to_welcome() else: left.emit())
	cities.read_cities.connect(_read_cities)
	cities.unavailable.connect(func(text: String): say.emit(text))
	cities.picked.connect(open_spots)
	add_child(cities)

func _ready() -> void:
	_read_cities("")

func _read_cities(q: String) -> void:
	P0HomePick.cities(session, q, func(d: Dictionary): _cities_read(d, q), func():
		_end_loading()
		if cities == null and welcome == null: _make_cities()
		if is_instance_valid(cities): cities.show_failed(q))

## The first read of a first pick: a city near — HOME-WELCOME, the list made behind it for `Choose another city`;
## none — the list (HOME-PICK-1-NOIP). Later reads (a search, a retry) go to the list.
func _cities_read(d: Dictionary, q: String) -> void:
	d = dev_near(d, q)
	if cities == null and welcome == null:
		var near = d.get("near", null)
		_end_loading(near is Dictionary)   # the flight starts under it: a dissolve, not a one-frame cut (不知火舞 3730603f)
		if near is Dictionary:
			welcome = Welcome.new(near, _safe.y, _safe.x)
			welcome.start_pressed.connect(func(): open_spots(near))
			welcome.other_pressed.connect(_other_city)
			add_child(welcome)
			_welcome_map(true)
			_make_cities("Back")
			cities.visible = false
		else: _make_cities()
	else: _end_loading()
	if is_instance_valid(cities): cities.show_cities(d, q)

## A debug build with user://p0_near (one line: an open city's id) reads that city as Near you on the first read: an
## emulator's address is the host's, so HOME-WELCOME can be filmed there (PR-2b). Never in a release build.
static func dev_near(d: Dictionary, q: String) -> Dictionary:
	if q != "" or d.get("near") is Dictionary or not OS.is_debug_build() or not FileAccess.file_exists("user://p0_near"):
		return d
	var id := FileAccess.get_file_as_string("user://p0_near").strip_edges()
	for r in (d.get("open", []) if d.get("open") is Array else []):
		if r is Dictionary and str(r.get("id", "")) == id: return d.merged({"near": r}, true)
	return d

## The first read's card outline goes: at once, or (`fade`, HOME-WELCOME's flight starting) over motion.dissolveMs.
func _end_loading(fade := false) -> void:
	if loading == null: return
	if fade and loading.is_inside_tree():
		loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := loading.create_tween()
		t.tween_property(loading, "modulate:a", 0.0, UiKit.secs(UiTokens.MOTION_DISSOLVE_MS))
		t.tween_callback(loading.queue_free)
	else: loading.queue_free()
	loading = null

## HOME-WELCOME's `Choose another city`: the list, nothing picked; the list covers the screen, so the map goes.
func _other_city() -> void:
	cities.visible = true
	welcome.visible = false
	_drop_map()

## The list's `‹ Back` (and Back) to HOME-WELCOME: its map again, straight at the city view (no second flight).
func back_to_welcome() -> void:
	cities.visible = false
	welcome.visible = true
	_welcome_map(false)

## HOME-WELCOME over the real map (340 §4, PR-2b): the P0 map in its pick mode over the near city — the camera flies
## from the globe to the city view, then the card slides in; `fly` false (back to the card) puts it there at once.
## Modal: the map takes no touches. No map (the tests, a navigation under way): the card at once, on the land.
func _welcome_map(fly: bool) -> void:
	_take_map(str(welcome.row.get("id", "")))
	_pass_touches(false)
	welcome.map = pick_map
	if pick_map == null or not pick_map.has_method("pick_fly"):
		if fly: welcome.slide_in(false)
		else: welcome.slide_in(true, true)   # back to the card: it slides in again all the same (不知火舞 bce34a87)
		return
	welcome.wait_for_map()
	# The card laid out first: where the city goes reads its height. A one-shot connection, not an await — it goes with
	# the flow if the flow is freed this frame (an await would resume on a freed instance; 亚瑟 on #512).
	get_tree().process_frame.connect(_welcome_fly.bind(fly, pick_map), CONNECT_ONE_SHOT)

func _welcome_fly(fly: bool, m: Variant) -> void:
	if not is_instance_valid(welcome) or pick_map != m: return
	var at: Vector2 = welcome.get_global_transform_with_canvas() * welcome.city_point()
	pick_map.pick_fly(WELCOME_ZOOM, WELCOME_FLY_S if fly else 0.0, at,
		func(): if is_instance_valid(welcome): welcome.slide_in(true))

## The map over `cluster`, the one up kept when it is already over it (HOME-WELCOME → its pin page: one map).
func _take_map(cluster: String) -> void:
	if pick_map != null and _map_city == cluster: return
	_drop_map()
	if open_map.is_valid(): pick_map = open_map.call(cluster)
	if pick_map == null: return
	_map_city = cluster
	if _land != null: _land.visible = false

## The pin page lets the drags and pinches through to the map; HOME-WELCOME (modal) does not.
func _pass_touches(on: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
	map_shown.emit(on)

## Pick your farm spot for a city row (HOME-PIN): its pin area read for this player; the home city itself in a change
## starts the pin on the farm (q(216) ⑨).
func open_spots(row: Dictionary) -> void:
	if spots != null: spots.queue_free()
	var id := str(row.get("id", ""))
	_glide = pick_map != null and _map_city == id and is_instance_valid(welcome) and welcome.visible
	_take_map(id)
	if pick_map != null: _pass_touches(true)
	var city_name := str(row.get("name", ""))
	var same := change_from != "" and id == change_from
	spots = PinPage.new(id, city_name, "Change home city" if change_from != "" else "Pick your farm spot", _safe.x, _safe.y,
		same, farm_now() if same else null, pick_map)
	spots.glide_in = _glide
	spots.back_pressed.connect(back_to_cities)
	spots.retry_pressed.connect(func(): _read_spots(id))
	spots.unavailable.connect(func(text: String): say.emit(text))
	spots.chosen.connect(func(lat: float, lng: float):
		if _sending: return
		_confirm(id, lat, lng, city_name))
	add_child(spots)
	_under = cities if cities != null and cities.visible else welcome
	if cities != null: cities.visible = false
	if welcome != null: welcome.visible = false
	_read_spots(id)

## One read counts at a time: an older one's late answer (a Retry pressed meanwhile, 周瑜 on #451) is dropped.
func _read_spots(id: String) -> void:
	var page := spots
	_spot_read += 1
	var n := _spot_read
	P0HomePick.spots(session, id, func(d: Dictionary):
		if is_instance_valid(page) and n == _spot_read:
			_spots_read = d
			page.show_area(d),
		func(): if is_instance_valid(page) and n == _spot_read: page.show_failed())

## Over the pin page, HOME-PIN-CONFIRM (a first pick: Build farm) or HOME-CHANGE-CONFIRM (a change, the home city too:
## Move farm) sends the pin; Cancel (or the scrim) closes it, the pin where it was.
func _confirm(cluster: String, lat: float, lng: float, city_name: String) -> void:
	close_confirm()
	if change_from != "": confirm = MoveConfirm.new(city_name, P0HomePick.resets_line(_spots_read, city_name))
	else: confirm = MoveConfirm.new(city_name, "", P0HomePin.confirm_line(city_name, Vector2(lat, lng), spots.pond))
	confirm.cancelled.connect(close_confirm)
	confirm.move_pressed.connect(func():
		if _sending: return
		_sending = true
		chose.emit(cluster, lat, lng))
	add_child(confirm)

## The farm as it stands (view.home.farm), for a re-pin in the home city; null without one.
func farm_now() -> Variant:
	var v: Dictionary = session.get("view") if session != null and session.get("view") is Dictionary else {}
	var h = v.get("home", null)
	return P0HomePin.lat_lng(h.get("farm")) if h is Dictionary else null

func close_confirm() -> void:
	if confirm != null: confirm.queue_free()
	confirm = null

## Back, a layer at a time: the confirm card, then the spot page, then the list opened from HOME-WELCOME back to it,
## then (CHANGE) out to Settings. HOME-WELCOME itself stays (a first pick has nowhere to go back to).
func back() -> void:
	if confirm != null: close_confirm()
	elif spots != null: back_to_cities()
	elif welcome != null and cities != null and cities.visible: back_to_welcome()
	elif change_from != "": left.emit()

## The spot page's `‹ Change city`: back to the page it covered — the list, or HOME-WELCOME after `Start here`.
func back_to_cities() -> void:
	close_confirm()
	if spots != null: spots.queue_free()
	spots = null
	if is_instance_valid(_under) and _under == welcome:   # back to the card: its map stays, at the city view
		welcome.visible = true
		_welcome_map(false)
		return
	_drop_map()
	if is_instance_valid(_under): _under.visible = true
	elif cities != null: cities.visible = true

## The pin page's map goes (‹ Change city, another city, the flow closed for any reason: built, ‹ Settings, a layer
## over it): popped by the host, the flow taking the touches again.
func _drop_map(later := false) -> void:
	if pick_map == null: return
	pick_map = null
	_map_city = ""
	if is_instance_valid(welcome): welcome.map = null
	if close_map.is_valid():
		if later: close_map.call_deferred()   # leaving the tree, maybe with the root busy (the app quitting)
		else: close_map.call()
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _land != null: _land.visible = true
	map_shown.emit(false)

func _exit_tree() -> void:
	_drop_map(true)

## The host's answer to `chose`: refused or lost, the page stays for another go.
func sent(_ok: bool) -> void:
	_sending = false
