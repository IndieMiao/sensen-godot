# G0-B 地图选街区 → 私有农场灰盒 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Godot 侧打通「选城市 → 街区级受限地图 → 三候选高亮与卡片 → 确认进入独立农场灰盒 → 摇杆/点按移动 → 返回地图状态恢复」，并用自动化公平校验守住 PRD §4.4 的三蓝图门槛。对应 Plane SGODOT-21。

**Architecture:** 新增 `modules/blueprint`（蓝图加载、checksum、`AStarGrid2D` 网格、地表 mesh、regions 配置、公平度量）、`modules/farm`（网格移动）、`modules/ui/touch_stick.gd`；`AppRouter` 从「切场景」升级为「场景栈」，地图常驻不销毁；`map_poc.gd` 加受限模式（固定 zoom/pitch/north-up、禁缩放旋转、边界内平移）、候选高亮层（Godot 透明层贴地 mesh，不动原生桥）和候选卡片；新场景 `scenes/city_select`、`scenes/farm`。所有数值不变量（可达性、时长）按逻辑格算，与 G0-A 的 Node 校验器公式一致。

**Tech Stack:** Godot 4.7.2（mobile 渲染器）、GDScript、gdUnit4（`tools/run_tests.sh`，orphans 计入失败）。

## Global Constraints

- 蓝图 JSON 格式与 canonical/checksum 定义以 `2026-09-03-g0a-blueprint-pipeline.md` Task 7 为准：`"|".join([layout_patch_id, str(revision), walkable 拼接, cultivable 拼接, buildable 拼接, visual 拼接, anchors_str])`，`anchors_str = "spawn:x,y;house:x,y;storage:x,y;well:x,y;exit:x,y;beds:" + 各畦 "x,y,x,y,x,y" 用 "/" 连接`。
- 坐标：逻辑格 `(i, j)`，mask 行索引 = j（y 向北），列索引 = i（x 向东）；世界系 `x = (i + 0.5) * cell_m * scale`，`z = -(j + 0.5) * cell_m * scale`，`y = 0`。
- 网格寻路 4 邻接（`AStarGrid2D.DIAGONAL_MODE_NEVER` + 曼哈顿启发），与 Node 侧 BFS 一致；走速 2.5 逻辑米/秒，单格动作 2.0 s。
- 不改 `tools/android/overlay/GodotMapPlugin.kt`、`tools/ios/*`、`MapBridge` 接口。
- 09-04 Demo 的自由漫游行为保留在代码里，只在受限模式下关闭；`demo-2026-09-04` tag 已打。
- UI 颜色只取 `DesignTokens`；新 UI 文案中文。
- 新脚本/场景生成的 `.uid` 文件随代码一起提交（仓库惯例）。
- 每个任务结束 `tools/run_tests.sh` 相关子目录必须绿且 `orphans` 为 0。
- 依赖 G0-A：Task 4 起需要 `assets/blueprints/safe_grid/r1/`（G0-A Task 8）；Task 14 需要 `assets/farm/data/regions.json` 与六个真实蓝图（G0-A Task 10）。Task 4 提供一份临时 `regions.json` 顶到 G0-A 交付。

## File Structure

```
modules/blueprint/blueprint.gd          FarmBlueprint：加载、字段、mask 查询、坐标换算、canonical/checksum
modules/blueprint/blueprint_grid.gd     BlueprintGrid：AStarGrid2D 封装，path/距离/时长
modules/blueprint/ground_mesh.gd        BlueprintGroundMesh：masks → ArrayMesh（顶点色）
modules/blueprint/regions.gd            FarmRegions：regions.json、最近城市、城市选择持久化
modules/blueprint/farm_choice.gd        FarmChoice：已选蓝图持久化（G0 本地；G1 起由服务端 farm_instance 替代）
modules/blueprint/fairness.gd           BlueprintFairness：far_bed_s / tour_s（与 Node validate 同公式）
modules/farm/player_mover.gd            PlayerMover：摇杆直走 + 点按寻路
modules/ui/touch_stick.gd          TouchStick
modules/ui/app_router.gd                场景栈 push/pop、suspend/resume 协议
scenes/map_poc/map_poc.gd               受限模式、边界、fly_to、suspend/resume、候选接入
scenes/map_poc/bridge_factory.gd        MapBridgeFactory.make()
scenes/map/candidate_overlay.gd         CandidateOverlay：候选高亮贴地 mesh
scenes/select/select_panel.gd           SelectPanel：三候选卡片 + 确认
scenes/city_select/city_select.{tscn,gd}
scenes/farm/farm.{tscn,gd}
tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json
tests/fixtures/scenes/stack_probe.{tscn,gd}
tests/blueprint/  tests/farm/  tests/ui/  tests/map/  tests/scenes/
```

---

### Task 1: FarmBlueprint 加载与 checksum

**Files:**
- Create: `modules/blueprint/blueprint.gd`
- Create: `tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json`
- Create: `tests/blueprint/test_blueprint.gd`

**Interfaces:**
- Produces: `class_name FarmBlueprint`（RefCounted）：字段 `layout_patch_id: String, revision: int, region_id: String, display_name: String, checksum: String, play_area_m: float, cell_m: float, grid: Vector2i, masks: Dictionary(String -> PackedStringArray), paths: Array[Dictionary], blocks: Array[Dictionary], anchors: Dictionary, overlay: Dictionary`；`static asset_path(id: String, rev: int) -> String`；`static load_file(path) -> FarmBlueprint`（失败返回 null 并 push_error）；`static from_dict(d) -> FarmBlueprint`；`in_bounds(c: Vector2i) -> bool`；`mask_has(mask: String, c) -> bool`；`is_walkable(c) -> bool`；`anchor(name) -> Vector2i`；`beds() -> Array`（每项 `{id: String, cells: Array[Vector2i]}`）；`reserved_bed() -> Dictionary`；`cell_to_world(c, scale := 1.0) -> Vector3`；`world_to_cell(w, scale := 1.0) -> Vector2i`；`canonical() -> String`；`compute_checksum() -> String`；`verify_checksum() -> bool`。
- `overlay` 结构：`{center: Vector2(lat, lng), paths: Array[PackedVector2Array(lat, lng)], blocks: Array[PackedVector2Array(lat, lng)]}`。

- [ ] **Step 1: 写 fixture 蓝图（8×8，四区块、十字路、右下角水塘不可走）**

`tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json`（checksum 由 Node 侧同一 canonical 算出，是跨语言一致性的锚）：
```json
{
 "format": 1, "layout_patch_id": "fix_grid", "revision": 1, "region_id": "test", "name": "Fixture Grid",
 "checksum": "d74f428b8c7fe9131cb8c9191aaf1009c5e1f993a941465f53f0cd9cb1a20ca7",
 "source": {"provider": "fixture"}, "play_area_m": 8, "cell_m": 1.0, "grid": [8, 8],
 "masks": {
  "visual":     ["11111111","11111111","11111111","11111111","11111111","11111111","11111111","11111111"],
  "walkable":   ["11111111","11111111","11111111","11111111","11111111","11111111","11111100","11111100"],
  "buildable":  ["11101111","11101111","11101111","00000000","11101111","11101111","11101100","11101100"],
  "cultivable": ["00000000","11101110","00000000","00000000","00000000","11100000","00000000","00000000"]
 },
 "paths": [{"id": "p0", "points": [[0, 3.5], [8, 3.5]], "width_m": 1}, {"id": "p1", "points": [[3.5, 0], [3.5, 8]], "width_m": 1}],
 "blocks": [
  {"id": "b0", "polygon": [[0,0],[3,0],[3,3],[0,3],[0,0]], "neighbors": ["b1","b2"]},
  {"id": "b1", "polygon": [[4,0],[8,0],[8,3],[4,3],[4,0]], "neighbors": ["b0","b3"]},
  {"id": "b2", "polygon": [[0,4],[3,4],[3,8],[0,8],[0,4]], "neighbors": ["b0","b3"]},
  {"id": "b3", "polygon": [[4,4],[8,4],[8,8],[4,8],[4,4]], "neighbors": ["b1","b2"]}
 ],
 "anchors": {
  "spawn": [3, 3], "house": [4, 5], "storage": [5, 5], "well": [3, 2], "exit": [3, 7],
  "beds": [{"id": "bed0", "cells": [[0,1],[1,1],[2,1]]}, {"id": "bed1", "cells": [[4,1],[5,1],[6,1]]}, {"id": "bed2", "cells": [[0,5],[1,5],[2,5]]}],
  "reserved_bed": {"id": "bed3", "cells": [[0,7],[1,7],[2,7]]}
 },
 "overlay_wgs84": {
  "center": [31.2, 121.4],
  "paths": [[[31.2, 121.3995], [31.2, 121.4005]], [[31.1995, 121.4], [31.2005, 121.4]]],
  "blocks": [[[31.2001, 121.3999], [31.2001, 121.4001], [31.1999, 121.4001], [31.1999, 121.3999], [31.2001, 121.3999]]]
 }
}
```

- [ ] **Step 2: 写失败测试**

`tests/blueprint/test_blueprint.gd`：
```gdscript
extends GdUnitTestSuite
## FarmBlueprint：加载、mask、坐标、canonical/checksum 与 Node 管线逐字一致。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"
const CANON := "fix_grid|1|1111111111111111111111111111111111111111111111111111110011111100|0000000011101110000000000000000000000000111000000000000000000000|1110111111101111111011110000000011101111111011111110110011101100|1111111111111111111111111111111111111111111111111111111111111111|spawn:3,3;house:4,5;storage:5,5;well:3,2;exit:3,7;beds:0,1,1,1,2,1/4,1,5,1,6,1/0,5,1,5,2,5"

func test_load_fields() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	assert_object(bp).is_not_null()
	assert_str(bp.layout_patch_id).is_equal("fix_grid")
	assert_int(bp.revision).is_equal(1)
	assert_that(bp.grid).is_equal(Vector2i(8, 8))
	assert_float(bp.cell_m).is_equal(1.0)
	assert_int(bp.blocks.size()).is_equal(4)
	assert_int(bp.paths.size()).is_equal(2)
	assert_that(bp.anchor("spawn")).is_equal(Vector2i(3, 3))
	assert_int(bp.beds().size()).is_equal(3)
	assert_that(bp.beds()[1].cells[2]).is_equal(Vector2i(6, 1))
	assert_that(bp.overlay.center).is_equal(Vector2(31.2, 121.4))

func test_masks_and_bounds() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	assert_bool(bp.is_walkable(Vector2i(3, 3))).is_true()
	assert_bool(bp.is_walkable(Vector2i(7, 7))).is_false() # 水塘
	assert_bool(bp.is_walkable(Vector2i(8, 0))).is_false() # 越界
	assert_bool(bp.mask_has("cultivable", Vector2i(1, 1))).is_true()
	assert_bool(bp.mask_has("buildable", Vector2i(3, 0))).is_false() # 路上不可建

func test_canonical_and_checksum_match_node_pipeline() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	assert_str(bp.canonical()).is_equal(CANON)
	assert_str(bp.compute_checksum()).is_equal("d74f428b8c7fe9131cb8c9191aaf1009c5e1f993a941465f53f0cd9cb1a20ca7")
	assert_bool(bp.verify_checksum()).is_true()
	bp.masks.walkable[7] = "11111110"
	assert_bool(bp.verify_checksum()).is_false()

func test_world_roundtrip() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var w := bp.cell_to_world(Vector2i(2, 5))
	assert_that(w).is_equal(Vector3(2.5, 0.0, -5.5))
	assert_that(bp.world_to_cell(w)).is_equal(Vector2i(2, 5))
	assert_that(bp.world_to_cell(Vector3(2.99, 0, -5.01))).is_equal(Vector2i(2, 5))
	assert_that(bp.cell_to_world(Vector2i(1, 1), 2.0)).is_equal(Vector3(3.0, 0.0, -3.0))

func test_missing_file_returns_null() -> void:
	assert_object(FarmBlueprint.load_file("res://tests/fixtures/blueprints/nope/r1/farm_blueprint.json")).is_null()
	assert_str(FarmBlueprint.asset_path("sh_a", 1)).is_equal("res://assets/blueprints/sh_a/r1/farm_blueprint.json")
```

- [ ] **Step 3: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: 解析错误 `FarmBlueprint` 未定义。

- [ ] **Step 4: 写 blueprint.gd**

```gdscript
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
```

- [ ] **Step 5: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: 5 passed，orphans 0。

- [ ] **Step 6: Commit**

```bash
git add modules/blueprint tests/blueprint tests/fixtures/blueprints
git commit -m "feat(blueprint): FarmBlueprint 加载、mask 查询与跨语言一致的 checksum"
```

---

### Task 2: BlueprintGrid（AStarGrid2D 寻路）

**Files:**
- Create: `modules/blueprint/blueprint_grid.gd`
- Create: `tests/blueprint/test_blueprint_grid.gd`

