class_name P0Garden
extends RefCounted
## The P0 homestead garden: the earlier fixed-plot layout (git c3b4204 FarmInterior) — 0.65 m cells,
## every plot its own thick soil bed (plot.glb) two cells apart so beds have walkways between them —
## grown to the 30 plots of plan §14.1.2 (6 columns × 5 rows), and from Homestead Lv3 to 40 (P1, q(59) §1.1): two more
## columns on the right, plots 30–39 row by row, the same grid as content.garden.plots (the server's sprinkler coverage).
## Plots and facilities are solid; the player works a bed from the walkway beside it. Pure data: no nodes, unit-tested.

const CELL_MM := 650
## 22 × 24 from row −2: the yard's front reaches two rows past row 0 (q(172) A, 不知火舞 282 4ddb69db: the farm grows
## toward the camera for a whole row of Homestead Lv7 beds), every older cell keeping its place in the world.
const GRID := Vector2i(22, 24)
const GRID_ORIGIN := Vector2i(0, -2)
const COLUMNS := 6                    # P0's field; plots 0–29
const ROWS := 5
const EXTRA_COLUMNS := 2              # P1 (q(59)): plots 30–39, right of the field, from Homestead Lv3
const P0_PLOTS := COLUMNS * ROWS
const GRID_PLOTS := (COLUMNS + EXTRA_COLUMNS) * ROWS   # 40: the field's own lattice, plots 0–39
## Homestead Lv7 (q(172) A; 用户 on 302, 不知火舞 282 4ddb69db): 8 more beds, 40–47 left to right, a whole row in front of
## the field (row −1: y 1, x 4–18) on its 2-cell lattice, the walkway y 2 between; the yard's front moved two rows toward
## the camera at every level to make room, the beds come at Lv7. [col, row] as content.garden.plots 40–47 (the test holds
## the two equal); sprinklers and Harvest All work on them as on the rest.
const EDGE_PLOTS := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1), Vector2i(3, -1), Vector2i(4, -1), Vector2i(5, -1),
	Vector2i(6, -1), Vector2i(7, -1)]
const MAX_PLOTS := 48
const PLOT_ORIGIN := Vector2i(4, 3)   # plot 0 sits nearest the camera, on the left
const BED_H := 0.15                   # soil bed thickness (plot.glb top), crops grow from here

## Point anchors (cells). The house faces the field; the stall (seed box for now) stands on its right and the
## rest bench (FARM-7, q(30)) on its left, two cells wide, clear of the beds, the stall and the mine.
const ANCHORS := {
	# q(172) A: the way in two rows nearer the camera (it was (9, 1) / (9, 0)), the field's new front row before it
	"spawn": Vector2i(9, -1), "exit": Vector2i(9, -2),
	"house": Vector2i(9, 16), "storage": Vector2i(14, 15),
	"well": Vector2i(15, 13), "mine": Vector2i(2, 14), "bench": Vector2i(5, 16),
	# SGODOT-231 / q(45): five gathering spots on the farm edge (no Old Tree in P0) and the workbench on the house's
	# right past the stall (SGODOT-224's rest bench takes the left, Vector2i(5, 16)).
	# P1 (q(59) §1.1): the two new columns take x 16–18 (rows 3–11) and x 19 straddles the Lv3 fence (12.95 m), so the well
	# moves to the yard row between the field and the house, the Rock Pile to the back right corner and the Timber Grove
	# to the front right corner, clear of the beds and of the way to the workbench (不知火舞 checks the places).
	"spot_grove": Vector2i(16, -1), "spot_rock_pile": Vector2i(18, 13), "spot_reed_bank": Vector2i(2, 4),
	"spot_clay_bank": Vector2i(2, 7), "spot_herb_patch": Vector2i(3, 17), "workbench": Vector2i(17, 16),
	# P1 (SGODOT-288, §13.3.6): the Old Tree (Hardwood, Homestead Lv3) on the left edge between the Clay Bank and the
	# mine mouth, in the gathering spots' column, off the beds (x 4–18) and the ways to the mine and the workbench
	# (刘邦 on 288; 不知火舞 checks the place)
	"spot_old_tree": Vector2i(2, 10),
}
## Solid footprints beyond the plots (inclusive rects: x, y, w, h).
const FOOTPRINTS := {
	"house": Rect2i(8, 15, 4, 3), "storage": Rect2i(14, 15, 1, 1),
	"well": Rect2i(15, 13, 1, 1), "mine": Rect2i(1, 13, 2, 2), "bench": Rect2i(5, 16, 2, 1),
	"spot_grove": Rect2i(16, -1, 1, 1), "spot_rock_pile": Rect2i(18, 13, 1, 1), "spot_reed_bank": Rect2i(2, 4, 1, 1),
	"spot_clay_bank": Rect2i(2, 7, 1, 1), "spot_herb_patch": Rect2i(3, 17, 1, 1), "workbench": Rect2i(16, 16, 3, 1),
	"spot_old_tree": Rect2i(2, 10, 1, 1),
}
## Scenery trees stand outside the walkable yard, so they are not footprints. The yard ends inside the Homestead fence
## ring (FENCE_RING: its back stretch between rows 18 and 19, its east one in column 19), whatever the level — a wall
## one sees is never walked through or on (q(145)); the same rect as Decorate's (decor.yard.walk).
const WALK_RECT := Rect2i(1, -2, 18, 21)   # x 1–18, y −2–18 (q(172) A: from y 0 before)
const CROP_CODES := {
	"crop_radish": "R", "crop_lettuce": "L", "crop_carrot": "C", "crop_chamomile": "H",
	"crop_herb": "B", "crop_potato": "P", "crop_chili": "I", "crop_tomato": "M",
	# P1 (SGODOT-240, content/farm_crops.json): placeholder plants from the closest existing one until their own
	# (q(59) §4: leafy heads, tall stalks, vines; today reuses old models, 275). Fruit trees grow as the old woody crop.
	"crop_cabbage": "L", "crop_cucumber": "L", "crop_corn": "H", "crop_strawberry": "M", "crop_melon": "M",
	"crop_pumpkin": "M", "crop_pineapple": "B", "crop_sweet_potato": "P", "crop_beet": "C",
	"crop_apple": "T", "crop_citrus": "T", "crop_grape": "B",
	"crop_quick_radish": "R",   # q(217): the teaching seed's Quick Radish grows as a radish
}

