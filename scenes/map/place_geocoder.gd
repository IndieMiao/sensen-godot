class_name PlaceGeocoder
extends Node
## 左上角标题的地名：Mapbox 反向地理编码（v6，types=place,region,country），回答"屏幕中心在哪个
## 城市/省州/国家里"。瓦片里的地名标签只能给出"最近的标签"，国界/州界附近会报错邻国，所以不用。
## 按 zoom 档位把中心量化成网格缓存，只在相机静止时请求；失败或海上返回空，标题回落 Explore。

const ENDPOINT := "https://api.mapbox.com/search/geocode/v6/reverse"
## 国名过长的常见国家用通用短名（官方全称在 360px 标题里只剩省略号）。
const SHORT_COUNTRY := {"cn": ["China", "中国"], "us": ["United States", "美国"], "gb": ["United Kingdom", "英国"], "kr": ["South Korea", "韩国"]}

var token := ""
## 最近一次完成的结果：{settlement, state, country}（缺项即没有）。
var places: Dictionary = {}
var _cache: Dictionary = {}
var _http: HTTPRequest
var _pending_key := ""
var _wanted_key := ""

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_completed)

## 网格量化：城市档 0.05°、省州档 0.5°、国家档 2°；同一格内移动不重复请求。
static func cell_key(lat: float, lng: float, zoom: float, locale: String) -> String:
	var step := 0.05 if zoom >= 7.0 else 0.5 if zoom >= 4.0 else 2.0
	return "%s|%.2f|%.2f|%s" % [str(step), snappedf(lat, step), snappedf(lng, step), "zh" if locale.begins_with("zh") else "en"]

func lookup(lat: float, lng: float, zoom: float, locale: String) -> void:
	var key := cell_key(lat, lng, zoom, locale)
	_wanted_key = key
	if _cache.has(key):
		places = _cache[key]
		return
	if token.is_empty() or not _pending_key.is_empty() or _http == null: return
	var parts := key.split("|")
	var url := "%s?longitude=%s&latitude=%s&types=place,region,country&language=%s&access_token=%s" % [
		ENDPOINT, parts[2], parts[1], "zh-Hans" if parts[3] == "zh" else "en", token]
	if _http.request(url) == OK: _pending_key = key

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var key := _pending_key
	_pending_key = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if key == _wanted_key: places = {}
		return
	var parsed := parse(body.get_string_from_utf8(), key.ends_with("|zh"))
	_cache[key] = parsed
	if _cache.size() > 256: _cache.erase(_cache.keys()[0])
	if key == _wanted_key: places = parsed
	# 等待期间中心已经移到别的格子：接着查最新那格。
	elif not _wanted_key.is_empty() and not _cache.has(_wanted_key):
		var p := _wanted_key.split("|")
		lookup(float(p[1]), float(p[2]), 7.0 if p[0] == "0.05" else 4.0 if p[0] == "0.5" else 0.0, "zh" if p[3] == "zh" else "en")

## v6 响应 → {settlement, state, country}。海上/无结果返回 {}。
static func parse(text: String, zh: bool) -> Dictionary:
	var data = JSON.parse_string(text)
	var out := {}
	if not data is Dictionary: return out
	for f in data.get("features", []):
		if not f is Dictionary: continue
		var props: Dictionary = f.get("properties", {})
		var name := str(props.get("name", "")).strip_edges()
		if name.is_empty(): continue
		match str(props.get("feature_type", "")):
			"place": out.settlement = name
			"region": out.state = name
			"country":
				var code := str((props.get("context", {}) as Dictionary).get("country", {}).get("country_code", "")).to_lower()
				out.country = SHORT_COUNTRY[code][1 if zh else 0] if SHORT_COUNTRY.has(code) else name
	return out
