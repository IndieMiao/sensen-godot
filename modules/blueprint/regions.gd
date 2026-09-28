class_name FarmRegions
extends RefCounted
## regions.json（G0-A 管线产物）：城市目录 + 候选蓝图索引。不含任何候选经纬度。

const DEFAULT_PATH := "res://assets/farm/data/regions.json"
const CHOICE_PATH := "user://region_choice.json"
## 服务端下发过的全球城市（SGODOT-136）：选城页选中、或自己农场所在的城市落在这里，
## 让地图 / 选址 / 搬迁按 id 查得到它们。测试进程默认不读，避免本机缓存污染用例。
const CITY_CACHE_PATH := "user://city_cache.json"
static var cache_path := "" if _is_test_process() else CITY_CACHE_PATH

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
	var r := from_text(FileAccess.get_file_as_string(DEFAULT_PATH))
	if r != null:
		var known := {}
		for x in r.regions: known[str(x.id)] = true
		for c in cached_cities():
			if not known.has(str(c.get("id", ""))): r.regions.append(c)
	return r

static func _is_test_process() -> bool:
	if DisplayServer.get_name() == "headless": return true
	for a in OS.get_cmdline_args():
		if str(a).to_lower().contains("gdunit"): return true
	return false

## 服务端 cityView → 地图与选址沿用的 region 字典。全球城市没有蓝图候选（全部走地理生成）。
static func region_from_city(view: Dictionary) -> Dictionary:
	var center: Array = view.get("center", [])
	var bounds: Array = view.get("placement_bounds", [])
	if str(view.get("id", "")).is_empty() or center.size() != 2 or bounds.size() != 4: return {}
	return {"id": str(view.id), "name": str(view.get("name", view.id)), "timezone": str(view.get("timezone", "UTC")),
		"placement_bounds": bounds.duplicate(), "center": center.duplicate(), "street_zoom": 16, "pitch": 45,
		"candidates": [], "country": str(view.get("country", "")), "country_code": str(view.get("country_code", "")),
		"radius_km": float(view.get("radius_km", 20)), "global": true}

static func cached_cities() -> Array:
	if cache_path.is_empty() or not FileAccess.file_exists(cache_path): return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
	return parsed.get("cities", []) if parsed is Dictionary and parsed.get("cities") is Array else []

static func cached_region(id: String) -> Dictionary:
	for c in cached_cities():
		if str(c.get("id", "")) == id: return c
	return {}

## 记住一座服务端城市。精品城市（本地 regions.json 已有）不入缓存。返回 region 字典。
static func remember_city(view: Dictionary) -> Dictionary:
	var region := region_from_city(view)
	if region.is_empty() or cache_path.is_empty(): return region
	var local := from_text(FileAccess.get_file_as_string(DEFAULT_PATH)) if FileAccess.file_exists(DEFAULT_PATH) else null
	if local != null and not local.region(region.id).is_empty(): return local.region(region.id)
	var cities := cached_cities().filter(func(c): return str(c.get("id", "")) != region.id)
	cities.push_front(region)
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"cities": cities.slice(0, 40)}))
		f.close()
	return region

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
	if f == null:
		push_error("FarmRegions: 选择保存失败 err=%d path=%s" % [FileAccess.get_open_error(), CHOICE_PATH])
		return
	f.store_string(JSON.stringify({"region_id": id}))

static func load_choice() -> String:
	if not FileAccess.file_exists(CHOICE_PATH):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CHOICE_PATH))
	return str(parsed.get("region_id", "")) if typeof(parsed) == TYPE_DICTIONARY else ""

static func clear_choice() -> void:
	if FileAccess.file_exists(CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHOICE_PATH))
