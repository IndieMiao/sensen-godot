extends RefCounted
## Rendering/hit testing only. Geometry and cells are authoritative offline products, never generated here.
const MAX_LAT := 85.051129
static func mercator_y(lat: float) -> float:
	var phi := deg_to_rad(clampf(lat, -MAX_LAT, MAX_LAT))
	return (1.0 - log(tan(PI * 0.25 + phi * 0.5)) / PI) * 0.5
static func latitude(y: float) -> float:
	return rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * y))))
static func project(lon: float, lat: float, center: Variant, size: Vector2, scale: float) -> Vector2:
	# Subtract in float64 BEFORE converting to Vector2(float32), otherwise block corners jitter at street zoom.
	return size * 0.5 + Vector2((lon - float(center[0])) / 360.0 * scale, (mercator_y(lat) - mercator_y(center[1])) * scale)
static func unproject(point: Vector2, center: Variant, size: Vector2, scale: float) -> PackedFloat64Array:
	var delta := point - size * 0.5
	return PackedFloat64Array([float(center[0]) + float(delta.x) / scale * 360.0, latitude(mercator_y(center[1]) + float(delta.y) / scale)])
static func bbox_intersects(a: Array, b: Array) -> bool:
	return a.size()==4 and b.size()==4 and float(a[0]) <= float(b[2]) and float(a[2]) >= float(b[0]) and float(a[1]) <= float(b[3]) and float(a[3]) >= float(b[1])
static func polygons(geometry: Dictionary) -> Array:
	var coords = geometry.get("coordinates", [])
	if not coords is Array: return []
	if geometry.get("type") == "Polygon": return [coords]
	if geometry.get("type") == "MultiPolygon": return coords
	return []
static func contains(point: Vector2, rings: Array) -> bool:
	if rings.is_empty() or not Geometry2D.is_point_in_polygon(point, rings[0]): return false
	for i in range(1,rings.size()):
		if Geometry2D.is_point_in_polygon(point,rings[i]): return false
	return true

static func valid_point(point:Variant) -> bool:
	if not point is Array or point.size()!=2:return false
	for value in point:
		if not (value is float or value is int) or not is_finite(float(value)):return false
	return absf(float(point[0]))<=180.0 and absf(float(point[1]))<=MAX_LAT

static func valid_bbox(box:Variant) -> bool:
	return box is Array and box.size()==4 and valid_point([box[0],box[1]]) and valid_point([box[2],box[3]]) and float(box[0])<float(box[2]) and float(box[1])<float(box[3])

static func valid_geometry(geometry:Dictionary) -> bool:
	var parts:=polygons(geometry)
	if parts.is_empty():return false
	for polygon in parts:
		if not polygon is Array or polygon.is_empty():return false
		for ring in polygon:
			if not ring is Array or ring.size()<4:return false
			for point in ring:
				if not valid_point(point):return false
			if ring[0]!=ring[-1]:return false
	return true

static func world_pixels(zoom:float,density:float,viewport_h:float,window_h:float) -> float:
	return 512.0*pow(2.0,zoom)*density*viewport_h/maxf(window_h,1.0)
