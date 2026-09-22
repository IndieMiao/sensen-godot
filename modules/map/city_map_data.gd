class_name CityMapData
extends RefCounted
## Authored landmarks are independent of temporary provider POI results.
const PATH := "res://assets/map/la_map.json"
const ART_PATH := "res://assets/map/poi/"
const CATEGORIES := {"restaurant": "Restaurant", "chinese_restaurant": "Chinese restaurant", "cafe": "Café", "bakery": "Bakery", "park": "Park", "museum": "Museum", "shop": "Shop", "flower_shop": "Florist", "beach": "Beach", "theme_park": "Attraction", "place": "Place"}
const SHOP_MAKI := ["grocery", "shop", "clothing-store", "convenience", "supermarket", "shoe", "jewelry-store", "gift", "hardware", "furniture", "mobile-phone", "alcohol-shop", "watch", "department-store", "optician", "laundry"]

static func landmarks(region_id: String) -> Array:
	if region_id != "los_angeles": return []
	var result: Array = JSON.parse_string(FileAccess.get_file_as_string(PATH)).landmarks
	for p in result:
		p.kind = "landmark"
	return result

static func residents(region_id: String, state: Dictionary) -> Array:
	if region_id != "los_angeles" or state.is_empty(): return []
	var result := []
	for p in JSON.parse_string(FileAccess.get_file_as_string(PATH)).residents:
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

## 每类可用的贴图套数（含基础图）。变体文件名：<key>_2.png、<key>_3.png……
const ART_VARIANTS := {"restaurant": 20, "chinese_restaurant": 20, "cafe": 20, "bakery": 20, "museum": 20}

## 同类 POI 在多套贴图间按名字哈希固定选择：同一家店永远同一张图，
## 不同店大概率不同图（餐饮同图扎堆的观感问题，2026-09-23 反馈）。
static func art_texture(poi: Dictionary) -> Texture2D:
	var key := art_key(poi)
	var count := int(ART_VARIANTS.get(key, 1))
	if count > 1 and str(poi.get("kind", "")) == "poi":
		var pick := absi(str(poi.get("name", "")).hash()) % count
		if pick > 0:
			var path := "%s%s_%d.png" % [ART_PATH, key, pick + 1]
			if ResourceLoader.exists(path): return load(path)
	return texture(key)
