extends Node3D
## G2 PoC：相机同步——角色钉在地理锚点上，随地图 pan/zoom/rotate/pitch 一起动。
##
## 协议（方案 spec §5.3）：单一权威位姿在 Godot。
##   手势 → 更新 (center, zoom, bearing, pitch) → 同帧：
##     a) 经 JNI 桥 map.setCamera(...) 喂给 Mapbox（jumpTo，无动画）
##     b) 用同一份位姿推导 Godot Camera3D（同 fov、同注视点、同方位/俯仰）
##   两个渲染器消费同一份数值，不存在"谁追谁"。
##
## 坐标系：世界原点 = 角色地理锚点；x=东、-z=北，单位米（等距近似，城市尺度够用；
## 浮动原点重锚是 G2 遗留项）。拖拽用相机→地面平面的射线反投影，倾角下依然精确。

const TOKEN_PATH := "res://mapbox_token.txt"
const START_LAT := 31.2304 # 上海人民广场附近 = 角色锚点
const START_LNG := 121.4737

const EARTH_CIRCUM := 40075016.686
const M_PER_DEG_LAT := 111319.4908 # 2πR/360
## Mapbox 相机族默认竖向 FOV ≈ 0.6435 rad（GL JS 实measured 36.87°）。
## 若真机观察到 pitch/zoom 变化时角色相对地图滑动，此值是第一校准项
## （终极手段：挂 no-op custom layer dump projectionMatrix 逐元素校准）。
const MAP_FOV_DEG := 36.87
## 角色屏幕等大系数：scale = 相机距离 / 此值。越小角色越大（产品口径 G5 定）。
const CHAR_DIST_PER_SCALE := 10.0

@onready var status: Label = $HUD/Margin/VBox/Status
@onready var rigs: Node3D = $Rigs
@onready var cam: Camera3D = $Camera3D

var map: Object = null
var center_world := Vector3.ZERO # 地图中心（相机注视点）的本地米制坐标
var zoom := 16.0
var bearing := 0.0
var pitch := 45.0
var pixel_ratio := 1.0
var _touch_count := 0
var _camera_dirty := true

func _ready() -> void:
	get_viewport().transparent_bg = true
	$Sun.rotation_degrees = Vector3(-55, 30, 0)
	_spawn_character()
	_wire_buttons()

	if Engine.has_singleton("GodotMap"):
		map = Engine.get_singleton("GodotMap")
		map.connect("map_ready", _on_map_ready)
		pixel_ratio = maxf(float(map.getPixelRatio()), 0.5)
		var token := _load_token()
		if token.is_empty():
			status.text = "G2: 缺 res://mapbox_token.txt（构建机放置，勿提交）"
		else:
			map.createMap(token, START_LAT, START_LNG, zoom)
			status.text = "G2: createMap 已调用，等待 map_ready…"
	else:
		status.text = "G2: 无 GodotMap 插件（桌面运行仅能看透明视口与角色）"
	_camera_dirty = true

func _process(_dt: float) -> void:
	if _camera_dirty:
		_camera_dirty = false
		_update_cameras()
	# 漂移自检：对照我方权威位姿与地图实际相机（每 30 帧刷一次 HUD）
	if map != null and Engine.get_process_frames() % 30 == 0:
		var geo := _world_to_geo(center_world)
		var info: String = map.getCameraInfo()
		status.text = "G2 权威: %.5f,%.5f z%.2f b%.0f p%.0f\n地图回读: %s" % [
			geo.x, geo.y, zoom, bearing, pitch, info]

## —— 相机同步核心 ————————————————————————————————————————————

func _world_to_geo(w: Vector3) -> Vector2: # 返回 (lat, lng)
	var lat := START_LAT + (-w.z) / M_PER_DEG_LAT
	var lng := START_LNG + w.x / (M_PER_DEG_LAT * cos(deg_to_rad(START_LAT)))
	return Vector2(lat, lng)

## 地图逻辑像素（512 瓦片 × pixelRatio 密度）下，屏幕中心处每逻辑像素的地面米数。
func _meters_per_logical_px(lat: float) -> float:
	return EARTH_CIRCUM * cos(deg_to_rad(lat)) / (512.0 * pow(2.0, zoom))

