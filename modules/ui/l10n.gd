class_name L10n
extends RefCounted
## Translate presentation values only; dictionary keys and saved IDs remain intact.

static func text(source: String) -> String:
	return TranslationServer.translate(source)

static func format_text(source: String, values: Variant) -> String:
	if values is Array:
		var translated := []
		for value in values:
			translated.append(item_name(value) if value is String else value)
		return text(source) % translated
	return text(source) % (item_name(values) if values is String else values)

static func item_name(id: String) -> String:
	if id in ["copper_ore", "rock_salt"]: return material_name(id)
	if id == "vegetable_soup": return dish_name(id)
	var names := {"wood": "Wood", "stone": "Stone", "fiber": "Reeds", "reeds": "Reeds", "salad": "Salad", "tea": "Tea", "nursery": "Nursery", "bistro": "Bistro", "courtyard": "Courtyard"}
	if TranslationServer.get_locale().begins_with("zh") and names.has(id): return text(names[id])
	return text(id)

static func material_name(id: String) -> String:
	return text({"wood": "Wood", "stone": "Stone", "fiber": "Reeds", "copper_ore": "Copper ore", "rock_salt": "Rock salt"}.get(id, id.capitalize()))

static func dish_name(id: String) -> String:
	return text({"salad": "Vegetable salad", "tea": "Chamomile tea", "vegetable_soup": "Rock-salt vegetable soup"}.get(id, id.capitalize()))

static func count_text(singular: String, plural: String, count: int) -> String:
	return format_text(singular if count == 1 else plural, count)
