class_name FarmBlueprint
extends RefCounted
## 只读街区蓝图（G0-A 管线产物 farm_blueprint.json）。
## 逻辑格 (i, j)：mask 行 = j（北为正），列 = i（东为正）。世界系 x = 东，z = -北。

const FORMAT := 1
const MASK_NAMES := ["visual", "walkable", "buildable", "cultivable"]
const POINT_ANCHORS := ["spawn", "house", "storage", "well", "exit"]

var layout_patch_id := ""
var revision := 0
var region_id := ""
var display_name := ""
var checksum := ""
## 权威尺寸是整数毫米（r2 起）。浮点 play_area_m / cell_m 是派生展示值，不进 canonical：
## JSON 解析不保留数值词法，同一份 "1.0" 在 TS 里 String() 得 "1"、在 GDScript 里 str() 得
## "1.0"，两端会算出不同的 checksum（Codex 三审 V3-I5）。
var cell_mm := 0
var play_area_mm := 0
var play_area_m := 0.0
var cell_m := 1.0
var grid := Vector2i.ZERO
var masks: Dictionary = {}
var paths: Array = []
var blocks: Array = []
var anchors: Dictionary = {}
var overlay: Dictionary = {}

static func asset_path(id: String, rev: int) -> String:
	return "res://assets/blueprints/%s/r%d/farm_blueprint.json" % [id, rev]

static func load_choice(choice: Dictionary) -> FarmBlueprint:
	var terrain = choice.get("farm_terrain", {})
	if choice.has("farm_terrain") and not terrain is Dictionary: return null
	if terrain is Dictionary and not terrain.is_empty():
		if str(choice.get("layout_patch_id", "")) != str(terrain.get("layout_id", "")): return null
		if not terrain.get("plot") is Dictionary: return null
		var revision = choice.get("revision", choice.get("blueprint_revision", 0))
		if not (revision is int or revision is float) or not is_finite(float(revision)) or float(revision) != floor(float(revision)): return null
		if revision != terrain.plot.get("revision", -1): return null
		if choice.has("blueprint_revision") and choice.blueprint_revision != revision: return null
		return FarmPlot.geography_for(terrain, str(choice.get("region_id", "")))
	if str(choice.get("layout_patch_id", "")).begins_with("geo_"): return null
	var bp := load_file(asset_path(str(choice.get("layout_patch_id", "")), int(choice.get("revision", choice.get("blueprint_revision", 2)))))
	if bp != null:
		return bp.with_location(choice.get("location", {}))
	return null

## Placement changes only the geographic overlay; logical cells and checksum stay identical.
func with_location(location: Dictionary) -> FarmBlueprint:
	if not FarmPlacement.is_valid(location):
		return self
	var placed := FarmBlueprint.new()
	for field in ["layout_patch_id", "revision", "region_id", "display_name", "checksum",
		"cell_mm", "play_area_mm", "play_area_m", "cell_m", "grid"]:
		placed.set(field, get(field))
	placed.masks = masks.duplicate(true)
	placed.paths = paths.duplicate(true)
	placed.blocks = blocks.duplicate(true)
	placed.anchors = anchors.duplicate(true)
	var origin: Vector2 = overlay.get("center", Vector2.ZERO)
	var destination := Vector2(float(location.lat), float(location.lng))
	var longitude_scale := cos(deg_to_rad(origin.x)) / cos(deg_to_rad(destination.x))
	placed.overlay = {"center": destination, "paths": [], "blocks": []}
	for group in ["paths", "blocks"]:
		for polygon in overlay.get(group, []):
			var points := PackedVector2Array()
			for point in polygon:
				var delta: Vector2 = point - origin
				points.append(destination + Vector2(delta.x, delta.y * longitude_scale))
			placed.overlay[group].append(points)
	return placed

static func load_file(path: String) -> FarmBlueprint:
	if not FileAccess.file_exists(path):
		push_error("FarmBlueprint: 文件不存在 %s" % path)
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("FarmBlueprint: JSON 解析失败 %s" % path)
		return null
	return from_dict(parsed)

