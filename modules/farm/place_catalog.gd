class_name PlaceCatalog
extends RefCounted

static func all() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/places.json")).places

static func find(id: String) -> Dictionary:
	for place in all():
		if str(place.id) == id: return place
	return {}

static func available(id: String, state: Dictionary) -> bool:
	if JourneyProgress.active(state): return id in ["nursery", "courtyard"] or id == "bistro" and JourneyProgress.unlocked(state, "bistro")
	var place := find(id)
	return not place.is_empty() and state.has("clock") and int(state.clock.get("chapter_index", -1)) >= int(place.chapter)
