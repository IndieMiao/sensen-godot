class_name CropField
extends Node3D
## 作物渲染：4 作物 × 4 可见阶段，每种作物一个 MultiMesh；另有一份杂草 MultiMesh 画荒地。
##
## **阶段是渲染派生量，从不进状态**。进度按 `watered_at → ready_at` 分四段：
##   0 / ⅓ / ⅔ / 成熟。ready_at 为 null（刚播种，或预测器预测了照料但服务端还没回包）
## 一律停在阶段 0——客户端不猜时长。
##
## 合并低面数植株：每种作物一个共享网格，植株数量不会增加场景节点。

const PlantMesh = preload("res://modules/farm/crop_plant_mesh.gd")

const CROPS := ["R", "L", "C", "H", "T", "B", "P", "I", "M"]
const STAGES := 4
## 与种子袋和作物 PNG 一致的根茎色，叶片保留自己的绿色。
const CROP_COLOR := {
	"R": Color(0.97, 0.96, 0.85),   # 白萝卜
	"L": Color(0.46, 0.76, 0.40),   # 生菜
	"C": Color(0.93, 0.60, 0.24),   # 胡萝卜
	"H": Color(0.95, 0.90, 0.52),   # 洋甘菊
	"T": Color(0.36, 0.52, 0.28),   # 果树：木本，阻挡通行
	"B": Color(0.55, 0.80, 0.38),   # 香草（P0）
	"P": Color(0.80, 0.64, 0.42),   # 土豆：块茎色（P0）
	"I": Color(0.88, 0.25, 0.20),   # 辣椒：果色（P0）
	"M": Color(0.90, 0.30, 0.22),   # 番茄：果色（P0）
}
## 带成熟细节层（根 / 花 / 果）的作物，及细节出现的阶段。
const DETAIL_STAGE := {"R": 2, "C": 2, "H": 3, "P": 2, "I": 2, "M": 2}
const WEED_COLOR := Color(0.46, 0.58, 0.30)
## 翻土层包含五条立体垄沟，与只清理过的平地分开。
const SOIL_COLOR := Color(0.55, 0.38, 0.23)
## 翻土层已交给地面 shader；这一层只在没有 PlotSurface 的旧场景里兜底。
const SOIL_SIZE := Vector3(0.92, 0.035, 0.92)
## 刚播下的幼苗用亮绿：阶段 0 曾是 0.10 高的暗绿小块，埋在畦面里根本看不见。
const SEEDLING_COLOR := Color(0.72, 0.93, 0.52)
## 四阶段的植株尺寸，单位是**格边长的倍数**而不是绝对米：过去这些数字是为 1.3m 的
## 田畦间距调的，0.5m 紧邻格下会让邻格的作物互相穿插。
const STAGE_SIZE := [
	Vector3(0.38, 0.32, 0.38),
	Vector3(0.54, 0.48, 0.54),
	Vector3(0.68, 0.68, 0.68),
	Vector3(0.80, 0.88, 0.80),
]
const WEED_SIZE := Vector3(0.48, 0.68, 0.48)
## 一格一株：0.5m 格里塞 4 株是 16 株/m²，视觉糊成一团且实例数翻四倍。
const PER_CELL := 1
const JITTER := 0.0

var bp: FarmBlueprint
var world_scale := 1.0
## 作物从地面往上长。田畦盒子随自由格子种田退役，这里通常是 0。
var ground_y := 0.0
## 独立土畦（P0 固定田位）没有地面 shader 画田况：荒地画杂草层，翻过的地画翻土板。
var ground_layers := false
## Plants are sized in cell units; a bed wider than its cell (P0 fixed beds: 0.94 m on 0.65 m cells) scales them up.
var plant_scale := 1.0
var _mm: Dictionary = {}       ## crop_id / "weed" / "soil" → MultiMeshInstance3D
var _detail_mm: Dictionary = {} # Roots and flowers appear only in their visible growth stage.

