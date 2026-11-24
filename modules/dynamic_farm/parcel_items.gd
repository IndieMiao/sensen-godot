extends RefCounted
## Names and icons of the parcel farm's items (C-59). The main farm's names and icons are reused
## read-only (P0 content and assets/p0/icons); only the parcel's own blueprints, which the main farm
## does not have, are named here, and show the existing recipe-card icon (no new art).
const NAMES := {"blueprint_cottage": "Cottage Blueprint", "blueprint_coop": "Coop Blueprint"}
const ICONS := {"blueprint_cottage": "recipe_card", "blueprint_coop": "recipe_card"}

static var _names := {}

## The item's display name, or "" for an id nothing names.
static func name_of(id: String) -> String:
	if NAMES.has(id): return NAMES[id]
	if _names.is_empty(): _names = _content_names()
	return str(_names.get(id, ""))

static func icon_of(id: String) -> Texture2D:
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
