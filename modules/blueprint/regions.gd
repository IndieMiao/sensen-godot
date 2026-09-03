class_name FarmRegions
extends RefCounted
## regions.json（G0-A 管线产物）：城市目录 + 候选蓝图索引。不含任何候选经纬度。

const DEFAULT_PATH := "res://assets/farm/data/regions.json"
const CHOICE_PATH := "user://region_choice.json"

var regions: Array = []

static func from_text(text: String) -> FarmRegions:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("regions"):
		return null
	var r := FarmRegions.new()
	r.regions = parsed.regions
	return r

static func load_default() -> FarmRegions:
	if not FileAccess.file_exists(DEFAULT_PATH):
		push_error("FarmRegions: 缺少 %s（先跑 G0-A 管线或写临时文件）" % DEFAULT_PATH)
		return null
	return from_text(FileAccess.get_file_as_string(DEFAULT_PATH))

func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for r in regions:
		out.append(str(r.id))
	return out

func region(id: String) -> Dictionary:
	for r in regions:
		if str(r.id) == id:
			return r
	return {}

func candidates(region_id: String) -> Array:
	return region(region_id).get("candidates", [])

static func nearest_region_id(p_regions: Array, lat: float, lng: float) -> String:
	var best := ""
	var best_d := INF
	for r in p_regions:
		var d := MapGeoMath.geo_to_world(lat, lng, float(r.center[0]), float(r.center[1])).length()
		if d < best_d:
			best_d = d
			best = str(r.id)
	return best

static func save_choice(id: String) -> void:
	var f := FileAccess.open(CHOICE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"region_id": id}))

static func load_choice() -> String:
	if not FileAccess.file_exists(CHOICE_PATH):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CHOICE_PATH))
	return str(parsed.get("region_id", "")) if typeof(parsed) == TYPE_DICTIONARY else ""

static func clear_choice() -> void:
	if FileAccess.file_exists(CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHOICE_PATH))
