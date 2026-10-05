class_name CityMapData
extends RefCounted
## Authored landmarks are independent of temporary provider POI results.
## 每座城市一份配置：总览视角、地标、居民锚点。有配置的城市就启用城市地图框架。
const CITY_DIR := "res://assets/map/cities/"
const ART_PATH := "res://assets/map/poi/"
const CATEGORIES := {"restaurant": "Restaurant", "chinese_restaurant": "Chinese restaurant", "cafe": "Café", "bakery": "Bakery", "park": "Park", "museum": "Museum", "shop": "Shop", "flower_shop": "Florist", "beach": "Beach", "theme_park": "Attraction", "place": "Place"}
const SHOP_MAKI := ["grocery", "shop", "clothing-store", "convenience", "supermarket", "shoe", "jewelry-store", "gift", "hardware", "furniture", "mobile-phone", "alcohol-shop", "watch", "department-store", "optician", "laundry"]

## 测试开关：为没有城市配置的城市保留的旧附近列表 UI 写测试时置 true。
static var force_legacy := false

static func has_city(region_id: String) -> bool:
	if force_legacy or region_id.is_empty(): return false
	return FileAccess.file_exists(CITY_DIR + region_id + ".json") or not FarmRegions.cached_region(region_id).is_empty()

static func city(region_id: String) -> Dictionary:
	if not has_city(region_id): return {}
	if not FileAccess.file_exists(CITY_DIR + region_id + ".json"): return generated_city(FarmRegions.cached_region(region_id))
	var data = JSON.parse_string(FileAccess.get_file_as_string(CITY_DIR + region_id + ".json"))
	return data if data is Dictionary else {}

## 没有人工配置的全球城市（SGODOT-136）：概览视角按城市半径取，无人工地标，
## 三位居民放在城市中心附近的固定偏移上，保证七日委托在任何城市都有人可找。
## 按玩家农场周边路网落位是 B1 的后续工作。
static func generated_city(region: Dictionary) -> Dictionary:
	var center: Array = region.get("center", [])
	if center.size() != 2: return {}
	var lat := float(center[0])
	var lng := float(center[1])
	var radius := float(region.get("radius_km", 20))
	var zoom := 11.0 if radius >= 45 else 11.5 if radius >= 30 else 12.0 if radius >= 20 else 12.5
	var spots := {"nursery": [0.012, -0.010], "bistro": [-0.008, 0.012], "courtyard": [0.004, 0.018]}
	var residents := []
	for spec in [["nursery_keeper", "nursery", "nursery"], ["bistro_owner", "bistro", "bistro"], ["restorer", "courtyard", "restorer"]]:
		var offset: Array = spots[spec[1]]
		residents.append({"id": spec[0], "place": spec[1], "slot": spec[2], "lat": lat + offset[0], "lng": lng + offset[1] / maxf(0.2, cos(deg_to_rad(lat)))})
	return {"format": 1, "generated": true, "overview": {"lat": lat, "lng": lng, "zoom": zoom, "bearing": 0.0},
		"landmarks": [], "residents": residents}

static func landmarks(region_id: String) -> Array:
	var data := city(region_id)
	var result: Array = data.get("landmarks", [])
	var overview: Dictionary = data.get("overview", {})
	if overview.has("lat") and overview.has("lng"):
		var own := result.map(func(p): return str(p.get("id", "")))
		for g in landmarks_near(float(overview.lat), float(overview.lng)):
			if not own.has(str(g.id)): result.append(g)
	for p in result:
		p.kind = "landmark"
	return result

## 设计部门的全国地标图标（Figma Landmark_icons）：任何城市都显示其地图中心 reach_km 内的地标。
## 城市景点 reach 40 km（纽约不带出费城的自由钟），国家公园等 150 km（弗拉格斯塔夫能看到大峡谷）。
const GLOBAL_LANDMARKS := "res://assets/map/landmarks.json"
static var _global_landmarks: Array = []

static func global_landmarks() -> Array:
	if _global_landmarks.is_empty() and FileAccess.file_exists(GLOBAL_LANDMARKS):
		var data = JSON.parse_string(FileAccess.get_file_as_string(GLOBAL_LANDMARKS))
		if data is Dictionary and data.get("landmarks") is Array: _global_landmarks = data.landmarks
	return _global_landmarks

static func landmarks_near(lat: float, lng: float) -> Array:
	var out := []
	for g in global_landmarks():
		if distance_km(lat, lng, float(g.lat), float(g.lng)) <= float(g.get("reach_km", 40)):
			out.append((g as Dictionary).duplicate(true))
	return out

static func distance_km(lat_a: float, lng_a: float, lat_b: float, lng_b: float) -> float:
	var x := deg_to_rad(lng_b - lng_a) * cos(deg_to_rad((lat_a + lat_b) * 0.5))
	var y := deg_to_rad(lat_b - lat_a)
	return 6371.0 * sqrt(x * x + y * y)

static func residents(region_id: String, state: Dictionary) -> Array:
	if state.is_empty(): return []
	var result := []
	for p in city(region_id).get("residents", []):
		if not ResidentCast.present(str(p.place), state).has(str(p.id)): continue
		p.kind = "resident"
		p.name = L10n.text(str(ResidentCast.definition(str(p.id)).name))
		p.category = "Resident"
		p.status = "Ready to deliver" if JourneyRequests.accepted(state, str(p.slot)) and JourneyRequests.supplies_ready(state, str(p.slot)) else "Talk"
		result.append(p)
	return result

