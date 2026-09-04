class_name CropField
extends Node3D
## 作物渲染：4 作物 × 4 可见阶段，每种作物一个 MultiMesh；另有一份杂草 MultiMesh 画荒地。
##
## **阶段是渲染派生量，从不进状态**（PRD §6.2）。进度按 `care_done_at → ready_at` 分四段：
##   0 / ⅓ / ⅔ / 成熟。ready_at 为 null（刚播种，或预测器预测了照料但服务端还没回包）
## 一律停在阶段 0——客户端不猜时长。
##
## 灰盒外观：BoxMesh 按阶段缩放 + 顶点色。真美术进来时只换 mesh 与材质，分段逻辑不动。

const CROPS := ["R", "L", "C", "H"]
const STAGES := 4
## 每种作物的灰盒色（成熟阶段整体提亮，见 _stage_color）。
const CROP_COLOR := {
	"R": Color(0.86, 0.36, 0.36),   # 小萝卜
	"L": Color(0.46, 0.76, 0.40),   # 生菜
	"C": Color(0.93, 0.60, 0.24),   # 胡萝卜
	"H": Color(0.95, 0.90, 0.52),   # 洋甘菊
}
const WEED_COLOR := Color(0.42, 0.47, 0.30)
## 四阶段的盒体尺寸（逻辑米）；成熟那阶段明显更高更挺。
const STAGE_SIZE := [
	Vector3(0.18, 0.10, 0.18),
	Vector3(0.26, 0.26, 0.26),
	Vector3(0.34, 0.46, 0.34),
	Vector3(0.40, 0.66, 0.40),
]
const WEED_SIZE := Vector3(0.22, 0.18, 0.22)
## 一格里散布几株，摆成 2×2。
const PER_CELL := 4
const JITTER := 0.22

var bp: FarmBlueprint
var world_scale := 1.0
var _mm: Dictionary = {}       ## crop_id / "weed" → MultiMeshInstance3D

func _init(p_bp: FarmBlueprint = null, p_scale := 1.0) -> void:
	bp = p_bp
	world_scale = p_scale

func _ready() -> void:
	for crop in CROPS:
		_mm[crop] = _make_layer(BoxMesh.new())
	_mm["weed"] = _make_layer(BoxMesh.new())

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
	mmi.material_override = mat
	add_child(mmi)
	return mmi

## 阶段号 0..3。**派生量**：ready_at 为 null 一律阶段 0，不猜时长。
static func stage_of(slot: Dictionary, now_ms: int) -> int:
	var ready = slot.get("ready_at")
	var started = slot.get("care_done_at")
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

## 这格该画什么：`""` 表示不画（cleared / tilled 都是空地）。
static func layer_of(slot: Dictionary) -> String:
	match str(slot.get("state", "")):
		"wild": return "weed"
		"sown", "growing": return str(slot.get("crop", ""))
		_: return ""

func sync(cells: Dictionary, now_ms: int) -> void:
	var buckets := {"weed": []}
	for crop in CROPS:
		buckets[crop] = []
	for id in cells:
		var slot: Dictionary = cells[id]
		var layer := layer_of(slot)
		if layer == "" or not buckets.has(layer):
			continue
		var cell := _parse_cell(str(id))
		var stage := 0 if layer == "weed" else stage_of(slot, now_ms)
		buckets[layer].append({"cell": cell, "stage": stage})
	for layer in buckets:
		_fill(_mm[layer], buckets[layer], layer)

func _fill(mmi: MultiMeshInstance3D, items: Array, layer: String) -> void:
	var mm := mmi.multimesh
	mm.instance_count = items.size() * PER_CELL
	var n := 0
	for item in items:
		var base: Vector3 = bp.cell_to_world(item.cell, world_scale)
		var size: Vector3 = (WEED_SIZE if layer == "weed" else STAGE_SIZE[item.stage]) * world_scale
		var color := _stage_color(layer, item.stage)
		for k in PER_CELL:
			var dx := (-1.0 if k % 2 == 0 else 1.0) * JITTER * world_scale
			var dz := (-1.0 if k < 2 else 1.0) * JITTER * world_scale
			var t := Transform3D(Basis().scaled(size), base + Vector3(dx, size.y * 0.5, dz))
			mm.set_instance_transform(n, t)
			mm.set_instance_color(n, color)
			n += 1

static func _stage_color(layer: String, stage: int) -> Color:
	if layer == "weed":
		return WEED_COLOR
	var c: Color = CROP_COLOR[layer]
	# 未成熟偏绿偏暗，成熟才回到作物本色并提亮——玩家一眼能挑出该收的格子。
	if stage >= STAGES - 1:
		return c.lightened(0.12)
	return c.lerp(Color(0.36, 0.62, 0.34), 1.0 - float(stage) / float(STAGES - 1)).darkened(0.1)

## 每层的实例数（格数 × PER_CELL）；测试用。
func counts() -> Dictionary:
	var out := {}
	for layer in _mm:
		out[layer] = (_mm[layer] as MultiMeshInstance3D).multimesh.instance_count
	return out

## 每层的格数。
func cell_counts() -> Dictionary:
	var out := {}
	for layer in counts():
		out[layer] = counts()[layer] / PER_CELL
	return out

static func _parse_cell(id: String) -> Vector2i:
	var parts := id.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))