func _init(p_bp: FarmBlueprint = null, p_scale := 1.0) -> void:
	bp = p_bp
	world_scale = p_scale

func _ready() -> void:
	for crop in CROPS:
		_mm[crop] = _make_layer(PlantMesh.build(crop, CROP_COLOR[crop]))
	_mm["weed"] = _make_layer(PlantMesh.build("weed", WEED_COLOR))
	_mm["soil"] = _make_layer(PlantMesh.build("soil", SOIL_COLOR))
	for crop in DETAIL_STAGE:
		_detail_mm[crop] = _make_layer(PlantMesh.build(crop + "_detail", CROP_COLOR[crop]))

func _make_layer(mesh: Mesh) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 0
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# 实例色是 8 位 sRGB；不声明的话会被当线性色，整体发白——真机上深棕翻土板成了浅褐。
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = mat
	add_child(mmi)
	return mmi

## 阶段号 0..3。**派生量**：ready_at 为 null 一律阶段 0，不猜时长。
static func stage_of(slot: Dictionary, now_ms: int) -> int:
	var ready = slot.get("ready_at")
	var started = slot.get("watered_at")
	if ready == null or started == null:
		return 0
	var span := int(ready) - int(started)
	if span <= 0:
		return STAGES - 1
	var progress := float(now_ms - int(started)) / float(span)
	if progress >= 1.0:
		return STAGES - 1
	if progress <= 0.0:
		return 0
	return clampi(int(progress * float(STAGES - 1)), 0, STAGES - 2)

## 这格该画什么：`""` 表示不画。
## 开垦过的空地由地面 shader 画垄沟，这里只负责立体的作物。
static func layer_of(slot: Dictionary) -> String:
	match str(slot.get("state", "")):
		"sown", "growing": return str(slot.get("crop", ""))
		_: return ""

## 访客快照没有 ready_at（spec §7.5 故意不发），阶段只能按 ripe 标志粗分：
## ripe → 成熟；growing → 阶段 1；sown → 阶段 0。冻结快照，不随时间走。
static func stage_from_snapshot(c: Dictionary) -> int:
	if bool(c.get("ripe", false)):
		return STAGES - 1
	return 1 if str(c.get("state", "")) == "growing" else 0

func sync_snapshot(cells: Array) -> void:
	var buckets := {"weed": [], "soil": []}
	for crop in CROPS:
		buckets[crop] = []
	for c in cells:
		var slot := {"state": c.get("state", ""), "crop": c.get("crop")}
		var layer := layer_of(slot)
		if layer == "" or not buckets.has(layer):
			continue
		buckets[layer].append({"cell": _parse_cell(str(c.get("cell_id", ""))),
			"stage": 0 if layer in ["weed", "soil"] else stage_from_snapshot(c)})
	_sync_buckets(buckets)

func sync(cells: Dictionary, now_ms: int) -> void:
	var buckets := {"weed": [], "soil": []}
	for crop in CROPS:
		buckets[crop] = []
	for id in cells:
		var slot: Dictionary = cells[id]
		var layer := layer_of(slot)
		if layer == "" and ground_layers:
			layer = {"wild": "weed", "tilled": "soil"}.get(str(slot.get("state", "")), "")
		if layer == "" or not buckets.has(layer):
			continue
		var cell := _parse_cell(str(id))
		var stage := 0 if layer in ["weed", "soil"] else stage_of(slot, now_ms)
		buckets[layer].append({"cell": cell, "stage": stage, "tint": slot.get("tint", Color.WHITE)})
	_sync_buckets(buckets)

func _sync_buckets(buckets: Dictionary) -> void:
	for layer in buckets:
		_fill(_mm[layer], buckets[layer], layer)
		if _detail_mm.has(layer):
			var detail_stage: int = DETAIL_STAGE[layer]
			var detailed: Array = buckets[layer].filter(func(item): return int(item.stage) >= detail_stage)
			_fill(_detail_mm[layer], detailed, layer)

