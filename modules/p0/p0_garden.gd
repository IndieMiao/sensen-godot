class_name P0Garden
extends RefCounted
## The P0 homestead garden: the earlier fixed-plot layout (git c3b4204 FarmInterior) — 0.65 m cells,
## every plot its own thick soil bed (plot.glb) two cells apart so beds have walkways between them — on the grid of
## content.garden.plots (the server's too: sprinkler coverage, greenhouses), 63 beds since SGODOT-355 b1.
## Plots and facilities are solid; the player works a bed from the walkway beside it. Pure data: no nodes, unit-tested.

const FarmArt = preload("res://modules/farm/farm_art.gd")

const CELL_MM := 650
## 22 × 24 from row −2: the yard's front reaches two rows past row 0 (q(172) A, 不知火舞 282 4ddb69db: the farm grows
## toward the camera for a whole row of Homestead Lv7 beds), every older cell keeping its place in the world.
const GRID := Vector2i(22, 24)
const GRID_ORIGIN := Vector2i(0, -2)
## SGODOT-355 b1 (不知火舞 approved 哪吒's grid, 11-02): the beds are content.garden.plots — 9 × 7 = 63, cols −1…7 × rows
## −2…4 on the 2-cell lattice (yard x 2–18, y −1–11), their ids in the order they open: the starting 2 × 4 in front of the
## farmhouse door, then row by row from the farmhouse out, each row's middle first. Read once from the content (the server
## holds the same table); nothing here knows the grid's size.
static var _grid: Array[Vector2i] = []
static var _ids := {}   # Vector2i [col, row] → plot id
static func _table() -> Array[Vector2i]:
	if _grid.is_empty():
		for at in P0Logic.content().get("garden", {}).get("plots", []): _grid.append(Vector2i(int(at[0]), int(at[1])))
		for i in _grid.size(): _ids[_grid[i]] = i
	return _grid
## How many beds the grid has (63): the most a homestead ever opens.
static func max_plots() -> int: return _table().size()
const PLOT_ORIGIN := Vector2i(4, 3)   # plot 0 sits nearest the camera, on the left
const BED_H := 0.15                   # soil bed thickness (plot.glb top), crops grow from here

## Point anchors (cells). The house faces the field; the stall (seed box for now) stands on its right and the
## rest bench (FARM-7, q(30)) on its left, two cells wide, clear of the beds and the stall. No mine mouth: the mines are
## wild sites (355 b1, v4q(5) ①).
const ANCHORS := {
	# q(172) A: the way in two rows nearer the camera (it was (9, 1) / (9, 0)), the field's new front row before it
	"spawn": Vector2i(9, -1), "exit": Vector2i(9, -2),
	"house": Vector2i(9, 16), "storage": Vector2i(14, 15),
	"well": Vector2i(15, 13), "bench": Vector2i(5, 16),
	# the workbench on the house's right past the stall (SGODOT-224's rest bench takes the left, Vector2i(5, 16)). The six
	# gathering spots left the farm for the cities (SGODOT-355 b1, v4 #49; two stood on the grid's new beds).
	"workbench": Vector2i(17, 16),
}
## Solid footprints beyond the plots (inclusive rects: x, y, w, h).
const FOOTPRINTS := {
	"house": Rect2i(8, 15, 4, 3), "storage": Rect2i(14, 15, 1, 1),
	"well": Rect2i(15, 13, 1, 1), "bench": Rect2i(5, 16, 2, 1),
	"workbench": Rect2i(16, 16, 3, 1),
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
	"crop_cress": "B", "crop_pea_shoots": "B", "crop_spinach": "L", "crop_scallion": "B", "crop_bok_choy": "L",
}

## q(245) stand-ins (354 f31fe553): Scallion uses B because mature C exposes an orange root; no new meshes.
const FAST_TINTS := {"crop_cress": Color(0.82, 1.0, 0.62), "crop_pea_shoots": Color(0.68, 1.0, 0.90),
	"crop_spinach": Color(0.63, 0.82, 0.70), "crop_scallion": Color(0.92, 1.0, 0.76), "crop_bok_choy": Color(0.93, 1.0, 0.94)}

## Beds open now: the view's garden.plots (the level's Plots plus the trees and sprinklers standing, SGODOT-355 b1); all
## of them with no view (the beds, the walk mask and the scenery are laid out for the whole grid, the farm shows the ones
## the view has).
static func plot_count(view = null) -> int:
	if view is Dictionary: return clampi(int((view as Dictionary).get("garden", {}).get("plots", max_plots())), 0, max_plots())
	return max_plots()

