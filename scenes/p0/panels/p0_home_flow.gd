extends Control
## The home pick (SGODOT-303): Choose your home city, then Pick your farm spot, one full-screen layer over no world
## (a new player's first pages, from p0_boot). The city page stays under the spot page, so `‹ Change city` comes back to
## it as it was (the search, the city picked). Reads through P0HomePick on the session; the choice goes out as
## choose_home by the host (P0Runtime.pick_home), which hears `chose` and answers with sent(ok).
## Emits chose(cluster, spot), say(text) for a toast.

signal chose(cluster: String, spot: int)
signal say(text: String)

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const PickPage := preload("res://scenes/p0/panels/p0_home_pick_page.gd")
const SpotPage := preload("res://scenes/p0/panels/p0_home_spot_page.gd")

var session: Node
var cities: Control
var spots: Control
var _safe := Vector2.ZERO    # top, bottom
var _sending := false

func _init(session_: Node = null, safe_top := 0.0, safe_bottom := 0.0) -> void:
	session = session_
	_safe = Vector2(safe_top, safe_bottom)
	name = "HomeFlow"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	cities = PickPage.new(safe_top, safe_bottom)
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
	spots = SpotPage.new(id, str(row.get("name", "")), "Pick your farm spot", _safe.x, _safe.y)
	spots.back_pressed.connect(back_to_cities)
	spots.retry_pressed.connect(func(): _read_spots(id))
	spots.unavailable.connect(func(text: String): say.emit(text))
	spots.chosen.connect(func(cluster: String, spot: int):
		if _sending: return
		_sending = true
		chose.emit(cluster, spot))
	add_child(spots)
	cities.visible = false
	_read_spots(id)

func _read_spots(id: String) -> void:
	var page := spots
	P0HomePick.spots(session, id, func(d: Dictionary): if is_instance_valid(page): page.show_spots(d.spots),
		func(): if is_instance_valid(page): page.show_failed())

func back_to_cities() -> void:
	if spots != null: spots.queue_free()
	spots = null
	cities.visible = true

## The host's answer to `chose`: refused or lost, the page stays for another go.
func sent(_ok: bool) -> void:
	_sending = false
