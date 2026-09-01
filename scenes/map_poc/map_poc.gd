extends Node3D
## G2 PoC：相机同步 + 多角色地理锚定 + 距离剔除。
##
## 协议（方案 spec §5.3）：单一权威位姿在 Godot。
##   手势 → 更新 (center_world, zoom, bearing, pitch) → 同帧：
##     a) 经 JNI 桥 map.setCamera(...) 喂给 Mapbox（jumpTo，无动画）
##     b) 用同一份位姿推导 Godot Camera3D
##
## 世界系：原点 = 浮动锚点（初始为上海人民广场），x=东、-z=北、单位米（MapGeoMath）。
## 浮动原点：地图中心离原点超过 REANCHOR_DIST_M 就把锚点搬到当前中心并重算全部
## 角色坐标，保证相机附近永远是小坐标（float32 精度；洛杉矶离上海 1.1 万公里）。
## 剔除：距地图中心 > CULL_FACTOR×相机距离的角色整体隐藏；RigActivity 的
## REDUCED/SLEEP 阈值按相机距离缩放（默认 8m/16m 是换装房尺度，在地图尺度下
## 会把所有角色永久 SLEEP——本场景必须覆写）。

const TOKEN_PATH := "res://mapbox_token.txt"
const START_LAT := 31.2304 # 上海人民广场附近 = 自己的角色锚点
const START_LNG := 121.4737
const LA_LAT := 34.0522 # 洛杉矶市中心
const LA_LNG := -118.2437

## Mapbox 相机族默认竖向 FOV ≈ 0.6435 rad（36.87°）。真机若见 pitch/zoom 变化时
## 角色相对地图滑动，此值是第一校准项（终极手段：no-op custom layer dump projectionMatrix）。
const MAP_FOV_DEG := 36.87
## 角色屏幕等大系数：scale = 相机距离 / 此值。越小角色越大（产品口径 G5 定）。
## 2026-08-29 调整：16.7 ≈ 10/0.6，角色缩小到原来的 0.6 倍。
const CHAR_DIST_PER_SCALE := 16.7

const PAWNS_NEAR_COUNT := 12 # 初始地图中心（上海）周边随机角色数
const PAWNS_LA_COUNT := 10 # 洛杉矶随机角色数
const NEAR_SPREAD_M := 900.0 # 上海散布半径（米）
const LA_SPREAD_M := 3000.0
const CULL_FACTOR := 4.0 # 距地图中心 > 4×相机距离 → 隐藏
const REANCHOR_DIST_M := 3000.0 # 浮动原点重锚阈值
## 等首个定位的上限；超时就用 START_LAT/LNG 当 home，演示内容照常可见。
const HOME_TIMEOUT_S := 3.0

@onready var rigs: Node3D = $Rigs
@onready var cam: Camera3D = $Camera3D
@onready var chip: PanelContainer = $HUD/SafeArea/Root/Chip
@onready var chip_dot: Panel = $HUD/SafeArea/Root/Chip/VBox/TitleRow/Dot
@onready var chip_title: Label = $HUD/SafeArea/Root/Chip/VBox/TitleRow/Title
@onready var chip_sub: Label = $HUD/SafeArea/Root/Chip/VBox/Sub
@onready var chip_debug: Label = $HUD/SafeArea/Root/Chip/VBox/Debug
@onready var tilt_btn: Button = $HUD/SafeArea/Root/Stack/Tilt
@onready var fly_btn: Button = $HUD/SafeArea/Root/Bottom/Fly
@onready var load_bar: ProgressBar = $HUD/SafeArea/Root/Chip/VBox/LoadBar

const DOT_WAIT := Color(0.62, 0.65, 0.68) # 连接中：灰
const DOT_OK := Color(0.31, 0.72, 0.58) # 同步中：薄荷绿（角色短裤色系）
const DOT_ERR := Color(0.9, 0.36, 0.34) # 出错：红

