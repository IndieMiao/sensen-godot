class_name LandmarkScenes
extends RefCounted
## Only authored, completed destinations can expose a scene entry.
const GRIFFITH := "res://scenes/landmark/griffith_observatory.tscn"

static func path_for(region_id: String, entry: Dictionary) -> String:
	if region_id == "los_angeles" and str(entry.get("kind", "")) == "landmark" \
			and str(entry.get("id", "")) == "griffith_observatory":
		return GRIFFITH
	return ""
