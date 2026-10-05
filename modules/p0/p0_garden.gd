class_name P0Garden
extends RefCounted
## The P0 homestead garden: the earlier fixed-plot layout (git c3b4204 FarmInterior) — 0.65 m cells,
## every plot its own thick soil bed (plot.glb) two cells apart so beds have walkways between them —
## grown to the 30 plots of plan §14.1.2 (6 columns × 5 rows). Plots and facilities are solid; the
## player works a bed from the walkway beside it. Pure data: no nodes, unit-tested.

const CELL_MM := 650
const GRID := Vector2i(22, 22)
const COLUMNS := 6
const ROWS := 5
const PLOT_ORIGIN := Vector2i(4, 3)   # plot 0 sits nearest the camera, on the left
const BED_H := 0.15                   # soil bed thickness (plot.glb top), crops grow from here

## Point anchors (cells). The house faces the field; the seed box and Bao stand on its right.
const ANCHORS := {
	"spawn": Vector2i(9, 1), "exit": Vector2i(9, 0),
	"house": Vector2i(9, 16), "storage": Vector2i(14, 15), "bao": Vector2i(15, 15),
	"well": Vector2i(17, 8), "mine": Vector2i(2, 14),
}
## Solid footprints beyond the plots (inclusive rects: x, y, w, h).
const FOOTPRINTS := {
	"house": Rect2i(8, 15, 4, 3), "storage": Rect2i(14, 15, 1, 1), "bao": Rect2i(15, 15, 1, 1),
	"well": Rect2i(17, 8, 1, 1), "mine": Rect2i(1, 13, 2, 2),
}
## Scenery trees stand outside the walkable yard, so they are not footprints.
const WALK_RECT := Rect2i(1, 0, 19, 20)
const CROP_CODES := {
	"crop_radish": "R", "crop_lettuce": "L", "crop_carrot": "C", "crop_chamomile": "H",
	"crop_herb": "B", "crop_potato": "P", "crop_chili": "I", "crop_tomato": "M",
}

static func plot_count() -> int: return COLUMNS * ROWS

static func cell_of(plot_id: int) -> Vector2i:
	return PLOT_ORIGIN + Vector2i((plot_id % COLUMNS) * 2, (plot_id / COLUMNS) * 2)

## -1 when the cell is not a plot.
static func id_of(cell: Vector2i) -> int:
	var d := cell - PLOT_ORIGIN
	if d.x < 0 or d.y < 0 or d.x % 2 != 0 or d.y % 2 != 0: return -1
	var col := d.x / 2
	var row := d.y / 2
	if col >= COLUMNS or row >= ROWS: return -1
	return row * COLUMNS + col

static func cell_id(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func blueprint() -> FarmBlueprint:
	var bp := FarmBlueprint.new()
	bp.layout_patch_id = "p0_garden"
	bp.revision = 1
	bp.display_name = "Homestead"
	bp.grid = GRID
	bp.cell_mm = CELL_MM
	bp.cell_m = CELL_MM / 1000.0
	bp.play_area_mm = GRID.x * CELL_MM
	bp.play_area_m = GRID.x * bp.cell_m
	bp.anchors = ANCHORS.duplicate()
	var beds: Array = []
	for row in ROWS:
		var cells: Array = []
		for col in COLUMNS: cells.append(cell_of(row * COLUMNS + col))
		beds.append({"id": "row%d" % row, "cells": cells})
	bp.anchors["beds"] = beds
	for key in FarmBlueprint.MASK_NAMES: bp.masks[key] = []
	for y in GRID.y:
		var walkable := ""
		var cultivable := ""
		for x in GRID.x:
			var c := Vector2i(x, y)
			var plot := id_of(c) >= 0
			cultivable += "1" if plot else "0"
			walkable += "1" if WALK_RECT.has_point(c) and not plot and not _in_footprint(c) else "0"
		bp.masks.visual.append("1".repeat(GRID.x))
		bp.masks.walkable.append(walkable)
		bp.masks.buildable.append("1".repeat(GRID.x))
		bp.masks.cultivable.append(cultivable)
	return bp

static func _in_footprint(c: Vector2i) -> bool:
	for key in FOOTPRINTS:
		var r: Rect2i = FOOTPRINTS[key]
		if r.has_point(c): return true
	return false

## P0 view → the old "x,y" cell dictionary CropField draws (wild weeds, tilled soil, crop stages).
## Growth stages come from ready_in and the crop's grow time (plan §5.3); "ready" is fully grown.
static func cells(view: Dictionary, now_ms: int) -> Dictionary:
	var grow := {}
	for c in view.get("crops", []): grow[str(c.get("id", ""))] = float(c.get("grow_h", 4)) * 3600000.0
	var out := {}
	for p in view.get("plots", []):
		var id := int(p.get("id", -1))
		if id < 0 or id >= plot_count(): continue
		var st := str(p.get("state", ""))
		var crop := str(p.get("crop", "")) if p.get("crop", null) != null else ""
		var code := str(CROP_CODES.get(crop, ""))
		var slot := {"state": st}
		match st:
			"sown":
				slot.crop = code
			"growing":
				var ready_at := now_ms + int(float(p.get("ready_in", 0)))
				slot = {"state": "growing", "crop": code, "ready_at": ready_at, "watered_at": ready_at - int(grow.get(crop, 3600000.0))}
			"ready":
				slot = {"state": "growing", "crop": code, "ready_at": now_ms, "watered_at": now_ms - int(grow.get(crop, 3600000.0))}
		out[cell_id(cell_of(id))] = slot
	return out

## Watered beds read darker; wild beds a touch greener; others plain (bed tint, multiplied in the shader).
static func bed_tint(state: String) -> Color:
	match state:
		"growing", "ready": return Color(0.80, 0.74, 0.70)
		"wild": return Color(0.94, 1.0, 0.90)
	return Color.WHITE
