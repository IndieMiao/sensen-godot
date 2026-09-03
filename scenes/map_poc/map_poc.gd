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
const INITIAL_ROLE_COUNT := 1 + PAWNS_NEAR_COUNT + PAWNS_LA_COUNT
const LOAD_BAR_MIN_VISIBLE_MS := 1800
const NEAR_SPREAD_M := 900.0 # 上海散布半径（米）
const LA_SPREAD_M := 900.0 # 跨城首屏也应立即看到角色，而不是只有数量没有内容
const CULL_FACTOR := 4.0 # 距地图中心 > 4×相机距离 → 隐藏
const REANCHOR_DIST_M := 3000.0 # 浮动原点重锚阈值
## 等首个定位的上限；超时就用 START_LAT/LNG 当 home，演示内容照常可见。
const HOME_TIMEOUT_S := 3.0

## 抬手惯性：速度按 exp(-DECAY*dt) 衰减，低于 MIN_SPEED 停止。
## EMA 平滑掉单帧抖动，否则最后一帧的抖动会决定整段滑行方向。
const FLING_DECAY := 4.0
const FLING_MIN_SPEED := 0.5 # 米/秒
const FLING_EMA := 0.35
## 缩放轴惯性的停止门槛（zoom 单位/秒）。zoom 是对数刻度，0.05 已经几乎看不出变化。
const ZOOM_FLING_MIN := 0.05
## 双击：300ms 内两次落点相距不超过 32 单位
const DOUBLE_TAP_S := 0.3
const DOUBLE_TAP_MAX_PX := 32.0

@onready var rigs: Node3D = $Rigs
@onready var cam: Camera3D = $Camera3D
@onready var safe_area: SafeAreaMargin = $HUD/SafeArea
@onready var top_panel: PanelContainer = $HUD/SafeArea/Root/TopPanel
@onready var status_dot: Panel = $HUD/SafeArea/Root/TopPanel/VBox/StatusRow/Dot
@onready var region_title: Label = $HUD/SafeArea/Root/TopPanel/VBox/TitleRow/RegionTitle
@onready var nearby_count: Label = $HUD/SafeArea/Root/TopPanel/VBox/TitleRow/NearbyCount
@onready var location_status: Label = $HUD/SafeArea/Root/TopPanel/VBox/StatusRow/LocationStatus
@onready var load_bar: ProgressBar = $HUD/SafeArea/Root/TopPanel/VBox/LoadSlot/LoadBar
@onready var side_toolbar: PanelContainer = $HUD/SafeArea/Root/SideToolbar
@onready var view_mode_switch: Button = $HUD/SafeArea/Root/SideToolbar/VBox/ViewGroup/ViewModeSwitch
@onready var view_mode_label: Label = $HUD/SafeArea/Root/SideToolbar/VBox/ViewGroup/ViewLabel
@onready var travel_btn: Button = $HUD/SafeArea/Root/SideToolbar/VBox/TravelGroup/Travel
@onready var travel_label: Label = $HUD/SafeArea/Root/SideToolbar/VBox/TravelGroup/TravelLabel
@onready var edit_avatar_btn: Button = $HUD/SafeArea/Root/SideToolbar/VBox/EditGroup/EditAvatar

const DOT_WAIT := DesignTokens.INK_MUTED
const DOT_OK := DesignTokens.ACCENT_DEEP
const DOT_ERR := DesignTokens.DANGER