**Interfaces:**
- Produces: `class_name BlueprintGrid`（RefCounted）：`_init(bp: FarmBlueprint)`；`var bp`；`var astar: AStarGrid2D`；`path(from: Vector2i, to: Vector2i) -> Array[Vector2i]`（含起点终点；不可达或越界返回空）；`distance_cells(from, to) -> float`（不可达 `INF`）；`walk_time(from, to, speed := 2.5) -> float`（秒，`distance * cell_m / speed`）。

- [ ] **Step 1: 写失败测试**

`tests/blueprint/test_blueprint_grid.gd`：
```gdscript
extends GdUnitTestSuite
## 4 邻接寻路，与 Node 侧 BFS 距离一致。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _grid() -> BlueprintGrid:
	return BlueprintGrid.new(FarmBlueprint.load_file(FIX))

func test_manhattan_distance_on_open_grid() -> void:
	var g := _grid()
	assert_float(g.distance_cells(Vector2i(3, 3), Vector2i(0, 1))).is_equal(5.0)
	assert_float(g.walk_time(Vector2i(3, 3), Vector2i(0, 1))).is_equal(2.0)
	assert_float(g.distance_cells(Vector2i(3, 3), Vector2i(3, 3))).is_equal(0.0)

func test_path_cells_are_walkable_and_contiguous() -> void:
	var g := _grid()
	var p := g.path(Vector2i(5, 7), Vector2i(7, 5))
	assert_int(p.size()).is_equal(5) # 4 步
	for i in p.size():
		assert_bool(g.bp.is_walkable(p[i])).is_true()
		if i > 0:
			assert_int(absi(p[i].x - p[i - 1].x) + absi(p[i].y - p[i - 1].y)).is_equal(1)

func test_unreachable_and_out_of_bounds() -> void:
	var g := _grid()
	assert_int(g.path(Vector2i(3, 3), Vector2i(7, 7)).size()).is_equal(0) # 水塘
	assert_float(g.distance_cells(Vector2i(3, 3), Vector2i(7, 7))).is_equal(INF)
	assert_int(g.path(Vector2i(3, 3), Vector2i(9, 9)).size()).is_equal(0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: `BlueprintGrid` 未定义。

- [ ] **Step 3: 写 blueprint_grid.gd**

```gdscript
class_name BlueprintGrid
extends RefCounted
## walkable mask → AStarGrid2D。4 邻接 + 曼哈顿，与 Node 校验器的 BFS 距离一致。

var bp: FarmBlueprint
var astar := AStarGrid2D.new()

func _init(p_bp: FarmBlueprint) -> void:
	bp = p_bp
	astar.region = Rect2i(0, 0, bp.grid.x, bp.grid.y)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for j in bp.grid.y:
		for i in bp.grid.x:
			var c := Vector2i(i, j)
			if not bp.is_walkable(c):
				astar.set_point_solid(c, true)

func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not bp.in_bounds(from) or not bp.in_bounds(to):
		return []
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return []
	return astar.get_id_path(from, to)

func distance_cells(from: Vector2i, to: Vector2i) -> float:
	var p := path(from, to)
	return INF if p.is_empty() else float(p.size() - 1)

func walk_time(from: Vector2i, to: Vector2i, speed := 2.5) -> float:
	var d := distance_cells(from, to)
	return INF if d == INF else d * bp.cell_m / speed
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: 8 passed。

- [ ] **Step 5: Commit**

```bash
git add modules/blueprint tests/blueprint
git commit -m "feat(blueprint): BlueprintGrid 四邻接寻路与时长"
```

---

### Task 3: 地表 mesh（顶点色灰盒）

**Files:**
- Create: `modules/blueprint/ground_mesh.gd`
- Create: `tests/blueprint/test_ground_mesh.gd`

**Interfaces:**
- Produces: `class_name BlueprintGroundMesh`：`const COLOR_GROUND/COLOR_PATH/COLOR_BLOCK/COLOR_BED/COLOR_WATER`；`static cell_color(bp, c: Vector2i) -> Color`；`static build(bp, scale := 1.0) -> ArrayMesh`（一个 surface，每格 6 顶点，含法线与顶点色）；`static material() -> StandardMaterial3D`（`vertex_color_use_as_albedo`）。

- [ ] **Step 1: 写失败测试**

`tests/blueprint/test_ground_mesh.gd`：
```gdscript
extends GdUnitTestSuite

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func test_mesh_has_six_vertices_per_cell() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var mesh := BlueprintGroundMesh.build(bp)
	assert_int(mesh.get_surface_count()).is_equal(1)
	var arrays := mesh.surface_get_arrays(0)
	assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(8 * 8 * 6)
	assert_int((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size()).is_equal(8 * 8 * 6)

func test_cell_colors_by_type() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(1, 1))).is_equal(BlueprintGroundMesh.COLOR_BED)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(3, 3))).is_equal(BlueprintGroundMesh.COLOR_PATH)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(1, 0))).is_equal(BlueprintGroundMesh.COLOR_BLOCK)
	assert_that(BlueprintGroundMesh.cell_color(bp, Vector2i(7, 7))).is_equal(BlueprintGroundMesh.COLOR_WATER)

func test_scale_expands_extent() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var aabb := BlueprintGroundMesh.build(bp, 2.0).get_aabb()
	assert_float(aabb.size.x).is_equal_approx(16.0, 1e-4)
	assert_float(aabb.size.z).is_equal_approx(16.0, 1e-4)
	assert_bool(BlueprintGroundMesh.material().vertex_color_use_as_albedo).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: `BlueprintGroundMesh` 未定义。

- [ ] **Step 3: 写 ground_mesh.gd**

```gdscript
class_name BlueprintGroundMesh
extends RefCounted
## masks → 平地 ArrayMesh，每格两个三角形，顶点色区分路/区块/田畦/水。灰盒口径，G4 换正式地表。

const COLOR_GROUND := Color(0.87, 0.89, 0.84)
const COLOR_PATH := Color(0.91, 0.84, 0.67)
const COLOR_BLOCK := Color(0.63, 0.80, 0.63)
const COLOR_BED := Color(0.59, 0.41, 0.27)
const COLOR_WATER := Color(0.55, 0.72, 0.86)

static func cell_color(bp: FarmBlueprint, c: Vector2i) -> Color:
	if bp.mask_has("cultivable", c):
		return COLOR_BED
	if not bp.is_walkable(c):
		return COLOR_WATER
	if bp.mask_has("buildable", c):
		return COLOR_BLOCK
	return COLOR_PATH

static func build(bp: FarmBlueprint, scale := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := bp.cell_m * scale
	for j in bp.grid.y:
		for i in bp.grid.x:
			var col := cell_color(bp, Vector2i(i, j))
			var x0 := i * s
			var x1 := (i + 1) * s
			var z0 := -j * s
			var z1 := -(j + 1) * s
			var quad := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1),
				Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
			for v in quad:
				st.set_normal(Vector3.UP)
				st.set_color(col)
				st.add_vertex(v)
	return st.commit()

static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	return m
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: 11 passed。

- [ ] **Step 5: Commit**

```bash
git add modules/blueprint tests/blueprint
git commit -m "feat(blueprint): 灰盒地表 mesh 生成"
```

---

### Task 4: FarmRegions 配置、城市选择持久化、临时 regions.json

**Files:**
- Create: `modules/blueprint/regions.gd`
- Create: `modules/blueprint/farm_choice.gd`
- Create: `assets/farm/data/regions.json`（**仅当 G0-A Task 10 尚未生成时**写这份临时版）
- Create: `tests/blueprint/test_regions.gd`

**Interfaces:**
- Produces: `class_name FarmRegions`（RefCounted）：`const DEFAULT_PATH := "res://assets/farm/data/regions.json"`、`const CHOICE_PATH := "user://region_choice.json"`；`var regions: Array`；`static from_text(text) -> FarmRegions`（null on error）；`static load_default() -> FarmRegions`；`ids() -> PackedStringArray`；`region(id) -> Dictionary`（缺则 `{}`）；`candidates(region_id) -> Array`；`static nearest_region_id(regions: Array, lat, lng) -> String`；`static save_choice(id)`、`static load_choice() -> String`、`static clear_choice()`。
- Produces: `class_name FarmChoice`：`const PATH := "user://farm_choice.json"`；`static save(layout_patch_id: String, revision: int)`；`static load() -> Dictionary`（`{}` 表示无）；`static clear()`。
- region 字典键：`id, name, timezone, center: [lat, lng], street_zoom, pitch, candidates: [{layout_patch_id, revision, name}]`。

- [ ] **Step 1: 若不存在则写临时 regions.json**

```bash
test -f assets/farm/data/regions.json && echo "exists, skip" || mkdir -p assets/farm/data
```
若不存在，`assets/farm/data/regions.json`（两城各指向 safe_grid，G0-A Task 10 会整体覆盖）：
```json
{
 "format": 1,
 "regions": [
  {"id": "shanghai", "name": "上海", "timezone": "Asia/Shanghai", "center": [31.2304, 121.4737], "street_zoom": 16.0, "pitch": 45.0,
   "candidates": [{"layout_patch_id": "safe_grid", "revision": 1, "name": "安全蓝图（临时）"}]},
  {"id": "los_angeles", "name": "Los Angeles", "timezone": "America/Los_Angeles", "center": [34.0522, -118.2437], "street_zoom": 16.0, "pitch": 45.0,
   "candidates": [{"layout_patch_id": "safe_grid", "revision": 1, "name": "Safe Grid (interim)"}]}
 ]
}
```

- [ ] **Step 2: 写失败测试**

`tests/blueprint/test_regions.gd`：
```gdscript
extends GdUnitTestSuite

const TEXT := """{"format":1,"regions":[
{"id":"shanghai","name":"上海","timezone":"Asia/Shanghai","center":[31.2304,121.4737],"street_zoom":16.0,"pitch":45.0,
 "candidates":[{"layout_patch_id":"sh_a","revision":1,"name":"A"},{"layout_patch_id":"sh_b","revision":1,"name":"B"}]},
{"id":"los_angeles","name":"LA","timezone":"America/Los_Angeles","center":[34.0522,-118.2437],"street_zoom":16.0,"pitch":45.0,
 "candidates":[{"layout_patch_id":"la_a","revision":1,"name":"LA-A"}]}]}"""

func after_test() -> void:
	FarmRegions.clear_choice()
	FarmChoice.clear()

func test_parse_and_query() -> void:
	var r := FarmRegions.from_text(TEXT)
	assert_object(r).is_not_null()
	assert_that(r.ids()).is_equal(PackedStringArray(["shanghai", "los_angeles"]))
	assert_str(r.region("shanghai").name).is_equal("上海")
	assert_int(r.candidates("shanghai").size()).is_equal(2)
	assert_str(r.candidates("los_angeles")[0].layout_patch_id).is_equal("la_a")
	assert_bool(r.region("mars").is_empty()).is_true()
	assert_object(FarmRegions.from_text("not json")).is_null()

func test_nearest_region() -> void:
	var r := FarmRegions.from_text(TEXT)
	assert_str(FarmRegions.nearest_region_id(r.regions, 34.1, -118.3)).is_equal("los_angeles")
	assert_str(FarmRegions.nearest_region_id(r.regions, 31.0, 121.0)).is_equal("shanghai")
	assert_str(FarmRegions.nearest_region_id([], 0.0, 0.0)).is_equal("")

func test_choice_roundtrip() -> void:
	assert_str(FarmRegions.load_choice()).is_equal("")
	FarmRegions.save_choice("los_angeles")
	assert_str(FarmRegions.load_choice()).is_equal("los_angeles")
	FarmChoice.save("sh_b", 1)
	assert_that(FarmChoice.load()).is_equal({"layout_patch_id": "sh_b", "revision": 1})

func test_default_file_loads() -> void:
	var r := FarmRegions.load_default()
	assert_object(r).is_not_null()
	assert_bool(r.ids().has("shanghai")).is_true()
	assert_bool(r.ids().has("los_angeles")).is_true()
```

- [ ] **Step 3: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: `FarmRegions` 未定义。

- [ ] **Step 4: 写 regions.gd 与 farm_choice.gd**