var map: MapBridge = null
var anchor_lat := START_LAT # 浮动锚点（世界原点的地理坐标）
var anchor_lng := START_LNG
## 权威地图中心用 f64 标量端到端保存（GDScript 变量是双精度）。
## 不得经 Vector2/Vector3 往返：float32 在经度 121° 只有 ~7.6e-6°≈0.7m 分辨率，
## z18+（0.03m/px）会造成角色-地图 10~20px 的静态偏差。
var center_lat := START_LAT
var center_lng := START_LNG
var center_world := Vector3.ZERO # 渲染派生量：中心的本地米制坐标（每次相机更新重算）
var zoom := 16.0
var bearing := 0.0
var pitch := 45.0
var pixel_ratio := 1.0
var _touch_count := 0
var _camera_dirty := true
var _in_la := false
var _rng := RandomNumberGenerator.new()
## 每项：{lat, lng, node: holder Node3D, activity: RigActivity}
## holder 包一层的原因：AvatarRig 装配完成时会无条件把自身 visible=true，
## 与剔除写的 visible 打架——所有权分离后本场景只碰 holder。
var _pawns: Array[Dictionary] = []
## 分帧装配队列：23 个蒙皮 rig 同帧 apply_config 会把装配风暴挤进一两帧
## （缓存全命中时 call_deferred 保证同帧 23 次全量网格合并），每帧只放行 2 个。
var _spawn_queue: Array[Dictionary] = []
var _dot_tween: Tween = null
## 错误态锁定芯片文案（缺 token 等），不再被周期刷新覆盖
var _chip_locked := false
## "我的位置"：定位成功则为真实位置，超时/无定位则回落 START_LAT/LNG。
## 自己、近处路人、全部 marker 都相对它摆放——绝不写死经纬度。
var home_lat := START_LAT
var home_lng := START_LNG
var _home_resolved := false
var marker_layer: MarkerLayer = null

func _ready() -> void:
	_rng.seed = 20260829 # 固定种子：装机验证时角色分布可复现
	get_viewport().transparent_bg = true
	$Sun.rotation_degrees = Vector3(-55, 30, 0)
	_spawn_la_fixture() # 压测夹具先排队；home 队列等定位确定后再插
	_wire_buttons()

	# marker 层：铺满 HUD 且排在最底，别挡住芯片和按钮。
	# 自身 MOUSE_FILTER_IGNORE 只是让层本身不吞事件，图钉 Button 仍然可点。
	marker_layer = MarkerLayer.new()
	marker_layer.name = "Markers"
	marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(marker_layer)
	$HUD.move_child(marker_layer, 0)

	# 窗口尺寸变化（旋屏/分屏/折叠屏）会改变两层的像素↔米换算基准，必须重推相机
	get_viewport().size_changed.connect(func(): _camera_dirty = true)

	map = _make_bridge()
	if map:
		map.map_ready.connect(_on_map_ready)
		map.location_update.connect(_on_location_update)
		map.set_map_visible(true)
		pixel_ratio = map.get_pixel_ratio()
		var token := _load_token()
		if token.is_empty():
			_set_dot(DOT_ERR, false)
			chip_title.text = "缺少地图密钥"
			chip_sub.text = "在工程根放置 mapbox_token.txt 后重新构建"
			_chip_locked = true
		else:
			map.create_map(token, START_LAT, START_LNG, zoom)
			_set_dot(DOT_WAIT, true) # 连接中：呼吸闪烁
		map.start_location()
	else:
		_set_dot(DOT_WAIT, false)
		chip_title.text = "地图预览"
		chip_sub.text = "桌面运行，无地图插件"
		_chip_locked = true
	# 定位兜底：拒绝授权 / 定位慢 / 桌面无插件，3 秒后一律回落上海默认点。
	# 没有这条，_spawn_home_cohort 永远不会被调用，地图上只剩洛杉矶夹具。
	get_tree().create_timer(HOME_TIMEOUT_S).timeout.connect(
		func(): _resolve_home(START_LAT, START_LNG))
	_camera_dirty = true