## 侧栏图标：白色描边 SVG，由主题的 icon_*_color 调制成墨色/主色。
## 两个双态按钮各备一对，图标与文案一起换，状态不靠单一线索表达。
const ICON_VIEW_3D := preload("res://assets/ui/icons/view_3d.svg")
const ICON_VIEW_2D := preload("res://assets/ui/icons/view_2d.svg")
const ICON_TRAVEL := preload("res://assets/ui/icons/travel.svg")
const ICON_PIN := preload("res://assets/ui/icons/pin.svg")

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
## 罗盘方向。2026-09-02 移除侧栏 Rotate 按钮后**没有任何入口会改它**，恒为 0（正北朝上）。
## 但它仍是相机协议（spec §5.3）的一部分：要参与 Godot 相机推导，也要随 set_camera
## 一起喂给 Mapbox，别因为"看起来是常量"就把它优化掉。要恢复旋转就加回一个 setter。
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
## 错误态锁定顶部状态文案（缺 token 等），不再被周期刷新覆盖。
var _header_locked := false
## home：定位成功则为真实位置，超时/无定位则回落 START_LAT/LNG。
## 自己、近处路人、全部 marker 都相对它摆放——绝不写死经纬度。
var home_lat := START_LAT
var home_lng := START_LNG
var _home_resolved := false
## 当前 home 是否来自超时回落（而非真实定位）。为真时允许下一手真实定位
## 纠正一次——纠正用掉之后立即置回 false，之后的定位更新一律忽略，与
## Android 侧 GodotMapPlugin.LAST_KNOWN_MAX_AGE_MS（5 分钟内的缓存才当作
## "当前位置"发出）保持同一个口径："只信一次，信完就不再变"。
var _home_from_fallback := false
var marker_layer: MarkerLayer = null
var _fling_vel := Vector3.ZERO
var _last_tap_ms := 0
var _last_tap_pos := Vector2.ZERO
var _zoom_tween: Tween = null
var _drag_accum_px := 0.0 # 当前手势累计拖拽位移，超过双击半径就作废 _last_tap_ms
## 本次手势里 _fling_vel 达到过的峰值（米/秒），按下时归零。
## 调试芯片读它：芯片每 30 帧才刷一次，抓不到瞬时值。用途是判断惯性"没触发"
## 还是"触发了但速度太小"——单帧多次 ScreenDrag 采样都除以整帧 dt 会系统性低估。
var _fling_peak := 0.0
## 缩放轴惯性速度（zoom 单位/秒），与 _fling_vel 是同一套语义、不同轴。
var _zoom_vel := 0.0
## 本次手势是否曾经有过 2 指以上。捏合抬手是一根一根抬的：第一根离开后
## _touch_count 掉回 1，剩下那根往往还在动，它的 drag 事件就会通过
## "_touch_count <= 1" 门禁把 pan 速度灌进 _fling_vel，抬手甩出一段意外平移。
## 所以一旦升级成多指，本次手势剩余时间一律不再喂 pan 速度，直到所有手指离开。
var _gesture_multi := false
var _load_bar_started_ms := 0
var _map_is_ready := false
## 受限模式（PRD §3.1）：由 FarmRegions 的城市选择触发；为真时地图只做「看见、选择、返回」。
var street_mode := false
var region: Dictionary = {}
## 平移边界（lat/lng）：position=(lat_min,lng_min)，size=(lat span,lng span)；零 size 不钳。
var pan_bounds := Rect2()
var candidate_overlay: CandidateOverlay = null
var select_panel: SelectPanel = null
var _candidate_bps: Dictionary = {} # layout_patch_id -> FarmBlueprint

func _ready() -> void:
	_load_bar_started_ms = Time.get_ticks_msec()
	_rng.seed = 20260829 # 固定种子：装机验证时角色分布可复现
	get_viewport().transparent_bg = true
	$Sun.rotation_degrees = Vector3(-55, 30, 0)
	var choice := FarmRegions.load_choice()
	var regions := FarmRegions.load_default()
	if regions != null and not choice.is_empty() and not regions.region(choice).is_empty():
		enter_street_mode(regions.region(choice))
	if not street_mode:
		_spawn_la_fixture() # 压测夹具先排队；home 队列等定位确定后再插
	_wire_buttons()

	# marker 层：铺满 HUD 且排在最底，别挡住芯片和按钮。
	# 自身 MOUSE_FILTER_IGNORE 只是让层本身不吞事件，图钉 Button 仍然可点。
	marker_layer = MarkerLayer.new()
	marker_layer.name = "Markers"
	marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_layer.z_index = -10
	$HUD.add_child(marker_layer)
	$HUD.move_child(marker_layer, 0)
	marker_layer.visible = not street_mode
	_sync_marker_margins()
	safe_area.margins_applied.connect(func(_m): call_deferred("_sync_marker_margins"))

	# 窗口尺寸变化（旋屏/分屏/折叠屏）会改变两层的像素↔米换算基准，必须重推相机
	get_viewport().size_changed.connect(func():
		_camera_dirty = true
		call_deferred("_sync_marker_margins"))
	call_deferred("_sync_marker_margins")

	map = _make_bridge()
	if map:
		map.map_ready.connect(_on_map_ready)
		map.location_update.connect(_on_location_update)
		map.set_map_visible(true)
		pixel_ratio = map.get_pixel_ratio()
		var token := _load_token()
		if token.is_empty():
			_map_is_ready = true
			_set_dot(DOT_ERR, false)
			region_title.text = "Map unavailable"
			location_status.text = "Check your connection"
			_header_locked = true
		else:
			var lat0 := float(region.center[0]) if street_mode else START_LAT
			var lng0 := float(region.center[1]) if street_mode else START_LNG
			map.create_map(token, lat0, lng0, zoom)
			_set_dot(DOT_WAIT, true) # 连接中：呼吸闪烁
		if not street_mode:
			map.start_location()
	else:
		_map_is_ready = true
		_set_dot(DOT_WAIT, false)
		region_title.text = "Map preview"
		location_status.text = "Location unavailable"
		_header_locked = true
	# 定位兜底：拒绝授权 / 定位慢 / 桌面无插件，3 秒后一律回落上海默认点。
	# 没有这条，_spawn_home_cohort 永远不会被调用，地图上只剩洛杉矶夹具。
	get_tree().create_timer(HOME_TIMEOUT_S).timeout.connect(
		func(): _resolve_home(START_LAT, START_LNG, true))
	if street_mode:
		_resolve_home(float(region.center[0]), float(region.center[1]), false)
		load_candidates(region)
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
	_step_fling(_dt)
	if not _spawn_queue.is_empty():
		# 每帧 1 个：装配（部件加载+网格合并）摊薄到 ~23 帧，压掉加载期卡顿
		var spec: Dictionary = _spawn_queue.pop_front()
		_add_pawn(spec.lat, spec.lng, spec.cfg, spec.anim, spec.cohort)
	if _camera_dirty:
		_camera_dirty = false
		_update_cameras()
	_update_load_bar()
	if Engine.get_process_frames() % 30 == 0:
		_refresh_header()