## [col, row] of a plot on the garden grid: content.garden.plots[id].
static func grid_of(plot_id: int) -> Vector2i:
	var t := _table()
	return t[plot_id] if plot_id >= 0 and plot_id < t.size() else Vector2i(-100, -100)

static func cell_of(plot_id: int) -> Vector2i:
	return PLOT_ORIGIN + grid_of(plot_id) * 2

## -1 when the cell is not a plot.
static func id_of(cell: Vector2i) -> int:
	var d := cell - PLOT_ORIGIN
	if d.x % 2 != 0 or d.y % 2 != 0: return -1
	_table()
	return int(_ids.get(Vector2i(d.x / 2, d.y / 2), -1))

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
	var rows := {}   # a bed row per grid row, left to right (the grid's own rows)
	for id in max_plots(): rows[grid_of(id).y] = rows.get(grid_of(id).y, []) + [grid_of(id)]
	var beds: Array = []
	for row in rows.keys():
		var cols: Array = rows[row]
		cols.sort_custom(func(a, b): return a.x < b.x)
		beds.append({"id": "row%d" % row, "cells": cols.map(func(g): return PLOT_ORIGIN + g * 2)})
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
## Lv3 adds the ring round the field and yard, open only at the way out to the map (its west stretch closed where the
## mine mouth stood, 355 b1).
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
	var out: Array = []
	out.append_array(_fence_run(Vector2(r.west, r.back), Vector2(r.east, r.back), []))
	out.append_array(_fence_run(Vector2(r.west, r.back), Vector2(r.west, r.front), []))
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

## The Kitchen Wing's models (Lv8, and the Master Farmhouse's, which has it built in) wait until the wing and the rest
## bench stand apart: today the wing's front wall cuts through the bench, and one sitting there sat half in the wall
## (不知火舞 448 b18d13c6, 上官婉儿). Until then Lv8 and Lv15 keep their old looks; the Porch's model is in.
const WING_WAITS := true

## Porch (Lv5) and Kitchen Wing (Lv8), a (timber) or b (stone): 赵云's porch_a / _b and kitchen_wing_a / _b (#858, in
## farm-dev by #875), each one model with its origin at the house anchor (P0Garden.ANCHORS.house, +Z toward the camera),
## put there as it is — the porch at the door, the wing on the house's left. Their colour is in the vertex colours
## (FarmArt.instance's material). While WING_WAITS the wing is the old one: a lean-to (a) or a stone room (b).
static func look_parts(bp: FarmBlueprint, stage: String, look: String) -> Array:
	if look not in ["a", "b"]: return []
	var house := bp.cell_to_world(ANCHORS.house)
	match stage:
		"porch": return [{"asset": "porch_" + look, "pos": house, "yaw": 0.0, "scale": Vector3.ONE}]
		"kitchen_extension":
			if not WING_WAITS:
				return [{"asset": "kitchen_wing_" + look, "pos": house, "yaw": 0.0, "scale": Vector3.ONE}]
			var wing := Vector3(house.x - HOUSE_FRONT - 0.5, 0, house.z - 0.75)
			if look == "a":   # Timber Kitchen Wing: a wooden lean-to on the left
				return [{"asset": "storage", "pos": wing, "yaw": PI * 0.5, "scale": Vector3.ONE * 1.6}]
			# Stone Kitchen Wing: a stone room with a chimney stack — the chimney a tall rock on the ground at the
			# room's back corner, sunk into it (never stacked: a rock on another's rounded top floats, 不知火舞 on #250)
			return [
				{"asset": "path_tile", "pos": wing + Vector3(0, 0.004, 0), "yaw": 0.0, "scale": Vector3(0.8, 1, 0.75)},
				{"asset": "rock", "pos": wing, "yaw": 0.2, "scale": Vector3(2.4, 2.2, 2.6)},
				{"asset": "rock", "pos": wing + Vector3(-0.35, 0, -0.25), "yaw": 1.1, "scale": Vector3(1.1, 3.0, 1.1)}]
	return []

## Master Farmhouse (Lv15, v4q(1)): 刘备's master_farmhouse_a (Timber Lodge) / _b (Stone Manor) (#854, in farm-dev by
## #875), the whole house with its porch and wing in one, origin at the house anchor as the house's own; while
## WING_WAITS the old house_barn / house_dome. Before it the farm's own style.
static func look_house(look: String, style := "cottage") -> String:
	if look in ["a", "b"]:
		if WING_WAITS: return "house_barn" if look == "a" else "house_dome"
		return "master_farmhouse_" + look
	return "house_" + style

## Whether the house shown for this Master Farmhouse look has the porch and wing in it (the standalone ones put away).
static func whole_house(look: String) -> bool:
	return look in ["a", "b"] and not WING_WAITS