`modules/blueprint/regions.gd`：
```gdscript
class_name FarmRegions
extends RefCounted
## regions.json（G0-A 管线产物）：城市目录 + 候选蓝图索引。不含任何候选经纬度。

const DEFAULT_PATH := "res://assets/farm/data/regions.json"
const CHOICE_PATH := "user://region_choice.json"

var regions: Array = []

static func from_text(text: String) -> FarmRegions:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("regions"):
		return null
	var r := FarmRegions.new()
	r.regions = parsed.regions
	return r

static func load_default() -> FarmRegions:
	if not FileAccess.file_exists(DEFAULT_PATH):
		push_error("FarmRegions: 缺少 %s（先跑 G0-A 管线或写临时文件）" % DEFAULT_PATH)
		return null
	return from_text(FileAccess.get_file_as_string(DEFAULT_PATH))

func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for r in regions:
		out.append(str(r.id))
	return out

func region(id: String) -> Dictionary:
	for r in regions:
		if str(r.id) == id:
			return r
	return {}

func candidates(region_id: String) -> Array:
	return region(region_id).get("candidates", [])

static func nearest_region_id(p_regions: Array, lat: float, lng: float) -> String:
	var best := ""
	var best_d := INF
	for r in p_regions:
		var d := MapGeoMath.geo_to_world(lat, lng, float(r.center[0]), float(r.center[1])).length()
		if d < best_d:
			best_d = d
			best = str(r.id)
	return best

static func save_choice(id: String) -> void:
	var f := FileAccess.open(CHOICE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"region_id": id}))

static func load_choice() -> String:
	if not FileAccess.file_exists(CHOICE_PATH):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CHOICE_PATH))
	return str(parsed.get("region_id", "")) if typeof(parsed) == TYPE_DICTIONARY else ""

static func clear_choice() -> void:
	if FileAccess.file_exists(CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHOICE_PATH))
```

`modules/blueprint/farm_choice.gd`：
```gdscript
class_name FarmChoice
extends RefCounted
## G0 本地记录玩家选定的蓝图。G1 起由服务端 farm_instance 取代，这里只剩缓存语义。

const PATH := "user://farm_choice.json"

static func save(layout_patch_id: String, revision: int) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"layout_patch_id": layout_patch_id, "revision": revision}))

static func load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("layout_patch_id"):
		return {}
	return {"layout_patch_id": str(parsed.layout_patch_id), "revision": int(parsed.get("revision", 1))}

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
```

- [ ] **Step 5: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: 15 passed。

- [ ] **Step 6: Commit**

```bash
git add modules/blueprint tests/blueprint assets/farm/data/regions.json
git commit -m "feat(blueprint): regions 配置、城市/蓝图选择持久化"
```

---

### Task 5: AppRouter 场景栈 + 换装房迁移

**Files:**
- Modify: `modules/ui/app_router.gd`
- Modify: `scenes/dressing_room/dressing_room.gd:100,136`（两处 `AppRouter.go_to_map()` → `AppRouter.pop_instance()`）
- Create: `tests/fixtures/scenes/stack_probe.gd`、`tests/fixtures/scenes/stack_probe.tscn`
- Create: `tests/ui/test_app_router_stack.gd`

**Interfaces:**
- Produces（AppRouter 新增）：`const FARM := "res://scenes/farm/farm.tscn"`、`const CITY_SELECT := "res://scenes/city_select/city_select.tscn"`；`push_instance(scene_path: String, args := {}) -> Node`（实例化、若有 `setup(args)` 则调用、挂到 `root`、把之前的顶层 `suspend()`）；`pop_instance() -> void`（栈空时回退 `go_to_map()`；否则释放顶层并 `resume()` 新顶层）；`instance_depth() -> int`；`top_instance() -> Node`；`handle_back()` 在栈非空时改为 pop。
- 协议：被压栈的场景可实现 `suspend()` / `resume()`；没有这两个方法的节点不被触碰。
- **2026-09-04 终审 C1 补记（原计划遗漏，faithfully implemented 成了真实缺陷）**：光靠
  `suspend()` 隐藏节点（`visible=false`、`process_mode` 关掉）不会让该场景的
  `Camera3D`/`WorldEnvironment` 跟着失去"当前"身份——Godot 4 里一台 Camera3D 只有
  `current == true` 或是视口里第一台相机时才会被选中，`WorldEnvironment` 同理只认树里
  第一个生效的 `Environment`。因此凡是自己拥有 `Camera3D`/`WorldEnvironment` 的场景，
  必须把这两者的所有权也纳入 `suspend()`/`resume()`：`suspend()` 里 `cam.current = false`
  并把 `world_env.environment` 摘下来存到成员变量，`resume()` 里 `cam.make_current()`
  并把存的 `Environment`插回去（范例见 Task 6 里 `map_poc.gd` 的 `suspend()`/`resume()`）。
  这条不是一个独立于 `suspend()`/`resume()` 的新协议（没有另开 `release_view()`/
  `acquire_view()` 一对方法）——理由：AppRouter 已有的 `suspend()`/`resume()` 分发是
  唯一、久经测试的挂载点，`map_poc.gd` 的这两个方法本来就在管一揽子"离场/回场"副作用
  （HUD、地图桥可见性、`transparent_bg`），相机与环境所有权是这份清单上很自然的下一项；
  另开一对方法只会多一处"忘记实现另一半"的地方，这正是本次事故的成因。
  新被压入（第一次入树）的场景不走这条路径——它们没有"之前的状态"要收回，直接在各自
  `_ready()` 里 `cam.make_current()` 即可（farm.gd/dressing_room.gd 都这么做）。
  回归测试同样要跟上：`tests/fixtures/scenes/stack_probe.tscn` 原来是个裸 `Node`，看不出
  这类缺陷——Step 1 的探针要补一个 `Camera3D`（`WorldEnvironment` 也顺手带上）并照抄上面
  这套协议，见下方 Step 1 更新后的代码。

- [ ] **Step 1: 写探针场景**

`tests/fixtures/scenes/stack_probe.gd`（2026-09-04 终审 C1 更新：带一个 `Camera3D` +
`WorldEnvironment`，照抄上面记录的相机/环境协议，否则探针发现不了 C1 那类缺陷）：
```gdscript
extends Node
## AppRouter 场景栈测试探针：记录 setup 参数与 suspend/resume 次数。
var args := {}
var suspended := 0
var resumed := 0
var back_locked := false

@onready var cam: Camera3D = $Camera3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
var _saved_environment: Environment

func setup(p_args: Dictionary) -> void:
	args = p_args

func _ready() -> void:
	cam.make_current()

func is_back_navigation_locked() -> bool:
	return back_locked

func suspend() -> void:
	suspended += 1
	cam.current = false
	if world_env.environment:
		_saved_environment = world_env.environment
	world_env.environment = null

func resume() -> void:
	resumed += 1
	cam.make_current()
	world_env.environment = _saved_environment
```

`tests/fixtures/scenes/stack_probe.tscn`：
```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://tests/fixtures/scenes/stack_probe.gd" id="1"]

[sub_resource type="Environment" id="Environment_probe"]
background_mode = 1
background_color = Color(0.2, 0.2, 0.2, 1)

[node name="StackProbe" type="Node"]
script = ExtResource("1")

[node name="Camera3D" type="Camera3D" parent="."]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_probe")
```

- [ ] **Step 2: 写失败测试**

`tests/ui/test_app_router_stack.gd`：
```gdscript
extends GdUnitTestSuite
## 场景栈：push 挂到 root 并 suspend 前一层；pop 释放顶层并 resume 新顶层；返回键先 pop。

const PROBE := "res://tests/fixtures/scenes/stack_probe.tscn"

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame

func test_push_passes_args_and_suspends_previous_top() -> void:
	var a := AppRouter.push_instance(PROBE, {"k": 1})
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_that(a.args).is_equal({"k": 1})
	assert_bool(a.get_parent() == get_tree().root).is_true()
	var b := AppRouter.push_instance(PROBE)
	assert_int(AppRouter.instance_depth()).is_equal(2)
	assert_int(a.suspended).is_equal(1)
	assert_int(b.suspended).is_equal(0)
	assert_bool(AppRouter.top_instance() == b).is_true()

func test_pop_frees_top_and_resumes_previous() -> void:
	var a := AppRouter.push_instance(PROBE)
	var b := AppRouter.push_instance(PROBE)
	AppRouter.pop_instance()
	await get_tree().process_frame
	assert_bool(is_instance_valid(b)).is_false()
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_int(a.resumed).is_equal(1)

func test_back_pops_when_stack_not_empty() -> void:
	var a := AppRouter.push_instance(PROBE)
	AppRouter.handle_back()
	await get_tree().process_frame
	assert_bool(is_instance_valid(a)).is_false()
	assert_int(AppRouter.instance_depth()).is_equal(0)

func test_back_respects_top_instance_lock() -> void:
	var a := AppRouter.push_instance(PROBE)
	a.back_locked = true
	AppRouter.handle_back()
	await get_tree().process_frame
	assert_bool(is_instance_valid(a)).is_true() # 锁住时不得弹栈
	assert_int(AppRouter.instance_depth()).is_equal(1)
	a.back_locked = false
	AppRouter.handle_back()
	await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(0)

func test_back_action_table_includes_city_select() -> void:
	assert_int(AppRouter.back_action_for_scene(AppRouter.CITY_SELECT)).is_equal(AppRouter.BACK_LEAVE_APP)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=city"]))).is_equal(AppRouter.CITY_SELECT)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=farm"]))).is_equal(AppRouter.FARM)

## C1（2026-09-04 终审）：压栈场景必须真的接管视口的当前相机，光隐藏节点不够——
## Godot 4 里 Camera3D 只有 current==true 或是视口里第一台相机时才会被选中。
func test_push_makes_probe_camera_current_and_pop_restores_previous() -> void:
	var a := AppRouter.push_instance(PROBE)
	assert_bool(get_viewport().get_camera_3d() == a.cam).is_true()
	var b := AppRouter.push_instance(PROBE)
	assert_bool(get_viewport().get_camera_3d() == b.cam).is_true()
	AppRouter.pop_instance()
	await get_tree().process_frame
	assert_bool(get_viewport().get_camera_3d() == a.cam).is_true()
```

- [ ] **Step 3: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/ui`
Expected: `push_instance` 不存在。

- [ ] **Step 4: 改 app_router.gd**

在常量区加：
```gdscript
const FARM := "res://scenes/farm/farm.tscn"
const CITY_SELECT := "res://scenes/city_select/city_select.tscn"
```
在 `var _navigation_pending := false` 后加：
```gdscript
## 实例栈（PRD §3.2 第二层空间）：地图常驻为底，农场/地点/换装房压在上面。
var _stack: Array[Node] = []
```
新增方法（放在 `go_to_stress()` 之后）：
```gdscript
func push_instance(scene_path: String, args := {}) -> Node:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("AppRouter 无法加载实例场景 %s" % scene_path)
		return null
	var inst := packed.instantiate()
	if inst.has_method("setup"):
		inst.call("setup", args)
	_suspend(top_instance() if not _stack.is_empty() else get_tree().current_scene)
	_stack.append(inst)
	get_tree().root.add_child(inst)
	return inst

func pop_instance() -> void:
	if _stack.is_empty():
		go_to_map() # 兼容 --qa-scene=dressing 直接以换装房为当前场景的情况
		return
	var top: Node = _stack.pop_back()
	top.queue_free()
	_resume(top_instance() if not _stack.is_empty() else get_tree().current_scene)

func instance_depth() -> int:
	return _stack.size()

func top_instance() -> Node:
	return _stack.back() if not _stack.is_empty() else null

func _suspend(node: Node) -> void:
	if node and node.has_method("suspend"):
		node.call("suspend")

func _resume(node: Node) -> void:
	if node and node.has_method("resume"):
		node.call("resume")
```
改 `go_to_dressing()`：
```gdscript
func go_to_dressing() -> void:
	push_instance(DRESS)
```
改 `handle_back()`：
```gdscript
func handle_back() -> void:
	if not _stack.is_empty():
		# 栈顶也要尊重返回锁：换装房保存中（_committing）被系统返回键弹栈会中断保存。
		# 与下方 current_scene 分支同一语义（2026-09-04 执行时补上，原计划漏了这一层）。
		if scene_locks_back_navigation(top_instance()):
			return
		pop_instance()
		return
	var current := get_tree().current_scene
	match back_action_for_scene(
			_current_scene_path(), scene_locks_back_navigation(current)):
		BACK_TO_MAP:
			go_to_map()
		BACK_LEAVE_APP:
			_leave_app()
```
`qa_scene_path` 的 match 加两项：
```gdscript
			"city":
				return CITY_SELECT
			"farm":
				return FARM
```
`back_action_for_scene` 的 match 改为：
```gdscript
	match scene_path:
		DRESS, STRESS, FARM:
			return BACK_TO_MAP
		MAP, CITY_SELECT:
			return BACK_LEAVE_APP
		_:
			return BACK_IGNORE
```
`scenes/dressing_room/dressing_room.gd` 第 100 行与 136 行的 `AppRouter.go_to_map()` 改为 `AppRouter.pop_instance()`。

- [ ] **Step 5: 跑测试确认通过（含换装流程回归）**

Run: `tools/run_tests.sh res://tests/ui && tools/run_tests.sh res://tests/integration && tools/run_tests.sh res://tests/scenes`
Expected: 全绿，orphans 0。

- [ ] **Step 6: Commit**

```bash
git add modules/ui/app_router.gd scenes/dressing_room/dressing_room.gd tests/ui tests/fixtures/scenes
git commit -m "feat(router): 场景栈 push/pop 与 suspend/resume 协议，换装房迁到栈上"
```

