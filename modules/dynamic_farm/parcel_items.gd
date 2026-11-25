extends RefCounted
## Names and icons of the parcel farm's items (C-59). The main farm's names are reused read-only (P0 content); only
## the parcel's own blueprints, which the main farm does not have, are named here. Icons are the UI v3 item art (C-86,
## Q-155; C-105) where it has the item; the blueprints keep the existing recipe-card icon, anything else P0's icon.
const NAMES := {"blueprint_cottage": "Cottage Blueprint", "blueprint_coop": "Coop Blueprint"}
const ICONS := {"blueprint_cottage": "recipe_card", "blueprint_coop": "recipe_card"}
## Parcel item → UiArt item art. The hoe is the v3 row tool; the wild herb (picked from the flowers) is the chamomile.
const ART := {"crop_carrot": "carrot", "seed_carrot": "seed_carrot", "wood": "wood", "stone": "stone",
	"wild_herb": "chamomile", "hoe_starter": "row_tool"}

static var _names := {}

## The item's display name, or "" for an id nothing names.
static func name_of(id: String) -> String:
	if NAMES.has(id): return NAMES[id]
	if _names.is_empty(): _names = _content_names()
	return str(_names.get(id, ""))

static func icon_of(id: String) -> Texture2D:
	if ART.has(id):
		var art := UiArt.item(str(ART[id]))
		if art != null: return art
	return P0Logic.icon(str(ICONS.get(id, id)))

static func _content_names() -> Dictionary:
	var content := P0Logic.content()
	var names := {}
	for crop: Dictionary in content.get("crops", []):
		names[str(crop.get("id", ""))] = str(crop.get("name", ""))
		names[str(crop.get("seed", ""))] = str(crop.get("seed_name", ""))
	names.merge(content.get("tools", {}).get("names", {}))
	for id: String in content.get("materials", {}):
		names[id] = str(content.materials[id].get("name", ""))
	names.erase("")
	return names
