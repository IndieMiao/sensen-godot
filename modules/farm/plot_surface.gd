class_name PlotSurface
extends MeshInstance3D
## 农场地面：一张平面 + 一张 64×64 的状态纹理，格子状态由 shader 按世界坐标采样。
##
## 为什么不是每格一个网格或 MultiMesh：地块状态每次预测、每次回包都会变，逐格重建实例
## 缓冲是纯浪费。纹理方案下状态变化只写被改的那几个像素 + 一次 texture update，
## **绘制永远是 1 个 draw call，与格数无关**——它天然撑得住全部 4096 格。
##
## 这也是取代逐格动作图标的那件东西：玩家看地面就知道哪块翻过、哪块浇过、哪块能收。
##
## 通道约定（与 shaders/plot_ground.gdshader 对应）：
##   R = 地面类型  0 草地 / 1 可开垦土 / 2 道路 / 3 不可通行
##   G = 格子状态  0 未开垦 / 1 已开垦 / 2 已播种 / 3 生长中 / 4 可收割
##   B = 湿度      0..255，浇水置满，随生长回落
##   A = 交互高亮  0 无 / 1 队列中 / 2 刷子命中 / 3 当前作业格

const KIND_GRASS := 0
const KIND_SOIL := 1
const KIND_PATH := 2
const KIND_BLOCKED := 3

const STATE_WILD := 0
const STATE_TILLED := 1
const STATE_SOWN := 2
const STATE_GROWING := 3
const STATE_RIPE := 4

var bp: FarmBlueprint
var world_scale := 1.0
var _image: Image
var _texture: ImageTexture
var _material: ShaderMaterial
var _dirty := false

func _init(p_bp: FarmBlueprint, p_scale := 1.0) -> void:
	bp = p_bp
	world_scale = p_scale

func _ready() -> void:
	name = "PlotSurface"
	_image = Image.create(bp.grid.x, bp.grid.y, false, Image.FORMAT_RGBA8)
	# 静态层：地面类型一次写死，之后只改 G/B/A 三个通道。
	for j in bp.grid.y:
		for i in bp.grid.x:
			var c := Vector2i(i, j)
			var kind := KIND_BLOCKED
			if bp.mask_has("cultivable", c): kind = KIND_SOIL
			elif FarmPlot.kind_at(bp.layout_patch_id, c) == "path": kind = KIND_PATH
			elif bp.is_walkable(c): kind = KIND_GRASS
			_image.set_pixel(i, j, Color8(kind, STATE_WILD, 0, 0))
	_texture = ImageTexture.create_from_image(_image)

	var plane := PlaneMesh.new()
	plane.size = Vector2(bp.grid.x, bp.grid.y) * bp.cell_m * world_scale
	mesh = plane
	# 平面中心在原点，而格 (0,0) 的世界坐标是 (+half_cell, -half_cell)，所以整体偏半张图。
	position = Vector3(plane.size.x * 0.5, 0.004, -plane.size.y * 0.5)

	_material = ShaderMaterial.new()
	_material.shader = preload("res://modules/farm/shaders/plot_ground.gdshader")
	_material.set_shader_parameter("plot_state", _texture)
	var source: Dictionary = FarmPlot.source_for(bp.layout_patch_id)
	var terrain_texture: Texture2D
	if source.has("ground_texture"):
		terrain_texture = load(str(source.ground_texture))
	else:
		terrain_texture = FarmTerrainMask.texture_for(bp)
	_material.set_shader_parameter("terrain_mask", terrain_texture)
	_material.set_shader_parameter("bank_grass", preload("res://assets/farm/art/water/bank_grass.png"))
	_material.set_shader_parameter("meadow_texture", preload("res://assets/farm/art/meadow.png"))
	_material.set_shader_parameter("grid_size", Vector2(bp.grid.x, bp.grid.y))
	_material.set_shader_parameter("cell_m", bp.cell_m * world_scale)
	_material.set_shader_parameter("woodland_start", -bp.cell_to_world(bp.anchor("house")).z + 3.75)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if bp.layout_patch_id.begins_with("geo_"): _add_geographic_water(terrain_texture, plane.size)