## The door's way out to the yard (the first of decor.yard.paths): no look stands on it.
const DOOR_PATH := Rect2i(8, 13, 3, 2)

## The yard cells a look's model stands on (亚瑟 on #896: the wing was a picture one walked into): every walkable cell
## that a wall or post of the model (its upright faces below 1 m, set at the house anchor) reaches more than LOOK_REACH
## into, and the cells those walls close in, less the house's own footprint and the door path. A floor (the porch's
## deck, a step) is walked on; a box round the whole model would close the yard in front of the wing. [] for a model
## not in the farm's art.
const LOOK_REACH := 0.1
static var _look_cells := {}
static func look_cells(bp: FarmBlueprint, asset: String) -> Array[Vector2i]:
	if _look_cells.has(asset): return (_look_cells[asset] as Array[Vector2i]).duplicate()
	var out: Array[Vector2i] = []
	var mesh := FarmArt.mesh_for(asset)
	if mesh == null: return out
	var house := bp.cell_to_world(ANCHORS.house)
	var half := bp.cell_m * 0.5 - LOOK_REACH
	var faces := mesh.get_faces()
	var walls: Array[Rect2] = []
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12 or absf(n.normalized().y) > 0.5 or minf(a.y, minf(b.y, c.y)) > 1.0: continue
		var r := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).expand(Vector2(c.x, c.z))
		walls.append(r)
	var box := mesh.get_aabb()
	var lo := bp.world_to_cell(house + Vector3(box.position.x, 0, box.position.z))
	var hi := bp.world_to_cell(house + Vector3(box.end.x, 0, box.end.z))
	var area := Rect2i(Vector2i(mini(lo.x, hi.x) - 1, mini(lo.y, hi.y) - 1), (lo - hi).abs() + Vector2i(3, 3))
	var shut := {}   # a cell one cannot be on: a wall in it, the house, or off the plan
	for x in range(area.position.x, area.end.x):
		for y in range(area.position.y, area.end.y):
			var cell := Vector2i(x, y)
			if FOOTPRINTS.house.has_point(cell) or not bp.is_walkable(cell):
				shut[cell] = true
				continue
			if DOOR_PATH.has_point(cell): continue
			var at := bp.cell_to_world(cell) - house
			var inner := Rect2(at.x - half, at.z - half, half * 2.0, half * 2.0)
			if walls.any(func(w: Rect2): return w.grow(0.0001).intersects(inner)):
				shut[cell] = true
				out.append(cell)
	# and the cells the walls close in (the wing's room): not reached from the area's edge
	var seen := {}
	var todo: Array[Vector2i] = []
	for x in range(area.position.x, area.end.x):
		for y in range(area.position.y, area.end.y):
			var cell := Vector2i(x, y)
			var edge := x == area.position.x or y == area.position.y or x == area.end.x - 1 or y == area.end.y - 1
			if edge and not shut.has(cell): todo.append(cell)
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		if seen.has(cell): continue
		seen[cell] = true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + d
			if area.has_point(next) and not shut.has(next) and not seen.has(next): todo.append(next)
	for x in range(area.position.x, area.end.x):
		for y in range(area.position.y, area.end.y):
			var cell := Vector2i(x, y)
			if not shut.has(cell) and not seen.has(cell): out.append(cell)
	_look_cells[asset] = out
	return out.duplicate()

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
## front fence (row 13) and the plaque; one cell nearer, the board lay over the bench.
## Anchor `chef_sign`: the post's foot, +Z toward the camera. A yard object (no decor on it); solid once the sign is up.
const CHEF_SIGN_CELL := Vector2i(5, 14)
## The cell under its hanging board (0.15 m from the board's edge to the cell's middle at shoulder height; the mine path's
## until the mouth left the farm, 355 b1): not walked while the sign stands, so no one passes through the board (不知火舞
## 282 33835f54, B; 上官婉儿 56fa9620) — the way round goes by (4,13) or (4,15). A yard object to decor, so nothing is
## placed under the board either.
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
## where a bed is still to open is plain ground, no step up); no view = any of the grid's.
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
	for c in view.get("fast_crops", []): grow[str(c.get("id", ""))] = float(c.get("grow_s", 0)) * 1000.0
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
		if FAST_TINTS.has(crop): slot.tint = FAST_TINTS[crop]
		out[cell_id(cell_of(id))] = slot
	return out

## Watered beds read darker; wild beds a touch greener; others plain (bed tint, multiplied in the shader).
static func bed_tint(state: String) -> Color:
	match state:
		"growing", "ready": return Color(0.80, 0.74, 0.70)
		"wild": return Color(0.94, 1.0, 0.90)
	return Color.WHITE
