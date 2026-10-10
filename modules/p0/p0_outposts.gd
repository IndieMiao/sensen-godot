class_name P0Outposts
extends RefCounted
## The P0 home-set outposts (assets/p0/p0_outposts.json, shared with the P0 server): id, role, name,
## map position, room capacity, placeholder art and anchors file (SGODOT-227). role is the counter
## entry id (open_keeper_greeting(role), SGODOT-224).

const PATH := "res://assets/p0/p0_outposts.json"
## Map pin art per role; tea / post / market borrow POI icons until outpost pin art exists.
const PIN_ART := {
	"tackle": "res://assets/p0/art/map/tackle_shop.webp",
	"tea": "res://assets/map/poi/icons/cafe_1.webp",
	"post": "res://assets/map/poi/icons/information_1.webp",
	"market": "res://assets/map/poi/icons/grocery_1.webp",
}

static var _list: Array = []

static func all() -> Array:
	if _list.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _list = parsed.get("outposts", [])
	return _list

## An outpost by id: the home set, else a generated one of a city already read (P0CityPlaces, SGODOT-280).
static func find(id: String) -> Dictionary:
	for o in all():
		if str(o.id) == id: return o
	if id.find("~") > 0: return (load("res://modules/p0/p0_city_places.gd").outpost(id) as Dictionary)
	return {}

static func by_role(role: String) -> Dictionary:
	for o in all():
		if str(o.role) == role: return o
	return {}

## A city-map place pin; `online` (all rooms together) is its pin's top-right count, none at 0 (q(137) ③).
static func place_entry(o: Dictionary, online := 0) -> Dictionary:
	var role := str(o.role)
	return {"id": str(o.id), "kind": "place", "name": str(o.name), "category": str(o.category),
		"lat": float(o.lat), "lng": float(o.lng), "art_path": str(PIN_ART.get(role, PIN_ART.tackle)),
		"action": "Go", "action_icon": "footprints", "filter": "pond",
		"online": online}   # who is in: the pin's top-right count (q(137) ③), the card's Online now
