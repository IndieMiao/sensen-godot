class_name PartThumbnailer
extends Node
## 运行时离屏渲染部件缩略图，按 part_id 缓存。
##
## 为什么不用 assets/avatar/thumbs/ 里的图：那 25 张是同一张 64×64 / 168 字节的
## 占位图（管线缺口，tools/pipeline/extract_parts.gd 的 _write_thumb 对所有部件都
## 没解析到真实贴图），信息量为零。等管线补齐要排期，而"不试穿就知道长什么样"
## 是换装页最缺的一环，所以在客户端自己渲。
##
## 材质不用额外处理：管线在 extract_parts 阶段就把 AvatarMaterialFactory 造好的
## 材质烘进了 .res（assembler_merged 也是直接读 mesh.surface_get_material），
## 所以单独实例化一个部件就带着正确外观。
##
## 光照刻意与换装房一致（环境光显式取色 0.3 白 + 平行光 1.0 + filmic 色调映射）：
## 缩略图和穿在身上的样子若打光不同，颜色对不上就失去了参考意义。见交接文档 §2.7。

## 渲染分辨率。显示时由主题的 icon_max_width 收到约 52 单位，留足超采样余量。
const RENDER_SIZE := 160
## 包围盒四周留白系数。
const FRAME_PADDING := 1.18
## 相机竖直视角；比换装房的 35 更窄，单个部件的透视更平。
const FOV_DEG := 28.0

var catalog: PartCatalog

var _viewport: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _cache: Dictionary = {}
## 单个 SubViewport 串行复用；并发请求排队，避免两个部件同时挂在台上。
var _busy := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_viewport.transparent_bg = true
	# 必须自带 World3D：否则会把宿主场景（角色、背板、地图）一起拍进来。
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	light.light_energy = 1.0
	_viewport.add_child(light)

	_cam = Camera3D.new()
	_cam.fov = FOV_DEG
	_viewport.add_child(_cam)

	_stage = Node3D.new()
	_viewport.add_child(_stage)


## 取 part_id 的缩略图；首次调用会渲一帧，之后走缓存。
## 渲染失败（部件缺失/无可见几何）返回 null，调用方应保留纯文案回退。
func thumbnail(part_id: String) -> Texture2D:
	if part_id.is_empty():
		return null
	if _cache.has(part_id):
		return _cache[part_id]
	while _busy:
		await get_tree().process_frame
		if not is_inside_tree():
			return null
		if _cache.has(part_id):
			return _cache[part_id]
	_busy = true
	var tex := await _render(part_id)
	_busy = false
	# 失败也记进缓存：否则每次切回这个分类都会重试一遍必然失败的渲染。
	_cache[part_id] = tex
	return tex


func _render(part_id: String) -> Texture2D:
	var meta = catalog.part(part_id) if catalog else null
	if meta == null:
		return null
	var def := load(meta.res_path) as AvatarPartDef
	if def == null:
		return null
	var node := _build(def)
	if node == null:
		return null
	_stage.add_child(node)
	# 等一帧让实例的变换与骨骼绑定落地，否则包围盒可能还是退化的。
	await get_tree().process_frame
	var texture: Texture2D = null
	if is_inside_tree():
		var box := DressingCamera.merged_aabb(_stage)
		if box.size.length() > 0.0:
			_aim_at(box)
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var image := _viewport.get_texture().get_image()
			if image != null and image.get_width() > 0:
				texture = ImageTexture.create_from_image(image)
	# 用 free() 而不是 queue_free()：渲染已经落帧，这里立刻回收是安全的，
	# 而延迟回收会在测试用例结束时被 gdUnit 记成 orphan node（跑测直接非零退出）。
	_stage.remove_child(node)
	node.free()
	return texture


## socket 类部件是 PackedScene（含 manifest 里的偏移），mesh 类是裸 Mesh。
## mesh 类带蒙皮但这里没有 Skeleton3D，会以绑定姿势渲出来——做缩略图足够。
func _build(def: AvatarPartDef) -> Node3D:
	if def.attach == "socket":
		if def.scene == null:
			return null
		var inst := def.scene.instantiate() as Node3D
		if inst == null:
			return null
		inst.position = def.offset_pos
		inst.rotation_degrees = def.offset_rot_deg
		inst.scale = def.offset_scale
		return inst
	if def.mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = def.mesh
	return mi


## 正面平视取景。角色零旋转时面朝 +Z（与换装房相机同侧），所以相机放在 +Z。
func _aim_at(box: AABB) -> void:
	var center := box.position + box.size * 0.5
	var half_tan := tan(deg_to_rad(FOV_DEG) * 0.5)
	if half_tan <= 0.0:
		return
	# 视口是正方形，取长边当约束，宽高都不会被裁。
	var radius := maxf(box.size.x, box.size.y) * 0.5 * FRAME_PADDING
	_cam.rotation = Vector3.ZERO
	_cam.position = Vector3(center.x, center.y, center.z + maxf(radius / half_tan, 0.05))