static func per_cell(layer: String) -> int:
	return 1 if layer == "soil" else PER_CELL

func _fill(mmi: MultiMeshInstance3D, items: Array, layer: String) -> void:
	var mm := mmi.multimesh
	var per := per_cell(layer)
	mm.instance_count = items.size() * per
	var n := 0
	for item in items:
		var color := _stage_color(layer, item.stage) * (item.get("tint", Color.WHITE) as Color)
		for t in _cell_instances(item.cell, layer, item.stage, bp.cell_to_world(item.cell, world_scale)):
			mm.set_instance_transform(n, t)
			mm.set_instance_color(n, color)
			n += 1

## One cell's instance transforms around `base` (the cell's world point; zero for a copy standing at the cell).
func _cell_instances(cell: Vector2i, layer: String, stage: int, base: Vector3) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var per := per_cell(layer)
	var unit := bp.cell_m * world_scale * plant_scale
	var size: Vector3
	match layer:
		"weed": size = WEED_SIZE * unit
		"soil": size = SOIL_SIZE * unit
		_: size = STAGE_SIZE[stage] * unit
	for k in per:
		var dx := 0.0 if per == 1 else (-1.0 if k % 2 == 0 else 1.0) * JITTER * unit
		var dz := 0.0 if per == 1 else (-1.0 if k < 2 else 1.0) * JITTER * unit
		# 从畦面顶部往上长，而不是从世界原点：否则矮的东西全埋在畦面盒子里
		var angle := float(posmod(cell.x * 7 + cell.y * 11 + k * 5, 16)) * TAU / 16.0
		var rotation := Basis.IDENTITY if layer == "soil" else Basis(Vector3.UP, angle)
		out.append(Transform3D(rotation * Basis.from_scale(size), base + Vector3(dx, ground_y + size.y * 0.5, dz)))
	return out

## A stand-alone copy of one cell's crop as the field draws it, standing at the cell (a child of this field): a
## harvest's pop plays on the copy while the field has already dropped the crop (SGODOT-289, Harvest ×N's wave).
## Its detail layer comes along at the stages that have one; same meshes and materials.
func ghost(cell: Vector2i, layer: String, stage := STAGES - 1, tint := Color.WHITE) -> Node3D:
	var root := Node3D.new()
	root.position = bp.cell_to_world(cell, world_scale)
	if not _mm.has(layer): return root
	var srcs: Array = [_mm[layer]]
	if _detail_mm.has(layer) and stage >= int(DETAIL_STAGE[layer]): srcs.append(_detail_mm[layer])
	var ts := _cell_instances(cell, layer, stage, Vector3.ZERO)
	for src in srcs:
		var m := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = (src as MultiMeshInstance3D).multimesh.mesh
		mm.instance_count = ts.size()
		for i in ts.size():
			mm.set_instance_transform(i, ts[i])
			mm.set_instance_color(i, _stage_color(layer, stage) * tint)
		m.multimesh = mm
		m.material_override = (src as MultiMeshInstance3D).material_override
		root.add_child(m)
	add_child(root)
	return root

static func _stage_color(layer: String, stage: int) -> Color:
	if layer == "weed":
		return Color.WHITE
	if layer == "soil":
		return Color.WHITE
	if stage == 0:
		return SEEDLING_COLOR
	return SEEDLING_COLOR.lerp(Color.WHITE, float(stage) / float(STAGES - 1))

## 每层的实例数（格数 × PER_CELL）；测试用。
func counts() -> Dictionary:
	var out := {}
	for layer in _mm:
		out[layer] = (_mm[layer] as MultiMeshInstance3D).multimesh.instance_count
	return out

## 每层的格数。
func cell_counts() -> Dictionary:
	var out := {}
	var c := counts()
	for layer in c:
		out[layer] = c[layer] / per_cell(layer)
	return out

static func _parse_cell(id: String) -> Vector2i:
	var parts := id.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))