static func art_key(poi: Dictionary) -> String:
	if poi.get("kind") == "pond": return "pond_" + str(poi.get("template_id", ""))
	if poi.has("art"): return str(poi.art)
	var maki := str(poi.get("maki", ""))
	var category := str(poi.get("category", "")).to_lower()
	# Cuisine is never inferred from a shop's name or from the broad food category.
	if category in ["chinese restaurant", "中餐厅", "中餐馆"]: return "chinese_restaurant"
	if maki.begins_with("restaurant") or maki in ["fast-food", "bar", "beer"]: return "restaurant"
	if maki in ["cafe", "bakery", "museum", "beach"]: return maki
	if maki in ["teahouse", "ice-cream"]: return "cafe"
	if maki == "confectionery": return "bakery"
	if maki in ["park", "garden", "picnic-site", "playground", "zoo", "dog-park"]: return "park"
	if maki in ["florist", "garden-centre"]: return "flower_shop"
	if maki == "art-gallery": return "museum"
	if maki in ["attraction", "amusement-park"]: return "theme_park"
	if maki in SHOP_MAKI: return "shop"
	var cls := str(poi.get("class", ""))
	if cls == "food_and_drink": return "restaurant"
	if cls == "park_like": return "park"
	if cls in ["store_like", "food_and_drink_stores"]: return "shop"
	return "place"

static func normalize(raw: Variant) -> Array:
	var result := []
	var ids := {}
	if not raw is Array: return result
	for item in raw:
		if not item is Dictionary: continue
		if not item.get("lat") is float and not item.get("lat") is int: continue
		if not item.get("lng") is float and not item.get("lng") is int: continue
		var lat := float(item.lat)
		var lng := float(item.lng)
		if not is_finite(lat) or not is_finite(lng) or absf(lat) > 85 or absf(lng) > 180: continue
		var id := str(item.get("id", ""))
		var title := str(item.get("name", "")).strip_edges().left(100)
		if id.is_empty() or title.is_empty() or ids.has(id): continue
		ids[id] = true
		var entry: Dictionary = item.duplicate()
		entry.name = title
		entry.kind = "poi"
		entry.art = art_key(item)
		entry.category = str(item.get("category", "")) if not str(item.get("category", "")).is_empty() else CATEGORIES.get(entry.art, "Place")
		result.append(entry)
		if result.size() >= 100: break
	return result

static func texture(key: String) -> Texture2D:
	var path := ART_PATH + key + ".png"
	if ResourceLoader.exists(path): return load(path)
	return GameUi.icon({"place":"map-pin", "beach":"sun", "theme_park":"star"}.get(key, "map-pin"))

## 普通 POI 用 Mapbox maki 语义的简单 3D 图标（不画建筑，地标除外），256px WebP。
## 每种 maki 的图标数 = ceil(洛杉矶 filterrank<5 采样数 / 10)，最少 2（2026-09-23 定案），
## 按名字哈希固定选一张。marker / parking / bridge 不上图。
const ICON_PATH := "res://assets/map/poi/icons/"
const ICON_VARIANTS := {"park": 20, "restaurant": 14, "school": 12, "fast-food": 10, "religious-christian": 9,
	"shop": 7, "grocery": 4, "fuel": 4, "lodging": 3, "cafe": 3, "bank": 3, "convenience": 3, "harbor": 3,
	"fire-station": 3, "pitch": 3, "doctor": 2, "information": 2, "restaurant-pizza": 2, "car-repair": 2,
	"fitness-centre": 2, "museum": 2, "theatre": 2, "beer": 2, "town-hall": 2, "bar": 2, "library": 2, "car": 2}
## 同义 maki 共用图标；既不在 ICON_VARIANTS 也不在这里的 maki 不上图。
const ICON_ALIAS := {"restaurant-noodle": "restaurant", "restaurant-seafood": "restaurant",
	"restaurant-sushi": "restaurant", "restaurant-bbq": "restaurant",
	"teahouse": "cafe", "supermarket": "grocery", "art-gallery": "museum",
	"garden": "park", "picnic-site": "park", "playground": "park", "dog-park": "park",
	"clothing-store": "shop", "shoe": "shop", "jewelry-store": "shop", "gift": "shop", "hardware": "shop",
	"furniture": "shop", "mobile-phone": "shop", "watch": "shop", "department-store": "shop", "optician": "shop"}
## 没有 maki 的旧数据/测试条目按语义族兜底。
const ICON_FROM_ART := {"restaurant": "restaurant", "chinese_restaurant": "restaurant", "cafe": "cafe", "park": "park", "shop": "shop"}

static func icon_key(poi: Dictionary) -> String:
	var maki := str(poi.get("maki", ""))
	if ICON_VARIANTS.has(maki): return maki
	if ICON_ALIAS.has(maki): return str(ICON_ALIAS[maki])
	if maki.is_empty(): return str(ICON_FROM_ART.get(art_key(poi), ""))
	return ""

## 地标用建筑贴图；普通 POI 用 maki 图标，同名永远同一张；无图标返回通用图钉（只用于卡片兜底）。
static func art_texture(poi: Dictionary) -> Texture2D:
	if poi.has("art_path") and ResourceLoader.exists(str(poi.art_path)): return load(str(poi.art_path))
	if poi.get("kind") == "pond": return SystemPonds.texture(str(poi.template_id))
	if str(poi.get("kind", "")) != "poi": return texture(art_key(poi))
	var key := icon_key(poi)
	if key.is_empty(): return texture("place")
	var pick := absi(str(poi.get("name", "")).hash()) % int(ICON_VARIANTS[key]) + 1
	var path := "%s%s_%d.webp" % [ICON_PATH, key, pick]
	return load(path) if ResourceLoader.exists(path) else texture("place")