---

### Task 6: 地图受限模式（street mode）与 suspend/resume

**Files:**
- Modify: `scenes/map_poc/map_poc.gd`
- Create: `tests/map/test_map_street_mode.gd`

**Interfaces:**
- Produces（map_poc 新增）：`var street_mode := false`、`var region: Dictionary = {}`、`var pan_bounds := Rect2()`（`position = (lat_min, lng_min)`，`size = (lat span, lng span)`，零 size = 不钳）；`enter_street_mode(r: Dictionary)`；`set_pan_bounds(center_lat, center_lng, half_m)`；`fly_to(lat, lng)`；`suspend()`；`resume()`。
- 受限模式行为：zoom/pitch 固定为 region 值，bearing 0；捏合、双击、俯仰手势忽略；拖拽保留但中心钳在 `pan_bounds`；不订阅定位，home = region.center；不生成洛杉矶夹具与随机路人；marker 层与侧栏 2D/3D、LA 按钮隐藏。

- [ ] **Step 1: 写失败测试**

`tests/map/test_map_street_mode.gd`：
```gdscript
extends GdUnitTestSuite
## PRD §3.1：街区级固定浏览范围——固定 zoom/pitch/north-up，禁缩放旋转，只能在边界内平移。

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"
const REGION := {"id": "t", "name": "T", "street_zoom": 16.0, "pitch": 45.0, "center": [31.2, 121.4]}

func _map() -> Node:
	var scene := (load(MAP_POC_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	scene.enter_street_mode(REGION)
	return scene

func test_zoom_and_pitch_locked() -> void:
	var m := _map()
	m._set_zoom(18.0)
	assert_float(m.zoom).is_equal(16.0)
	var mag := InputEventMagnifyGesture.new()
	mag.factor = 2.0
	m._unhandled_input(mag)
	assert_float(m.zoom).is_equal(16.0)
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 100)
	m._unhandled_input(pan)
	assert_float(m.pitch).is_equal(45.0)
	assert_float(m.bearing).is_equal(0.0)

func test_double_tap_does_not_zoom() -> void:
	var m := _map()
	for k in 2:
		var down := InputEventScreenTouch.new()
		down.pressed = true
		down.position = Vector2(100, 100)
		m._unhandled_input(down)
		var up := InputEventScreenTouch.new()
		up.pressed = false
		up.position = Vector2(100, 100)
		m._unhandled_input(up)
	assert_float(m.zoom).is_equal(16.0)
	assert_object(m._zoom_tween).is_null()

func test_pan_clamped_to_bounds() -> void:
	var m := _map()
	m.set_pan_bounds(31.2, 121.4, 300.0)
	m._apply_world_delta(Vector3(5000.0, 0.0, 0.0))
	assert_float(m.center_lng).is_less_equal(m.pan_bounds.position.y + m.pan_bounds.size.y + 1e-9)
	m._apply_world_delta(Vector3(0.0, 0.0, 5000.0)) # 向南
	assert_float(m.center_lat).is_greater_equal(m.pan_bounds.position.x - 1e-9)

func test_fly_to_and_home_from_region() -> void:
	var m := _map()
	assert_float(m.home_lat).is_equal(31.2)
	assert_bool(m.street_mode).is_true()
	m.fly_to(31.3, 121.5)
	assert_float(m.center_lat).is_equal(31.3)
	assert_float(m.center_lng).is_equal(121.5)

func test_suspend_resume() -> void:
	var m := _map()
	m.suspend()
	assert_int(m.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_bool(m.visible).is_false()
	assert_bool(m.get_node("HUD").visible).is_false()
	m.resume()
	assert_int(m.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_bool(m.visible).is_true()
	assert_bool(m._camera_dirty).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/map`
Expected: `enter_street_mode` 不存在。

- [ ] **Step 3: 改 map_poc.gd**

变量区（`var _map_is_ready := false` 之后）加：
```gdscript
## 受限模式（PRD §3.1）：由 FarmRegions 的城市选择触发；为真时地图只做「看见、选择、返回」。
var street_mode := false
var region: Dictionary = {}
## 平移边界（lat/lng）：position=(lat_min,lng_min)，size=(lat span,lng span)；零 size 不钳。
var pan_bounds := Rect2()
```
`_ready()` 开头 `_rng.seed = 20260829` 之后、`_spawn_la_fixture()` 之前插入，并把 `_spawn_la_fixture()` 改为条件调用：
```gdscript
	var choice := FarmRegions.load_choice()
	var regions := FarmRegions.load_default()
	if regions != null and not choice.is_empty() and not regions.region(choice).is_empty():
		enter_street_mode(regions.region(choice))
	if not street_mode:
		_spawn_la_fixture() # 压测夹具先排队；home 队列等定位确定后再插
```
marker 层创建后（`$HUD.move_child(marker_layer, 0)` 之后）加一行：
```gdscript
	marker_layer.visible = not street_mode
```
`map.create_map(token, START_LAT, START_LNG, zoom)` 与定位部分改为：
```gdscript
			var lat0 := float(region.center[0]) if street_mode else START_LAT
			var lng0 := float(region.center[1]) if street_mode else START_LNG
			map.create_map(token, lat0, lng0, zoom)
			_set_dot(DOT_WAIT, true) # 连接中：呼吸闪烁
		if not street_mode:
			map.start_location()
```
`_ready()` 末尾（`_camera_dirty = true` 之前）加：
```gdscript
	if street_mode:
		_resolve_home(float(region.center[0]), float(region.center[1]), false)
```
新增方法（放在 `_teleport` 附近）：
```gdscript
## —— 受限模式 ——————————————————————————————————————————————————

func enter_street_mode(r: Dictionary) -> void:
	street_mode = true
	region = r
	zoom = float(r.get("street_zoom", 16.0))
	pitch = float(r.get("pitch", 45.0))
	bearing = 0.0
	if is_node_ready():
		view_mode_switch.get_parent().visible = false
		travel_btn.get_parent().visible = false
		if marker_layer:
			marker_layer.visible = false
		if not _home_resolved:
			_resolve_home(float(r.center[0]), float(r.center[1]), false)
	_camera_dirty = true

func set_pan_bounds(center_lat: float, center_lng: float, half_m: float) -> void:
	var dlat := half_m / MapGeoMath.M_PER_DEG_LAT
	var dlng := half_m / (MapGeoMath.M_PER_DEG_LAT * cos(deg_to_rad(center_lat)))
	pan_bounds = Rect2(center_lat - dlat, center_lng - dlng, 2.0 * dlat, 2.0 * dlng)
	_clamp_to_bounds()

func _clamp_to_bounds() -> void:
	if pan_bounds.size == Vector2.ZERO:
		return
	center_lat = clampf(center_lat, pan_bounds.position.x, pan_bounds.position.x + pan_bounds.size.x)
	center_lng = clampf(center_lng, pan_bounds.position.y, pan_bounds.position.y + pan_bounds.size.y)

func fly_to(lat: float, lng: float) -> void:
	_teleport(lat, lng)
	_clamp_to_bounds()

## 场景栈协议（AppRouter.push_instance）：进入第二层实例时地图完全隐藏并停渲染，
## 同时交出相机与环境的所有权——只隐藏节点不够：Godot 4 里 Camera3D/WorldEnvironment
## 不会因为父节点 visible=false 就失去"当前"身份，压栈场景会看见地图相机冻结的位姿
## 和地图的天空/环境光（2026-09-04 终审 C1；协议本身记在 Task 5 的"协议"条目下）。
func suspend() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	$HUD.visible = false
	if map:
		map.set_map_visible(false)
	get_viewport().transparent_bg = false
	cam.current = false
	if world_env.environment:
		_saved_environment = world_env.environment
	world_env.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	$HUD.visible = true
	get_viewport().transparent_bg = true
	if map:
		map.set_map_visible(true)
	_camera_dirty = true
	cam.make_current()
	world_env.environment = _saved_environment
```
本任务同时要在变量区新增（放在 `@onready var cam: Camera3D = $Camera3D` 后面、
`var _camera_dirty := true` 后面）：
```gdscript
@onready var world_env: WorldEnvironment = $WorldEnvironment
...
## suspend() 里从 world_env.environment 摘下来的引用，resume() 时原样插回去。
var _saved_environment: Environment
```
`_apply_world_delta` 末尾加 `_clamp_to_bounds()`。`_set_zoom` 开头加 `if street_mode: return`。`_unhandled_input` 里：双击分支 `_tween_zoom(zoom + 1.0)` 改为 `if not street_mode: _tween_zoom(zoom + 1.0)`；`elif e is InputEventMagnifyGesture:` 改为 `elif e is InputEventMagnifyGesture and not street_mode:`；`elif e is InputEventPanGesture:` 改为 `elif e is InputEventPanGesture and not street_mode:`。`_spawn_home_cohort()` 里 `for i in PAWNS_NEAR_COUNT:` 改为 `for i in (0 if street_mode else PAWNS_NEAR_COUNT):`。`_teleport()` 已有 `_reposition_pawns()`，不动。

- [ ] **Step 4: 跑测试确认通过（含既有地图回归）**

Run: `tools/run_tests.sh res://tests/map`
Expected: 全绿（既有 fling/双击/marker 用例在非受限模式下不受影响）。

- [ ] **Step 5: Commit**

```bash
git add scenes/map_poc/map_poc.gd tests/map
git commit -m "feat(map): 街区级受限模式、平移边界、fly_to 与场景栈 suspend/resume"
```

---

### Task 7: CandidateOverlay 候选高亮层

**Files:**
- Create: `scenes/map/candidate_overlay.gd`
- Create: `tests/map/test_candidate_overlay.gd`

**Interfaces:**
- Produces: `class_name CandidateOverlay extends Node3D`：`const Y_LIFT := 0.3`、`const ALPHA_IDLE := 0.16`、`const ALPHA_SELECTED := 0.42`、`const PATH_WIDTH_M := 4.0`；`set_candidates(bps: Array, anchor_lat, anchor_lng)`；`select(id: String)`；`selected_id: String`；`reanchor(anchor_lat, anchor_lng)`；`candidate_ids() -> PackedStringArray`；`candidate_center(id) -> Vector2(lat, lng)`；`static geo_to_local(lat, lng, anchor_lat, anchor_lng) -> Vector2(x, z)`（**不能叫 `to_local`**：与 `Node3D` 内置的同名实例方法 `to_local(Vector3) -> Vector3` 冲突，是硬解析错误；2026-09-04 执行时发现并改名，与 `MapGeoMath.geo_to_world` 命名一致）；`static block_mesh(pts: PackedVector2Array) -> ArrayMesh`；`static path_mesh(pts: PackedVector2Array, width: float) -> ArrayMesh`。

- [ ] **Step 1: 写失败测试**

`tests/map/test_candidate_overlay.gd`：
```gdscript
extends GdUnitTestSuite
## 候选高亮由同一份蓝图的 overlay_wgs84 生成（PRD §4.5「不允许分别临摹」），在 Godot 层贴地绘制。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func test_to_local_center_is_origin() -> void:
	assert_that(CandidateOverlay.geo_to_local(31.2, 121.4, 31.2, 121.4)).is_equal(Vector2.ZERO)
	var east := CandidateOverlay.geo_to_local(31.2, 121.401, 31.2, 121.4)
	assert_bool(east.x > 0.0 and absf(east.y) < 1e-6).is_true()

func test_meshes_from_fixture() -> void:
	var ov := auto_free(CandidateOverlay.new())
	add_child(ov)
	var bp := FarmBlueprint.load_file(FIX)
	ov.set_candidates([bp], 31.2, 121.4)
	assert_that(ov.candidate_ids()).is_equal(PackedStringArray(["fix_grid"]))
	assert_that(ov.candidate_center("fix_grid")).is_equal(Vector2(31.2, 121.4))
	var node := ov.get_child(0) as Node3D
	assert_int(node.get_child_count()).is_equal(3) # 1 block + 2 paths
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	assert_int((CandidateOverlay.block_mesh(square).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(6)
	assert_int((CandidateOverlay.path_mesh(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), 4.0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(12)

func test_select_changes_alpha_and_reanchor_moves() -> void:
	var ov := auto_free(CandidateOverlay.new())
	add_child(ov)
	var bp := FarmBlueprint.load_file(FIX)
	ov.set_candidates([bp], 31.2, 121.4)
	var mi := ov.get_child(0).get_child(0) as MeshInstance3D
	assert_float((mi.material_override as StandardMaterial3D).albedo_color.a).is_equal_approx(CandidateOverlay.ALPHA_IDLE, 1e-6)
	ov.select("fix_grid")
	assert_str(ov.selected_id).is_equal("fix_grid")
	assert_float((mi.material_override as StandardMaterial3D).albedo_color.a).is_equal_approx(CandidateOverlay.ALPHA_SELECTED, 1e-6)
	var before := (ov.get_child(0) as Node3D).position
	ov.reanchor(31.2, 121.41)
	assert_bool((ov.get_child(0) as Node3D).position.x < before.x).is_true() # 锚点东移，候选相对西移
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/map`
Expected: `CandidateOverlay` 未定义。

