class_name FarmPlot
extends RefCounted
## 农场地面属性（SGODOT-128 自由格子种田）。
##
## 读 `assets/farm/data/farm_plot.json`，把矩形、椭圆和曲线路径光栅化成一份 `FarmBlueprint`。
## 这是农场空间的唯一权威：哪些格能开垦、能放道具、能站人。
##
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

static func source_for(layout_id: String) -> Dictionary:
	return document().get("layouts", {}).get(layout_id, {})

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
		var bounds := region_bounds(region, curve)
		for j in range(maxi(0, floori(bounds.position.y)), mini(gy, ceili(bounds.end.y) + 1)):
			for i in range(maxi(0, floori(bounds.position.x)), mini(gx, ceili(bounds.end.x) + 1)):
				if region_contains(region, Vector2(i, j), curve): kinds[j * gx + i] = k

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
	return result

static func compute_checksum(bp: FarmBlueprint) -> String:
	return canonical(bp).sha256_text()

static func verify_checksum(bp: FarmBlueprint) -> bool:
	return not bp.checksum.is_empty() and compute_checksum(bp) == bp.checksum
