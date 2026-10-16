extends RefCounted
## The spot page's still map (HOME-PICK-3; 不知火舞 28883acf): Web Mercator on the 328 × 268 card, north up, and the
## open cities' baked pictures (assets/p0/home_spots/maps.json, from tools/p0/bake_home_spot_maps.ts: the game map's
## style, framed round each city's beginner pond and its three spots with room for a player's scatter). A picture is
## used only while every point lands inside it with CLEAR to spare (the spot table changed and it was not baked again:
## the plain card instead). Pure and static. Preloaded, no class_name (a new global class needs an editor import).

const MANIFEST := "res://assets/p0/home_spots/maps.json"
const DIR := "res://assets/p0/home_spots/"
const TILE := 512.0           # Mapbox's world is 512 · 2^zoom px wide (its static images too)
const MAX_ZOOM := 16.0        # three spots close together are not drawn closer than this
## How far a pin or the pond's name reaches from its point (left, top, right, bottom): a spot pin 36 across when
## picked; the pond's disc stands on its point (MapDestination anchor_offset) and its short name hangs under it.
const SPOT_REACH := Vector4(18, 18, 18, 18)
const POND_REACH := Vector4(30, 40, 30, 20)

static var _manifest = null

## A (lat, lng) in mercator units, 0..1 each way.
static func merc(at: Vector2) -> Vector2:
	var lat := clampf(at.x, -85.0, 85.0)
	return Vector2((at.y + 180.0) / 360.0, 0.5 - log(tan(PI / 4.0 + deg_to_rad(lat) / 2.0)) / TAU)

## A (lat, lng) on the card of the frame {center (mercator), scale (px per unit)}.
static func to_card(frame: Dictionary, at: Vector2, card: Vector2) -> Vector2:
	if frame.is_empty(): return card * 0.5
	return (merc(at) - (frame.center as Vector2)) * float(frame.scale) + card * 0.5

## The frame round the points (the pond first, then the spots): each reach clear of the edge by `clear`.
static func fit(points: Array, card: Vector2, clear: float) -> Dictionary:
	if points.is_empty(): return {}
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in points:
		var m := merc(p)
		lo = lo.min(m)
		hi = hi.max(m)
	var reach := Vector4(maxf(SPOT_REACH.x, POND_REACH.x), maxf(SPOT_REACH.y, POND_REACH.y), maxf(SPOT_REACH.z, POND_REACH.z),
		maxf(SPOT_REACH.w, POND_REACH.w))
	var inner := card - Vector2(reach.x + reach.z, reach.y + reach.w) - Vector2.ONE * clear * 2.0
	var span := (hi - lo).max(Vector2.ONE * 1e-9)
	var scale := minf(minf(inner.x / span.x, inner.y / span.y), TILE * pow(2.0, MAX_ZOOM))
	# centred in the inner box, which sits off the card's middle by the uneven reach
	var shift := Vector2(reach.x - reach.z, reach.y - reach.w) * 0.5
	return {center = (lo + hi) * 0.5 - shift / scale, scale = scale}

## Whether every point, with its reach, lands inside the card `clear` from its edge in this frame.
static func fits(entry: Dictionary, points: Array, card: Vector2, clear: float) -> bool:
	var frame := frame_of(entry)
	if frame.is_empty(): return false
	for i in points.size():
		var r := POND_REACH if i == 0 else SPOT_REACH
		var at := to_card(frame, points[i], card)
		if at.x - r.x < clear or at.y - r.y < clear or at.x + r.z > card.x - clear or at.y + r.w > card.y - clear: return false
	return true

## A baked picture's frame: its centre and zoom as it was asked of the map.
static func frame_of(entry: Dictionary) -> Dictionary:
	if not entry.has("lat") or not entry.has("zoom"): return {}
	return {center = merc(Vector2(float(entry.lat), float(entry.get("lng", 0.0)))), scale = TILE * pow(2.0, float(entry.zoom))}

## The city's baked picture's entry {file, lat, lng, zoom}, {} without one.
static func map(cluster: String) -> Dictionary:
	if _manifest == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
		_manifest = parsed.get("cities", {}) if parsed is Dictionary and parsed.get("cities") is Dictionary else {}
	var e = (_manifest as Dictionary).get(cluster, {})
	return e if e is Dictionary and ResourceLoader.exists(DIR + str(e.get("file", ""))) else {}

static func texture(entry: Dictionary) -> Texture2D:
	return load(DIR + str(entry.get("file", ""))) if not entry.is_empty() else null
