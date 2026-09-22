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
	return not force_legacy and not region_id.is_empty() and FileAccess.file_exists(CITY_DIR + region_id + ".json")

static func city(region_id: String) -> Dictionary:
	if not has_city(region_id): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(CITY_DIR + region_id + ".json"))
	return data if data is Dictionary else {}

static func landmarks(region_id: String) -> Array:
	var result: Array = city(region_id).get("landmarks", [])
	for p in result:
		p.kind = "landmark"
	return result

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
	if str(poi.get("kind", "")) != "poi": return texture(art_key(poi))
	var key := icon_key(poi)
	if key.is_empty(): return texture("place")
	var pick := absi(str(poi.get("name", "")).hash()) % int(ICON_VARIANTS[key]) + 1
	var path := "%s%s_%d.webp" % [ICON_PATH, key, pick]
	return load(path) if ResourceLoader.exists(path) else texture("place")