- [ ] **Step 3: 写 candidate_overlay.gd**

```gdscript
class_name CandidateOverlay
extends Node3D
## 三个候选街区的高亮：蓝图 overlay_wgs84 → 浮动原点本地米制 → 贴地 mesh。
## 每个候选一个子 Node3D（position = 候选中心的本地坐标），mesh 顶点相对候选中心，
## 重锚只需改子节点 position。

const Y_LIFT := 0.3 # 贴地抬高，避开与 y=0 地面/角色底面的 z-fighting
const ALPHA_IDLE := 0.16
const ALPHA_SELECTED := 0.42
const PATH_WIDTH_M := 4.0

var selected_id := ""
var _items: Dictionary = {} # id -> {node, mats: Array[StandardMaterial3D], center: Vector2(lat,lng)}
var _anchor_lat := 0.0
var _anchor_lng := 0.0

static func geo_to_local(lat: float, lng: float, anchor_lat: float, anchor_lng: float) -> Vector2:
	var w := MapGeoMath.geo_to_world(lat, lng, anchor_lat, anchor_lng)
	return Vector2(w.x, w.z)

static func _material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(DesignTokens.ACCENT, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func block_mesh(pts: PackedVector2Array) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(pts[i].x, Y_LIFT, pts[i].y))
	return st.commit()

static func path_mesh(pts: PackedVector2Array, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var n := (b - a).orthogonal().normalized() * (width * 0.5)
		var quad := [a + n, b + n, b - n, a + n, b - n, a - n]
		for q in quad:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q.x, Y_LIFT, q.y))
	return st.commit()

func set_candidates(bps: Array, anchor_lat: float, anchor_lng: float) -> void:
	for c in get_children():
		c.queue_free()
	_items.clear()
	selected_id = ""
	_anchor_lat = anchor_lat
	_anchor_lng = anchor_lng
	for bp in bps:
		var center: Vector2 = bp.overlay.center
		var node := Node3D.new()
		node.name = bp.layout_patch_id
		add_child(node)
		var mats: Array[StandardMaterial3D] = []
		for pg in bp.overlay.blocks:
			var local := PackedVector2Array()
			for ll in pg:
				local.append(geo_to_local(ll.x, ll.y, center.x, center.y))
			if local.size() > 1 and local[0].is_equal_approx(local[local.size() - 1]):
				local.remove_at(local.size() - 1)
			mats.append(_add_mesh(node, block_mesh(local), ALPHA_IDLE))
		for pl in bp.overlay.paths:
			var local := PackedVector2Array()
			for ll in pl:
				local.append(geo_to_local(ll.x, ll.y, center.x, center.y))
			mats.append(_add_mesh(node, path_mesh(local, PATH_WIDTH_M), ALPHA_IDLE))
		_items[bp.layout_patch_id] = {"node": node, "mats": mats, "center": center}
	reanchor(anchor_lat, anchor_lng)

func _add_mesh(parent: Node3D, mesh: ArrayMesh, alpha: float) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(alpha)
	parent.add_child(mi)
	return mi.material_override

func select(id: String) -> void:
	selected_id = id
	for key in _items:
		var alpha := ALPHA_SELECTED if key == id else ALPHA_IDLE
		for m in _items[key].mats:
			m.albedo_color = Color(DesignTokens.ACCENT, alpha)

func reanchor(anchor_lat: float, anchor_lng: float) -> void:
	_anchor_lat = anchor_lat
	_anchor_lng = anchor_lng
	for key in _items:
		var c: Vector2 = _items[key].center
		var l := geo_to_local(c.x, c.y, anchor_lat, anchor_lng)
		(_items[key].node as Node3D).position = Vector3(l.x, 0.0, l.y)

func candidate_ids() -> PackedStringArray:
	return PackedStringArray(_items.keys())

func candidate_center(id: String) -> Vector2:
	return _items.get(id, {}).get("center", Vector2.ZERO)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/map`
Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
git add scenes/map tests/map
git commit -m "feat(map): 候选街区高亮层（蓝图 overlay → Godot 贴地 mesh）"
```

---

### Task 8: SelectPanel 三候选卡片

**Files:**
- Create: `scenes/select/select_panel.gd`
- Create: `tests/ui/test_select_panel.gd`

**Interfaces:**
- Produces: `class_name SelectPanel extends PanelContainer`：`signal candidate_focused(id: String)`、`signal confirmed(id: String)`；`const CAPACITY_TEXT := "9 格起步 · 首周可扩到 12 格"`；`set_candidates(items: Array)`（每项 `{id: String, name: String, preview: Texture2D 或 null}`）；`focus(id: String)`；`focused_id: String`；`card_count() -> int`；`confirm_button: Button`。
- PRD §4.3 第 4 条：三张卡片容量文案完全相同。

- [ ] **Step 1: 写失败测试**

`tests/ui/test_select_panel.gd`：
```gdscript
extends GdUnitTestSuite

func _panel() -> SelectPanel:
	var p := auto_free(SelectPanel.new())
	add_child(p)
	p.set_candidates([
		{"id": "a", "name": "甲", "preview": null},
		{"id": "b", "name": "乙", "preview": null},
		{"id": "c", "name": "丙", "preview": null}])
	return p

func test_three_cards_same_capacity_text() -> void:
	var p := _panel()
	assert_int(p.card_count()).is_equal(3)
	for card in p.cards():
		assert_bool((card as Button).text.ends_with(SelectPanel.CAPACITY_TEXT)).is_true()
	assert_bool(p.confirm_button.disabled).is_true()

func test_focus_and_confirm_emit() -> void:
	var p := _panel()
	var focused: Array = []
	var confirmed: Array = []
	p.candidate_focused.connect(func(id): focused.append(id))
	p.confirmed.connect(func(id): confirmed.append(id))
	(p.cards()[1] as Button).emit_signal("pressed")
	assert_that(focused).is_equal(["b"])
	assert_str(p.focused_id).is_equal("b")
	assert_bool(p.confirm_button.disabled).is_false()
	p.confirm_button.emit_signal("pressed")
	assert_that(confirmed).is_equal(["b"])

func test_focus_api_marks_card_pressed() -> void:
	var p := _panel()
	p.focus("c")
	assert_bool((p.cards()[2] as Button).button_pressed).is_true()
	assert_str(p.focused_id).is_equal("c")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/ui`
Expected: `SelectPanel` 未定义。

- [ ] **Step 3: 写 select_panel.gd**

```gdscript
class_name SelectPanel
extends PanelContainer
## 底部候选卡片（PRD §4.3 / §10.2）：三张卡容量文案一致，只有名字与缩略图不同。

signal candidate_focused(id: String)
signal confirmed(id: String)

const CAPACITY_TEXT := "9 格起步 · 首周可扩到 12 格"
const CARD_MIN := Vector2(104, 156)

var focused_id := ""
var confirm_button: Button
var _cards: Array[Button] = []
var _row: HBoxContainer
var _group := ButtonGroup.new()

func _init() -> void:
	name = "SelectPanel"
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_3)
	add_child(vbox)
	var title := Label.new()
	title.text = "选一片街区，生成你的农场"
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	vbox.add_child(title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	vbox.add_child(_row)
	confirm_button = Button.new()
	confirm_button.text = "确认创建"
	confirm_button.disabled = true
	confirm_button.pressed.connect(func(): if not focused_id.is_empty(): confirmed.emit(focused_id))
	vbox.add_child(confirm_button)
	# 必须放在所有子节点加完之后（2026-09-04 终审 C2）：set_anchors_and_offsets_preset
	# 的默认档 PRESET_MODE_MINSIZE 按**调用那一刻**的 get_combined_minimum_size() 算
	# offset_top；子节点还没挂上去时那是 0，面板会整个长在父容器底边以下、彻底不可见。
	# 候选卡是真正的高度大头（在 set_candidates() 里动态加，不在这里），所以那边也要
	# 在加完卡片后重新调一次这个 preset，否则仍然按"还没有卡片"时的尺寸定住。
	_apply_bottom_preset()

func _apply_bottom_preset() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)

func set_candidates(items: Array) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	focused_id = ""
	confirm_button.disabled = true
	for item in items:
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = _group
		card.custom_minimum_size = CARD_MIN
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.text = "%s\n%s" % [item.name, CAPACITY_TEXT]
		card.icon = item.get("preview")
		card.expand_icon = true
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.set_meta("id", item.id)
		card.pressed.connect(_on_card_pressed.bind(card))
		_row.add_child(card)
		_cards.append(card)
	_apply_bottom_preset() # 卡片才是高度大头，加完之后必须重算一次 offset_top（C2）

func _on_card_pressed(card: Button) -> void:
	focused_id = str(card.get_meta("id"))
	card.button_pressed = true
	confirm_button.disabled = false
	candidate_focused.emit(focused_id)

func focus(id: String) -> void:
	for card in _cards:
		if str(card.get_meta("id")) == id:
			_on_card_pressed(card)
			return

func cards() -> Array[Button]:
	return _cards

func card_count() -> int:
	return _cards.size()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/ui`
Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
git add scenes/select tests/ui
git commit -m "feat(select): 三候选卡片面板"
```

---

### Task 9: 地图接入候选流（高亮 + 卡片 + 确认进农场）

**Files:**
- Modify: `scenes/map_poc/map_poc.gd`
- Create: `tests/map/test_map_candidates.gd`

**Interfaces:**
- Produces（map_poc 新增）：`var candidate_overlay: CandidateOverlay`、`var select_panel: SelectPanel`、`var _candidate_bps: Dictionary`（id → FarmBlueprint）；`load_candidates(r: Dictionary)`（由 `enter_street_mode` 在节点就绪时调用）；`focus_candidate(id)`（fly_to 中心 + 边界 300 m + overlay.select + panel.focus）；`_on_candidate_confirmed(id)`（`FarmChoice.save` + `AppRouter.push_instance(AppRouter.FARM, {...})`）。
- 依赖：`assets/farm/data/regions.json` 与其引用的蓝图存在（Task 4 临时版 + G0-A safe_grid）。

- [ ] **Step 1: 写失败测试**

`tests/map/test_map_candidates.gd`：
```gdscript
extends GdUnitTestSuite
## 受限模式下地图加载 region 的候选：高亮层 + 卡片；聚焦候选时相机飞到蓝图中心并设边界。

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"

func after_test() -> void:
	FarmChoice.clear()

func _map_with_region() -> Node:
	var scene := (load(MAP_POC_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	var regions := FarmRegions.load_default()
	scene.enter_street_mode(regions.region("shanghai"))
	return scene

func test_candidates_loaded_into_overlay_and_panel() -> void:
	var m := _map_with_region()
	var n := FarmRegions.load_default().candidates("shanghai").size()
	assert_object(m.candidate_overlay).is_not_null()
	assert_int(m.candidate_overlay.get_child_count()).is_equal(m._candidate_bps.size())
	assert_int(m.select_panel.card_count()).is_equal(n)
	assert_bool(m._candidate_bps.size() >= 1).is_true()

func test_focus_flies_to_center_and_sets_bounds() -> void:
	var m := _map_with_region()
	var id: String = m._candidate_bps.keys()[0]
	var center: Vector2 = m._candidate_bps[id].overlay.center
	m.focus_candidate(id)
	assert_float(m.center_lat).is_equal_approx(center.x, 1e-9)
	assert_float(m.center_lng).is_equal_approx(center.y, 1e-9)
	assert_bool(m.pan_bounds.size.x > 0.0).is_true()
	assert_str(m.candidate_overlay.selected_id).is_equal(id)
	assert_str(m.select_panel.focused_id).is_equal(id)

func test_confirm_saves_choice() -> void:
	var m := _map_with_region()
	var id: String = m._candidate_bps.keys()[0]
	m._save_choice(id)
	assert_str(FarmChoice.load().layout_patch_id).is_equal(id)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/map`
Expected: `candidate_overlay` 不存在。

- [ ] **Step 3: 改 map_poc.gd**