func _refresh_header() -> void:
	nearby_count.text = _people_count_text(_visible_role_count())
	if _header_locked:
		return
	region_title.text = _region_title_text()
	location_status.text = _location_status_text()

func _people_count_text(count: int) -> String:
	return "%d %s" % [count, "person" if count == 1 else "people"]

func _region_title_text() -> String:
	if _in_la:
		return "Los Angeles"
	if not _home_resolved:
		return "Nearby"
	return "Demo Area" if _home_from_fallback else "Near You"

func _location_status_text() -> String:
	if _in_la:
		return "Exploring"
	if is_instance_valid(load_bar) and load_bar.visible:
		return "Loading map..."
	if not _home_resolved:
		return "Locating..."
	return "Demo location" if _home_from_fallback else "Location ready"

func _visible_role_count() -> int:
	var visible := 0
	for p in _pawns:
		if p.cohort != "self" and p.ready and (p.node as Node3D).visible:
			visible += 1
	return visible

func _system_safe_margins() -> Vector4:
	return Vector4(
		safe_area.get_theme_constant(&"margin_left"),
		safe_area.get_theme_constant(&"margin_top"),
		safe_area.get_theme_constant(&"margin_right"),
		safe_area.get_theme_constant(&"margin_bottom"))

func _sync_marker_margins() -> void:
	if marker_layer == null or not is_instance_valid(marker_layer):
		return
	var margins := _system_safe_margins()
	var top_height := maxf(top_panel.size.y, top_panel.get_combined_minimum_size().y)
	var reserved_top := top_panel.position.y + top_height
	var reserved_right := maxf(
		side_toolbar.size.x, side_toolbar.get_combined_minimum_size().x)
	marker_layer.set_safe_margins(Vector4(
		margins.x,
		margins.y + reserved_top + DesignTokens.SPACE_2,
		margins.z + reserved_right + DesignTokens.SPACE_2,
		margins.w + DesignTokens.SPACE_2))

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
	_clamp_to_bounds()

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
	if candidate_overlay:
		candidate_overlay.reanchor(anchor_lat, anchor_lng)

## 相机射线与地面平面（y=0）的交点。近地平线的甩飞防护不在这里做——
## 在拖拽处对单次 delta 限幅（limit_length(d)），比丢弃命中点的手感更接近原生地图。
func _ground_point(screen_pos: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(
		cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))