## Mapbox 相机到注视点的距离（米）：d_px = (H/2)/tan(fov/2)，再乘地面分辨率。
func _cam_distance_m(lat: float) -> float:
	var h_logical := float(DisplayServer.window_get_size().y) / pixel_ratio
	return (h_logical * 0.5) / tan(deg_to_rad(MAP_FOV_DEG * 0.5)) \
			* _meters_per_logical_px(lat)

func _update_cameras() -> void:
	var geo := _world_to_geo(center_world)
	# 下限守卫：headless/未就绪时窗口尺寸可能为 0，避免 look_at 退化
	var d := maxf(_cam_distance_m(geo.x), 1.0)
	var beta := deg_to_rad(bearing)
	var phi := deg_to_rad(pitch)
	# 罗盘 bearing 对应的世界水平方向（北 = -z，东 = +x）
	var heading := Vector3(sin(beta), 0.0, -cos(beta))
	# 相机在注视点"身后"（heading 反方向）仰起 pitch
	cam.position = center_world - heading * (d * sin(phi)) + Vector3(0, d * cos(phi), 0)
	cam.look_at(center_world, heading) # up 提示用 heading，pitch=0 也不退化
	cam.fov = MAP_FOV_DEG
	cam.near = maxf(d / 1000.0, 0.05)
	cam.far = d * 8.0
	# 角色屏幕等大：随相机距离等比缩放（原点在脚底，放大不离地）
	rigs.scale = Vector3.ONE * maxf(d / CHAR_DIST_PER_SCALE, 0.001)
	# 同一份位姿喂给地图（单一权威）
	if map:
		map.setCamera(geo.x, geo.y, zoom, bearing, pitch)

## 相机射线与地面平面（y=0）的交点；近地平线的极远命中丢弃。
func _ground_point(screen_pos: Vector2) -> Variant:
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(
		cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	if hit == null:
		return null
	var d := _cam_distance_m(_world_to_geo(center_world).x)
	if (hit as Vector3).distance_to(cam.position) > d * 20.0:
		return null
	return hit

## —— 输入与 UI ————————————————————————————————————————————————

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_touch_count += 1 if e.pressed else -1
		_touch_count = maxi(_touch_count, 0)
	if e is InputEventScreenDrag and _touch_count <= 1:
		# 抓地拖拽：让按下时的地面点始终跟在手指下（倾角下精确）
		var prev = _ground_point(e.position - e.relative)
		var now = _ground_point(e.position)
		if prev != null and now != null:
			center_world += (prev as Vector3) - (now as Vector3)
			_camera_dirty = true
	elif e is InputEventMagnifyGesture:
		_set_zoom(zoom + log(e.factor) / log(2.0))
	elif e is InputEventPanGesture:
		_set_pitch(pitch - e.delta.y * 0.2)

func _wire_buttons() -> void:
	$HUD/Margin/VBox/Row1/ZoomIn.pressed.connect(func(): _set_zoom(zoom + 1.0))
	$HUD/Margin/VBox/Row1/ZoomOut.pressed.connect(func(): _set_zoom(zoom - 1.0))
	$HUD/Margin/VBox/Row1/PitchUp.pressed.connect(func(): _set_pitch(pitch + 15.0))
	$HUD/Margin/VBox/Row1/PitchDown.pressed.connect(func(): _set_pitch(pitch - 15.0))
	$HUD/Margin/VBox/Row2/Rotate.pressed.connect(func(): _set_bearing(bearing + 30.0))
	$HUD/Margin/VBox/Row2/ToDressing.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/dressing_room/dressing_room.tscn"))

func _set_zoom(v: float) -> void:
	zoom = clampf(v, 3.0, 20.0)
	_camera_dirty = true

func _set_pitch(v: float) -> void:
	pitch = clampf(v, 0.0, 70.0)
	_camera_dirty = true

func _set_bearing(v: float) -> void:
	bearing = fmod(v + 360.0, 360.0)
	_camera_dirty = true

## —— 初始化 ————————————————————————————————————————————————————

func _on_map_ready() -> void:
	status.text = "G2: map_ready ✅"
	_camera_dirty = true

func _load_token() -> String:
	if not FileAccess.file_exists(TOKEN_PATH):
		return ""
	var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""

func _spawn_character() -> void:
	var rig := Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	rigs.add_child(rig)
	rig.apply_config(Avatar.slot_table.default_config())
	rig.config_applied.connect(func(_c):
		var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap:
			ap.play("idle"))
