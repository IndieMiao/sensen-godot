extends Control
## The home pick (SGODOT-303): Choose your home city, then Pick your farm spot, one full-screen layer over no world
## (a new player's first pages, from p0_boot). The city page stays under the spot page, so `‹ Change city` comes back to
## it as it was (the search, the city picked). Reads through P0HomePick on the session; the choice goes out as
## choose_home by the host (P0Runtime.pick_home), which hears `chose` and answers with sent(ok).
## CHANGE (SGODOT-303 PR-4: change_from, the home now): from Settings — HOME-CHANGE-PICK, the spot page titled `Change
## home city`, and a spot asks HOME-CHANGE-CONFIRM first; its Move farm is the `chose` (change_home), Cancel leaves the
## spot page as it was. ‹ Settings (and Back on the city page) emits `left`.
## Emits chose(cluster, spot), say(text) for a toast, left (CHANGE).

signal chose(cluster: String, spot: int)
signal say(text: String)
signal left

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const PickPage := preload("res://scenes/p0/panels/p0_home_pick_page.gd")
const SpotPage := preload("res://scenes/p0/panels/p0_home_spot_page.gd")
const MoveConfirm := preload("res://scenes/p0/panels/p0_home_move_confirm.gd")

var session: Node
var cities: Control
var spots: Control
var _safe := Vector2.ZERO    # top, bottom
var _sending := false
var _spot_read := 0
var change_from := ""
var confirm: Control
var _spots_read := {}        # the spot page's read (its resets_day for the confirm card)

func _init(session_: Node = null, safe_top := 0.0, safe_bottom := 0.0, change_from_ := "") -> void:
	session = session_
	change_from = change_from_
	_safe = Vector2(safe_top, safe_bottom)
	name = "HomeFlow"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	cities = PickPage.new(safe_top, safe_bottom, change_from)
	cities.back_pressed.connect(func(): left.emit())
	cities.read_cities.connect(_read_cities)
	cities.unavailable.connect(func(text: String): say.emit(text))
	cities.picked.connect(open_spots)
	add_child(cities)

func _ready() -> void:
	_read_cities("")

func _read_cities(q: String) -> void:
	P0HomePick.cities(session, q, func(d: Dictionary): if is_instance_valid(cities): cities.show_cities(d, q),
		func(): if is_instance_valid(cities): cities.show_failed(q))

## Pick your farm spot for a city row: its three spots read for this player.
func open_spots(row: Dictionary) -> void:
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
		_sending = true
		chose.emit(cluster, spot))
	add_child(spots)
	cities.visible = false
	_read_spots(id)

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

## Back, a layer at a time: the confirm card, then the spot page, then (CHANGE) out to Settings.
func back() -> void:
	if confirm != null: close_confirm()
	elif spots != null: back_to_cities()
	elif change_from != "": left.emit()

func back_to_cities() -> void:
	close_confirm()
	if spots != null: spots.queue_free()
	spots = null
	cities.visible = true

## The host's answer to `chose`: refused or lost, the page stays for another go.
func sent(_ok: bool) -> void:
	_sending = false
