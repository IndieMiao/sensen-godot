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
	var names := {"wood": "Wood", "stone": "Stone", "fiber": "Reeds", "reeds": "Reeds", "salad": "Salad", "tea": "Tea", "nursery": "Nursery", "bistro": "Bistro", "courtyard": "Courtyard"}
	if TranslationServer.get_locale().begins_with("zh") and names.has(id): return text(names[id])
	return text(id)

static func count_text(singular: String, plural: String, count: int) -> String:
	return format_text(singular if count == 1 else plural, count)
