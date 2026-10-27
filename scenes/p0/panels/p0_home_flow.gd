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
## Emits chose(cluster, spot), say(text) for a toast, left (CHANGE).

signal chose(cluster: String, spot: int)
signal say(text: String)
signal left

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const PickPage := preload("res://scenes/p0/panels/p0_home_pick_page.gd")
const SpotPage := preload("res://scenes/p0/panels/p0_home_spot_page.gd")
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
	_end_loading()
	if cities == null and welcome == null:
		var near = d.get("near", null)
		if near is Dictionary:
			welcome = Welcome.new(near, _safe.y)
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

## Pick your farm spot for a city row: its three spots read for this player.
func open_spots(row: Dictionary) -> void:
	_ack_city()
	if spots != null: spots.queue_free()
	var id := str(row.get("id", ""))
	var city_name := str(row.get("name", ""))
	spots = SpotPage.new(id, city_name, "Change home city" if change_from != "" else "Pick your farm spot", _safe.x, _safe.y)
	spots.back_pressed.connect(back_to_cities)
	spots.retry_pressed.connect(func(): _read_spots(id))
	spots.unavailable.connect(func(text: String): say.emit(text))
	spots.chosen.connect(func(cluster: String, spot: int):
		if _sending: return
		if change_from != "":
			_confirm(cluster, spot, city_name)
			return
		_ack_city()   # explicit retry after a lost ack, before the queued choose_home
		_sending = true
		chose.emit(cluster, spot))
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
			page.show_spots(d.spots),
		func(): if is_instance_valid(page) and n == _spot_read: page.show_failed())

## HOME-CHANGE-CONFIRM over the spot page: Move farm sends the change; Cancel (or the scrim) closes it.
func _confirm(cluster: String, spot: int, city_name: String) -> void:
	close_confirm()
	confirm = MoveConfirm.new(city_name, P0HomePick.resets_line(_spots_read, city_name))
	confirm.cancelled.connect(close_confirm)
	confirm.move_pressed.connect(func():
		if _sending: return
		_sending = true
		chose.emit(cluster, spot))
	add_child(confirm)

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
	if is_instance_valid(_under): _under.visible = true
	elif cities != null: cities.visible = true

## The host's answer to `chose`: refused or lost, the page stays for another go.
func sent(_ok: bool) -> void:
	_sending = false
