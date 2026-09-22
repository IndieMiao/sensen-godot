class_name FarmTerrainMask
extends RefCounted
## Smooth continuous terrain at 8 samples per cell; the 64² grid remains authoritative
## for actions. Cache by immutable checksum, so visiting the same farm does not rebake.

const RESOLUTION := 512
const CACHE_LIMIT := 8
const COLORS := {"path": "#ff0000", "rock": "#00ff00", "water": "#0000ff"}
static var _cache: Dictionary = {}

static func texture_for(bp: FarmBlueprint) -> Texture2D:
	if _cache.has(bp.checksum): return _cache[bp.checksum]
	var source := FarmPlot.source_for(bp.layout_patch_id)
	var unit := float(RESOLUTION) / bp.grid.x
	# Godot's native SVG rasterizer is available on Android too. It resolves hundreds
	# of geographic polygons without millions of interpreted point-in-ring calls.
	var base: String = COLORS.get(source.get("default_kind", "soil"), "#000000")
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="%s"/>' % base
	for region in source.get("regions", []):
		var color: String = COLORS.get(region.kind, "#000000")
		if region.has("rect"):
			var r: Array = region.rect
			svg += '<rect x="%f" y="%f" width="%f" height="%f" fill="%s"/>' % [r[0] * unit, r[1] * unit, r[2] * unit, r[3] * unit, color]
		elif region.has("ellipse"):
			var e: Array = region.ellipse
			# Fishing water and its decorative bank use the ellipse's world rim.
			# Adding half a cell here drew a second, shifted pond in GeographicWater
			# outside that rim (0.4m on compact farms). Other terrain keeps its
			# cell-centered visual sampling; geography polygons remain unchanged.
			var center_offset := 0.0 if region.kind == "water" else 0.5
			svg += '<ellipse cx="%f" cy="%f" rx="%f" ry="%f" fill="%s"/>' % [(e[0] + center_offset) * unit, (e[1] + center_offset) * unit, e[2] * unit, e[3] * unit, color]
		elif region.has("path"):
			var points := PackedStringArray()
			for point in FarmPlot.path_points(region.path): points.append('%f,%f' % [(point.x + 0.5) * unit, (point.y + 0.5) * unit])
			svg += '<polyline points="%s" fill="none" stroke="%s" stroke-width="%f" stroke-linecap="round" stroke-linejoin="round"/>' % [' '.join(points), color, float(region.width) * unit]
		elif region.has("polygon"):
			var d := _ring_path(region.polygon, unit)
			for hole in region.get("holes", []): d += _ring_path(hole, unit)
			svg += '<path d="%s" fill="%s" fill-rule="evenodd"/>' % [d, color]
	svg += '</svg>'
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK: return null
	image.convert(Image.FORMAT_RGBA8)
	_encode_water_depth(image, bp.play_area_m)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	while _cache.size() >= CACHE_LIMIT: _cache.erase(_cache.keys()[0])
	_cache[bp.checksum] = texture
	return texture

static func _ring_path(points: Array, unit: float) -> String:
	var result := ""
	for i in points.size():
		var p: Array = points[i]
		result += '%s%f,%f ' % ['M' if i == 0 else 'L', (p[0] + 0.5) * unit, (p[1] + 0.5) * unit]
	return result + 'Z '

## Precompute a shoreline distance field once. Water shading then needs one mask
## lookup instead of sampling many neighbours on every pixel of every frame.
static func _encode_water_depth(image: Image, extent: float) -> void:
	var bytes := image.get_data()
	var distances := PackedFloat32Array()
	distances.resize(RESOLUTION * RESOLUTION)
	for n in distances.size(): distances[n] = 10000.0 if bytes[n * 4 + 2] > 127 else 0.0
	for y in RESOLUTION:
		for x in RESOLUTION:
			var n := y * RESOLUTION + x
			if distances[n] == 0: continue
			if x > 0: distances[n] = minf(distances[n], distances[n - 1] + 1)
			if y > 0:
				distances[n] = minf(distances[n], distances[n - RESOLUTION] + 1)
				if x > 0: distances[n] = minf(distances[n], distances[n - RESOLUTION - 1] + 1.414214)
				if x < RESOLUTION - 1: distances[n] = minf(distances[n], distances[n - RESOLUTION + 1] + 1.414214)
	for y in range(RESOLUTION - 1, -1, -1):
		for x in range(RESOLUTION - 1, -1, -1):
			var n := y * RESOLUTION + x
			if x < RESOLUTION - 1: distances[n] = minf(distances[n], distances[n + 1] + 1)
			if y < RESOLUTION - 1:
				distances[n] = minf(distances[n], distances[n + RESOLUTION] + 1)
				if x > 0: distances[n] = minf(distances[n], distances[n + RESOLUTION - 1] + 1.414214)
				if x < RESOLUTION - 1: distances[n] = minf(distances[n], distances[n + RESOLUTION + 1] + 1.414214)
			bytes[n * 4 + 3] = int(clampf(distances[n] * extent / RESOLUTION / 1.8, 0.0, 1.0) * 255.0)
	image.set_data(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8, bytes)