## 平台桥工厂（避免 MapBridge 基类反向引用子类的脚本环）
func _make_bridge() -> MapBridge:
	if Engine.has_singleton("GodotMap"):
		return MapBridgeAndroid.new()
	if OS.get_name() == "iOS":
		return MapBridgeIOS.new()
	return null

func _exit_tree() -> void:
	# 场景切走的清理：transparent_bg 是根视口全局态，不还原会把换装房的
	# Environment 背景干掉、地图从底下透上来；地图本体也要停渲染省电。
	get_viewport().transparent_bg = false
	if map:
		map.set_map_visible(false)

func _process(_dt: float) -> void:
	if map:
		map.poll()
	if not _spawn_queue.is_empty():
		# 每帧 1 个：装配（部件加载+网格合并）摊薄到 ~23 帧，压掉加载期卡顿
		var spec: Dictionary = _spawn_queue.pop_front()
		_add_pawn(spec.lat, spec.lng, spec.cfg, spec.anim)
	if _camera_dirty:
		_camera_dirty = false
		_update_cameras()
	_update_load_bar()
	if Engine.get_process_frames() % 30 == 0:
		_refresh_chip()

func _refresh_chip() -> void:
	if _chip_locked:
		return
	chip_title.text = "洛杉矶" if _in_la else "我的位置"
	chip_sub.text = "%.4f, %.4f  ·  z%.1f" % [center_lat, center_lng, zoom]
	if chip_debug.visible:
		var vis := 0
		for p in _pawns:
			if (p.node as Node3D).visible:
				vis += 1
		var info := map.camera_info() if map else ""
		chip_debug.text = "同步 b%.0f° p%.0f°  ·  角色 %d/%d\n回读 %s" % [
			bearing, pitch, vis, _pawns.size(), info if not info.is_empty() else "—"]

## —— 相机同步核心 ————————————————————————————————————————————

func _cam_distance() -> float:
	var h_logical := float(DisplayServer.window_get_size().y) / pixel_ratio
	# 下限守卫：headless/未就绪时窗口尺寸可能为 0，避免 look_at 退化
	return maxf(MapGeoMath.cam_distance_m(h_logical, MAP_FOV_DEG, center_lat, zoom), 1.0)

## 世界位移（米，来自拖拽）累加进 f64 权威中心。cos 用 anchor_lat 与
## geo_to_world 保持严格互逆（重锚半径内两者差异可忽略）。
## 纬度钳在 Web Mercator 边界：低 zoom 一屏拖拽可跨 50°，不钳会拖过极点——
## cos 变负导致东西镜像、Mapbox 端 LatLng 越 ±90 直接抛异常、权威值与地图分叉。
func _apply_world_delta(delta: Vector3) -> void:
	center_lat = clampf(
		center_lat + (-delta.z) / MapGeoMath.M_PER_DEG_LAT, -85.051129, 85.051129)
	center_lng += delta.x / (MapGeoMath.M_PER_DEG_LAT * cos(deg_to_rad(anchor_lat)))
	center_lng = wrapf(center_lng, -180.0, 180.0)

func _update_cameras() -> void:
	center_world = MapGeoMath.geo_to_world(center_lat, center_lng, anchor_lat, anchor_lng)
	_maybe_reanchor()
	var d := _cam_distance()
	var beta := deg_to_rad(bearing)
	var phi := deg_to_rad(pitch)
	# 罗盘 bearing 对应的世界水平方向（北 = -z，东 = +x）
	var heading := Vector3(sin(beta), 0.0, -cos(beta))
	cam.position = center_world - heading * (d * sin(phi)) + Vector3(0, d * cos(phi), 0)
	cam.look_at(center_world, heading) # up 提示用 heading，pitch=0 也不退化
	cam.fov = MAP_FOV_DEG
	cam.near = maxf(d / 1000.0, 0.05)
	cam.far = d * 8.0
	_update_pawns(d)
	if marker_layer:
		marker_layer.sync(cam, anchor_lat, anchor_lng, d * CULL_FACTOR, center_world)
	# 同一份位姿喂给地图（单一权威）
	if map:
		map.set_camera(center_lat, center_lng, zoom, bearing, pitch)