变量区加：
```gdscript
var candidate_overlay: CandidateOverlay = null
var select_panel: SelectPanel = null
var _candidate_bps: Dictionary = {} # layout_patch_id -> FarmBlueprint
```
`enter_street_mode(r)` 里 `if is_node_ready():` 块末尾加 `load_candidates(r)`；同时在 `_ready()` 末尾的 `if street_mode:` 块里、`_resolve_home(...)` 之后加 `load_candidates(region)`（`_ready` 早期调用 `enter_street_mode` 时节点尚未就绪，所以这里补一次）。
新增方法：
```gdscript
## —— 候选流（PRD §4.3）——————————————————————————————————————————

func load_candidates(r: Dictionary) -> void:
	if candidate_overlay:
		return
	_candidate_bps.clear()
	var items: Array = []
	for c in r.get("candidates", []):
		var id := str(c.layout_patch_id)
		var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path(id, int(c.get("revision", 1))))
		if bp == null:
			continue
		_candidate_bps[id] = bp
		var preview_path := "res://assets/blueprints/%s/r%d/preview.png" % [id, int(c.get("revision", 1))]
		items.append({"id": id, "name": str(c.get("name", id)),
			"preview": load(preview_path) if ResourceLoader.exists(preview_path) else null})
	candidate_overlay = CandidateOverlay.new()
	candidate_overlay.name = "Candidates"
	add_child(candidate_overlay)
	candidate_overlay.set_candidates(_candidate_bps.values(), anchor_lat, anchor_lng)
	select_panel = SelectPanel.new()
	$HUD/SafeArea/Root.add_child(select_panel)
	select_panel.set_candidates(items)
	select_panel.candidate_focused.connect(focus_candidate)
	select_panel.confirmed.connect(_on_candidate_confirmed)
	if not items.is_empty():
		focus_candidate(items[0].id)

func focus_candidate(id: String) -> void:
	if not _candidate_bps.has(id):
		return
	var center: Vector2 = _candidate_bps[id].overlay.center
	fly_to(center.x, center.y)
	set_pan_bounds(center.x, center.y, 300.0)
	candidate_overlay.select(id)
	if select_panel.focused_id != id:
		select_panel.focus(id)

func _save_choice(id: String) -> void:
	FarmChoice.save(id, _candidate_bps[id].revision)

func _on_candidate_confirmed(id: String) -> void:
	_save_choice(id)
	AppRouter.push_instance(AppRouter.FARM, {"layout_patch_id": id, "revision": _candidate_bps[id].revision})
```
`_reposition_pawns()` 末尾加：
```gdscript
	if candidate_overlay:
		candidate_overlay.reanchor(anchor_lat, anchor_lng)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/map`
Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
git add scenes/map_poc/map_poc.gd tests/map
git commit -m "feat(map): 候选高亮与卡片接入，确认后压栈进入农场"
```

---

### Task 10: TouchStick

**Files:**
- Create: `modules/ui/touch_stick.gd`
- Create: `tests/ui/test_touch_stick.gd`

**Interfaces:**
- Produces: `class_name TouchStick`（**不能叫 `VirtualJoystick`**：Godot 4.7 已有同名内置类，GDScript 禁止遮蔽原生类；2026-09-04 执行时经 `ClassDB.class_exists` 核实后改名），`extends Control`：`signal changed(vector: Vector2)`；`@export var radius := 56.0`、`@export var dead_zone := 0.15`；`var vector := Vector2.ZERO`（单位圆内，x 右、y 下）；`static knob_vector(center, pos, radius, dead) -> Vector2`；处理 `InputEventScreenTouch/Drag`（按 `index` 锁定一根手指）。

- [ ] **Step 1: 写失败测试**

`tests/ui/test_touch_stick.gd`：
```gdscript
extends GdUnitTestSuite

func test_knob_vector_dead_zone_and_clamp() -> void:
	var c := Vector2(100, 100)
	assert_that(TouchStick.knob_vector(c, Vector2(104, 100), 56.0, 0.15)).is_equal(Vector2.ZERO)
	var v := TouchStick.knob_vector(c, Vector2(100, 400), 56.0, 0.15)
	assert_float(v.length()).is_equal_approx(1.0, 1e-6)
	assert_float(v.y).is_equal_approx(1.0, 1e-6)
	var half := TouchStick.knob_vector(c, Vector2(128, 100), 56.0, 0.15)
	assert_float(half.x).is_equal_approx(0.5, 1e-6)

func test_touch_sequence_updates_vector_and_emits() -> void:
	var j := auto_free(TouchStick.new())
	j.size = Vector2(140, 140)
	add_child(j)
	var got: Array = []
	j.changed.connect(func(v): got.append(v))
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.index = 0
	down.position = Vector2(70, 70)
	j._gui_input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(126, 70)
	j._gui_input(drag)
	assert_float(j.vector.x).is_equal_approx(1.0, 1e-6)
	var other := InputEventScreenDrag.new()
	other.index = 1
	other.position = Vector2(70, 130)
	j._gui_input(other) # 另一根手指不影响
	assert_float(j.vector.x).is_equal_approx(1.0, 1e-6)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.index = 0
	up.position = Vector2(126, 70)
	j._gui_input(up)
	assert_that(j.vector).is_equal(Vector2.ZERO)
	assert_bool(got.size() >= 2).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/ui`
Expected: `TouchStick` 未定义。

- [ ] **Step 3: 写 touch_stick.gd**

```gdscript
class_name TouchStick
extends Control
## 左下角虚拟摇杆（PRD §3.4）。按下点即摇杆中心（浮动式），单指锁定，抬手归零。

signal changed(vector: Vector2)

@export var radius := 56.0
@export var dead_zone := 0.15

var vector := Vector2.ZERO
var _touch_index := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO

static func knob_vector(center: Vector2, pos: Vector2, p_radius: float, dead: float) -> Vector2:
	var v := (pos - center) / p_radius
	if v.length() > 1.0:
		v = v.normalized()
	return Vector2.ZERO if v.length() < dead else v

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _touch_index < 0:
			_touch_index = e.index
			_center = e.position
			_set(Vector2.ZERO, e.position)
			accept_event()
		elif not e.pressed and e.index == _touch_index:
			_touch_index = -1
			_set(Vector2.ZERO, _center)
			accept_event()
	elif e is InputEventScreenDrag and e.index == _touch_index:
		_set(knob_vector(_center, e.position, radius, dead_zone), e.position)
		accept_event()

func _set(v: Vector2, knob_pos: Vector2) -> void:
	_knob = knob_pos
	if v != vector:
		vector = v
		changed.emit(vector)
	queue_redraw()

func _draw() -> void:
	var c := _center if _touch_index >= 0 else size * 0.5
	draw_circle(c, radius, Color(DesignTokens.INK, 0.12))
	draw_arc(c, radius, 0.0, TAU, 48, Color(DesignTokens.INK, 0.35), 2.0)
	var k := c + vector * radius if _touch_index >= 0 else c
	draw_circle(k, radius * 0.4, Color(DesignTokens.ACCENT, 0.9))
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/ui`
Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
git add modules/ui/touch_stick.gd tests/ui
git commit -m "feat(ui): 虚拟摇杆"
```

---

### Task 11: PlayerMover 网格移动

**Files:**
- Create: `modules/farm/player_mover.gd`
- Create: `tests/farm/test_player_mover.gd`

**Interfaces:**
- Produces: `class_name PlayerMover extends RefCounted`：`_init(bp: FarmBlueprint, grid: BlueprintGrid, world_scale := 1.0)`；`var position: Vector3`（世界系，初始在 spawn 格中心）；`var speed := 2.5`（逻辑米/秒）；`var facing := Vector3(0, 0, 1)`；`cell() -> Vector2i`；`set_target_cell(c) -> bool`（不可达返回 false 且不动）；`set_joystick(v: Vector2)`（x 东、y 南；非零时清除路径）；`is_moving() -> bool`；`step(dt: float)`。

- [ ] **Step 1: 写失败测试**

`tests/farm/test_player_mover.gd`：
```gdscript
extends GdUnitTestSuite

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _mover() -> PlayerMover:
	var bp := FarmBlueprint.load_file(FIX)
	return PlayerMover.new(bp, BlueprintGrid.new(bp))

func test_starts_at_spawn() -> void:
	var m := _mover()
	assert_that(m.cell()).is_equal(Vector2i(3, 3))
	assert_bool(m.is_moving()).is_false()

func test_tap_path_reaches_target_in_expected_time() -> void:
	var m := _mover()
	assert_bool(m.set_target_cell(Vector2i(0, 1))).is_true()
	assert_bool(m.is_moving()).is_true()
	for i in 130: # 5 格 / 2.5 m/s = 2.0 s = 120 帧，留 10 帧余量
		m.step(1.0 / 60.0)
	assert_that(m.cell()).is_equal(Vector2i(0, 1))
	assert_bool(m.is_moving()).is_false()

func test_unreachable_target_rejected() -> void:
	var m := _mover()
	assert_bool(m.set_target_cell(Vector2i(7, 7))).is_false()
	assert_bool(m.is_moving()).is_false()

func test_joystick_moves_east_and_stops_at_water() -> void:
	var m := _mover()
	m.set_joystick(Vector2(1, 0))
	m.step(0.5)
	assert_float(m.position.x).is_greater(3.5)
	m.position = m.bp.cell_to_world(Vector2i(5, 7))
	for i in 60:
		m.step(1.0 / 60.0)
	assert_that(m.cell()).is_equal(Vector2i(5, 7)) # (6,7) 是水塘，卡在边上
	m.set_joystick(Vector2.ZERO)
	assert_bool(m.is_moving()).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/farm`
Expected: `PlayerMover` 未定义。

- [ ] **Step 3: 写 player_mover.gd**

```gdscript
class_name PlayerMover
extends RefCounted
## 农场内移动：摇杆直走（逐帧撞墙检查）或点按寻路（沿 BlueprintGrid 路径）。
## 时间不变量按逻辑格：speed 是逻辑米/秒，world_scale 只放大视觉。

var bp: FarmBlueprint
var grid: BlueprintGrid
var world_scale := 1.0
var position := Vector3.ZERO
var speed := 2.5
var facing := Vector3(0, 0, 1)
var joystick := Vector2.ZERO
var _path: Array[Vector2i] = []
var _path_idx := 0

func _init(p_bp: FarmBlueprint, p_grid: BlueprintGrid, p_scale := 1.0) -> void:
	bp = p_bp
	grid = p_grid
	world_scale = p_scale
	position = bp.cell_to_world(bp.anchor("spawn"), world_scale)

func cell() -> Vector2i:
	return bp.world_to_cell(position, world_scale)

func set_target_cell(c: Vector2i) -> bool:
	var p := grid.path(cell(), c)
	if p.is_empty():
		return false
	_path = p
	_path_idx = 1
	joystick = Vector2.ZERO
	return true

func set_joystick(v: Vector2) -> void:
	joystick = v
	if v != Vector2.ZERO:
		_path.clear()
		_path_idx = 0

func is_moving() -> bool:
	return joystick != Vector2.ZERO or _path_idx < _path.size()

func step(dt: float) -> void:
	var stride := speed * world_scale * dt
	if joystick != Vector2.ZERO:
		var dir := Vector3(joystick.x, 0.0, joystick.y)
		var next := position + dir * stride
		if bp.is_walkable(bp.world_to_cell(next, world_scale)):
			position = next
		facing = dir.normalized()
		return
	if _path_idx >= _path.size():
		return
	var target := bp.cell_to_world(_path[_path_idx], world_scale)
	var to := target - position
	if to.length() <= stride:
		position = target
		_path_idx += 1
	else:
		position += to.normalized() * stride
	if to.length() > 1e-6:
		facing = to.normalized()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/farm`
Expected: 4 passed。

- [ ] **Step 5: Commit**

```bash
git add modules/farm tests/farm
git commit -m "feat(farm): PlayerMover 摇杆直走与点按寻路"
```

---

### Task 12: 农场灰盒场景

**Files:**
- Create: `scenes/farm/farm.tscn`
- Create: `scenes/farm/farm.gd`
- Create: `tests/farm/test_farm_scene.gd`

**Interfaces:**
- Produces：`scenes/farm/farm.tscn` 根 `Farm`（Node3D，脚本 farm.gd）；`setup(args: Dictionary)`（`{"blueprint": FarmBlueprint}` 优先，否则 `{"layout_patch_id", "revision"}`）；`var bp, grid, mover`；`prop_count() -> int`；`WORLD_SCALE := 1.0`、`CAM_DIST := 16.0`、`CAM_PITCH_DEG := 45.0`；退出按钮 → `AppRouter.pop_instance()`。
- 场景树：`Farm/Sun(DirectionalLight3D)`、`WorldEnvironment`、`Camera3D`、`Ground(MeshInstance3D)`、`Props(Node3D)`、`Player(Node3D)`、`HUD(CanvasLayer)/SafeArea(SafeAreaMargin)/Root(Control)/Title(Label)`、`.../ExitButton(Button)`、`.../Joystick(TouchStick)`。
- **2026-09-04 终审 C1 补记**：`Farm` 是靠 `AppRouter.push_instance` 压栈进场的新实例，
  不会经过 Task 5 记录的 suspend/resume 协议（那条协议只管"已经在栈里、被别人盖住/
  揭开"的场景）——自己的 `Camera3D` 要不要成为视口当前相机，得在 `_ready()` 第一次
  入树时自己抢：`cam.make_current()`。不抢的话会保留住地图（或任何压在下面的场景）
  冻结的相机位姿，真机表现是农场里看见的是地图相机俯视几百米外的一个小灰盒，而不是
  农场本身。`WorldEnvironment` 因为是树里第一个（下层地图的环境已经在 suspend() 里被
  摘空），不需要额外动作就会生效。