static func _cell(v) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1]))

static func _points(arr) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out

## 校验必需字段存在且类型符合。失败时返回缺失的字段列表，成功时返回空数组。
static func _missing_keys(d: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	if not d.has("layout_patch_id"):
		missing.append("layout_patch_id")
	if not d.has("revision"):
		missing.append("revision")
	if not d.has("grid") or typeof(d.grid) != TYPE_ARRAY or d.grid is Array and d.grid.size() < 2:
		missing.append("grid")
	if not d.has("masks") or typeof(d.masks) != TYPE_DICTIONARY:
		missing.append("masks")
	elif typeof(d.masks) == TYPE_DICTIONARY:
		for name in MASK_NAMES:
			if not (d.masks as Dictionary).has(name):
				missing.append("masks.%s" % name)
	if not d.has("anchors") or typeof(d.anchors) != TYPE_DICTIONARY:
		missing.append("anchors")
	elif typeof(d.anchors) == TYPE_DICTIONARY:
		var a := d.anchors as Dictionary
		for name in POINT_ANCHORS:
			if not a.has(name):
				missing.append("anchors.%s" % name)
		if not a.has("beds") or typeof(a.beds) != TYPE_ARRAY or (a.beds as Array).is_empty():
			missing.append("anchors.beds")
		elif typeof(a.beds) == TYPE_ARRAY:
			for bed in a.beds as Array:
				if typeof(bed) != TYPE_DICTIONARY or not (bed as Dictionary).has("cells"):
					missing.append("anchors.beds[].cells")
					break
		if not a.has("reserved_bed") or typeof(a.reserved_bed) != TYPE_DICTIONARY:
			missing.append("anchors.reserved_bed")
		elif typeof(a.reserved_bed) == TYPE_DICTIONARY and not (a.reserved_bed as Dictionary).has("cells"):
			missing.append("anchors.reserved_bed.cells")
	return missing

## 字段级校验，与 packages/blueprint-core/src/parse.ts 同一套规则。checksum 只证明
## 「没被改过」，不证明「合法」——越界坐标、非法 mask 字符照样能算出一个合法的 sha256
## （Codex 二审 Important 10）。返回第一条错误信息，全部通过时返回空串。
static func _field_error(d: Dictionary) -> String:
	var id := str(d.get("layout_patch_id", ""))
	var id_re := RegEx.create_from_string("^[a-z0-9_]{1,32}$")
	if id_re.search(id) == null:
		return "layout_patch_id %s 不匹配 ^[a-z0-9_]{1,32}$" % id
	var g = d.get("grid", [])
	if typeof(g) != TYPE_ARRAY or (g as Array).size() != 2:
		return "grid 不是 [x, y]"
	var gx := int((g as Array)[0])
	var gy := int((g as Array)[1])
	if gx < 1 or gy < 1 or gx > 4096 or gy > 4096:
		return "grid 越界 %d,%d" % [gx, gy]
	for key in ["cell_mm", "play_area_mm"]:
		var v = d.get(key, null)
		# JSON 里的 1000.5 会被解析成 float；整数值的 float 允许（JSON 无整数类型），
		# 但带小数的一律拒绝——毫米是权威单位，不接受亚毫米精度。
		if v == null or (typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT):
			return "%s 缺失或非数值" % key
		if typeof(v) == TYPE_FLOAT and float(v) != floor(float(v)):
			return "%s 必须是整数毫米，收到 %s" % [key, str(v)]
		var n := int(v)
		if n < 1 or n > 100000:
			return "%s 越界 %d" % [key, n]
	for name in MASK_NAMES:
		var rows = (d.masks as Dictionary)[name]
		if typeof(rows) != TYPE_ARRAY or (rows as Array).size() != gy:
			return "masks.%s 应有 %d 行" % [name, gy]
		for row in rows as Array:
			if typeof(row) != TYPE_STRING or (row as String).length() != gx:
				return "masks.%s 每行应是 %d 字符" % [name, gx]
			for ch in row as String:
				if ch != "0" and ch != "1":
					return "masks.%s 只能含 0 与 1" % name
	var a := d.anchors as Dictionary
	var cells_to_check: Array = []
	for name in POINT_ANCHORS:
		cells_to_check.append(a[name])
	if (a.beds as Array).size() != 3:
		return "anchors.beds 必须恰好 3 条"
	for bed in a.beds as Array:
		var bc = (bed as Dictionary).cells
		if typeof(bc) != TYPE_ARRAY or (bc as Array).size() != 3:
			return "田畦必须恰好 3 格"
		cells_to_check.append_array(bc as Array)
	var rb = (a.reserved_bed as Dictionary).cells
	if typeof(rb) != TYPE_ARRAY or (rb as Array).size() != 3:
		return "预留畦必须恰好 3 格"
	cells_to_check.append_array(rb as Array)
	for c in cells_to_check:
		if typeof(c) != TYPE_ARRAY or (c as Array).size() != 2:
			return "格坐标不是 [i, j]"
		var ci := int((c as Array)[0])
		var cj := int((c as Array)[1])
		if ci < 0 or cj < 0 or ci >= gx or cj >= gy:
			return "格坐标越界 %d,%d" % [ci, cj]
	return ""

static func from_dict(d: Dictionary) -> FarmBlueprint:
	if int(d.get("format", 0)) != FORMAT:
		push_error("FarmBlueprint: 不支持的 format %s" % str(d.get("format")))
		return null
	var missing := _missing_keys(d)
	if not missing.is_empty():
		push_error("FarmBlueprint: 字段缺失/类型不符 %s" % ", ".join(missing))
		return null
	var field_error := _field_error(d)
	if not field_error.is_empty():
		push_error("FarmBlueprint: %s" % field_error)
		return null
	var bp := FarmBlueprint.new()
	bp.layout_patch_id = str(d.layout_patch_id)
	bp.revision = int(d.revision)
	bp.region_id = str(d.get("region_id", ""))
	bp.display_name = str(d.get("name", bp.layout_patch_id))
	bp.checksum = str(d.get("checksum", ""))
	bp.cell_mm = int(d.get("cell_mm", 0))
	bp.play_area_mm = int(d.get("play_area_mm", 0))
	if bp.cell_mm <= 0 or bp.play_area_mm <= 0:
		push_error("FarmBlueprint: 缺少整数毫米字段 cell_mm / play_area_mm（r2 起必需）")
		return null
	bp.play_area_m = float(bp.play_area_mm) / 1000.0
	bp.cell_m = float(bp.cell_mm) / 1000.0
	bp.grid = Vector2i(int(d.grid[0]), int(d.grid[1]))
	for name in MASK_NAMES:
		bp.masks[name] = PackedStringArray(d.masks[name])
	for p in d.get("paths", []):
		bp.paths.append({"id": str(p.id), "points": _points(p.points), "width_m": float(p.get("width_m", 3.0))})
	for b in d.get("blocks", []):
		bp.blocks.append({"id": str(b.id), "polygon": _points(b.polygon), "neighbors": PackedStringArray(b.get("neighbors", []))})
	var a: Dictionary = d.anchors
	for name in POINT_ANCHORS:
		bp.anchors[name] = _cell(a[name])
	var beds: Array = []
	for bed in a.beds:
		var cells: Array[Vector2i] = []
		for c in bed.cells:
			cells.append(_cell(c))
		beds.append({"id": str(bed.id), "cells": cells})
	bp.anchors["beds"] = beds
	var rcells: Array[Vector2i] = []
	for c in a.reserved_bed.cells:
		rcells.append(_cell(c))
	bp.anchors["reserved_bed"] = {"id": str(a.reserved_bed.id), "cells": rcells}
	var ov: Dictionary = d.get("overlay_wgs84", {})
	var ov_paths: Array = []
	for pl in ov.get("paths", []):
		ov_paths.append(_points(pl))
	var ov_blocks: Array = []
	for pg in ov.get("blocks", []):
		ov_blocks.append(_points(pg))
	var c = ov.get("center", [0.0, 0.0])
	bp.overlay = {"center": Vector2(float(c[0]), float(c[1])), "paths": ov_paths, "blocks": ov_blocks}
	return bp

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid.x and c.y < grid.y

func mask_has(mask: String, c: Vector2i) -> bool:
	if not in_bounds(c) or not masks.has(mask):
		return false
	return (masks[mask] as PackedStringArray)[c.y][c.x] == "1"

func is_walkable(c: Vector2i) -> bool:
	return mask_has("walkable", c)

func anchor(name: String) -> Vector2i:
	return anchors.get(name, Vector2i(-1, -1))

func beds() -> Array:
	return anchors.get("beds", [])

func reserved_bed() -> Dictionary:
	return anchors.get("reserved_bed", {})

func cell_to_world(c: Vector2i, scale := 1.0) -> Vector3:
	return Vector3((c.x + 0.5) * cell_m * scale, 0.0, -(c.y + 0.5) * cell_m * scale)

func world_to_cell(w: Vector3, scale := 1.0) -> Vector2i:
	return Vector2i(floori(w.x / (cell_m * scale)), floori(-w.z / (cell_m * scale)))

static func _cs(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

## 与 packages/blueprint-core/src/canonical.ts 逐字节一致，由 golden corpus
## （tests/blueprint/test_canonical.gd 与 packages/blueprint-core/test/canonical.test.ts
## 加载同一份 golden/corpus.json）两端钉住。改这里必须同步改那边。
##
## 文法（spec §5.1，单行用 | 连接）：
##   <id>|<format>|<revision>|<gx>,<gy>|<cell_mm>|<play_area_mm>
##   |<walkable>|<cultivable>|<buildable>|<visual>
##   |spawn:i,j;house:i,j;storage:i,j;well:i,j;exit:i,j;beds:<畦0>/<畦1>/<畦2>;reserved:<畦>
##
## 相对 r1 补了 format / revision / grid / cell_mm / play_area_mm / reserved_bed
## （2026-09-04 决策①）。r1 的公式不覆盖它们：把 grid 从 [64,64] 手改成 [32,128]、
## 或把 cell_m 从 1 改成 2（驱动每一次距离与耗时换算），checksum 照样通过，而客户端
## 会把同一份 4096 字符的 mask 解读成完全不同的网格。
##
## name 与 region_id 刻意不进 canonical：改显示名不该让已有存档失效。
func canonical() -> String:
	var bed_strs := PackedStringArray()
	for bed in beds():
		var cs := PackedStringArray()
		for c in bed.cells:
			cs.append(_cs(c))
		bed_strs.append(",".join(cs))
	var rcs := PackedStringArray()
	for c in reserved_bed().get("cells", []):
		rcs.append(_cs(c))
	var anchors_str := "spawn:%s;house:%s;storage:%s;well:%s;exit:%s;beds:%s;reserved:%s" % [
		_cs(anchor("spawn")), _cs(anchor("house")), _cs(anchor("storage")),
		_cs(anchor("well")), _cs(anchor("exit")), "/".join(bed_strs), ",".join(rcs)]
	return "|".join(PackedStringArray([
		layout_patch_id, str(FORMAT), str(revision),
		"%d,%d" % [grid.x, grid.y], str(cell_mm), str(play_area_mm),
		"".join(masks.walkable), "".join(masks.cultivable), "".join(masks.buildable), "".join(masks.visual),
		anchors_str]))

func compute_checksum() -> String:
	return canonical().sha256_text()

func verify_checksum() -> bool:
	return not checksum.is_empty() and compute_checksum() == checksum