## 抬手后的惯性滑行：指数衰减，低于阈值停止。有手指按下时直接清零
## （新触摸打断惯性是原生地图的通用手感）。
func _step_fling(dt: float) -> void:
	# ⚠️ 手指按着时"不推进"但**绝不清零**——速度要留到抬手那一刻用。
	# 原先这两件事写在同一个条件里，于是拖拽期间每帧都把刚积累的速度清掉
	# （300ms 拖拽 ≈ 18 帧 = 清 18 次），抬手那帧手指通常已不动、没有新的 drag
	# 事件补速度，惯性就永远不触发。2026-09-01 真机实测"完全没有惯性"的根因。
	# 打断惯性是按下事件的职责，_unhandled_input 的 pressed 分支已经清零。
	if _touch_count > 0:
		return
	# 平移轴与缩放轴各自独立存活/衰减：捏合完松手要能继续缩，拖拽完松手要能继续滑。
	var pan_alive := _fling_vel.length() >= FLING_MIN_SPEED
	var zoom_alive := absf(_zoom_vel) >= ZOOM_FLING_MIN
	if not pan_alive:
		_fling_vel = Vector3.ZERO
	if not zoom_alive:
		_zoom_vel = 0.0
	if not pan_alive and not zoom_alive:
		return
	if pan_alive:
		# 与拖拽路径同款限幅：帧率抖动导致 vel*dt 失配时，不至于把地图甩出几千公里。
		_apply_world_delta((_fling_vel * dt).limit_length(_cam_distance()))
		_fling_vel *= exp(-FLING_DECAY * dt)
	if zoom_alive:
		_set_zoom(zoom + _zoom_vel * dt) # _set_zoom 自带 3~20 钳位
		_zoom_vel *= exp(-FLING_DECAY * dt)
	_camera_dirty = true

## 双击判定：与上一次触摸的时间差与落点距离都在窗口内。
func _is_double_tap(now_ms: int, pos: Vector2) -> bool:
	if _last_tap_ms <= 0:
		return false
	return now_ms - _last_tap_ms <= int(DOUBLE_TAP_S * 1000.0) \
		and pos.distance_to(_last_tap_pos) <= DOUBLE_TAP_MAX_PX

