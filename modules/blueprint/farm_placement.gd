class_name FarmPlacement
extends RefCounted
## Map coordinates are [latitude, longitude], matching the bundled blueprint overlays.

const METERS_PER_DEGREE := 111320.0
const FOOTPRINT_MARGIN_M := 300.0
const GENERATION_VERSION := 2
const GENERATED_EXTENT_M := 160.0

static func is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	if value.size() != 2:
		return false
	for key in ["lat", "lng"]:
		var n = value.get(key)
		if typeof(n) != TYPE_FLOAT and typeof(n) != TYPE_INT:
			return false
		if not is_finite(float(n)):
			return false
	return absf(float(value.lat)) <= 85.0 and absf(float(value.lng)) <= 180.0

static func from_center(center: Vector2) -> Dictionary:
	return {"lat": snappedf(center.x, 0.000001), "lng": snappedf(center.y, 0.000001)}

static func contains(region: Dictionary, location: Dictionary, margin_m := FOOTPRINT_MARGIN_M) -> bool:
	if not is_valid(location):
		return false
	var bounds: Array = region.get("placement_bounds", [])
	if bounds.size() != 4:
		return false
	var lat := float(location.lat)
	var lng := float(location.lng)
	var dlat := margin_m / METERS_PER_DEGREE
	var dlng := dlat / cos(deg_to_rad(lat))
	return lat - dlat >= float(bounds[0]) and lng - dlng >= float(bounds[1]) \
		and lat + dlat <= float(bounds[2]) and lng + dlng <= float(bounds[3])

static func generated_contains(region: Dictionary, location: Dictionary) -> bool:
	return contains(region, location, GENERATED_EXTENT_M * 0.5)

## The selection outline describes the real source area, not an invented layout.
static func preview(region_id: String, center: Vector2) -> FarmBlueprint:
	var bp := FarmBlueprint.new()
	bp.layout_patch_id = "map_selection"
	bp.region_id = region_id
	bp.display_name = "My Farm"
	bp.revision = 1
	var latitude := GENERATED_EXTENT_M * 0.5 / METERS_PER_DEGREE
	var longitude := latitude / cos(deg_to_rad(center.x))
	bp.overlay = {"center": center, "paths": [], "blocks": [PackedVector2Array([
		center + Vector2(-latitude, -longitude), center + Vector2(-latitude, longitude),
		center + Vector2(latitude, longitude), center + Vector2(latitude, -longitude)])]}
	return bp