## Plots the homestead has now: the view's garden.plots (30, 40 from Homestead Lv3); MAX_PLOTS with no view (the beds,
## the walk mask and the scenery are laid out for all 40, and the farm shows only the ones the view has).
static func plot_count(view = null) -> int:
	if view is Dictionary: return clampi(int((view as Dictionary).get("garden", {}).get("plots", P0_PLOTS)), 0, MAX_PLOTS)
	return MAX_PLOTS

## [col, row] of a plot on the garden grid: content.garden.plots[id].
static func grid_of(plot_id: int) -> Vector2i:
	if plot_id < P0_PLOTS: return Vector2i(plot_id % COLUMNS, plot_id / COLUMNS)
	if plot_id >= GRID_PLOTS: return EDGE_PLOTS[plot_id - GRID_PLOTS]
	var k := plot_id - P0_PLOTS
	return Vector2i(COLUMNS + k % EXTRA_COLUMNS, k / EXTRA_COLUMNS)

static func cell_of(plot_id: int) -> Vector2i:
	return PLOT_ORIGIN + grid_of(plot_id) * 2

## -1 when the cell is not a plot.
static func id_of(cell: Vector2i) -> int:
	var d := cell - PLOT_ORIGIN
	if d.x % 2 != 0 or d.y % 2 != 0: return -1
	var col := d.x / 2
	var row := d.y / 2
	if col < 0 or row < 0 or row >= ROWS:
		var edge := EDGE_PLOTS.find(Vector2i(col, row))
		return GRID_PLOTS + edge if edge >= 0 else -1
	if col < COLUMNS: return row * COLUMNS + col
	if col < COLUMNS + EXTRA_COLUMNS: return P0_PLOTS + row * EXTRA_COLUMNS + col - COLUMNS
	return -1