func _add_geographic_water(terrain_texture: Texture2D, extent: Vector2) -> void:
	var water := MeshInstance3D.new()
	water.name = "GeographicWater"
	var plane := PlaneMesh.new()
	plane.size = extent
	water.mesh = plane
	water.position.y = 0.051
	water.layers = 2
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://modules/fishing/water.gdshader")
	material.set_shader_parameter("geographic_water", true)
	material.set_shader_parameter("geographic_mask", terrain_texture)
	material.set_shader_parameter("geographic_extent", extent)
	material.set_shader_parameter("exclude_farm_basin", false)
	material.set_shader_parameter("pebble_bed", preload("res://assets/farm/art/water/sediment.png"))
	material.set_shader_parameter("surface_flow", preload("res://assets/farm/art/water/surface_flow.png"))
	material.set_shader_parameter("caustics", preload("res://assets/farm/art/water/caustic_light.png"))
	water.material_override = material
	add_child(water)

## 按当前视图刷新全部格子状态。只写变化的像素，纹理一帧上传一次。
func sync(cells: Dictionary, now_ms: int) -> void:
	for j in bp.grid.y:
		for i in bp.grid.x:
			_write(Vector2i(i, j), STATE_WILD, 0)
	for id in cells:
		var cell := _parse(str(id))
		if not bp.in_bounds(cell): continue
		var slot: Dictionary = cells[id]
		_write(cell, _state_of(slot, now_ms), _moisture_of(slot, now_ms))
	_flush()

## 交互高亮：队列中 / 刷子命中 / 当前作业格。与状态分开，不触发整张重算。
func highlight(queued: Array, brushed: Array, current) -> void:
	for j in bp.grid.y:
		for i in bp.grid.x:
			_write_alpha(Vector2i(i, j), 0)
	for cell in queued: _write_alpha(cell, 1)
	for cell in brushed: _write_alpha(cell, 2)
	if current != null: _write_alpha(current, 3)
	_flush()

static func _state_of(slot: Dictionary, now_ms: int) -> int:
	match str(slot.get("state", "")):
		"tilled": return STATE_TILLED
		"sown": return STATE_SOWN
		"growing":
			var ready = slot.get("ready_at")
			return STATE_RIPE if ready != null and int(ready) <= now_ms else STATE_GROWING
	return STATE_WILD

## 湿土会随生长慢慢干回去：浇水那一刻最深，成熟时基本干透。
static func _moisture_of(slot: Dictionary, now_ms: int) -> int:
	var watered = slot.get("watered_at")
	var ready = slot.get("ready_at")
	if watered == null: return 0
	if ready == null: return 255
	var span := int(ready) - int(watered)
	if span <= 0: return 0
	var progress := clampf(float(now_ms - int(watered)) / float(span), 0.0, 1.0)
	return int((1.0 - progress) * 255.0)

func _write(cell: Vector2i, state: int, moisture: int) -> void:
	var current := _image.get_pixelv(cell)
	var kind := int(current.r8)
	if int(current.g8) == state and int(current.b8) == moisture: return
	_image.set_pixelv(cell, Color8(kind, state, moisture, current.a8))
	_dirty = true

func _write_alpha(cell: Vector2i, value: int) -> void:
	if not bp.in_bounds(cell): return
	var current := _image.get_pixelv(cell)
	if int(current.a8) == value: return
	_image.set_pixelv(cell, Color8(current.r8, current.g8, current.b8, value))
	_dirty = true

func _flush() -> void:
	if not _dirty: return
	_texture.update(_image)
	_dirty = false

static func _parse(id: String) -> Vector2i:
	var parts := id.split(",")
	if parts.size() != 2: return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))
