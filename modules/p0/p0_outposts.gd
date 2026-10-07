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

static func find(id: String) -> Dictionary:
	for o in all():
		if str(o.id) == id: return o
	return {}

static func by_role(role: String) -> Dictionary:
	for o in all():
		if str(o.role) == role: return o
	return {}

## A city-map place pin; `online` > 0 adds "· N online" to its label (all rooms together).
static func place_entry(o: Dictionary, online := 0) -> Dictionary:
	var role := str(o.role)
	return {"id": str(o.id), "kind": "place", "name": str(o.name), "category": str(o.category),
		"lat": float(o.lat), "lng": float(o.lng), "art_path": str(PIN_ART.get(role, PIN_ART.tackle)),
		"action": "Go", "action_icon": "footprints", "filter": "pond",
		"tag": ("%d online" % online) if online > 0 else ""}