- [ ] **Step 1: 写失败测试**

`tests/farm/test_farm_scene.gd`：
```gdscript
extends GdUnitTestSuite
## 农场灰盒：加载蓝图 → 地表 + 锚点道具 + 玩家 + 相机；出口按钮接到场景栈。

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _farm() -> Node:
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX)})
	add_child(auto_free(scene))
	return scene

func test_builds_ground_props_and_player_at_spawn() -> void:
	var f := _farm()
	assert_object(f.get_node("Ground").mesh).is_not_null()
	# house + storage + well + exit + 9 田格 + 3 预留格
	assert_int(f.prop_count()).is_equal(4 + 9 + 3)
	assert_that(f.mover.cell()).is_equal(Vector2i(3, 3))
	assert_bool(f.get_node("Player").get_child_count() >= 1).is_true()
	assert_str(f.get_node("HUD/SafeArea/Root/Title").text).is_equal("Fixture Grid")

func test_process_moves_player_and_camera_follows() -> void:
	var f := _farm()
	f.mover.set_target_cell(Vector2i(3, 6))
	for i in 90:
		f._process(1.0 / 60.0)
	var player := f.get_node("Player") as Node3D
	assert_that(f.mover.cell()).is_equal(Vector2i(3, 6))
	assert_that(player.position).is_equal(f.mover.position)
	var cam := f.get_node("Camera3D") as Camera3D
	assert_bool(cam.position.y > player.position.y).is_true()
	assert_bool(cam.position.z > player.position.z).is_true() # 相机在南侧看向北

func test_exit_button_wired_to_router() -> void:
	var f := _farm()
	var btn := f.get_node("HUD/SafeArea/Root/ExitButton") as Button
	assert_int(btn.pressed.get_connections().size()).is_equal(1)

func test_tap_ground_sets_target() -> void:
	var f := _farm()
	var target := f.bp.cell_to_world(Vector2i(1, 5))
	f._on_ground_tapped(target)
	assert_bool(f.mover.is_moving()).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/farm`
Expected: 场景不存在。

- [ ] **Step 3: 写 farm.tscn**

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scenes/farm/farm.gd" id="1_farm"]
[ext_resource type="Script" path="res://modules/ui/safe_area_margin.gd" id="2_sa"]
[ext_resource type="Script" path="res://modules/ui/touch_stick.gd" id="3_joy"]

[sub_resource type="Environment" id="Environment_farm"]
background_mode = 1
background_color = Color(0.82, 0.9, 0.96, 1)
ambient_light_source = 2
ambient_light_color = Color(0.9, 0.92, 0.9, 1)
ambient_light_energy = 0.6

[node name="Farm" type="Node3D"]
script = ExtResource("1_farm")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866, -0.354, 0.354, 0, 0.707, 0.707, -0.5, -0.612, 0.612, 0, 20, 0)
shadow_enabled = true

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_farm")

[node name="Camera3D" type="Camera3D" parent="."]
fov = 45.0

[node name="Ground" type="MeshInstance3D" parent="."]

[node name="Props" type="Node3D" parent="."]

[node name="Player" type="Node3D" parent="."]

[node name="HUD" type="CanvasLayer" parent="."]

