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
	# 11-08's cathedral (role church, no keeper): in from 0.3.0, so that build shows it right, not as a tackle shop
	"church": "res://assets/map/poi/icons/religious-christian_3_nocross.webp",
}
## SGODOT-351: the card room, San Francisco's fifth outpost — its pin and table wear i-cards (安其拉, Figma 176:165934;
## the recipe card if the file is missing), never the bar POI's; the pin only once the table is open to this player (q(238)).
const CARDS_ICON := "res://assets/p0/icons/cards.svg"
static func cards_icon() -> Texture2D:
	return load(CARDS_ICON) if ResourceLoader.exists(CARDS_ICON) else P0Logic.icon("recipe_card")

## The card room shows on the map once its gate is passed — Homestead Lv2 and the guide over (q(238), C11-3) — its pin
## hidden before, no grey card, no words (不知火舞 351 8aa69403). The client reads the gate from the view itself, not
## view.blackjack: 0.2.12 ships the room, Lou and his greeting to a server without the table (用户 via 奕星 on 351), so
## a player past the gate walks in there too; only Play asks whether the table is open (P0Ui._play_blackjack).
## TEMPORARY (iOS 0.3.1 (2), 11-07): Grace Cathedral closed on iOS — entering it crashed iOS 0.3.1 (1) at once (an
## external tester; Android's release build enters it fine), its cause still being found. Its pin is not drawn there, so
## nothing opens the room. Take this out with the cause's fix (奕星 11-07). Tests set it.
static var church_closed := OS.get_name() == "iOS"

static func shown(o: Dictionary, view: Dictionary) -> bool:
	if str(o.get("role", "")) == "church": return not church_closed
	if str(o.get("role", "")) != "casino": return true
	var h = view.get("homestead", {})
	return h is Dictionary and int(h.get("level", 1)) >= 2 and not P0Guide.guide_on(view)

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

## The written city's outpost of a role (the hand-written table). The player's own home set is home(view, role).
static func by_role(role: String) -> Dictionary:
	for o in all():
		if str(o.role) == role: return o
	return {}

## The id of the player's home-set outpost of a role (SGODOT-303 view.home.set: market / tea / tackle / post, and pond),
## frozen when the home was picked; the written city's where the view has none (an older server) or lacks the role.
static func home_id(view: Dictionary, role: String) -> String:
	var h = view.get("home", null)
	var set_ = (h as Dictionary).get("set", null) if h is Dictionary else null
	if set_ is Dictionary and str((set_ as Dictionary).get(role, "")) != "": return str(set_[role])
	return str(by_role(role).get("id", ""))

## The player's home-set outpost of a role: the written city's from its table, a generated home's once its places are
## in (P0CityPlaces, read when the view comes: P0Runtime); {} before then.
static func home(view: Dictionary, role: String) -> Dictionary:
	return find(home_id(view, role))

## A city-map place pin; `online` (all rooms together) is its pin's top-right count, none at 0 (q(137) ③).
static func place_entry(o: Dictionary, online := 0) -> Dictionary:
	var role := str(o.role)
	return {"id": str(o.id), "kind": "place", "name": str(o.name), "category": str(o.category),
		"lat": float(o.lat), "lng": float(o.lng), "art_path": str(PIN_ART.get(role, PIN_ART.tackle)),
		"action": "Go", "action_icon": "footprints", "filter": "pond",
		"online": online}   # who is in: the pin's top-right count (q(137) ③), the card's Online now
