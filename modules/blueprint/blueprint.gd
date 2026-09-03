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

static func from_dict(d: Dictionary) -> FarmBlueprint:
	if int(d.get("format", 0)) != FORMAT:
		push_error("FarmBlueprint: 不支持的 format %s" % str(d.get("format")))
		return null
	var bp := FarmBlueprint.new()
	bp.layout_patch_id = str(d.layout_patch_id)
	bp.revision = int(d.revision)
	bp.region_id = str(d.get("region_id", ""))
	bp.display_name = str(d.get("name", bp.layout_patch_id))
	bp.checksum = str(d.get("checksum", ""))
	bp.play_area_m = float(d.get("play_area_m", 0.0))
	bp.cell_m = float(d.get("cell_m", 1.0))
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

## 与 tools/geo_blueprint/src/writer.ts 的 canonical() 逐字一致，改一处必须改两处。
func canonical() -> String:
	var bed_strs := PackedStringArray()
	for bed in beds():
		var cs := PackedStringArray()
		for c in bed.cells:
			cs.append(_cs(c))
		bed_strs.append(",".join(cs))
	var anchors_str := "spawn:%s;house:%s;storage:%s;well:%s;exit:%s;beds:%s" % [
		_cs(anchor("spawn")), _cs(anchor("house")), _cs(anchor("storage")),
		_cs(anchor("well")), _cs(anchor("exit")), "/".join(bed_strs)]
	return "|".join(PackedStringArray([
		layout_patch_id, str(revision),
		"".join(masks.walkable), "".join(masks.cultivable), "".join(masks.buildable), "".join(masks.visual),
		anchors_str]))

func compute_checksum() -> String:
	return canonical().sha256_text()

func verify_checksum() -> bool:
	return not checksum.is_empty() and compute_checksum() == checksum