## 浮动原点：地图中心跑远了就把锚点搬过来（f64 精确拷贝），所有几何重算。
func _maybe_reanchor() -> void:
	if center_world.length() < REANCHOR_DIST_M:
		return
	anchor_lat = center_lat
	anchor_lng = center_lng
	center_world = Vector3.ZERO
	_reposition_pawns()

func _update_pawns(d: float) -> void:
	var s := maxf(d / CHAR_DIST_PER_SCALE, 0.001)
	var cull_r := d * CULL_FACTOR
	for p in _pawns:
		var n := p.node as Node3D # holder：可见性/位置/缩放归本场景管
		var act := p.activity as RigActivity
		# ready 门禁：装配完成+首帧姿态应用前绝不显示——半成品蒙皮网格在地图
		# 缩放（~25×）下会渲染成通天拉伸毛刺（2026-08-29 真机截图实证）。
		var vis: bool = p.ready and n.position.distance_to(center_world) <= cull_r
		if n.visible != vis:
			n.visible = vis
			# 不等 RigActivity 的 0.25s 节流：隐藏立即停播，显形立即恢复
			if act:
				act.apply_level(RigActivity.Level.SLEEP if not vis else RigActivity.Level.ACTIVE)
		if not vis:
			continue
		n.scale = Vector3.ONE * s
		if act:
			# 阈值随相机距离缩放（RigActivity 默认 8/16m 是换装房尺度）。
			# SLEEP 界必须盖过剔除半径：剔除按"距中心≤4d"，而 RigActivity 按
			# "距相机"判——相机离中心 d，可见角色距相机最大 ~5d，故取 5.5d，
			# 保证屏内角色不会被距离档误打 SLEEP（高 pitch 远侧冻结 bug）。
			act.reduced_distance = d * 3.0
			act.sleep_distance = d * (CULL_FACTOR + 1.5)

func _reposition_pawns() -> void:
	for p in _pawns:
		(p.node as Node3D).position = MapGeoMath.geo_to_world(
			p.lat, p.lng, anchor_lat, anchor_lng)

## 相机射线与地面平面（y=0）的交点。近地平线的甩飞防护不在这里做——
## 在拖拽处对单次 delta 限幅（limit_length(d)），比丢弃命中点的手感更接近原生地图。
func _ground_point(screen_pos: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(
		cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))

## —— 输入与 UI ————————————————————————————————————————————————

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_touch_count += 1 if e.pressed else -1
		_touch_count = maxi(_touch_count, 0)
	if e is InputEventScreenDrag and _touch_count <= 1:
		# 抓地拖拽：让按下时的地面点始终跟在手指下（倾角下精确）。
		# 高 pitch 时屏幕上缘一像素对应的地面位移可达 ~0.4d，单次 delta 限幅到 d
		# 防止一次拖拽把地图甩出上百公里。
		var prev = _ground_point(e.position - e.relative)
		var now = _ground_point(e.position)
		if prev != null and now != null:
			var delta := (prev as Vector3) - (now as Vector3)
			_apply_world_delta(delta.limit_length(_cam_distance()))
			_camera_dirty = true
	elif e is InputEventMagnifyGesture:
		_set_zoom(zoom + log(e.factor) / log(2.0))
	elif e is InputEventPanGesture:
		_set_pitch(pitch - e.delta.y * 0.2)

