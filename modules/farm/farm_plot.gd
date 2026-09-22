class_name FarmPlot
extends RefCounted
## 农场地面属性（SGODOT-128 自由格子种田）。
##
## 读 `assets/farm/data/farm_plot.json`，把矩形、椭圆和曲线路径光栅化成一份 `FarmBlueprint`。
## 这是农场空间的唯一权威：哪些格能开垦、能放道具、能站人。
##
## 旧农场保留本地布局；新农场使用服务器冻结的真实地理布局，导航与地面共用这份数据。
## 过去 `FarmInterior` 把服务端的 12 个格重排进一张 20×20 的合成网格、并在会话边界翻译
## 格 ID；现在农场格 ID **就是**服务端格 ID，那层翻译连同它的整类 bug 一起消失。
##
## 光栅化规则必须与 `server/src/domain/plot.ts` 逐字一致：全格先铺 default_kind，
## 再按 regions 声明顺序逐条绘制、后写覆盖先写；rect = [i0, j0, w, h] 是半开区间。
## 两端各算一份 checksum 对账，谁改歪了 golden 测试立刻变红。

const DATA_PATH := "res://assets/farm/data/farm_plot.json"

## kind → 三个属性位。故意写死在代码里：JSON 只声明地形，不声明规则。
const KIND_TRAITS := {
	"soil":     {"till": true,  "place": true,  "walk": true},
	"path":     {"till": false, "place": true,  "walk": true},
	"lawn":     {"till": false, "place": true,  "walk": true},
	"water":    {"till": false, "place": false, "walk": false},
	"building": {"till": false, "place": false, "walk": false},
	"rock":     {"till": false, "place": false, "walk": false},
}
const KIND_ORDER := ["soil", "path", "lawn", "water", "building", "rock"]

static var _cache: Dictionary = {}
static var _document: Dictionary = {}
## layout id → 逐格 kind 序号（KIND_ORDER 下标）。三张 mask 是有损的——water、
## building、rock 的可开垦/可通行/可放置全是 false，从 mask 反推分不开它们，
## 而摆景物必须分得开（花草不能撒进池塘或墙里）。光栅化时本来就算出来了，留住即可。
static var _kinds: Dictionary = {}
static var _terrain_order: Array[String] = []
static var _terrain_fingerprints: Dictionary = {}

## Register the server's immutable layout before constructing a scene. Never substitute a
## template after corrupt or incomplete geographic data: it would disagree with the server.
static func register_terrain(terrain: Dictionary) -> FarmBlueprint:
	if int(terrain.get("format", 0)) != 1: return null
	var id := str(terrain.get("layout_id", ""))
	if RegEx.create_from_string("^geo_[a-f0-9]{20}$").search(id) == null: return null
	var src = terrain.get("plot")
	if not src is Dictionary or not _valid_source(src): return null
	var checksum := str(src.get("checksum", ""))
	if RegEx.create_from_string("^[a-f0-9]{64}$").search(checksum) == null: return null
	var fingerprint := _source_fingerprint(src)
	if _cache.has(id):
		return _cache[id] if _cache[id].checksum == checksum and _terrain_fingerprints.get(id, "") == fingerprint else null
	var doc := document()
	doc.layouts[id] = src.duplicate(true)
	var bp := blueprint_for(id)
	if not verify_checksum(bp):
		_cache.erase(id)
		_kinds.erase(id)
		doc.layouts.erase(id)
		return null
	_terrain_fingerprints[id] = fingerprint
	_terrain_order.append(id)
	# Keep layouts still referenced by stacked farm scenes; discard old visit caches.
	for old_id in _terrain_order.duplicate():
		if _terrain_order.size() <= 24: break
		if old_id != id and _cache[old_id].get_reference_count() <= 1:
			_cache.erase(old_id)
			_kinds.erase(old_id)
			_terrain_fingerprints.erase(old_id)
			doc.layouts.erase(old_id)
			_terrain_order.erase(old_id)
	return bp

