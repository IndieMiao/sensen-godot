extends RefCounted
## P0's ponds (SGODOT-270): the San Francisco points Journey's server already serves, bundled in
## assets/p0/p0_ponds.json because assets/ponds/catalog.json is frozen (its sha256 is Journey's catalog_revision). The
## P0 server reads the same file for each fishing place's map point. Each entry is registered with SystemPonds as a
## server-only pond on a bundled template, so SystemPonds.location / site / blueprint know it like a catalog pond.
## Templates (Pond / River) live on content.fishing.places (q(36)), not here. Preloaded, no class_name (a new global
## class needs an editor import).

const PATH := "res://assets/p0/p0_ponds.json"
static var _entries: Array = []

## Every P0 pond, registered with SystemPonds on the first call.
static func all() -> Array:
	if _entries.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		for raw in (data.get("locations", []) if data is Dictionary else []):
			var entry := SystemPonds.accept(raw)
			if entry.is_empty(): push_error("P0 ponds: %s does not fit a bundled template" % str(raw.get("id", "?")))
			else: _entries.append(entry)
	return _entries.duplicate(true)

## SystemPonds.location for a P0 pond, registering the list first ({} for an unknown id).
static func location(id: String) -> Dictionary:
	all()
	return SystemPonds.location(id)
