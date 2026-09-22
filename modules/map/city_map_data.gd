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

## 视觉足迹：贴图中实体像素（alpha>0.5、行密度>=3%）的底边/底座范围，
## 由 tools/art/gen_poi_footprints.gd 离线烘焙；地图阴影据此贴住可视底座。
const ART_FOOTPRINTS := {
	"bakery": {"cx": -0.014, "bottom": 0.938, "width": 0.645},
	"beach": {"cx": -0.014, "bottom": 0.938, "width": 0.574},
	"cafe": {"cx": -0.021, "bottom": 0.934, "width": 0.551},
	"chinese_restaurant": {"cx": 0.014, "bottom": 0.938, "width": 0.668},
	"flower_shop": {"cx": 0.018, "bottom": 0.938, "width": 0.684},
	"griffith_observatory": {"cx": -0.002, "bottom": 0.938, "width": 0.855},
	"hollywood_sign": {"cx": 0.066, "bottom": 0.953, "width": 0.766},
	"museum": {"cx": -0.006, "bottom": 0.938, "width": 0.605},
	"park": {"cx": 0.053, "bottom": 0.934, "width": 0.684},
	"restaurant": {"cx": 0.021, "bottom": 0.938, "width": 0.699},
	"santa_monica_pier": {"cx": 0.254, "bottom": 0.949, "width": 0.391},
	"shop": {"cx": 0.010, "bottom": 0.938, "width": 0.637},
	"theme_park": {"cx": 0.016, "bottom": 0.938, "width": 0.742},
}

static func art_footprint(key: String) -> Dictionary:
	return ART_FOOTPRINTS.get(key, {"cx": 0.0, "bottom": 0.94, "width": 0.7})

static func texture(key: String) -> Texture2D:
	var path := ART_PATH + key + ".png"
	if ResourceLoader.exists(path): return load(path)
	return GameUi.icon({"place":"map-pin", "beach":"sun", "theme_park":"star"}.get(key, "map-pin"))
