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
var _land: ColorRect        # a first pick's ground under its pages: off while the real map is under the pin page
var open_map := Callable()
var close_map := Callable()
var return_main := Callable()   # only the host of a test account's first city pick supplies this

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
	if change_from == "" and return_main.is_valid(): cities.add_return_main(return_main)
	cities.back_pressed.connect(func(): if welcome != null: back_to_welcome() else: left.emit())
	cities.read_cities.connect(_read_cities)
	cities.unavailable.connect(func(text: String): say.emit(text))
	cities.picked.connect(open_spots)
	add_child(cities)

func _ready() -> void:
	# a test account's card is the taller (Return to main account): the first read's outline holds that place too
	if loading != null and return_main.is_valid():
		loading.add_return_main(func(): pass)   # never pressed: quieted below
		Welcome._quiet(loading.card)
	_read_cities("")

func _read_cities(q: String) -> void:
	P0HomePick.cities(session, q, func(d: Dictionary): _cities_read(d, q), func():
		_end_loading()
		if cities == null and welcome == null: _make_cities()
		if is_instance_valid(cities): cities.show_failed(q))

## The first read of a first pick: a city near — HOME-WELCOME, the list made behind it for `Choose another city`;
## none — the list (HOME-PICK-1-NOIP). Later reads (a search, a retry) go to the list.
func _cities_read(d: Dictionary, q: String) -> void:
	_end_loading()
	if cities == null and welcome == null:
		var near = d.get("near", null)
		if near is Dictionary:
			welcome = Welcome.new(near, _safe.y)
			if return_main.is_valid(): welcome.add_return_main(return_main)
			welcome.start_pressed.connect(func(): open_spots(near))
			welcome.other_pressed.connect(_other_city)
			add_child(welcome)
			_make_cities("Back")
			cities.visible = false
		else: _make_cities()
	if is_instance_valid(cities): cities.show_cities(d, q)

func _end_loading() -> void:
	if loading != null: loading.queue_free()
	loading = null

## HOME-WELCOME's `Choose another city`: the list, nothing picked.
func _other_city() -> void:
	cities.visible = true
	welcome.visible = false

## The list's `‹ Back` (and Back) to HOME-WELCOME.
func back_to_welcome() -> void:
	cities.visible = false
	welcome.visible = true

## Pick your farm spot for a city row (HOME-PIN): its pin area read for this player; the home city itself in a change
## starts the pin on the farm (q(216) ⑨).
func open_spots(row: Dictionary) -> void:
	_ack_city()
	if spots != null: spots.queue_free()
	_drop_map()
	var id := str(row.get("id", ""))
	if open_map.is_valid(): pick_map = open_map.call(id)
	if pick_map != null:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _land != null: _land.visible = false
		map_shown.emit(true)
	var city_name := str(row.get("name", ""))
	var same := change_from != "" and id == change_from
	spots = PinPage.new(id, city_name, "Change home city" if change_from != "" else "Pick your farm spot", _safe.x, _safe.y,
		same, farm_now() if same else null, pick_map)
	if change_from == "" and return_main.is_valid(): spots.add_return_main(return_main)   # a change has Settings
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

## Start here / Continue confirms S0; merely selecting a row, opening the list or changing home does not.
func _ack_city() -> void:
	if change_from == "" and session != null: session.guide_ack("t_city")

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
		_ack_city()   # explicit retry after a lost ack, before the queued choose_home
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
	_drop_map()
	if is_instance_valid(_under): _under.visible = true
	elif cities != null: cities.visible = true

## The pin page's map goes (‹ Change city, another city, the flow closed for any reason: built, ‹ Settings, a layer
## over it): popped by the host, the flow taking the touches again.
func _drop_map(later := false) -> void:
	if pick_map == null: return
	pick_map = null
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