func _wire_buttons() -> void:
	$HUD/SafeArea/Root/Stack/ZoomIn.pressed.connect(func(): _set_zoom(zoom + 1.0))
	$HUD/SafeArea/Root/Stack/ZoomOut.pressed.connect(func(): _set_zoom(zoom - 1.0))
	tilt_btn.pressed.connect(_on_tilt_pressed)
	$HUD/SafeArea/Root/Stack/Rotate.pressed.connect(func(): _set_bearing(bearing + 30.0))
	fly_btn.pressed.connect(_on_fly_pressed)
	$HUD/SafeArea/Root/Bottom/Dress.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/dressing_room/dressing_room.tscn"))
	# 点定位芯片展开/收起工程数据（触屏经 emulate_mouse 到达，只接鼠标事件防双触发）
	chip.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			chip_debug.visible = not chip_debug.visible
			_refresh_chip())

## 倾角在 2D 俯视与 3D 斜视之间切换；按钮文案显示"将要切去的模式"
func _on_tilt_pressed() -> void:
	_set_pitch(45.0 if pitch < 10.0 else 0.0)

func _update_tilt_label() -> void:
	tilt_btn.text = "2D" if pitch >= 10.0 else "3D"

func _on_fly_pressed() -> void:
	_in_la = not _in_la
	fly_btn.text = "回我的位置" if _in_la else "飞洛杉矶"
	_teleport(LA_LAT, LA_LNG) if _in_la else _teleport(home_lat, home_lng)

func _teleport(lat: float, lng: float) -> void:
	anchor_lat = lat
	anchor_lng = lng
	center_lat = lat
	center_lng = lng
	center_world = Vector3.ZERO
	_reposition_pawns()
	_camera_dirty = true

func _set_zoom(v: float) -> void:
	zoom = clampf(v, 3.0, 20.0)
	_camera_dirty = true

func _set_pitch(v: float) -> void:
	pitch = clampf(v, 0.0, 70.0)
	_update_tilt_label()
	_camera_dirty = true

func _set_bearing(v: float) -> void:
	bearing = fmod(v + 360.0, 360.0)
	_camera_dirty = true

## —— 初始化 ————————————————————————————————————————————————————

func _on_map_ready() -> void:
	_set_dot(DOT_OK, false) # 同步中：常亮薄荷绿
	if map:
		pixel_ratio = map.get_pixel_ratio() # iOS 桥的真实 scale 随 READY 到达
	_camera_dirty = true