static func cell_id(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func blueprint() -> FarmBlueprint:
	var bp := FarmBlueprint.new()
	bp.layout_patch_id = "p0_garden"
	bp.revision = 1
	bp.display_name = "Homestead"
	bp.grid = GRID
	bp.grid_origin = GRID_ORIGIN
	bp.cell_mm = CELL_MM
	bp.cell_m = CELL_MM / 1000.0
	bp.play_area_mm = GRID.x * CELL_MM
	bp.play_area_m = GRID.x * bp.cell_m
	bp.anchors = ANCHORS.duplicate()
	var beds: Array = []
	for row in ROWS:
		var cells: Array = []
		for col in COLUMNS: cells.append(cell_of(row * COLUMNS + col))
		for col in EXTRA_COLUMNS: cells.append(cell_of(P0_PLOTS + row * EXTRA_COLUMNS + col))
		beds.append({"id": "row%d" % row, "cells": cells})
	beds.append({"id": "edge", "cells": EDGE_PLOTS.map(func(g): return PLOT_ORIGIN + g * 2)})   # Homestead Lv7's 40–47
	bp.anchors["beds"] = beds
	for key in FarmBlueprint.MASK_NAMES: bp.masks[key] = []
	for y in range(GRID_ORIGIN.y, GRID_ORIGIN.y + GRID.y):
		var walkable := ""
		var cultivable := ""
		for x in range(GRID_ORIGIN.x, GRID_ORIGIN.x + GRID.x):
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
const FENCE_RING := {"west": 0.38, "east": 12.95, "back": -12.35, "front": 1.4}   # front 0.1 → 1.4: two rows nearer (q(172) A)

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

## Homestead looks (LOOK-PICK, SGODOT-282; 上官婉儿 e4d03424): Lv3 / 5 / 8 are standalone parts beside the farmhouse,
## Lv10 swaps the whole house. P1 builds them from placeholder models — a (timber) from the wooden pieces (fence, storage),
## b (stone) from rock / path_tile — until the designed ones replace them. Each part is {asset, pos, yaw, scale: Vector3},
## standing on the ground (y 0; a paving tile just above it); none is solid (they stand off the door path and the
## walkways). The house front is HOUSE_FRONT in front of its anchor.
const HOUSE_FRONT := 1.13            # house_cottage's front wall from its anchor (m, toward the field)
const STONE_PER_SEG := 3             # rocks along one fence segment's length (Stone Wall)
const STONE_SCALE := Vector3(1.15, 1.3, 1.0)   # rock.glb 0.41 × 0.36: three make a low wall 1.24 long, 0.46 high

## Fence & Mailbox b (Stone Wall): the fence's segments as rows of rocks, the same run and gaps.
static func stone_wall(segments: Array) -> Array:
	var out: Array = []
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var yaw := float(seg.yaw)
		var along := Vector3(cos(yaw), 0, -sin(yaw))   # the segment's local +x in the world
		var length := FENCE_SEG * float(seg.get("stretch", 1.0))
		for k in STONE_PER_SEG:
			var t := (float(k) + 0.5) / STONE_PER_SEG - 0.5
			out.append({"asset": "rock", "pos": (seg.pos as Vector3) + along * (t * length),
				"yaw": yaw + 0.35 * float((i * STONE_PER_SEG + k) % 3 - 1), "scale": STONE_SCALE})
	return out

## Porch (Lv5) and Kitchen Wing (Lv8) parts, a or b. The porch stands at the door between the house front and the
## yard fence's front row (0.8 m), clear of the door path, the plaque and the sign; the kitchen wing on the house's
## left behind the rest bench.
static func look_parts(bp: FarmBlueprint, stage: String, look: String) -> Array:
	var house := bp.cell_to_world(ANCHORS.house)
	var porch_z := house.z + HOUSE_FRONT + 0.35
	match [stage, look]:
		["porch", "a"]:   # Timber Porch: two railings flanking the door
			return [{"asset": "fence", "pos": Vector3(house.x - 0.85, 0, porch_z), "yaw": PI * 0.5, "scale": Vector3(0.55, 1, 1)},
				{"asset": "fence", "pos": Vector3(house.x + 0.85, 0, porch_z), "yaw": PI * 0.5, "scale": Vector3(0.55, 1, 1)}]
		["porch", "b"]:   # Stone Porch: a paved landing and two rocks either side
			return [{"asset": "path_tile", "pos": Vector3(house.x, 0.004, porch_z), "yaw": 0.0, "scale": Vector3(1.1, 1, 0.6)},
				{"asset": "rock", "pos": Vector3(house.x - 0.85, 0, porch_z), "yaw": 0.4, "scale": Vector3.ONE * 1.4},
				{"asset": "rock", "pos": Vector3(house.x + 0.85, 0, porch_z), "yaw": -0.6, "scale": Vector3.ONE * 1.4}]
		["kitchen_extension", "a"]:   # Timber Kitchen Wing: a wooden lean-to on the left
			return [{"asset": "storage", "pos": Vector3(house.x - HOUSE_FRONT - 0.5, 0, house.z - 0.75), "yaw": PI * 0.5, "scale": Vector3.ONE * 1.6}]
		["kitchen_extension", "b"]:   # Stone Kitchen Wing: a stone room with a chimney stack
			return [{"asset": "path_tile", "pos": Vector3(house.x - HOUSE_FRONT - 0.5, 0.004, house.z - 0.75), "yaw": 0.0, "scale": Vector3(0.8, 1, 0.75)},
				{"asset": "rock", "pos": Vector3(house.x - HOUSE_FRONT - 0.5, 0, house.z - 0.75), "yaw": 0.2, "scale": Vector3(2.4, 2.2, 2.6)},
				# the chimney: a tall rock standing on the ground at the room's back corner, sunk into it (never stacked:
				# a rock set on another's rounded top floats, 不知火舞 on #250)
				{"asset": "rock", "pos": Vector3(house.x - HOUSE_FRONT - 0.85, 0, house.z - 1.0), "yaw": 1.1, "scale": Vector3(1.1, 3.0, 1.1)}]
	return []

## Master Farmhouse (Lv10): the house model, a Timber Lodge (house_barn) or a Stone Manor (house_dome); before Lv10 the
## farm's own style (不知火舞 e6b93272: placeholders until Stark's design).
static func look_house(look: String, style := "cottage") -> String:
	match look:
		"a": return "house_barn"
		"b": return "house_dome"
	return "house_" + style

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

## The Chef's Sign (Homestead Lv10, §7.7; SGODOT-282): a free-standing hanging sign on a post (上官婉儿's prop shape,
## 不知火舞 on 282) left of the door, in the plaque's row, two cells left of it: the board hangs to the post's left, on the
## grass left of the bench, clear of it on screen and tapped apart from it. Nearer the door are the path (x 8–10), the Lv3
## front fence (row 13) and the plaque; one cell nearer, the board lay over the bench. Off the mine path (x 3–4).
## Anchor `chef_sign`: the post's foot, +Z toward the camera. A yard object (no decor on it); solid once the sign is up.
const CHEF_SIGN_CELL := Vector2i(5, 14)
## The mine path's cell under its hanging board (0.15 m from the board's edge to the cell's middle at shoulder height):
## not walked while the sign stands, so no one passes through the board (不知火舞 282 33835f54, B; 上官婉儿 56fa9620) —
## the way to the mine goes by (4,13) or (4,15). Still a path to decor (nothing is placed on it).
const CHEF_SIGN_BOARD_CELL := Vector2i(4, 14)

static func chef_sign_point(bp: FarmBlueprint) -> Vector3:
	return bp.cell_to_world(CHEF_SIGN_CELL)

## The Notice Board (Homestead Lv5, q(164); SGODOT-284): beside the Homestead Stall, off the beds, the paths, the bench,
## the Chef's Sign and every facility (苏烈 / 哪吒's two candidates, 不知火舞 picks: A (15, 15) right of the stall, under
## the well; B (13, 15) left of it, between the farmhouse and the stall). Anchor `notice_board`: its foot, +Z toward the
## camera. A yard object (no decor on it); solid once it is up.
const NOTICE_BOARD_CELL := Vector2i(15, 15)

static func notice_board_point(bp: FarmBlueprint) -> Vector3:
	return bp.cell_to_world(NOTICE_BOARD_CELL)

## The farmhouse Mailbox (§12.5.2, q(24); SGODOT-234 C): by the house's right wall, between the Homestead sign and the
## stall (about 1.45 m from each), clear of the door path, the fence and the field. Solid, one cell.
const MAILBOX_CELL := Vector2i(12, 16)

static func mailbox_point(bp: FarmBlueprint) -> Vector3:
	return bp.cell_to_world(MAILBOX_CELL)

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
		if not bp.in_bounds(c): continue
		var r := c - bp.grid_origin
		var row: String = bp.masks.walkable[r.y]
		bp.masks.walkable[r.y] = row.substr(0, r.x) + "0" + row.substr(r.x + 1)

## True when a world point stands on a bed (the player steps up onto it): one of the beds the view has (哪吒 on #215:
## at Homestead Lv1–2 the place of 30–39 is plain ground, no step up); no view = any of the 40.
static func on_bed(bp: FarmBlueprint, p: Vector3, view = null) -> bool:
	var c := bp.world_to_cell(p)
	var id := id_of(c)
	if id < 0 or id >= plot_count(view): return false
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
	for q in view.get("quick_seeds", []): grow[str(q.get("id", ""))] = float(q.get("grow_s", 45)) * 1000.0   # q(217)
	var out := {}
	for p in view.get("plots", []):
		var id := int(p.get("id", -1))
		if id < 0 or id >= plot_count(view): continue
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
				# A picked tree regrowing (q(118)) stays a grown tree without fruit: the stage below ripe, not a sapling again.
				if bool(p.get("tree", false)) and int(p.get("picks", 0)) > 0:
					slot.watered_at = ready_at - int(maxf(1.0, float(p.get("ready_in", 0))) / 0.3)
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
