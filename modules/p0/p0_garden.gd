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

## Point anchors (cells). The house faces the field; the stall (seed box for now) stands on its right.
const ANCHORS := {
	"spawn": Vector2i(9, 1), "exit": Vector2i(9, 0),
	"house": Vector2i(9, 16), "storage": Vector2i(14, 15),
	"well": Vector2i(17, 8), "mine": Vector2i(2, 14),
	# SGODOT-231 / q(45): five gathering spots on the farm edge (no Old Tree in P0) and the workbench on the house's
	# right past the stall (SGODOT-224's rest bench takes the left, Vector2i(5, 16)).
	"spot_grove": Vector2i(17, 12), "spot_rock_pile": Vector2i(18, 4), "spot_reed_bank": Vector2i(2, 4),
	"spot_clay_bank": Vector2i(2, 7), "spot_herb_patch": Vector2i(3, 17), "workbench": Vector2i(17, 16),
}
## Solid footprints beyond the plots (inclusive rects: x, y, w, h).
const FOOTPRINTS := {
	"house": Rect2i(8, 15, 4, 3), "storage": Rect2i(14, 15, 1, 1),
	"well": Rect2i(17, 8, 1, 1), "mine": Rect2i(1, 13, 2, 2),
	"spot_grove": Rect2i(17, 12, 1, 1), "spot_rock_pile": Rect2i(18, 4, 1, 1), "spot_reed_bank": Rect2i(2, 4, 1, 1),
	"spot_clay_bank": Rect2i(2, 7, 1, 1), "spot_herb_patch": Rect2i(3, 17, 1, 1), "workbench": Rect2i(16, 16, 3, 1),
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
			# Beds are walkable (crops don't block); facilities, the yard edge (trees) and rocks do.
			walkable += "1" if WALK_RECT.has_point(c) and not _in_footprint(c) else "0"
		bp.masks.visual.append("1".repeat(GRID.x))
		bp.masks.walkable.append(walkable)
		bp.masks.buildable.append("1".repeat(GRID.x))
		bp.masks.cultivable.append(cultivable)
	return bp

## Homestead fence (plan §8.3, q(35); 不知火舞 on SGODOT-228 7e1db1f8), one fence.glb kit:
## Lv1–2 only the stretch in front of the farmhouse, either side of the door path with a 2 m opening;
## Lv3 adds the ring round the field and yard, open at the mine and the way out to the map.
## Each segment is {pos: Vector3, yaw: float, stretch: float} (stretch scales fence.glb along its length).
const FENCE_SEG := 1.24              # fence.glb length (m)
const FENCE_FRONT_ROW := 13          # the yard row between the field and the farmhouse
const FENCE_RING := {"west": 0.38, "east": 12.95, "back": -12.35, "front": 0.1}

static func fence_front(bp: FarmBlueprint) -> Array:
	var door := bp.cell_to_world(ANCHORS.house)
	var z := bp.cell_to_world(Vector2i(0, FENCE_FRONT_ROW)).z
	return [{"pos": Vector3(door.x - 1.0 - FENCE_SEG * 0.5, 0, z), "yaw": 0.0, "stretch": 1.0},
		{"pos": Vector3(door.x + 1.0 + FENCE_SEG * 0.5, 0, z), "yaw": 0.0, "stretch": 1.0}]

static func fence_ring(bp: FarmBlueprint) -> Array:
	var r := FENCE_RING
	var exit := bp.cell_to_world(ANCHORS.exit)
	var mine := Rect2i(FOOTPRINTS.mine)
	var mine_z0 := bp.cell_to_world(mine.position).z + bp.cell_m * 0.5        # near edge of the mine (towards the camera)
	var mine_z1 := mine_z0 - mine.size.y * bp.cell_m
	var out: Array = []
	out.append_array(_fence_run(Vector2(r.west, r.back), Vector2(r.east, r.back), []))
	out.append_array(_fence_run(Vector2(r.west, r.back), Vector2(r.west, r.front), [Vector2(mine_z1 - 0.2, mine_z0 + 0.2)]))
	out.append_array(_fence_run(Vector2(r.east, r.back), Vector2(r.east, r.front), []))
	out.append_array(_fence_run(Vector2(r.west, r.front), Vector2(r.east, r.front), [Vector2(exit.x - 1.0, exit.x + 1.0)]))
	return out

## Segments along a → b (xz), evenly stretched to fill it; gaps are [from, to] on the axis the run follows.
static func _fence_run(a: Vector2, b: Vector2, gaps: Array) -> Array:
	var length := a.distance_to(b)
	var n := maxi(1, roundi(length / FENCE_SEG))
	var step := length / n
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var out: Array = []
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		var c := p.x if along_x else p.y
		var lo := c - step * 0.5
		var hi := c + step * 0.5
		if gaps.any(func(g: Vector2): return hi > minf(g.x, g.y) and lo < maxf(g.x, g.y)): continue
		out.append({"pos": Vector3(p.x, 0, p.y), "yaw": 0.0 if along_x else PI * 0.5, "stretch": step / FENCE_SEG})
	return out

## Points along the yard fence for block_points: the player walks round it, through the door opening.
static func fence_block_points(bp: FarmBlueprint) -> Array:
	var points: Array = []
	for seg in fence_front(bp):
		for k in 5: points.append(seg.pos + Vector3((k / 4.0 - 0.5) * FENCE_SEG * 0.9, 0, 0))
	return points

## The Homestead sign (WorldBadges · Farm 1135:79267): right of the farmhouse door, between the house and the
## yard fence, clear of the door path (cell 9) so the door and the sign stay two tap targets.
const SIGN_CELL := Vector2i(11, 14)

static func sign_point(bp: FarmBlueprint) -> Vector3:
	return bp.cell_to_world(SIGN_CELL)

## The Upgrade Plaque (HOME-LV3-FENCE 1510:97492): left of the farmhouse door, mirroring the sign, from the first upgrade.
const PLAQUE_CELL := Vector2i(7, 14)

static func plaque_point(bp: FarmBlueprint) -> Vector3:
	return bp.cell_to_world(PLAQUE_CELL)

## LOCK-07 (亚瑟 / 不知火舞 / 周瑜 on SGODOT-231): one finger card on the farm at a time — the nearest facility within
## its reach; the card showing keeps it unless another is CARD_KEEP nearer, so standing between two never flickers.
## cands = [[id, position, reach m], ...]; an exact tie goes to the earlier entry. Distance on the ground (a bed or a
## slope never pushes a facility out of reach). The one copy: SGODOT-231 folded its own P0FarmMaterials.pick_card in.
const CARD_KEEP := 0.2

static func pick_card(cands: Array, at: Vector3, current: String) -> String:
	var best := ""
	var best_d := INF
	var current_d := INF
	for c in cands:
		var p: Vector3 = c[1]
		var d := Vector2(at.x - p.x, at.z - p.z).length()
		if d > float(c[2]): continue
		if str(c[0]) == current: current_d = d
		if d < best_d:
			best = str(c[0])
			best_d = d
	return current if current_d < INF and current_d <= best_d + CARD_KEEP else best

## Mark scenery rocks solid: each rock blocks the cell it stands in (trees already stand outside the yard).
static func block_points(bp: FarmBlueprint, points: Array) -> void:
	for p in points:
		var c := bp.world_to_cell(p)
		if c.y < 0 or c.y >= bp.masks.walkable.size() or c.x < 0 or c.x >= GRID.x: continue
		var row: String = bp.masks.walkable[c.y]
		bp.masks.walkable[c.y] = row.substr(0, c.x) + "0" + row.substr(c.x + 1)

## True when a world point stands on a bed (the player steps up onto it).
static func on_bed(bp: FarmBlueprint, p: Vector3) -> bool:
	var c := bp.world_to_cell(p)
	if id_of(c) < 0: return false
	var centre := bp.cell_to_world(c)
	return absf(p.x - centre.x) < 0.47 and absf(p.z - centre.z) < 0.47   # plot.glb is 0.94 m across

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