## 芯片状态圆点：颜色 + 是否呼吸闪烁（连接中）
func _set_dot(color: Color, pulse: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	chip_dot.add_theme_stylebox_override("panel", sb)
	if _dot_tween:
		_dot_tween.kill()
		_dot_tween = null
	chip_dot.modulate.a = 1.0
	if pulse:
		_dot_tween = create_tween().set_loops()
		_dot_tween.tween_property(chip_dot, "modulate:a", 0.3, 0.7)
		_dot_tween.tween_property(chip_dot, "modulate:a", 1.0, 0.7)

func _load_token() -> String:
	if not FileAccess.file_exists(TOKEN_PATH):
		return ""
	var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""

## 自己的角色装扮：读换装房存档。Avatar.load_outfit()（avatar_service.gd:33-35）
## 内部已在无存档时回落 slot_table.default_config()，此处不需要再守卫 null。
func self_config() -> AvatarConfig:
	return Avatar.load_outfit()

## 自己 + 近处路人，全部相对 home 摆放。绝不写死经纬度：写死的话定位到任何
## 非上海的位置，这些角色都会落在 CULL_FACTOR×相机距离之外被剔除，地图空无一人。
func _spawn_home_cohort() -> void:
	# push_front：自己排队头，第一个出队，玩家最先看到自己
	_spawn_queue.push_front({"lat": home_lat, "lng": home_lng,
		"cfg": self_config(), "anim": "idle", "cohort": "self"})
	for i in PAWNS_NEAR_COUNT:
		var off := _rand_offset_deg(NEAR_SPREAD_M, home_lat)
		_spawn_queue.append({"lat": home_lat + off.y, "lng": home_lng + off.x,
			"cfg": _random_config(), "anim": _rand_anim(), "cohort": "near"})

## 洛杉矶夹具：验证跨洋剔除 + 浮动原点重锚，不是演示内容，坐标保持绝对，
## 不跟随定位——改成相对就失去了这个夹具的意义。
func _spawn_la_fixture() -> void:
	for i in PAWNS_LA_COUNT:
		var off := _rand_offset_deg(LA_SPREAD_M, LA_LAT)
		_spawn_queue.append({"lat": LA_LAT + off.y, "lng": LA_LNG + off.x,
			"cfg": _random_config(), "anim": _rand_anim(), "cohort": "la"})

## 确定"我的位置"并把演示内容锚上去。首个有效定位与 3 秒超时先到者生效；
## 之后的定位更新不再改锚点（避免演示中途所有内容整体位移）。
func _resolve_home(lat: float, lng: float) -> void:
	if _home_resolved:
		return
	_home_resolved = true
	home_lat = lat
	home_lng = lng
	_teleport(lat, lng)
	_spawn_home_cohort()
	if marker_layer:
		marker_layer.set_home(lat, lng)

func _on_location_update(lat: float, lng: float, _accuracy: float) -> void:
	_resolve_home(lat, lng)

func _add_pawn(lat: float, lng: float, cfg: AvatarConfig, anim: String) -> void:
	var holder := Node3D.new()
	holder.visible = false # ready 门禁：config_applied + 首帧姿态之前不显示
	rigs.add_child(holder)
	holder.position = MapGeoMath.geo_to_world(lat, lng, anchor_lat, anchor_lng)
	# 默认朝南（世界系 +z；rig 零旋转即面向 bearing=0 时位于南侧的相机，
	# G1 真机截图已证实）。若换模型后前向翻转，只需在此处统一加 PI。
	var rig := Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	holder.add_child(rig)
	var activity: RigActivity = null
	for c in rig.get_children():
		if c is RigActivity:
			activity = c
			break
	var pawn := {"lat": lat, "lng": lng, "node": holder, "activity": activity, "ready": false}
	rig.config_applied.connect(func(_c):
		var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap:
			ap.play(anim)
			ap.advance(0.0) # 强制立刻应用首帧骨骼姿态，杜绝未蒙皮帧被渲染
		pawn.ready = true
		_camera_dirty = true) # 下一帧重跑剔除，按当前相机决定是否显示
	rig.apply_config(cfg)
	_pawns.append(pawn)
	_camera_dirty = true

func _update_load_bar() -> void:
	if not load_bar.visible:
		return
	var total := 1 + PAWNS_NEAR_COUNT + PAWNS_LA_COUNT
	var ready := 0
	for p in _pawns:
		if p.ready:
			ready += 1
	load_bar.max_value = total
	load_bar.value = ready
	if ready >= total and _spawn_queue.is_empty():
		load_bar.visible = false

func _rand_anim() -> String:
	return "idle" if _rng.randf() > 0.4 else "walk"

## 以 spread_m 为半径的随机散布，返回 (dlng, dlat) 度偏移。
func _rand_offset_deg(spread_m: float, lat: float) -> Vector2:
	var r := _rng.randf_range(spread_m * 0.15, spread_m)
	var th := _rng.randf_range(0.0, TAU)
	return Vector2(
		cos(th) * r / (MapGeoMath.M_PER_DEG_LAT * cos(deg_to_rad(lat))),
		sin(th) * r / MapGeoMath.M_PER_DEG_LAT)

func _random_config() -> AvatarConfig:
	var cfg := Avatar.slot_table.default_config()
	for slot_def in Avatar.slot_table.slots:
		var pool := Avatar.catalog.parts_for_slot(slot_def.slot_name)
		if pool.is_empty():
			continue
		if slot_def.required or _rng.randf() > 0.5:
			cfg.slots[slot_def.slot_name] = pool[_rng.randi_range(0, pool.size() - 1)].id
	return cfg
