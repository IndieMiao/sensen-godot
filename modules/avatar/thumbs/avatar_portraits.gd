class_name AvatarPortraits
extends Node
## 全身形象的离屏「证件照」：给一份 AvatarConfig，渲一张正方形透明底小图，按配置内容缓存。
## 列表（会话 / 关注者 / feed 作者）与主页头像都从这里取——同一套装扮只渲一次。
##
## 与 PartThumbnailer 同一套光照与串行台面；区别是这里装的是整套 rig（要等异步装配收敛）。
## headless（跑测试）与渲染失败一律返回 null，调用方保留占位图标。

const RENDER_SIZE := 192
const FRAME_PADDING := 1.12
const FOV_DEG := 28.0
## 装配等待上限：部件资源缺失时 rig 会一直 busy，别把整张列表卡死。
const ASSEMBLE_TIMEOUT_S := 4.0
## 装配收敛后先渲几帧再取图；仍是空图就再多试几帧。
const WARMUP_FRAMES := 3
const RETRY_FRAMES := 6

var _dumped := 0

var _viewport: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _cache: Dictionary = {}
var _busy := false

## 挂在 Avatar 门面下的共享实例；测试里也能拿到（headless 直接给 null 纹理）。
static func shared() -> AvatarPortraits:
	var host: Node = Engine.get_main_loop().root.get_node_or_null("Avatar") if Engine.get_main_loop() is SceneTree else null
	if host == null:
		return null
	var existing := host.get_node_or_null("Portraits") as AvatarPortraits
	if existing != null:
		return existing
	var p := AvatarPortraits.new()
	p.name = "Portraits"
	host.add_child(p)
	return p

static func cache_key(config: AvatarConfig) -> String:
	return config.to_json_text() if config != null else ""

func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_viewport.transparent_bg = true
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
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	_viewport.add_child(light)
	_cam = Camera3D.new()
	_cam.fov = FOV_DEG
	_viewport.add_child(_cam)
	_stage = Node3D.new()
	_viewport.add_child(_stage)

func can_render() -> bool:
	return DisplayServer.get_name() != "headless" and is_inside_tree()

## 取这套装扮的头像；首次渲一帧，之后走缓存。失败返回 null 并记入缓存（不反复重试）。
func portrait(config: AvatarConfig) -> Texture2D:
	if config == null or not can_render():
		return null
	var key := cache_key(config)
	if _cache.has(key):
		return _cache[key]
	while _busy:
		await get_tree().process_frame
		if not is_inside_tree():
			return null
		if _cache.has(key):
			return _cache[key]
	_busy = true
	var tex := await _render(config)
	_busy = false
	_cache[key] = tex
	return tex

func _render(config: AvatarConfig) -> Texture2D:
	var avatar := get_parent()
	if avatar == null or not avatar.has_method("create_rig"):
		return null
	var rig: Node3D = avatar.create_rig()
	_stage.add_child(rig)
	rig.apply_config(config)
	var waited := 0.0
	while rig.is_busy() and waited < ASSEMBLE_TIMEOUT_S:
		var dt := get_tree().root.get_process_delta_time()
		waited += maxf(dt, 1.0 / 60.0)
		await get_tree().process_frame
		if not is_inside_tree():
			rig.free()
			return null
	await get_tree().process_frame
	var texture: Texture2D = null
	if is_inside_tree() and not rig.is_busy():
		rig.visible = true
		var box := DressingCamera.merged_aabb(_stage)
		if box.size.length() > 0.0:
			_aim_at(box)
			# 连续渲几帧再取：第一帧蒙皮 / 材质往往还没就位，抓到的是一张全透明图（桌面 QA 截图里
			# 头像位置就是空白）。取到有像素的图才算成功；被遮挡的窗口里 frame_post_draw 不来，
			# 所以用 force_draw 兜底而不是死等。
			_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			for attempt in WARMUP_FRAMES + RETRY_FRAMES:
				await get_tree().process_frame
				if not is_inside_tree():
					break
				if attempt < WARMUP_FRAMES - 1:
					continue
				RenderingServer.force_draw()
				var image := _viewport.get_texture().get_image()
				if image != null and image.get_used_rect().has_area():
					texture = ImageTexture.create_from_image(image)
					_dump(image)
					break
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_stage.remove_child(rig)
	rig.free()
	return texture

## SENSEN_PORTRAIT_DEBUG=1：把渲出来的图落到 user://qa/portrait_NN.png，排查取景 / 光照用。
func _dump(image: Image) -> void:
	if OS.get_environment("SENSEN_PORTRAIT_DEBUG") != "1":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://qa"))
	_dumped += 1
	image.save_png("user://qa/portrait_%02d.png" % _dumped)

## 正面平视的头肩特写：角色零旋转面朝 +Z。全身照缩到 40 px 只剩一根火柴人，
## 所以取包围盒顶部 HEAD_FRACTION 那一段（头 + 肩），T-pose 的手臂也正好裁掉。
const HEAD_FRACTION := 0.42
const HEAD_CENTER_FROM_TOP := 0.21

func _aim_at(box: AABB) -> void:
	var top := box.position.y + box.size.y
	var center := Vector3(box.get_center().x, top - box.size.y * HEAD_CENTER_FROM_TOP, box.get_center().z)
	var extent := box.size.y * HEAD_FRACTION * FRAME_PADDING
	var dist := (extent * 0.5) / tan(deg_to_rad(FOV_DEG) * 0.5) + box.size.z * 0.5
	_cam.position = center + Vector3(0.0, 0.0, dist)
	_cam.look_at(center, Vector3.UP)
