class_name LandmarkScenes
extends RefCounted
## Only authored, completed destinations can expose a scene entry. P0 opens these two (q(295)); a new one needs its own
## q row.
const GRIFFITH := "res://scenes/landmark/griffith_observatory.tscn"
const ALCATRAZ := "res://scenes/landmark/alcatraz_island.tscn"
const SCENES := {"los_angeles/griffith_observatory": GRIFFITH, "san_francisco/alcatraz_island": ALCATRAZ}

static func path_for(region_id: String, entry: Dictionary) -> String:
	if str(entry.get("kind", "")) != "landmark": return ""
	return str(SCENES.get("%s/%s" % [region_id, str(entry.get("id", ""))], ""))

## Whether `path` is one of these scenes (AppRouter's Back, P0's loading cover).
static func is_scene(path: String) -> bool:
	return path in SCENES.values()

## The region a landmark with a scene is in ("" for none): P0's dev entry `landmark:<id>`.
static func region_of(id: String) -> String:
	for key in SCENES:
		if str(key).get_slice("/", 1) == id: return str(key).get_slice("/", 0)
	return ""