## 双击放大走 Tween 而不是瞬变——瞬变在地图上很跳，是"不丝滑"的另一半。
func _tween_zoom(target: float) -> void:
	_zoom_vel = 0.0 # 双击接管缩放，清掉残余的捏合惯性
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_method(_set_zoom, zoom, clampf(target, 3.0, 20.0), 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## —— 输入与 UI ————————————————————————————————————————————————

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_touch_count += 1 if e.pressed else -1
		_touch_count = maxi(_touch_count, 0)
		if e.pressed:
			_fling_vel = Vector3.ZERO # 新触摸立即打断惯性
			_zoom_vel = 0.0 # 缩放轴同理
			if _touch_count >= 2:
				# 第二指落下：丢掉第一指此前攒的 pan 速度，本次手势按捏合处理
				_gesture_multi = true
				_fling_vel = Vector3.ZERO
		elif _touch_count == 0:
			_gesture_multi = false # 全部离手，下一次手势重新判定
			if _zoom_tween: # 惯性的另一半：新触摸也要打断还在跑的双击变焦
				_zoom_tween.kill()
				_zoom_tween = null
			_drag_accum_px = 0.0 # 新手势重新计里程，配合下面的拖拽门禁
			_fling_peak = 0.0
			if _touch_count <= 1: # 第二指落下（捏合起手）不算双击，镜像拖拽路径的门禁
				if _is_double_tap(Time.get_ticks_msec(), e.position):
					_last_tap_ms = 0
					if not street_mode:
						_tween_zoom(zoom + 1.0)
				else:
					_last_tap_ms = Time.get_ticks_msec()
					_last_tap_pos = e.position
	if e is InputEventScreenDrag and _touch_count <= 1 and not _gesture_multi:
		# 抓地拖拽：让按下时的地面点始终跟在手指下（倾角下精确）。
		# 高 pitch 时屏幕上缘一像素对应的地面位移可达 ~0.4d，单次 delta 限幅到 d
		# 防止一次拖拽把地图甩出上百公里。
		var prev = _ground_point(e.position - e.relative)
		var now = _ground_point(e.position)
		if prev != null and now != null:
			var delta := ((prev as Vector3) - (now as Vector3)).limit_length(_cam_distance())
			_apply_world_delta(delta)
			# 惯性速度：位移换算成米/秒后 EMA 平滑，抬手接着走
			var dt := maxf(get_process_delta_time(), 0.001)
			_fling_vel = _fling_vel.lerp(delta / dt, FLING_EMA)
			_fling_peak = maxf(_fling_peak, _fling_vel.length())
			_camera_dirty = true
		# 累计拖拽位移超过双击判定半径就作废当前这次落点：按下→短拖拽→抬手→
		# 300ms 内再按一次不该被判成双击变焦——那是拖拽中途的手抖，不是双击。
		_drag_accum_px += e.relative.length()
		if _drag_accum_px > DOUBLE_TAP_MAX_PX:
			_last_tap_ms = 0
	elif e is InputEventMagnifyGesture and not street_mode:
		# 与拖拽同款：应用之后把变化量换算成 zoom/秒 做 EMA 平滑，松手接着走。
		var dz := log(e.factor) / log(2.0)
		_set_zoom(zoom + dz)
		var zdt := maxf(get_process_delta_time(), 0.001)
		_zoom_vel = lerpf(_zoom_vel, dz / zdt, FLING_EMA)
	elif e is InputEventPanGesture and not street_mode:
		_set_pitch(pitch - e.delta.y * 0.2)

func _wire_buttons() -> void:
	view_mode_switch.toggled.connect(_on_view_mode_toggled)
	travel_btn.pressed.connect(_on_fly_pressed)
	edit_avatar_btn.pressed.connect(func(): AppRouter.go_to_dressing())
	_update_view_mode()

func _on_view_mode_toggled(is_3d: bool) -> void:
	_set_pitch(45.0 if is_3d else 0.0)

func _update_view_mode() -> void:
	if not is_instance_valid(view_mode_switch):
		return
	var is_3d := pitch >= 10.0
	view_mode_switch.set_pressed_no_signal(is_3d)
	view_mode_switch.icon = ICON_VIEW_3D if is_3d else ICON_VIEW_2D
	view_mode_switch.tooltip_text = "Switch to 2D" if is_3d else "Switch to 3D"
	# 文案在按钮外面（RailCaption），状态变化要连它一起更新
	view_mode_label.text = "3D" if is_3d else "2D"

func _on_fly_pressed() -> void:
	_in_la = not _in_la
	travel_btn.icon = ICON_PIN if _in_la else ICON_TRAVEL
	travel_btn.tooltip_text = "Back Nearby" if _in_la else "Explore Los Angeles"
	travel_label.text = "Nearby" if _in_la else "LA"
	_teleport(LA_LAT, LA_LNG) if _in_la else _teleport(home_lat, home_lng)
	_refresh_header()

func _teleport(lat: float, lng: float) -> void:
	anchor_lat = lat
	anchor_lng = lng
	center_lat = lat
	center_lng = lng
	center_world = Vector3.ZERO
	_reposition_pawns()
	_camera_dirty = true

## —— 受限模式 ——————————————————————————————————————————————

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
		load_candidates(r)
	_camera_dirty = true

func set_pan_bounds(center_lat: float, center_lng: float, half_m: float) -> void:
	var dlat := half_m / MapGeoMath.M_PER_DEG_LAT
	var dlng := half_m / (MapGeoMath.M_PER_DEG_LAT * cos(deg_to_rad(center_lat)))
	pan_bounds = Rect2(center_lat - dlat, center_lng - dlng, 2.0 * dlat, 2.0 * dlng)
	_clamp_to_bounds()

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

func _clamp_to_bounds() -> void:
	if pan_bounds.size == Vector2.ZERO:
		return
	center_lat = clampf(center_lat, pan_bounds.position.x, pan_bounds.position.x + pan_bounds.size.x)
	center_lng = clampf(center_lng, pan_bounds.position.y, pan_bounds.position.y + pan_bounds.size.y)

func fly_to(lat: float, lng: float) -> void:
	_teleport(lat, lng)
	_clamp_to_bounds()

## 场景栈协议（AppRouter.push_instance）：进入第二层实例时地图完全隐藏并停渲染。
func suspend() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	$HUD.visible = false
	if map:
		map.set_map_visible(false)
	get_viewport().transparent_bg = false

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	$HUD.visible = true
	get_viewport().transparent_bg = true
	if map:
		map.set_map_visible(true)
	_camera_dirty = true

func _set_zoom(v: float) -> void:
	if street_mode:
		return
	zoom = clampf(v, 3.0, 20.0)
	_camera_dirty = true

func _set_pitch(v: float) -> void:
	pitch = clampf(v, 0.0, 70.0)
	_update_view_mode()
	_camera_dirty = true

## —— 初始化 ————————————————————————————————————————————————————

func _on_map_ready() -> void:
	_map_is_ready = true
	_set_dot(DOT_OK, false) # 同步中：常亮薄荷绿
	if map:
		pixel_ratio = map.get_pixel_ratio() # iOS 桥的真实 scale 随 READY 到达
	_camera_dirty = true

## 芯片状态圆点：颜色 + 是否呼吸闪烁（连接中）
func _set_dot(color: Color, pulse: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	status_dot.add_theme_stylebox_override("panel", sb)
	if _dot_tween:
		_dot_tween.kill()
		_dot_tween = null
	status_dot.modulate.a = 1.0
	if pulse:
		_dot_tween = create_tween().set_loops()
		_dot_tween.tween_property(status_dot, "modulate:a", 0.3, 0.7)
		_dot_tween.tween_property(status_dot, "modulate:a", 1.0, 0.7)

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
	for i in (0 if street_mode else PAWNS_NEAR_COUNT):
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
## is_fallback：本次调用是不是 3 秒超时回落（而非真实定位）。首个调用（无论
## 来源）落锁 home；若落锁的是回落点，允许随后第一手真实定位纠正一次
## （_correct_home），再之后一律忽略——语义与顶部 _home_from_fallback 的
## 注释一致，也是"首个定位或超时先到者生效，之后不再挪锚点"这条不变量在
## 加入纠正机制后的精确表述。
func _resolve_home(lat: float, lng: float, is_fallback: bool = false) -> void:
	if _home_resolved:
		if _home_from_fallback and not is_fallback:
			_correct_home(lat, lng)
		return
	_home_resolved = true
	_home_from_fallback = is_fallback
	home_lat = lat
	home_lng = lng
	# _in_la 为真说明用户已经手动飞去洛杉矶：这里只更新 home 数据和角色队列，
	# 不把镜头拽回去——否则相机瞬移回家但 _in_la/Fly 按钮文案仍停在"洛杉矶"，
	# 下一次按 Fly 又飞去洛杉矶，状态和画面对不上。
	if not _in_la:
		_teleport(lat, lng)
	_spawn_home_cohort()
	if marker_layer:
		marker_layer.set_home(lat, lng)
	if is_node_ready():
		_refresh_header()

## 回落点 -> 真实定位的一次性纠正。home 队列（self/near）可能已经排队甚至
## 已经装配完成，重新生成会打乱随机布局、白白重付一次装配代价——所以是
## 平移已有条目的经纬度（按 delta 整体搬），而不是重新 _spawn_home_cohort()。
## 洛杉矶夹具坐标绝对、故意不跟 home 走，靠 cohort 字段甄别、跳过不动。
func _correct_home(lat: float, lng: float) -> void:
	_home_from_fallback = false # 纠正机会用掉即焚，无论后面还会不会再调用本函数
	var d_lat := lat - home_lat
	var d_lng := lng - home_lng
	home_lat = lat
	home_lng = lng
	for spec in _spawn_queue:
		if spec.cohort != "la":
			spec.lat += d_lat
			spec.lng += d_lng
	for p in _pawns:
		if p.cohort != "la":
			p.lat += d_lat
			p.lng += d_lng
	if not _in_la: # 同 _resolve_home：镜头已经飞去洛杉矶就不拽回来
		_teleport(lat, lng)
	else:
		_reposition_pawns() # 镜头留在洛杉矶，但 home 队伍的世界坐标仍要跟着搬
		_camera_dirty = true
	if marker_layer:
		marker_layer.set_home(lat, lng)
	if is_node_ready():
		_refresh_header()

func _on_location_update(lat: float, lng: float, _accuracy: float) -> void:
	_resolve_home(lat, lng)

func _add_pawn(lat: float, lng: float, cfg: AvatarConfig, anim: String, cohort: String) -> void:
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
	# cohort 保留到 pawn 记录里：home 纠正（_correct_home）要靠它分清哪些已生成
	# 的角色跟着 home 搬（self/near）、哪些是绝对坐标的洛杉矶夹具不能动。
	var pawn := {"lat": lat, "lng": lng, "node": holder, "activity": activity, "ready": false,
		"cohort": cohort}
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
	var ready := 0
	for p in _pawns:
		if p.ready:
			ready += 1
	load_bar.max_value = INITIAL_ROLE_COUNT + 1
	load_bar.value = ready + (1 if _map_is_ready else 0)
	var elapsed_ms := Time.get_ticks_msec() - _load_bar_started_ms
	if _map_is_ready and ready >= INITIAL_ROLE_COUNT and _spawn_queue.is_empty() \
			and elapsed_ms >= LOAD_BAR_MIN_VISIBLE_MS:
		load_bar.visible = false
		_refresh_header()

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