static func _source_fingerprint(src: Dictionary) -> String:
	var normalized := src.duplicate(true)
	# Public snapshots sanitize provider-specific region IDs. Those labels do not
	# change terrain, while geometry/order/anchors and every rendering field do.
	for region in normalized.regions: region.erase("id")
	return JSON.stringify(_normalized_numbers(normalized), "", true, true).sha256_text()

static func _normalized_numbers(value: Variant) -> Variant:
	if value is int or value is float: return float(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(_normalized_numbers(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _normalized_numbers(value[key])
		return result
	return value

static func _valid_point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n): return (n is int or n is float) and is_finite(float(n)) and absf(float(n)) <= 4096.0)

static func _valid_source(src: Dictionary) -> bool:
	if not _valid_point(src.get("grid")) or float(src.grid[0]) not in [40.0, 64.0] or src.grid[0] != src.grid[1]: return false
	var edge := int(src.grid[0])
	if src.get("cell_mm") != (800 if edge == 40 else 750) or src.get("revision") != 1: return false
	if str(src.get("default_kind", "")) not in KIND_ORDER: return false
	var anchors = src.get("anchors")
	if not anchors is Dictionary: return false
	for key in ["spawn", "exit", "house", "storage", "well", "mine", "stall"]:
		if not anchors.has(key): return false
	for cell in anchors.values():
		if not _valid_point(cell): return false
		for n in cell:
			if n != floor(float(n)) or n < 0 or n >= edge: return false
	var regions = src.get("regions")
	if not regions is Array or regions.size() > 1024: return false
	for region in regions:
		if not region is Dictionary or str(region.get("kind", "")) not in KIND_ORDER: return false
		var shapes := 0
		for key in ["rect", "ellipse", "path", "polygon"]:
			if not region.has(key): continue
			shapes += 1
			var value = region[key]
			if not value is Array: return false
			if key in ["rect", "ellipse"]:
				if value.size() != 4 or not _valid_point(value.slice(0, 2)) or not _valid_point(value.slice(2, 4)): return false
				if float(value[2]) <= 0 or float(value[3]) <= 0: return false
			else:
				if value.size() < (3 if key == "polygon" else 2) or value.size() > 8192: return false
				for point in value:
					if not _valid_point(point): return false
				if key == "path":
					var width = region.get("width")
					if not (width is int or width is float) or not is_finite(float(width)) or float(width) <= 0: return false
		if shapes != 1: return false
		var holes = region.get("holes", [])
		if not holes is Array or holes.size() > 256: return false
		for ring in holes:
			if not ring is Array or ring.size() < 3 or ring.size() > 8192: return false
			for point in ring:
				if not _valid_point(point): return false
	return true

static func source_for(layout_id: String) -> Dictionary:
	return document().get("layouts", {}).get(layout_id, {})

## A generated farm uses the same descriptor type as saved farms, but its map overlay
## comes from the selected location. No old street template is translated onto it.
static func geography_for(terrain: Dictionary, region_id := "") -> FarmBlueprint:
	var plot := register_terrain(terrain)
	if plot == null: return null
	var source: Dictionary = terrain.get("source", {})
	var center: Dictionary = source.get("center", {})
	# Private visitor snapshots intentionally omit provenance and the real location.
	if not source.is_empty() and not FarmPlacement.is_valid(center): return null
	var extent := float(source.get("extent_m", plot.play_area_m * 5.0))
	if not is_finite(extent) or extent <= 0 or extent > 10000: return null
	var bp := FarmBlueprint.new()
	for field in ["layout_patch_id", "revision", "display_name", "checksum", "cell_mm", "play_area_mm", "play_area_m", "cell_m", "grid"]:
		bp.set(field, plot.get(field))
	bp.region_id = region_id
	bp.masks = plot.masks.duplicate(true)
	bp.anchors = plot.anchors.duplicate(true)
	var origin := Vector2(float(center.get("lat", 0.0)), float(center.get("lng", 0.0)))
	bp.overlay = {"center": origin, "paths": [], "blocks": []}
	if source.is_empty(): return bp
	for region in source_for(plot.layout_patch_id).regions:
		if region.get("kind") != "path" or not region.has("path") or not str(region.get("id", "")).begins_with("geo_"): continue
		var points := PackedVector2Array()
		for point in region.path: points.append(_geographic_point(Vector2(point[0], point[1]), origin, extent, plot.grid.x))
		bp.overlay.paths.append(points)
	var boundary := PackedVector2Array()
	var edge := float(plot.grid.x) - 0.5
	for point in [Vector2(-0.5, -0.5), Vector2(edge, -0.5), Vector2(edge, edge), Vector2(-0.5, edge), Vector2(-0.5, -0.5)]:
		boundary.append(_geographic_point(point, origin, extent, plot.grid.x))
	bp.overlay.blocks.append(boundary)
	return bp

static func _geographic_point(cell: Vector2, center: Vector2, extent: float, grid_edge: int) -> Vector2:
	var meters := ((cell + Vector2.ONE * 0.5) / float(grid_edge) - Vector2.ONE * 0.5) * extent
	return center + Vector2(meters.y / FarmPlacement.METERS_PER_DEGREE,
		meters.x / (FarmPlacement.METERS_PER_DEGREE * cos(deg_to_rad(center.x))))

static func document() -> Dictionary:
	if _document.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("FarmPlot: 无法解析 %s" % DATA_PATH)
			return {}
		_document = parsed
	return _document

static func default_layout_id() -> String:
	return str(document().get("default_layout", ""))

## 光栅化成 FarmBlueprint。复用现有类型，`BlueprintGrid` / `PlayerMover` / `CropField`
## 一个字都不用改，只是构造来源换了。
static func blueprint_for(layout_id := "") -> FarmBlueprint:
	var doc := document()
	if doc.is_empty():
		return null
	var id := layout_id if not layout_id.is_empty() else str(doc.get("default_layout", ""))
	var layouts: Dictionary = doc.get("layouts", {})
	if not layouts.has(id):
		push_error("FarmPlot: 未知布局 %s" % id)
		return null
	if _cache.has(id):
		return _cache[id]

	var src: Dictionary = layouts[id]
	var grid: Array = src.get("grid", [64, 64])
	var gx := int(grid[0])
	var gy := int(grid[1])

	# 1. 逐格定 kind：先铺底，再按声明顺序覆盖。
	var kinds := PackedByteArray()
	kinds.resize(gx * gy)
	kinds.fill(maxi(0, KIND_ORDER.find(str(src.get("default_kind", "soil")))))
	for region in src.get("regions", []):
		var k := KIND_ORDER.find(str(region.get("kind", "")))
		if k < 0:
			continue
		var curve := path_points(region.get("path", []))
		var precise_curve := precise_path_points(region.get("path", [])) if id.begins_with("geo_") else []
		var bounds := region_bounds(region, curve)
		for j in range(maxi(0, floori(bounds.position.y)), mini(gy, ceili(bounds.end.y) + 1)):
			for i in range(maxi(0, floori(bounds.position.x)), mini(gx, ceili(bounds.end.x) + 1)):
				var contains := precise_region_contains(region, i, j, precise_curve) if id.begins_with("geo_") else region_contains(region, Vector2(i, j), curve)
				if contains: kinds[j * gx + i] = k

	# 2. kind → 三张 mask。visual 恒为 1：地面外观由 shader 按 kind 决定。
	var bp := FarmBlueprint.new()
	bp.layout_patch_id = id
	bp.revision = int(src.get("revision", 1))
	bp.display_name = str(src.get("name", id))
	bp.grid = Vector2i(gx, gy)
	bp.cell_mm = int(src.get("cell_mm", 500))
	bp.cell_m = float(bp.cell_mm) / 1000.0
	bp.play_area_mm = bp.cell_mm * gx
	bp.play_area_m = float(bp.play_area_mm) / 1000.0
	bp.checksum = str(src.get("checksum", ""))
	for name in FarmBlueprint.MASK_NAMES:
		bp.masks[name] = PackedStringArray()
	for j in gy:
		var walkable := ""
		var cultivable := ""
		var buildable := ""
		for i in gx:
			var traits: Dictionary = KIND_TRAITS[KIND_ORDER[kinds[j * gx + i]]]
			walkable += "1" if traits.walk else "0"
			cultivable += "1" if traits.till else "0"
			buildable += "1" if traits.place else "0"
		bp.masks.visual.append("1".repeat(gx))
		bp.masks.walkable.append(walkable)
		bp.masks.cultivable.append(cultivable)
		bp.masks.buildable.append(buildable)

	# 3. 锚点。没有田畦概念了，beds / reserved_bed 留空。
	bp.anchors = {"beds": [], "reserved_bed": {"id": "", "cells": []}}
	for key in src.get("anchors", {}):
		var cell: Array = src.anchors[key]
		bp.anchors[key] = Vector2i(int(cell[0]), int(cell[1]))
	_cache[id] = bp
	_kinds[id] = kinds
	return bp

static func path_points(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points.size() - 1):
		var a: Array = points[maxi(0, i - 1)]
		var b: Array = points[i]
		var c: Array = points[i + 1]
		var d: Array = points[mini(points.size() - 1, i + 2)]
		var p0 := Vector2(a[0], a[1])
		var p1 := Vector2(b[0], b[1])
		var p2 := Vector2(c[0], c[1])
		var p3 := Vector2(d[0], d[1])
		for step in 8:
			var t := float(step) / 8.0
			result.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
	if not points.is_empty(): result.append(Vector2(points[-1][0], points[-1][1]))
	return result

## Godot Vector2 uses float32; JavaScript and scalar GDScript floats use float64.
## Preserve original geographic coordinates throughout authoritative rasterization,
## including curve interpolation and stroke distances close to a cell boundary.
static func precise_path_points(points: Array) -> Array:
	var result: Array = []
	for i in range(points.size() - 1):
		var p0: Array = points[maxi(0, i - 1)]
		var p1: Array = points[i]
		var p2: Array = points[i + 1]
		var p3: Array = points[mini(points.size() - 1, i + 2)]
		for step in 8:
			var t := float(step) / 8.0
			var point: Array = []
			for axis in 2:
				point.append(0.5 * (2 * p1[axis] + (-p0[axis] + p2[axis]) * t
					+ (2 * p0[axis] - 5 * p1[axis] + 4 * p2[axis] - p3[axis]) * t * t
					+ (-p0[axis] + 3 * p1[axis] - 3 * p2[axis] + p3[axis]) * t * t * t))
			result.append(point)
	if not points.is_empty(): result.append(points[-1])
	return result

static func precise_region_contains(region: Dictionary, i: int, j: int, curve: Array) -> bool:
	if region.has("polygon"):
		if not ring_contains(region.polygon, Vector2(i, j)): return false
		for hole in region.get("holes", []):
			if ring_contains(hole, Vector2(i, j)): return false
		return true
	if region.has("rect"):
		var r: Array = region.rect
		return i >= r[0] and i < r[0] + r[2] and j >= r[1] and j < r[1] + r[3]
	if region.has("ellipse"):
		var e: Array = region.ellipse
		var x := (float(i) - float(e[0])) / float(e[2])
		var y := (float(j) - float(e[1])) / float(e[3])
		return x * x + y * y <= 1.00001
	if region.has("path"):
		var radius := float(region.width) * 0.5
		for n in range(1, curve.size()):
			var a: Array = curve[n - 1]
			var b: Array = curve[n]
			var dx := float(b[0]) - float(a[0])
			var dy := float(b[1]) - float(a[1])
			var t := clampf(((float(i) - float(a[0])) * dx + (float(j) - float(a[1])) * dy) / maxf(dx * dx + dy * dy, 0.000000000001), 0, 1)
			var x := float(i) - float(a[0]) - t * dx
			var y := float(j) - float(a[1]) - t * dy
			if x * x + y * y <= radius * radius + 0.00001: return true
	return false

static func region_contains(region: Dictionary, point: Vector2, curve: PackedVector2Array) -> bool:
	if region.has("rect"):
		var r: Array = region.rect
		return Rect2(r[0], r[1], r[2], r[3]).has_point(point)
	if region.has("ellipse"):
		var e: Array = region.ellipse
		return ((point - Vector2(e[0], e[1])) / Vector2(e[2], e[3])).length_squared() <= 1.00001
	if region.has("path"):
		var radius := float(region.get("width", 1.0)) * 0.5
		for n in range(1, curve.size()):
			var a := curve[n - 1]
			var span := curve[n] - a
			var t := clampf((point - a).dot(span) / maxf(span.length_squared(), 0.000000000001), 0, 1)
			if point.distance_squared_to(a + span * t) <= radius * radius + 0.00001: return true
	if region.has("polygon"):
		if not ring_contains(region.polygon, point): return false
		for hole in region.get("holes", []):
			if ring_contains(hole, point): return false
		return true
	return false

static func region_bounds(region: Dictionary, curve: PackedVector2Array) -> Rect2:
	if region.has("rect"):
		var r: Array = region.rect
		return Rect2(r[0], r[1], r[2], r[3])
	if region.has("ellipse"):
		var e: Array = region.ellipse
		return Rect2(e[0] - e[2], e[1] - e[3], e[2] * 2, e[3] * 2).grow(0.0001)
	var points := curve
	if region.has("polygon"):
		points = PackedVector2Array()
		for p in region.polygon: points.append(Vector2(p[0], p[1]))
	if points.is_empty(): return Rect2()
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points: result = result.expand(point)
	return result.grow(float(region.get("width", 0)) * 0.5 + 0.0001)

## Matches the server's polygon rasterizer, including boundaries and island holes.
static func ring_contains(ring: Array, point: Vector2) -> bool:
	var inside := false
	for i in ring.size():
		var a: Array = ring[(i + ring.size() - 1) % ring.size()]
		var b: Array = ring[i]
		var ax := float(a[0])
		var ay := float(a[1])
		var dx := float(b[0]) - ax
		var dy := float(b[1]) - ay
		var t := clampf(((float(point.x) - ax) * dx + (float(point.y) - ay) * dy) / maxf(dx * dx + dy * dy, 1.0e-30), 0, 1)
		var x := float(point.x) - ax - t * dx
		var y := float(point.y) - ay - t * dy
		if x * x + y * y <= 1.0e-14: return true
		if (ay > point.y) != (float(b[1]) > point.y) and point.x < dx * (float(point.y) - ay) / dy + ax:
			inside = not inside
	return inside

## 这一格的真实 kind（soil/path/lawn/water/building/rock）。越界或布局缺失返回 ""。
static func kind_at(layout_id: String, cell: Vector2i) -> String:
	var bp := blueprint_for(layout_id)
	if bp == null or not bp.in_bounds(cell):
		return ""
	var kinds: PackedByteArray = _kinds.get(layout_id, PackedByteArray())
	var index := cell.y * bp.grid.x + cell.x
	if index < 0 or index >= kinds.size():
		return ""
	return KIND_ORDER[kinds[index]]

## 与 `server/src/domain/plot.ts` 的 `canonical()` 逐字节一致。改这里必须同步改那边。
static func canonical(bp: FarmBlueprint) -> String:
	var result := "|".join(PackedStringArray([
		bp.layout_patch_id, "1", str(bp.revision),
		"%d,%d" % [bp.grid.x, bp.grid.y], str(bp.cell_mm),
		"".join(bp.masks.walkable), "".join(bp.masks.cultivable), "".join(bp.masks.buildable),
	]))
	if bp.layout_patch_id.begins_with("geo_"):
		var kinds := ""
		for kind in _kinds.get(bp.layout_patch_id, PackedByteArray()): kinds += str(kind)
		var anchors := PackedStringArray()
		var names: Array = source_for(bp.layout_patch_id).get("anchors", {}).keys()
		names.sort()
		for name in names:
			var cell := bp.anchor(name)
			anchors.append("%s:%d,%d" % [name, cell.x, cell.y])
		result += "|kinds:" + kinds + "|anchors:" + ";".join(anchors)
	return result

static func compute_checksum(bp: FarmBlueprint) -> String:
	return canonical(bp).sha256_text()

static func verify_checksum(bp: FarmBlueprint) -> bool:
	return not bp.checksum.is_empty() and compute_checksum(bp) == bp.checksum