[node name="SafeArea" type="MarginContainer" parent="HUD"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("2_sa")

[node name="Root" type="Control" parent="HUD/SafeArea"]
layout_mode = 2
mouse_filter = 2

[node name="Title" type="Label" parent="HUD/SafeArea/Root"]
layout_mode = 1
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -120.0
offset_right = 120.0
offset_top = 12.0
offset_bottom = 40.0
horizontal_alignment = 1

[node name="ExitButton" type="Button" parent="HUD/SafeArea/Root"]
layout_mode = 1
anchors_preset = 0
offset_left = 12.0
offset_top = 12.0
offset_right = 132.0
offset_bottom = 56.0
text = "离开农场"

[node name="Joystick" type="Control" parent="HUD/SafeArea/Root"]
layout_mode = 1
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 16.0
offset_top = -176.0
offset_right = 176.0
offset_bottom = -16.0
script = ExtResource("3_joy")
```

- [ ] **Step 4: 写 farm.gd**

```gdscript
extends Node3D
## 私有农场实例（PRD §3.2 第二层）灰盒：蓝图地表 + 锚点原语 + 自己的 Avatar + 45° 跟随相机。
## 由 AppRouter.push_instance(AppRouter.FARM, {...}) 压在地图之上；退出即 pop。

const WORLD_SCALE := 1.0 # 逻辑米 → 世界米；G1 调观感时只改这里，时长不变量不受影响
const CAM_DIST := 16.0
const CAM_PITCH_DEG := 45.0
const TAP_MAX_PX := 16.0

var bp: FarmBlueprint
var grid: BlueprintGrid
var mover: PlayerMover
var _args := {}
var _rig: AvatarRig
var _anim := ""
var _tap_start := Vector2.ZERO

@onready var cam: Camera3D = $Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var props: Node3D = $Props
@onready var player: Node3D = $Player
@onready var title: Label = $HUD/SafeArea/Root/Title
@onready var exit_btn: Button = $HUD/SafeArea/Root/ExitButton
@onready var joystick: TouchStick = $HUD/SafeArea/Root/Joystick

func setup(args: Dictionary) -> void:
	_args = args

func _ready() -> void:
	# 压栈进入的新实例不会经过 Task 5 的 suspend/resume 协议；自己的相机要不要
	# 成为当前相机得在第一次入树时自己抢，否则会保留住下层场景冻结的相机位姿
	# （2026-09-04 终审 C1）。WorldEnvironment 不需要额外动作：下层地图在
	# suspend() 里已经把自己的 environment 摘空，Farm 自己的 WorldEnvironment
	# 会自动成为树里"第一个有效"的那个。
	cam.make_current()
	bp = _args.get("blueprint")
	if bp == null:
		bp = FarmBlueprint.load_file(FarmBlueprint.asset_path(
			str(_args.get("layout_patch_id", "")), int(_args.get("revision", 1))))
	if bp == null:
		push_error("Farm: 缺少蓝图，退出实例")
		call_deferred("_leave")
		return
	grid = BlueprintGrid.new(bp)
	ground.mesh = BlueprintGroundMesh.build(bp, WORLD_SCALE)
	ground.material_override = BlueprintGroundMesh.material()
	_build_props()
	mover = PlayerMover.new(bp, grid, WORLD_SCALE)
	_spawn_player()
	title.text = bp.display_name
	exit_btn.pressed.connect(_leave)
	joystick.changed.connect(mover.set_joystick)
	player.position = mover.position
	_update_camera()

func _leave() -> void:
	AppRouter.pop_instance()

func prop_count() -> int:
	return props.get_child_count()

func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	props.add_child(mi)

func _build_props() -> void:
	var s := WORLD_SCALE
	_box(bp.cell_to_world(bp.anchor("house"), s), Vector3(2.4, 2.2, 2.4) * s, Color(0.35, 0.45, 0.75))
	_box(bp.cell_to_world(bp.anchor("storage"), s), Vector3(0.9, 0.9, 0.9) * s, Color(0.5, 0.5, 0.5))
	_box(bp.cell_to_world(bp.anchor("well"), s), Vector3(0.8, 1.0, 0.8) * s, Color(0.3, 0.6, 0.85))
	_box(bp.cell_to_world(bp.anchor("exit"), s), Vector3(0.3, 2.0, 0.3) * s, Color(0.85, 0.3, 0.3))
	for bed in bp.beds():
		for c in bed.cells:
			_box(bp.cell_to_world(c, s), Vector3(0.9, 0.15, 0.9) * s, BlueprintGroundMesh.COLOR_BED)
	for c in bp.reserved_bed().get("cells", []):
		_box(bp.cell_to_world(c, s), Vector3(0.9, 0.08, 0.9) * s, Color(0.78, 0.66, 0.55))

func _spawn_player() -> void:
	_rig = Avatar.create_rig()
	_rig.assembler = AvatarAssemblerMerged.new()
	player.add_child(_rig)
	_rig.config_applied.connect(func(_c): _play("idle"))
	_rig.apply_config(Avatar.load_outfit())

func _play(anim: String) -> void:
	if _anim == anim or _rig == null:
		return
	var ap := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(anim):
		ap.play(anim)
		_anim = anim

func _process(dt: float) -> void:
	if mover == null:
		return
	mover.step(dt)
	player.position = mover.position
	if mover.is_moving():
		player.look_at(player.position + mover.facing, Vector3.UP)
		_play("walk")
	else:
		_play("idle")
	_update_camera()

func _update_camera() -> void:
	var phi := deg_to_rad(CAM_PITCH_DEG)
	cam.position = player.position + Vector3(0.0, CAM_DIST * sin(phi), CAM_DIST * cos(phi))
	cam.look_at(player.position + Vector3(0, 0.8, 0), Vector3.UP)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_tap_start = e.position
		elif e.position.distance_to(_tap_start) <= TAP_MAX_PX:
			var hit = Plane(Vector3.UP, 0.0).intersects_ray(
				cam.project_ray_origin(e.position), cam.project_ray_normal(e.position))
			if hit != null:
				_on_ground_tapped(hit as Vector3)

func _on_ground_tapped(world: Vector3) -> void:
	mover.set_target_cell(bp.world_to_cell(world, WORLD_SCALE))

func is_back_navigation_locked() -> bool:
	return false
```

- [ ] **Step 5: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/farm`
Expected: 全绿，orphans 0（`auto_free` 释放场景，rig 随之释放）。

- [ ] **Step 6: Commit**

```bash
git add scenes/farm tests/farm
git commit -m "feat(farm): 农场灰盒场景（地表、锚点、玩家、跟随相机、摇杆/点按）"
```

---

### Task 13: 城市选择场景、桥工厂、主场景切换

**Files:**
- Create: `scenes/map_poc/bridge_factory.gd`
- Modify: `scenes/map_poc/map_poc.gd:194-200`（`_make_bridge` 改为调用工厂）
- Create: `scenes/city_select/city_select.tscn`、`scenes/city_select/city_select.gd`
- Modify: `project.godot`（`run/main_scene`）
- Create: `tests/scenes/test_city_select.gd`

**Interfaces:**
- Produces: `class_name MapBridgeFactory`：`static make() -> MapBridge`（Android 插件 → `MapBridgeAndroid`，iOS → `MapBridgeIOS`，否则 null）。
- Produces: `scenes/city_select/city_select.gd`：`const LOCATE_TIMEOUT_S := 3.0`；`static pick_region(regions: Array, lat, lng, has_fix: bool, fallback := "") -> String`；`region_buttons() -> Array[Button]`；`choose(id)`（`FarmRegions.save_choice` + `AppRouter.go_to_map()`）；`locate()`（一次性前台定位，PRD §4.3 第 1 条）；`status: Label`。
- `project.godot`：`run/main_scene="res://scenes/city_select/city_select.tscn"`。

- [ ] **Step 1: 写失败测试**

`tests/scenes/test_city_select.gd`：
```gdscript
extends GdUnitTestSuite

const SCENE := "res://scenes/city_select/city_select.tscn"

func after_test() -> void:
	FarmRegions.clear_choice()

func test_one_button_per_region() -> void:
	var s := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(s))
	assert_int(s.region_buttons().size()).is_equal(FarmRegions.load_default().ids().size())
	assert_object(s.get_node("%UseCurrent")).is_not_null()

func test_pick_region_pure() -> void:
	var regions := FarmRegions.load_default().regions
	assert_str(s_pick(regions, 34.0, -118.2, true)).is_equal("los_angeles")
	assert_str(s_pick(regions, 0.0, 0.0, false, "shanghai")).is_equal("shanghai")
	assert_str(s_pick(regions, 0.0, 0.0, false)).is_equal("")

func s_pick(regions: Array, lat: float, lng: float, has_fix: bool, fallback := "") -> String:
	var script := load("res://scenes/city_select/city_select.gd")
	return script.pick_region(regions, lat, lng, has_fix, fallback)

func test_main_scene_is_city_select() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal(SCENE)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/scenes`
Expected: 场景不存在。

- [ ] **Step 3: 写 bridge_factory.gd 并改 map_poc**

`scenes/map_poc/bridge_factory.gd`：
```gdscript
class_name MapBridgeFactory
extends RefCounted
## 平台桥工厂（避免 MapBridge 基类反向引用子类的脚本环）。地图场景与城市选择页共用。

static func make() -> MapBridge:
	if Engine.has_singleton("GodotMap"):
		return MapBridgeAndroid.new()
	if OS.get_name() == "iOS":
		return MapBridgeIOS.new()
	return null
```
`map_poc.gd` 的 `_make_bridge()` 函数体改为 `return MapBridgeFactory.make()`。

- [ ] **Step 4: 写 city_select.tscn 与 city_select.gd**

`scenes/city_select/city_select.tscn`：
```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scenes/city_select/city_select.gd" id="1_cs"]
[ext_resource type="Script" path="res://modules/ui/safe_area_margin.gd" id="2_sa"]

[node name="CitySelect" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1_cs")

[node name="SafeArea" type="MarginContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("2_sa")

[node name="VBox" type="VBoxContainer" parent="SafeArea"]
layout_mode = 2
alignment = 1

[node name="Title" type="Label" parent="SafeArea/VBox"]
layout_mode = 2
text = "先选一座城市"
horizontal_alignment = 1

[node name="Buttons" type="VBoxContainer" parent="SafeArea/VBox"]
unique_name_in_owner = true
layout_mode = 2

[node name="UseCurrent" type="Button" parent="SafeArea/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "使用当前城市"

[node name="Status" type="Label" parent="SafeArea/VBox"]
unique_name_in_owner = true
layout_mode = 2
horizontal_alignment = 1
```

`scenes/city_select/city_select.gd`：
```gdscript
extends Control
## 首次进入：手选城市为默认路径；「使用当前城市」只请求一次前台大致定位（PRD §4.3 / §11.3）。

const LOCATE_TIMEOUT_S := 3.0

var regions: FarmRegions
var _bridge: MapBridge = null
var _located := false

@onready var buttons: VBoxContainer = %Buttons
@onready var use_current: Button = %UseCurrent
@onready var status: Label = %Status

static func pick_region(p_regions: Array, lat: float, lng: float, has_fix: bool, fallback := "") -> String:
	return FarmRegions.nearest_region_id(p_regions, lat, lng) if has_fix else fallback

func _ready() -> void:
	regions = FarmRegions.load_default()
	if regions == null:
		status.text = "缺少城市配置"
		return
	for r in regions.regions:
		var b := Button.new()
		b.text = str(r.name)
		b.custom_minimum_size = Vector2(0, DesignTokens.BTN_PAD_V * 2 + DesignTokens.FONT_BODY)
		b.pressed.connect(choose.bind(str(r.id)))
		buttons.add_child(b)
	use_current.pressed.connect(locate)
	status.text = ""

func region_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in buttons.get_children():
		if c is Button:
			out.append(c)
	return out

func choose(id: String) -> void:
	FarmRegions.save_choice(id)
	AppRouter.go_to_map()

func locate() -> void:
	if _bridge == null:
		_bridge = MapBridgeFactory.make()
	if _bridge == null:
		status.text = "此设备无法定位，请手选城市"
		return
	use_current.disabled = true
	status.text = "正在定位…"
	_bridge.location_update.connect(_on_location, CONNECT_ONE_SHOT)
	_bridge.start_location()
	get_tree().create_timer(LOCATE_TIMEOUT_S).timeout.connect(func():
		if not _located:
			use_current.disabled = false
			status.text = "定位超时，请手选城市")

func _on_location(lat: float, lng: float, _accuracy: float) -> void:
	if _located:
		return
	_located = true
	choose(pick_region(regions.regions, lat, lng, true))

func _process(_dt: float) -> void:
	if _bridge:
		_bridge.poll()
```
`project.godot` 的 `run/main_scene="res://scenes/map_poc/map_poc.tscn"` 改为 `run/main_scene="res://scenes/city_select/city_select.tscn"`。

- [ ] **Step 5: 跑测试确认通过（含地图回归）**

Run: `tools/run_tests.sh res://tests/scenes && tools/run_tests.sh res://tests/map`
Expected: 全绿。

- [ ] **Step 6: Commit**

```bash
git add scenes/city_select scenes/map_poc/bridge_factory.gd scenes/map_poc/map_poc.gd project.godot tests/scenes
git commit -m "feat(city): 城市选择页（手选 + 一次性定位）、桥工厂、主场景切换"
```

---

### Task 14: 公平校验测试、全量测试、Android 构建与人工验收清单

**Files:**
- Create: `modules/blueprint/fairness.gd`
- Create: `tests/blueprint/test_fairness.gd`
- Create: `docs/superpowers/plans/2026-09-XX-g0-handoff.md`（XX = 实际日期）

**Interfaces:**
- Produces: `class_name BlueprintFairness`：`const WALK_SPEED := 2.5`、`const ACTION_S := 2.0`、`const MAX_FAR_BED_S := 12.0`、`const MAX_SPREAD := 0.10`；`static metrics(bp, grid) -> Dictionary {far_bed_s, tour_s}`（与 Node `anchors.validate` 同公式：far = 出生点到任一田格最远 BFS 距离；tour = 出生点 → 各畦首格依次 → 出生点，再加 9 × 2 s）；`static spread(values: Array) -> float`。
- 依赖 G0-A Task 10 产出的 `regions.json` 与六个蓝图。

- [ ] **Step 1: 写失败测试**

`tests/blueprint/test_fairness.gd`：
```gdscript
extends GdUnitTestSuite
## PRD §4.4：出生点到最远田畦时间差 <10%，九格巡回时间差 <10%；同时验证真实蓝图 checksum 跨语言一致。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func test_metrics_on_fixture_match_node_formula() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var m := BlueprintFairness.metrics(bp, BlueprintGrid.new(bp))
	assert_float(m.far_bed_s).is_equal_approx(2.0, 1e-6) # 最远田格 5 格 / 2.5
	assert_float(m.tour_s).is_equal_approx(22.0 / 2.5 + 18.0, 1e-6) # 5+4+8+5 格 + 9×2 s

func test_spread() -> void:
	assert_float(BlueprintFairness.spread([10.0, 10.5, 11.0])).is_equal_approx(0.1, 1e-9)
	assert_float(BlueprintFairness.spread([])).is_equal(0.0)

func test_shipped_blueprints_fair_and_checksummed() -> void:
	var regions := FarmRegions.load_default()
	assert_object(regions).is_not_null()
	var far: Array = []
	var tour: Array = []
	var seen := {}
	for rid in regions.ids():
		for c in regions.candidates(rid):
			var id := str(c.layout_patch_id)
			if seen.has(id) or id.begins_with("safe"):
				continue
			seen[id] = true
			var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path(id, int(c.revision)))
			assert_object(bp).override_failure_message("缺少蓝图 %s" % id).is_not_null()
			assert_bool(bp.verify_checksum()).override_failure_message("checksum 跨语言不一致: %s" % id).is_true()
			var m := BlueprintFairness.metrics(bp, BlueprintGrid.new(bp))
			assert_float(m.far_bed_s).is_less_equal(BlueprintFairness.MAX_FAR_BED_S)
			far.append(m.far_bed_s)
			tour.append(m.tour_s)
	assert_int(seen.size()).override_failure_message("需要 6 个真实蓝图（G0-A Task 10）").is_equal(6)
	assert_float(BlueprintFairness.spread(far)).is_less_equal(BlueprintFairness.MAX_SPREAD)
	assert_float(BlueprintFairness.spread(tour)).is_less_equal(BlueprintFairness.MAX_SPREAD)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/blueprint`
Expected: `BlueprintFairness` 未定义。

- [ ] **Step 3: 写 fairness.gd**

```gdscript
class_name BlueprintFairness
extends RefCounted
## 与 tools/geo_blueprint/src/anchors.ts validate() 同一套公式，Godot 侧再算一遍做双端守卫。

const WALK_SPEED := 2.5
const ACTION_S := 2.0
const MAX_FAR_BED_S := 12.0
const MAX_SPREAD := 0.10

static func metrics(bp: FarmBlueprint, grid: BlueprintGrid) -> Dictionary:
	var spawn := bp.anchor("spawn")
	var far := 0.0
	var firsts: Array[Vector2i] = []
	for bed in bp.beds():
		for c in bed.cells:
			far = maxf(far, grid.distance_cells(spawn, c))
		firsts.append(bed.cells[0])
	var tour := 0.0
	var cur := spawn
	for nxt in firsts + [spawn]:
		tour += grid.distance_cells(cur, nxt)
		cur = nxt
	var n_cells := 0
	for bed in bp.beds():
		n_cells += bed.cells.size()
	return {
		"far_bed_s": far * bp.cell_m / WALK_SPEED,
		"tour_s": tour * bp.cell_m / WALK_SPEED + n_cells * ACTION_S,
	}

static func spread(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var lo: float = values.min()
	var hi: float = values.max()
	return (hi - lo) / maxf(lo, 1e-9)
```

- [ ] **Step 4: 跑全量测试**

Run: `tools/run_tests.sh`
Expected: 全绿，orphans 0。`test_shipped_blueprints_fair_and_checksummed` 在 G0-A Task 10 完成前会因「需要 6 个真实蓝图」失败，这是预期的门禁，不要改断言。

- [ ] **Step 5: 构建 Android 并写人工验收清单**

```bash
tools/android/setup_android_build.sh
godot --headless --path . --export-debug "Android" build/sensen-g0-debug.apk
adb install -r build/sensen-g0-debug.apk
```
新建 `docs/superpowers/plans/2026-09-XX-g0-handoff.md`，沿用 `2026-09-01-internal-demo-handoff.md` 的「机器验证 / 人工验收」两栏格式，人工项固定如下（没亲眼确认的不打勾）：

| # | 验收项 | 判据 |
|---|---|---|
| 1 | 开 App 落在城市选择页；点「上海」进入受限地图 | 地图 zoom 16 / 45° / 正北，捏合与双击不改缩放，旋转手势无效 |
| 2 | 三张候选卡片文案一致；点卡片地图飞到对应街区并高亮 | 高亮贴地不撕裂、不漂移；拖出 300 m 边界被挡住 |
| 3 | 「确认创建」→ 卡片展开、地图消失、进入农场 | 地图 HUD 与 Mapbox 完全不可见 |
| 4 | 农场内摇杆与点按都能到达房屋、储物、水井、三畦、出口 | 无卡死、无穿越 |
| 5 | 「离开农场」→ 回到地图，相机中心、选中卡片、高亮与离开前一致 | 与 PRD §10.3 |
| 6 | 去标签后把三张 preview.png 与三个农场灰盒配对 | 至少 5 名同事中 4 名配对正确（Gate 0 缩小版） |
| 7 | 换城市到洛杉矶重复 1-5 | 同上 |
| 8 | 地图 → 换装房 → 返回，地图仍在原候选 | 场景栈迁移后的回归 |
| 9 | 真机 RSS：进入农场后 `adb shell dumpsys meminfo com.sensen.avatarphase1` | 记录数值，作为 D2 场景栈常驻的基线 |

- [ ] **Step 6: Commit**

```bash
git add modules/blueprint tests/blueprint docs/superpowers/plans/2026-09-*-g0-handoff.md
git commit -m "feat(blueprint): 公平校验（与 Node 校验器同公式）+ G0 人工验收清单"
```

---

## Self-Review

- **Spec coverage**：PRD §3.1 受限浏览（Task 6）、§3.2 独立实例与地图隐藏（Task 5/6/12）、§3.4 农场内移动与相机（Task 10/11/12）、§4.3 创建流程 1-7 条（Task 9/13：手选城市、一次性定位、三候选同源高亮、缩略预览、相同容量文案、确认后地图消失；第 7 条「普通地图不再常驻显示土地边界」= 返回地图后 overlay 仍在选择态，G1 创建 farm_instance 后隐藏，本 Gate 不做）、§4.4 公平门槛（Task 14）、§4.5 同源编译（Task 7 直接吃蓝图 overlay）、§4.6 checksum 双端一致（Task 1 fixture + Task 14 真实蓝图）、§10.3 返回恢复（Task 5 场景栈 + Task 6 suspend/resume）、§11.5 网格 A*/静态 mesh（Task 2/3）。
- **留到 G1**：`farm_instance_id` 与服务端创建；卡片扩展动画；候选 overlay 在创建后隐藏；地表 .res 烘焙（G4）。
- **Placeholder scan**：无 TBD；每步有代码与命令。
- **Type consistency**：`FarmBlueprint.overlay.center` 为 `Vector2(lat, lng)`，Task 7/9 按 `.x = lat, .y = lng` 使用；`BlueprintGrid.distance_cells` 返回 `float`/`INF`，Task 14 直接求和；`PlayerMover.set_joystick(Vector2)` 与 `TouchStick.changed(Vector2)` 签名匹配（Task 12 直接 connect）；`AppRouter.push_instance` 返回 `Node`，Task 5 测试用 `.args/.suspended` 走探针脚本。
- **风险提示**：`AStarGrid2D.get_id_path` 在 4.7 返回 `Array[Vector2i]`；`Geometry2D.triangulate_polygon` 对自交多边形返回空，Task 7 的 overlay 多边形来自 GEOS polygonize，不会自交；Task 12 的 `player.look_at` 在 facing 与 UP 平行时会报错，facing 恒水平所以不会发生。
