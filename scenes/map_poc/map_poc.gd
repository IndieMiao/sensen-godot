extends Node3D
## Native map camera sync, local/selected 3D avatars, geographic portraits and city POIs.
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

const PAWNS_NEAR_COUNT := 0 # People use portrait markers.
const PAWNS_LA_COUNT := 0 # No synthetic full-body LA crowd.
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
## Finger motion allowed within one tap; separate from the distance between two taps.
const TAP_SLOP_PX := 8.0

@onready var rigs: Node3D = $Rigs
@onready var cam: Camera3D = $Camera3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
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
var _touch_points: Dictionary = {}
var _touch_cooldown := 0.0
var _camera_dirty := true
## suspend() 里从 world_env.environment 摘下来的引用，resume() 时原样插回去
## （suspend/resume 协议的一部分，见 app_router.gd::_suspend 的类注释）。
var _saved_environment: Environment
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
var _map_mouse_down := false
var _load_bar_started_ms := 0
var _map_is_ready := false
## 受限模式（PRD §3.1）：由 FarmRegions 的城市选择触发；为真时地图只做「看见、选择、返回」。
var street_mode := false
var region: Dictionary = {}
## 平移边界（lat/lng）：position=(lat_min,lng_min)，size=(lat span,lng span)；零 size 不钳。
var pan_bounds := Rect2()
var candidate_overlay: CandidateOverlay = null
var select_panel: SelectPanel = null
## 已有农场时的「家」模式：不再选地，底部是 Nearby Farmers，侧栏多一个 My Farm。
var nearby_panel: NearbyPanel = null
var my_farm_btn: Button = null
var _nearby_from_presets := false
var _nearby_entries: Array = []
var _farm_choice: Dictionary = {}
## 上次拉取 Nearby 的地区。is_node_ready() 在 _ready() 内部就已经为真，所以
## enter_street_mode() 与 _ready() 尾部会各进一次 _build_region_ui()——按地区去重，别刷两遍。
var _nearby_region := ""
var _candidate_bps: Dictionary = {} # layout_patch_id -> FarmBlueprint
const STREET_ZOOM_MIN := 15.0
const STREET_ZOOM_MAX := 18.0
## 城市地图的无缝缩放（spec 2026-09-23-map-seamless-zoom-city-switch）：
## 下限 z2 = 竖屏能放下中国/美国本土全境；低于 CITY_DETAIL_ZOOM 只剩城市气泡与自己的 2D 头像。
const CITY_MIN_ZOOM := 2.0
const CITY_DETAIL_ZOOM := 9.0
## 城市地图 pitch 随 zoom 压平：z≥PITCH_FULL_ZOOM 为 CITY_PITCH，z≤PITCH_FLAT_ZOOM 为 0。
## pitch=0 时标记走精确 Mercator 投影（geo_to_screen），所以压平区必须覆盖全部低 zoom。
const CITY_PITCH := 35.0
const PITCH_FLAT_ZOOM := 8.0
const PITCH_FULL_ZOOM := 11.0
## 自动切城：z≥AUTO_SWITCH_ZOOM 且屏幕中心落进某座已开通城市的 placement_bounds；
## 当前城市的边界外扩 CITY_EXIT_MARGIN（按跨度比例）才算离开，边界上来回拖不抖动。
const AUTO_SWITCH_ZOOM := 7.0
const CITY_EXIT_MARGIN := 0.1
var _zoom_elastic := 0.0
var _focus_tween: Tween
var city_map: CityMapView
var _city_hidden: Dictionary = {}
var farm_markers: FarmMarkers
var journey_map: JourneyMap
var neighbours_toggle: Button
var journey_footer: HBoxContainer
var journey_backdrop: ColorRect
var journey_camera_controls: Array[Button] = []
var farm_overlay: CandidateOverlay
var _zoom_label: Label
var _nearby_generation := 0
var _map_controls_built := false
var _placement_mode := false
var _placement_location: Dictionary = {}
var _placement_pin: TextureRect
var _placing_busy := false
var _opening_farm := false
var _relocation_mode := false
var _relocation_session: FarmSession
var _relocation_preview: FarmRelocationPreview
var _relocation_generation := 0
var _relocation_committed := false
## 城市气泡上的各城农场数（region_id -> int），进入低 zoom 时拉取，60 秒内不重拉。
var city_farm_counts := {}
var _counts_fetched_ms := -1
var _last_city_detail := true
## 为真时清选中不 kill _focus_tween（低 zoom 门槛在飞行途中被跨过）。
var _hold_motion := false
## 城市视角的"静止"罗盘方向；实际 bearing = city_bearing × city_view_factor(zoom)。
var city_bearing := 0.0

func _ready() -> void:
	# A new picker can sit above a suspended map whose camera is still registered.
	cam.make_current()
	safe_area.theme = GameUi.theme()
	var language := LanguageButton.new()
	$HUD/SafeArea/Root.add_child(language)
	language.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	language.offset_left = -44
	language.offset_bottom = 44
	side_toolbar.offset_top = 58
	Localization.language_changed.connect(_refresh_language)
	top_panel.add_theme_stylebox_override("panel", GameUi.panel_style(10))
	side_toolbar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	load_bar.remove_theme_stylebox_override("background")
	load_bar.remove_theme_stylebox_override("fill")
	$HUD/SafeArea/Root.resized.connect(_layout_relocation_card)
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
	if Net:
		Net.booted.connect(_on_net_booted)

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
		map.set_language(TranslationServer.get_locale())
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
		_build_region_ui(region)
	_camera_dirty = true

## 平台桥工厂（避免 MapBridge 基类反向引用子类的脚本环）；城市选择页共用同一工厂。
func _make_bridge() -> MapBridge:
	return MapBridgeFactory.make()

func _exit_tree() -> void:
	# 场景切走的清理：transparent_bg 是根视口全局态，不还原会把换装房的
	# Environment 背景干掉、地图从底下透上来；地图本体也要停渲染省电。
	get_viewport().transparent_bg = false
	if map:
		map.set_map_visible(false)

func _process(_dt: float) -> void:
	_touch_cooldown = maxf(0.0, _touch_cooldown - _dt)
	if map:
		map.poll()
	_step_fling(_dt)
	if absf(_zoom_elastic) > 0.001 and _touch_count == 0:
		_zoom_elastic = lerpf(_zoom_elastic, 0.0, 1.0 - exp(-12.0 * _dt))
		_camera_dirty = true
	elif _touch_count == 0 and _zoom_elastic != 0.0:
		_zoom_elastic = 0.0
		_camera_dirty = true
	if not _spawn_queue.is_empty():
		# 每帧 1 个：装配（部件加载+网格合并）摊薄到 ~23 帧，压掉加载期卡顿
		var spec: Dictionary = _spawn_queue.pop_front()
		_add_pawn(spec.lat, spec.lng, spec.cfg, spec.anim, spec.cohort)
	if _camera_dirty:
		_camera_dirty = false
		_update_cameras()
	_update_load_bar()
	_sync_farm_markers()
	if city_map:
		_update_active_city()
		_update_city_detail()
		city_map.tick(_dt)
	if _placement_mode and _placement_pin:
		_placement_pin.position = cam.unproject_position(center_world) - _placement_pin.get_parent().global_position - Vector2(14, 28)
	if Engine.get_process_frames() % 30 == 0:
		_refresh_header()

func _refresh_header() -> void:
	nearby_count.text = _nearby_label_text()
	if _header_locked:
		return
	region_title.text = _region_title_text()
	location_status.text = str(region.get("name", "")) if street_mode and not load_bar.visible else _location_status_text()

func _refresh_language() -> void:
	_refresh_header()
	if map: map.set_language(TranslationServer.get_locale())
	if farm_markers: farm_markers.refresh_language()
	if city_map: city_map._last_state = ""; city_map.refresh_content()
	if _zoom_label: _zoom_label.text = L10n.format_text("Zoom %.0f", zoom)
	if nearby_panel:
		nearby_panel.refresh_language()
		nearby_panel.set_place_state(Net.session.state if Net and Net.session else {})
	_camera_dirty = true

func _people_count_text(count: int) -> String:
	return L10n.format_text("%d %s", [count, "person" if count == 1 else "people"])

## D4（2026-09-04 真机实测）：受限模式下按设计不生成近处路人（_spawn_home_cohort
## 只排玩家自己），人数结构性恒为 0——"0 people" 是误导性的空信息。受限模式下
## 改显示已选城市名字（region.name，来自 FarmRegions），比一个恒为零的数字更有
## 意义；自由漫游路径的人数文案保持不变。
func _nearby_label_text() -> String:
	if street_mode:
		return str(region.get("name", ""))
	return _people_count_text(_visible_role_count())

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
	var h_logical := _map_logical_height()
	# 下限守卫：headless/未就绪时窗口尺寸可能为 0，避免 look_at 退化
	return maxf(MapGeoMath.cam_distance_m(h_logical, MAP_FOV_DEG, center_lat, zoom + _zoom_elastic), 1.0)

func _map_logical_height() -> float:
	var height := float(DisplayServer.window_get_size().y)
	if height <= 0: height = get_viewport().get_visible_rect().size.y
	return maxf(1.0, height / pixel_ratio)

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
		map.set_camera(center_lat, center_lng, zoom + _zoom_elastic, bearing, pitch)
	if _placement_mode:
		_update_placement_preview()

## 浮动原点：地图中心跑远了就把锚点搬过来（f64 精确拷贝），所有几何重算。
func _maybe_reanchor() -> void:
	# 低 zoom 一帧能拖出上千公里：阈值随相机距离放宽，避免每帧重锚；
	# 精度只影响 3D 内容，而 3D 内容只在高 zoom（d 小）时出现。
	if center_world.length() < maxf(REANCHOR_DIST_M, _cam_distance() * 0.25):
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
		var character_scale := 1.15 if city_map else 0.8
		# ready 门禁：装配完成+首帧姿态应用前绝不显示——半成品蒙皮网格在地图
		# 缩放（~25×）下会渲染成通天拉伸毛刺（2026-08-29 真机截图实证）。
		var vis: bool = p.ready and n.position.distance_to(center_world) <= cull_r and city_detail_visible()
		if city_map and str(p.cohort).begins_with("farm:"):
			vis = vis and farm_markers.selected_id == str(p.cohort).trim_prefix("farm:")
		if street_mode and farm_markers and city_map == null:
			var id := str(p.cohort).trim_prefix("farm:")
			if farm_markers.selected_id == id: character_scale = 1.0
			vis = vis and farm_markers.visible_farm_ids.has(id)
			n.position = farm_markers.world_positions.get(id, MapGeoMath.geo_to_world(p.lat, p.lng, anchor_lat, anchor_lng))
		if n.visible != vis:
			n.visible = vis
			# 不等 RigActivity 的 0.25s 节流：隐藏立即停播，显形立即恢复
			if act:
				act.apply_level(RigActivity.Level.SLEEP if not vis else RigActivity.Level.ACTIVE)
		if not vis:
			continue
		n.scale = Vector3.ONE * s * character_scale
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
	if farm_overlay:
		farm_overlay.reanchor(anchor_lat, anchor_lng)

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
	if street_mode and ((zoom >= STREET_ZOOM_MAX and target > STREET_ZOOM_MAX) or (zoom <= _minimum_zoom() and target < _minimum_zoom())):
		_zoom_elastic = 0.16 if target > STREET_ZOOM_MAX else -0.16
		_camera_dirty = true
		return
	_zoom_tween = create_tween()
	_zoom_tween.tween_method(_set_zoom, zoom, clampf(target, _minimum_zoom(), STREET_ZOOM_MAX if street_mode else 20.0), 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## —— 输入与 UI ————————————————————————————————————————————————

func _unhandled_input(e: InputEvent) -> void:
	if _placing_busy or _relocation_preview != null: return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.device != InputEvent.DEVICE_ID_EMULATION:
		if not e.pressed and not _map_mouse_down: return
		_map_mouse_down = e.pressed
		var touch := InputEventScreenTouch.new()
		touch.position = e.position
		touch.pressed = e.pressed
		_unhandled_input(touch)
		return
	if e is InputEventMouseMotion and _map_mouse_down:
		var drag := InputEventScreenDrag.new()
		drag.position = e.position
		drag.relative = e.relative
		_unhandled_input(drag)
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if _touch_points.has(e.index): return
			_touch_points[e.index] = e.position
		else:
			if not _touch_points.has(e.index): return
			_touch_points.erase(e.index)
		_touch_count = _touch_points.size()
		_touch_cooldown = 0.12
		if e.canceled:
			_gesture_multi = true
			_fling_vel = Vector3.ZERO
			_zoom_vel = 0.0
		if e.pressed:
			_fling_vel = Vector3.ZERO # 新触摸立即打断惯性
			_zoom_vel = 0.0 # 缩放轴同理
			if _focus_tween: _focus_tween.kill()
			if _zoom_tween:
				_zoom_tween.kill()
				_zoom_tween = null
			if _touch_count == 1:
				_drag_accum_px = 0.0
				_fling_peak = 0.0
			if _touch_count >= 2:
				# 第二指落下：丢掉第一指此前攒的 pan 速度，本次手势按捏合处理
				_gesture_multi = true
				_fling_vel = Vector3.ZERO
		elif _touch_count == 0:
			if not _gesture_multi and _drag_accum_px <= TAP_SLOP_PX:
				# Tap jitter must not leave a fling after choosing a location or closing a drawer.
				_fling_vel = Vector3.ZERO
				if city_map and not e.canceled and farm_markers and farm_markers.activate_at(e.position):
					_last_tap_ms = 0
				elif city_map and not e.canceled and city_map.activate_at(e.position):
					_last_tap_ms = 0
				elif city_map and not e.canceled and not city_map.selected.is_empty():
					city_map.clear_selection()
					_last_tap_ms = 0
				elif not _relocation_mode and not e.canceled and farm_markers and (not farm_markers.selected_id.is_empty() or (nearby_panel and nearby_panel.visible)):
					_clear_farm_selection()
					if nearby_panel: _set_nearby_open(false)
				elif not _relocation_mode and not e.canceled and journey_map and journey_map.visible and journey_map.activate_at(e.position):
					_last_tap_ms = 0
				elif _placement_mode and not _placing_busy:
					var point = _ground_point(e.position)
					if point != null:
						var delta := (point as Vector3) - center_world
						_apply_world_delta(delta)
						_camera_dirty = true
				elif _is_double_tap(Time.get_ticks_msec(), e.position):
					_last_tap_ms = 0
					_tween_zoom(zoom + 1.0)
				else:
					_last_tap_ms = Time.get_ticks_msec()
					_last_tap_pos = e.position
			else:
				_last_tap_ms = 0
			_gesture_multi = false
	if e is InputEventScreenDrag:
		if not _touch_points.has(e.index): return
		var previous: Vector2 = _touch_points[e.index]
		_touch_points[e.index] = e.position
		if _gesture_multi:
			if _touch_count == 2:
				var other: Vector2 = _touch_points.values()[0] if _touch_points.keys()[1] == e.index else _touch_points.values()[1]
				var old_span := previous.distance_to(other)
				var new_span: float = e.position.distance_to(other)
				# Raw spans also cover pinches below Android's native minimum scaling span.
				if old_span >= 16.0 and new_span >= 16.0:
					_magnify(new_span / old_span)
				if not street_mode:
					_set_pitch(pitch - (e.position.y - previous.y) * 0.1)
			return
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
		# A drag cannot become a placement tap or seed the next double tap.
		_drag_accum_px += e.relative.length()
		if _drag_accum_px > TAP_SLOP_PX:
			_last_tap_ms = 0
	elif e is InputEventMagnifyGesture:
		if _touch_count == 0 and _touch_cooldown <= 0.0:
			_magnify(e.factor)
	elif e is InputEventPanGesture and not street_mode and _touch_count == 0 and _touch_cooldown <= 0.0:
		_set_pitch(pitch - e.delta.y * 0.2)

func _magnify(factor: float) -> void:
	if factor <= 0.0 or not is_finite(factor): return
	var dz := log(factor) / log(2.0)
	_set_zoom(zoom + dz)
	var zdt := maxf(get_process_delta_time(), 0.001)
	_zoom_vel = lerpf(_zoom_vel, dz / zdt, FLING_EMA)

func _wire_buttons() -> void:
	view_mode_switch.toggled.connect(_on_view_mode_toggled)
	travel_btn.icon = GameUi.icon("map-pin" if _in_la else "route")
	edit_avatar_btn.icon = GameUi.icon("shirt")
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
	view_mode_switch.icon = GameUi.icon("box" if is_3d else "map")
	view_mode_switch.tooltip_text = "Switch to 2D" if is_3d else "Switch to 3D"
	# 文案在按钮外面（RailCaption），状态变化要连它一起更新
	view_mode_label.text = "3D" if is_3d else "2D"

func _on_fly_pressed() -> void:
	_in_la = not _in_la
	travel_btn.icon = GameUi.icon("map-pin" if _in_la else "route")
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
	if is_instance_valid(city_map) and not CityMapData.has_city(str(r.get("id", ""))): _remove_city_map()
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
		_build_region_ui(r)
		_build_map_controls()
	_camera_dirty = true

## Called after the owner DTO commits, even when the current map is suspended.
func refresh_owned_farm_after_relocation(choice: Dictionary) -> void:
	var bp := FarmBlueprint.load_choice(choice)
	if bp == null or bp.overlay.is_empty(): return
	_farm_choice = choice.duplicate(true)
	var own_region := FarmRegions.load_default().region(bp.region_id)
	if not own_region.is_empty(): region = own_region
	_nearby_generation += 1
	_snapshots.clear()
	_anchor_self_to_farm(bp.overlay.center)
	if farm_markers:
		farm_markers.put("self", bp, "My Farm", true)
		farm_markers.selected_id = ""
		if is_instance_valid(farm_markers.miniature):
			farm_markers.miniature.hide()
			farm_markers.miniature.set("_key", "")
	if farm_overlay:
		farm_overlay.set_candidates([bp], anchor_lat, anchor_lng)
		farm_overlay.select(bp.layout_patch_id)
		farm_overlay.hide()
	if farm_markers == null:
		_enter_farm_home(region)
	else:
		_set_nearby_open(false)
		_refresh_nearby()
	_focus_region(region, bp)
	_camera_dirty = true

## Relocation always receives the owner's city, never the city currently browsed.
func enter_relocation_mode(r: Dictionary, owner_session: FarmSession = null) -> void:
	_remove_city_map()
	_relocation_session = owner_session if owner_session != null else Net.session
	_relocation_mode = true
	# _ready may already have built the owner's regular map before router entry.
	_nearby_generation += 1
	for control in [nearby_panel, my_farm_btn, journey_footer, journey_map, journey_backdrop, farm_markers, farm_overlay]:
		if is_instance_valid(control): control.hide()
	if is_instance_valid(farm_markers) and is_instance_valid(farm_markers.miniature): farm_markers.miniature.hide()
	enter_street_mode(r)
	if is_node_ready(): edit_avatar_btn.get_parent().hide()
	if _relocation_session != null and FarmPlacement.is_valid(_relocation_session.location):
		fly_to(float(_relocation_session.location.lat), float(_relocation_session.location.lng))

func _preview_relocation() -> void:
	if _placing_busy or not FarmPlacement.generated_contains(region, _placement_location): return
	if _relocation_session == null: return
	_placing_busy = true
	_reset_gesture()
	select_panel.set_saving(true)
	# Generating geography has no side effects: the player may leave while it loads.
	select_panel._cancel.disabled = false
	_relocation_generation += 1
	var generation := _relocation_generation
	var data: Dictionary = await _relocation_session.preview_relocation(str(region.get("id", "")), _placement_location)
	if not is_inside_tree() or generation != _relocation_generation: return
	_placing_busy = false
	if data.is_empty():
		select_panel.set_saving(false, _relocation_error(_relocation_session.last_error_code))
		return
	_relocation_preview = FarmRelocationPreview.new()
	$HUD/SafeArea/Root.add_child(_relocation_preview)
	_layout_relocation_card()
	_relocation_preview.confirmed.connect(_confirm_relocation)
	_relocation_preview.reselected.connect(_reselect_relocation)
	_relocation_preview.cancelled.connect(_cancel_relocation)
	if not _relocation_preview.configure(data, str(region.get("id", ""))):
		_reselect_relocation()
		select_panel.set_saving(false, _generation_error("INVALID_FARM_TERRAIN"))
		return
	select_panel.hide()
	side_toolbar.hide()
	if _placement_pin: _placement_pin.hide()
	_layout_relocation_card.call_deferred()

func _layout_relocation_card() -> void:
	if not is_instance_valid(_relocation_preview): return
	var area: Vector2 = ($HUD/SafeArea/Root as Control).size
	var width := minf(620, maxf(1, area.x - 8))
	var height := minf(620, maxf(1, area.y - 86))
	_relocation_preview.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_relocation_preview.position = Vector2((area.x - width) * 0.5, area.y - height - 4)
	_relocation_preview.size = Vector2(width, height)

func _reselect_relocation() -> void:
	if _placing_busy or (_relocation_session != null and _relocation_session.relocation_pending()): return
	if _relocation_preview:
		_relocation_preview.queue_free()
		_relocation_preview = null
	select_panel.show()
	side_toolbar.show()
	select_panel.set_saving(false)
	if _placement_pin: _placement_pin.show()
	_update_placement_preview()

func _confirm_relocation() -> void:
	if _placing_busy or _relocation_preview == null or _relocation_session == null: return
	_placing_busy = true
	_reset_gesture()
	_relocation_preview.set_busy(true)
	if _relocation_committed:
		await _finish_relocation()
		return
	var succeeded: bool = await _relocation_session.confirm_relocation(_relocation_preview.preview)
	if not is_inside_tree(): return
	_placing_busy = false
	if not succeeded:
		_relocation_preview.set_busy(false, _relocation_session.relocation_pending(), _relocation_error(_relocation_session.last_error_code))
		if not _relocation_session.relocation_pending() and _relocation_session.last_error_code in ["RELOCATION_EXPIRED", "RELOCATION_CONFLICT"]:
			_relocation_preview.confirm_button.disabled = true
		return
	_relocation_committed = true
	await _finish_relocation()

func _finish_relocation() -> void:
	_placing_busy = true
	var choice := _relocation_session.farm_choice()
	FarmChoice.save_choice(choice)
	await AppRouter.complete_farm_relocation(choice)
	if not is_inside_tree(): return
	# Scene loading can fail after the server commits. Retry entering the confirmed
	# farm without issuing another relocation or resuming obsolete geometry.
	_placing_busy = false
	_relocation_preview.set_busy(false, true)
	_relocation_preview.confirm_button.text = "Enter your farm"
	_relocation_preview.status.text = "Your farm has moved. Tap to enter it."

func _cancel_relocation() -> void:
	if _relocation_committed: return
	if _relocation_session != null and _relocation_session.relocation_pending(): return
	# Preview requests may finish later; their result cannot mutate a farm or reopen UI.
	if _placing_busy and _relocation_preview != null: return
	_relocation_generation += 1
	AppRouter.cancel_farm_relocation()

static func _relocation_error(code: String) -> String:
	return {
		"RELOCATION_UNAVAILABLE": "This farm has no relocation opportunity left.",
		"RELOCATION_EXPIRED": "This preview expired. Choose the location again.",
		"RELOCATION_CONFLICT": "Your farm changed. Preview again to include the latest crops and decorations.",
		"RELOCATION_BUSY": "Finish fishing and return from the mine before relocating.",
		"RELOCATION_NO_SPACE": "This area cannot fit your crops and decorations. Choose another location.",
		"PENDING_ACTION": "Check the previous action before relocating.",
		"LOCAL_STORAGE": "Could not save the previous action. Try again.",
	}.get(code, _generation_error(code))

## 已经有农场就不再选地：候选层与 Create Farm 都不建，直接进「家」模式。
## _ready() 与 enter_street_mode() 两个入口都走这里，且可重入。
func _build_region_ui(r: Dictionary) -> void:
	if _relocation_mode:
		load_candidates(r)
		if select_panel: select_panel.set_relocation_mode()
		return
	_farm_choice = _resolve_farm_choice()
	if _farm_choice.is_empty():
		load_candidates(r)
	elif farm_markers == null:
		_placement_mode = false
		if _placement_pin: _placement_pin.visible = false
		if candidate_overlay:
			remove_child(candidate_overlay)
			candidate_overlay.queue_free()
			candidate_overlay = null
		if select_panel:
			select_panel.get_parent().remove_child(select_panel)
			select_panel.queue_free()
			select_panel = null
		_enter_farm_home(r)
	elif str(r.get("id", "")) != _nearby_region:
		_focus_region(r, FarmBlueprint.load_choice(_farm_choice))
		_ensure_legacy_nearby_panel()
		_setup_journey_map()
		_install_city_map()
		_refresh_nearby()

func set_pan_bounds(center_lat: float, center_lng: float, half_m: float) -> void:
	var dlat := half_m / MapGeoMath.M_PER_DEG_LAT
	var dlng := half_m / (MapGeoMath.M_PER_DEG_LAT * cos(deg_to_rad(center_lat)))
	pan_bounds = Rect2(center_lat - dlat, center_lng - dlng, 2.0 * dlat, 2.0 * dlng)
	_clamp_to_bounds()

## —— 候选流（PRD §4.3）——————————————————————————————————————————

func load_candidates(r: Dictionary) -> void:
	if candidate_overlay: return
	_candidate_bps.clear()
	var center := Vector2(float(r.center[0]), float(r.center[1]))
	var preview := FarmPlacement.preview(str(r.get("id", "")), center)
	_candidate_bps[preview.layout_patch_id] = preview
	candidate_overlay = CandidateOverlay.new()
	candidate_overlay.name = "FarmSelection"
	candidate_overlay.outline_only = true
	candidate_overlay.placement_outline = true
	add_child(candidate_overlay)
	candidate_overlay.set_candidates([preview], anchor_lat, anchor_lng)
	select_panel = SelectPanel.new()
	$HUD/SafeArea/Root.add_child(select_panel)
	select_panel.set_generation_mode()
	select_panel.confirmed.connect(_on_candidate_confirmed)
	select_panel.placement_cancelled.connect(_cancel_placement)
	fly_to(center.x, center.y)
	_begin_placement(preview.layout_patch_id)

func focus_candidate(id: String) -> void:
	if not _candidate_bps.has(id):
		return
	var center: Vector2 = _candidate_bps[id].overlay.center
	set_pan_bounds(center.x, center.y, 300.0)
	fly_to(center.x, center.y)
	candidate_overlay.select(id)
	if select_panel.focused_id != id:
		select_panel.focus(id)

func _save_choice(id: String) -> void:
	FarmChoice.save(id, _candidate_bps[id].revision, _placement_location if _placement_mode else {})

func _on_candidate_confirmed(id: String) -> void:
	if _placing_busy: return
	if _relocation_mode:
		await _preview_relocation()
		return
	if not _placement_mode:
		_begin_placement(id)
		return
	if not FarmPlacement.generated_contains(region, _placement_location): return
	_placing_busy = true
	_reset_gesture()
	select_panel.set_saving(true)
	var choice := await _resolve_confirmed_farm(id)
	if not is_inside_tree(): return
	_placing_busy = false
	if choice.is_empty():
		select_panel.set_saving(false, location_status.text)
		return
	AppRouter.open_instance(AppRouter.FARM, choice)

func _begin_placement(id: String) -> void:
	if not _candidate_bps.has(id): return
	_placement_mode = true
	_reset_gesture()
	var bounds: Array = region.get("placement_bounds", [])
	if bounds.size() == 4:
		pan_bounds = Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]) - float(bounds[0]), float(bounds[3]) - float(bounds[1]))
	candidate_overlay.outline_only = true
	if select_panel.generation_mode:
		candidate_overlay.move_candidate(id, Vector2(center_lat, center_lng))
	else:
		var preview: FarmBlueprint = _candidate_bps[id].with_location({"lat": center_lat, "lng": center_lng})
		candidate_overlay.set_candidates([preview], anchor_lat, anchor_lng)
	candidate_overlay.select(id)
	if _placement_pin == null:
		_placement_pin = GameUi.picture(GameUi.icon("map-pin"), 28)
		_placement_pin.modulate = GameUi.GREEN
		$HUD/SafeArea/Root.add_child(_placement_pin)
	_placement_pin.visible = true
	_update_placement_preview()

func _update_placement_preview() -> void:
	if not _placement_mode or select_panel == null or _placing_busy or _relocation_preview != null: return
	var next_location := {"lat": snappedf(center_lat, 0.000001), "lng": snappedf(center_lng, 0.000001)}
	if _relocation_mode and next_location == _placement_location: return
	_placement_location = next_location
	candidate_overlay.move_candidate(select_panel.focused_id, Vector2(center_lat, center_lng))
	select_panel.set_placement_mode(true, FarmPlacement.generated_contains(region, _placement_location))

func _cancel_placement() -> void:
	if _relocation_mode:
		_cancel_relocation()
		return
	if _placing_busy: return
	AppRouter.go_to_city_select()

## 玩家选了 id，但**服务端已有农场时以服务端为准**：ensure_farm 取回的是旧农场，客户端若
## 仍按新选的蓝图进场，发出去的格子全在别的坐标上（2026-09-04 真机全程 CELL_NOT_CULTIVABLE）。
## 只有服务器确认农场后才能进入；失败留在选地页，允许重新连接。
func _resolve_confirmed_farm(_id: String) -> Dictionary:
	if await _connect_farm_service():
		if not is_inside_tree(): return {}
		var ok: bool = await Net.session.ensure_generated_farm(str(region.get("id", "")), _placement_location)
		if not is_inside_tree(): return {}
		if not ok:
			location_status.text = _generation_error(Net.session.last_error_code)
			return {}
		var choice := Net.session.farm_choice()
		if FarmBlueprint.load_choice(choice) == null:
			location_status.text = _generation_error("INVALID_FARM_TERRAIN")
			return {}
		if _id != "map_selection" and str(choice.layout_patch_id) != _id:
			location_status.text = L10n.format_text("You already have a farm at %s", _candidate_name(str(choice.layout_patch_id)))
		FarmChoice.save_choice(choice)
		return choice
	location_status.text = "Could not connect. Try again."
	return {}

static func _generation_error(code: String) -> String:
	return {
		"LOCATION_ALL_WATER": "This area is entirely water. Choose another location.",
		"LOCATION_ALL_DESERT": "This area is entirely desert. Choose another location.",
		"LOCATION_UNSUITABLE": "There is not enough usable land. Choose another location.",
		"GEOGRAPHY_UNAVAILABLE": "Map service is temporarily unavailable. Please try again.",
		"GEOGRAPHY_INCOMPLETE": "This area has insufficient terrain information. Move the map to choose another area.",
		"INVALID_FARM_TERRAIN": "The farm terrain could not be verified. Retry loading it.",
		"GENERATION_UNSUPPORTED": "This server needs the compact farm update. Try again after updating.",
		"LOCATION_OUTSIDE_REGION": "Choose an area inside this city",
		"INVALID_LOCATION": "Choose a valid farm location",
		"TRANSPORT": "Could not connect. Try again.",
	}.get(code, "Could not save farm. Try again.")

func _candidate_name(layout_id: String) -> String:
	for c in region.get("candidates", []):
		if str(c.get("layout_patch_id", "")) == layout_id:
			return str(c.get("name", layout_id))
	return layout_id

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
## 和地图的天空/环境光（2026-09-04 终审 C1）。
func suspend() -> void:
	_reset_gesture()
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	$HUD.visible = false
	if map: map.set_map_visible(false)
	get_viewport().transparent_bg = false
	cam.current = false
	if world_env.environment:
		_saved_environment = world_env.environment
	world_env.environment = null

func resume() -> void:
	_reset_gesture()
	_refresh_self_outfit()
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	$HUD.visible = true
	get_viewport().transparent_bg = true
	if map:
		map.set_map_visible(true)
	_camera_dirty = true
	cam.make_current()
	world_env.environment = _saved_environment
	if street_mode: _build_region_ui(region)
	if nearby_panel:
		nearby_panel._apply_bottom_preset()
		nearby_panel.set_place_state(Net.session.state if Net and Net.session else {})

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_gesture()

func _reset_gesture() -> void:
	if _touch_count > 0: _touch_cooldown = 0.12
	_touch_count = 0
	_touch_points.clear()
	_map_mouse_down = false
	_gesture_multi = false
	_drag_accum_px = 0.0
	_last_tap_ms = 0
	_fling_vel = Vector3.ZERO
	_zoom_vel = 0.0
	if _focus_tween: _focus_tween.kill()
	if _zoom_tween: _zoom_tween.kill()

func _set_zoom(v: float) -> void:
	zoom = clampf(v, _minimum_zoom(), STREET_ZOOM_MAX if street_mode else 20.0)
	if street_mode and v != zoom:
		_zoom_elastic = clampf((v - zoom) * 0.35, -0.16, 0.16)
		_zoom_vel = 0
	if city_map:
		# pitch 与 bearing 一起随 zoom 回正：国家级是正北朝上的平面图，放大回城市恢复城市视角。
		pitch = city_pitch_for(zoom)
		bearing = city_bearing * city_view_factor(zoom)
	if _zoom_label: _zoom_label.text = L10n.format_text("Zoom %.0f", zoom)
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

func _refresh_self_outfit() -> void:
	var saved := self_config()
	for spec in _spawn_queue:
		if spec.cohort == "self" and not saved.changed_slots(spec.cfg).is_empty():
			spec.cfg = saved
	for pawn in _pawns:
		if pawn.cohort != "self":
			continue
		var rig := pawn.get("rig") as AvatarRig
		if rig == null or saved.changed_slots(rig.desired_config()).is_empty():
			continue
		pawn.ready = false
		pawn.node.visible = false
		rig.apply_config(saved)
		if not rig.is_busy():
			_finish_pawn_outfit(pawn)

func _finish_pawn_outfit(pawn: Dictionary) -> void:
	if not is_instance_valid(pawn.node) or pawn.node.is_queued_for_deletion(): return
	var rig := pawn.rig as AvatarRig
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		ap.advance(0.0)
	pawn.ready = true
	if pawn.has("popup"):
		var id := str(pawn.cohort).trim_prefix("farm:")
		if city_map and farm_markers and farm_markers.selected_id == id:
			farm_markers.expanded_avatar_id = id
			pawn.popup.pop()
	_camera_dirty = true

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
	var popup: MapAvatarPopup
	if city_map and cohort.begins_with("farm:"):
		popup = MapAvatarPopup.new()
		holder.add_child(popup)
		popup.add_child(rig)
	else:
		holder.add_child(rig)
	var activity: RigActivity = null
	for c in rig.get_children():
		if c is RigActivity:
			activity = c
			break
	# cohort 保留到 pawn 记录里：home 纠正（_correct_home）要靠它分清哪些已生成
	# 的角色跟着 home 搬（self/near）、哪些是绝对坐标的洛杉矶夹具不能动。
	var pawn := {"lat": lat, "lng": lng, "node": holder, "rig": rig, "activity": activity, "ready": false,
		"cohort": cohort}
	if popup: pawn.popup = popup
	rig.config_applied.connect(func(_c):
		if not is_instance_valid(holder) or holder.is_queued_for_deletion(): return
		var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap:
			ap.play(anim)
			ap.advance(0.0) # 强制立刻应用首帧骨骼姿态，杜绝未蒙皮帧被渲染
		_finish_pawn_outfit(pawn))
	# config_applied only covers initial loading; later outfit changes finish via busy_changed.
	rig.busy_changed.connect(func(busy):
		if not busy and not pawn.ready:
			_finish_pawn_outfit(pawn))
	rig.apply_config(cfg)
	_pawns.append(pawn)
	_camera_dirty = true

## D3（2026-09-04 真机实测）：受限模式顶栏卡死在「Loading map...」——这里原来
## 无条件用自由漫游的 INITIAL_ROLE_COUNT（1 自己 + 12 近处路人 + 10 洛杉矶夹具
## = 23）当门禁，但受限模式下 _spawn_home_cohort() 不排近处路人（for i in
## (0 if street_mode else PAWNS_NEAR_COUNT)）、_spawn_la_fixture() 在 _ready()
## 里被 `if not street_mode` 整个跳过——ready 顶多到 1（玩家自己），23 永远
## 够不着，进度条永远不消失，_location_status_text() 也就永远卡在加载态。
func _expected_role_count() -> int:
	return 1 if street_mode else INITIAL_ROLE_COUNT

func _update_load_bar() -> void:
	if not load_bar.visible:
		return
	var ready := 0
	for p in _pawns:
		if p.ready:
			ready += 1
	var expected := _expected_role_count()
	load_bar.max_value = expected + 1
	load_bar.value = ready + (1 if _map_is_ready else 0)
	var elapsed_ms := Time.get_ticks_msec() - _load_bar_started_ms
	if _map_is_ready and ready >= expected and _spawn_queue.is_empty() \
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


## —— 家模式 + 访问骨架（PRD §3.3 / §8.4）——————————————————————————————————

## 我的农场用哪张蓝图：登录且服务端有农场 → 服务端说了算，并把本地缓存改成一致；
## 否则用本地缓存（离线或还没建场）。
func _resolve_farm_choice() -> Dictionary:
	if Net and Net.logged_in() and Net.session.has_farm() and not Net.session.layout_patch_id.is_empty():
		var server := Net.session.farm_choice()
		var local := FarmChoice.load()
		if local != server:
			FarmChoice.save_choice(server)
		return server
	if _server_has_no_farm():
		return {}
	return FarmChoice.load()

func _server_has_no_farm() -> bool:
	return Net and Net.logged_in() and not Net.session.has_farm() and Net.session.last_error_code == "NO_FARM"

func _show_farm_selection() -> void:
	_remove_city_map()
	# A cached choice may belong to a different server. Keep it on disk until a new farm is confirmed.
	_nearby_generation += 1
	for node in [nearby_panel, my_farm_btn, farm_markers, farm_overlay]:
		if node:
			node.get_parent().remove_child(node)
			node.queue_free()
	nearby_panel = null
	my_farm_btn = null
	farm_markers = null
	farm_overlay = null
	_snapshots.clear()
	_farm_choice = {}
	_nearby_region = ""
	load_candidates(region)
	_camera_dirty = true

## Net 在地图 _ready() 之后才 boot 完的情况：登录一到就重看一遍——有农场就从选地切到家。
func _on_net_booted(_ok: bool) -> void:
	if _relocation_mode: return
	if not street_mode:
		return
	if _server_has_no_farm():
		_show_farm_selection()
		return
	if farm_markers != null:
		if nearby_panel: nearby_panel.set_place_state(Net.session.state if Net and Net.session else {})
		if _ok and Net.logged_in():
			_snapshots.clear()
			_refresh_nearby()
		return
	if Net.session.has_farm():
		if candidate_overlay:
			remove_child(candidate_overlay)
			candidate_overlay.queue_free()
			candidate_overlay = null
		if select_panel:
			select_panel.get_parent().remove_child(select_panel)
			select_panel.queue_free()
			select_panel = null
		_build_region_ui(region)

## Keep the browsing city independent of the saved farm's location.
func _focus_region(r: Dictionary, own_farm: FarmBlueprint) -> void:
	var center := Vector2(float(r.center[0]), float(r.center[1]))
	if own_farm and own_farm.region_id == str(r.get("id", "")) and not own_farm.overlay.is_empty():
		center = own_farm.overlay.center
	if _focus_tween: _focus_tween.kill()
	_reset_gesture()
	set_pan_bounds(center.x, center.y, 450.0)
	fly_to(center.x, center.y)

## 有农场之后地图的常态：显示所选城市，底部挂 Nearby Farmers。
func _enter_farm_home(r: Dictionary) -> void:
	var bp := FarmBlueprint.load_choice(_farm_choice)
	if bp != null and not bp.overlay.is_empty():
		_anchor_self_to_farm(bp.overlay.center)
	_focus_region(r, bp)
	farm_markers = FarmMarkers.new()
	farm_markers.name = "FarmMarkers"
	farm_markers.miniature = preload("res://scenes/map/farm_map_model.gd").new()
	farm_markers.miniature.name = "SelectedFarmModel"
	add_child(farm_markers.miniature)
	$HUD/SafeArea/Root.add_child(farm_markers)
	$HUD/SafeArea/Root.move_child(farm_markers, 0)
	farm_markers.focused.connect(func(id):
		if city_map:
			if id == "self": _clear_farm_selection()
			else: _select_city_player(id)
		elif id == "self": _focus_own_farm()
		elif nearby_panel:
			_set_nearby_open(true)
			nearby_panel.focus(id))
	farm_markers.cluster_focused.connect(func(_ids): _camera_dirty = true)
	if bp: farm_markers.put("self", bp, "My Farm", true)
	farm_overlay = CandidateOverlay.new()
	farm_overlay.name = "FarmOverlay"
	farm_overlay.outline_only = true
	add_child(farm_overlay)
	if bp:
		farm_overlay.set_candidates([bp], anchor_lat, anchor_lng)
		farm_overlay.select(bp.layout_patch_id)
	farm_overlay.hide()
	my_farm_btn = Button.new()
	my_farm_btn.name = "MyFarm"
	my_farm_btn.text = "My Farm"
	my_farm_btn.icon = GameUi.icon("house")
	my_farm_btn.theme_type_variation = &"AccentButton"
	my_farm_btn.custom_minimum_size.y = 44.0
	my_farm_btn.pressed.connect(_open_my_farm)
	$HUD/SafeArea/Root.add_child(my_farm_btn)
	my_farm_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	my_farm_btn.offset_left = -152
	my_farm_btn.offset_right = -52
	my_farm_btn.offset_top = 4
	my_farm_btn.offset_bottom = 48
	_build_map_controls()
	_ensure_legacy_nearby_panel()
	_setup_journey_map()
	_install_city_map()
	_refresh_nearby()

func _ensure_legacy_nearby_panel() -> void:
	if CityMapData.has_city(str(region.get("id", ""))) or nearby_panel: return
	nearby_panel = NearbyPanel.new()
	nearby_panel.farm_focused.connect(_on_farm_focused)
	nearby_panel.visit_requested.connect(_on_visit_requested)
	nearby_panel.street_requested.connect(_on_street_visit_requested)
	nearby_panel.place_requested.connect(_open_place)
	nearby_panel.close_requested.connect(func(): _set_nearby_open(false))
	$HUD/SafeArea/Root.add_child(nearby_panel)
	nearby_panel.set_place_state({})
	nearby_panel.set_social_only()

func _setup_journey_map() -> void:
	if CityMapData.has_city(str(region.get("id", ""))) or not nearby_panel: return
	if not Net or not Net.session or not JourneyProgress.active(Net.session.state) or journey_map: return
	journey_map = JourneyMap.new()
	if Net.session.farm_terrain.is_empty(): journey_map.configure(JourneyStreets.load_for(Net.session))
	journey_map.hide()
	$HUD/SafeArea/Root.add_child(journey_map)
	$HUD/SafeArea/Root.move_child(journey_map, 0)
	journey_map.place_requested.connect(_open_place)
	journey_map.street_requested.connect(func(target_id):
		if AppRouter.top_instance() == null and Net and Net.session:
			AppRouter.open_instance(AppRouter.STREET, {"session": Net.session, "target": target_id}))
	journey_map.farm_requested.connect(_open_my_farm)
	nearby_panel.hide()
	journey_backdrop = ColorRect.new()
	journey_backdrop.color = Color("d9e7d3")
	journey_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	journey_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$HUD.add_child(journey_backdrop)
	$HUD.move_child(journey_backdrop, 0)
	var footer := HBoxContainer.new()
	journey_footer = footer
	footer.name = "JourneyFooter"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -48
	$HUD/SafeArea/Root.add_child(footer)
	for spec in [["plus", "Zoom in", 1.0], ["minus", "Zoom out", -1.0]]:
		var b := GameUi.button(spec[0], "", spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _tween_zoom(zoom + float(spec[2])))
		footer.add_child(b)
		journey_camera_controls.append(b)
	var focus := GameUi.button("locate-fixed", "", "Focus my farm")
	focus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus.pressed.connect(_focus_own_farm)
	footer.add_child(focus)
	journey_camera_controls.append(focus)
	var explore := GameUi.button("sprout", "", "Enter your farm")
	explore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explore.pressed.connect(_open_my_farm)
	footer.add_child(explore)
	neighbours_toggle = GameUi.button("users-round", "", "Nearby farmers")
	neighbours_toggle.name = "NearbyToggle"
	neighbours_toggle.toggle_mode = true
	neighbours_toggle.pressed.connect(func(): _set_nearby_open(not nearby_panel.visible))
	neighbours_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	footer.add_child(neighbours_toggle)
	var outfit := GameUi.button("user-round", "", "Your outfit")
	outfit.size_flags_horizontal = Control.SIZE_SHRINK_END
	outfit.pressed.connect(AppRouter.go_to_dressing)
	footer.add_child(outfit)
	nearby_panel.close_button.show()
	footer.resized.connect(_layout_journey_drawer)
	$HUD/SafeArea/Root.resized.connect(_layout_journey_drawer)
	top_panel.resized.connect(_layout_journey_drawer)
	_layout_journey_drawer()

func _layout_journey_drawer() -> void:
	if not nearby_panel: return
	var root := $HUD/SafeArea/Root as Control
	if city_map and is_instance_valid(city_map.dock):
		nearby_panel.set_available_space(root.size.y - city_map.dock.position.y + 8,
			maxf(44, city_map.dock.position.y - CityMapView.CONTENT_TOP - 16))
		return
	if not journey_footer: return
	var footer_height := maxf(48, journey_footer.get_combined_minimum_size().y)
	journey_footer.offset_top = -footer_height
	journey_footer.offset_bottom = 0
	var reserved_top := top_panel.position.y + maxf(top_panel.size.y, top_panel.get_combined_minimum_size().y) + 12
	nearby_panel.set_available_space(footer_height + 8, root.size.y - reserved_top - footer_height - 8)

func _set_nearby_open(open: bool) -> void:
	if city_map: return
	if not nearby_panel: return
	_reset_gesture()
	if not open: _clear_farm_selection()
	nearby_panel.visible = open
	if neighbours_toggle:
		neighbours_toggle.set_pressed_no_signal(open)
		neighbours_toggle.icon = GameUi.icon("chevron-down" if open else "users-round")
		neighbours_toggle.tooltip_text = "Close nearby panel" if open else "Nearby farmers"
	_layout_journey_drawer()
	_camera_dirty = true

func _clear_farm_selection() -> void:
	if _focus_tween and not _hold_motion: _focus_tween.kill()
	_clear_city_player()
	if nearby_panel:
		nearby_panel.clear_focus()
		nearby_panel.show_group([])
	if farm_markers: farm_markers.selected_id = ""
	if farm_overlay: farm_overlay.hide()
	UiState.write({"selected_farm_id": ""})
	_camera_dirty = true

func is_back_navigation_locked() -> bool:
	if city_map and city_map.consume_back(): return true
	if _relocation_mode:
		_cancel_relocation()
		return true
	if farm_markers and ((nearby_panel and nearby_panel.visible) or not farm_markers.selected_id.is_empty()):
		_clear_farm_selection()
		if nearby_panel: _set_nearby_open(false)
		return true
	return false

func _open_place(id: String) -> void:
	if AppRouter.top_instance() != null or not Net or not Net.session: return
	if not PlaceCatalog.available(id, Net.session.state): return
	AppRouter.open_instance(AppRouter.PLACE, {"place_id": id, "session": Net.session})

func _anchor_self_to_farm(center: Vector2) -> void:
	home_lat = center.x
	home_lng = center.y
	for list in [_pawns, _spawn_queue]:
		for p in list:
			if p.cohort == "self":
				p.lat = center.x
				p.lng = center.y
	_reposition_pawns()

func _build_map_controls() -> void:
	if _map_controls_built: return
	_map_controls_built = true
	var rail := side_toolbar.get_node("VBox")
	side_toolbar.offset_top = 58
	rail.add_theme_constant_override("separation", 8)
	top_panel.custom_minimum_size = Vector2(150, 68)
	nearby_count.visible = false
	region_title.add_theme_font_size_override("font_size", 16)
	edit_avatar_btn.custom_minimum_size = Vector2(44, 44)
	edit_avatar_btn.icon = GameUi.icon("user-round")
	edit_avatar_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	edit_avatar_btn.get_parent().get_node("EditLabel").visible = false
	for spec in [["plus", "Zoom in", 1.0], ["minus", "Zoom out", -1.0]]:
		var b := GameUi.button(spec[0], "", spec[1])
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.pressed.connect(func(): _tween_zoom(zoom + float(spec[2])))
		rail.add_child(b)
	_zoom_label = GameUi.label(L10n.format_text("Zoom %.0f", zoom), 11, GameUi.BLUE)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rail.add_child(_zoom_label)
	var home_button := GameUi.button("locate-fixed", "", "Focus my farm")
	home_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	home_button.pressed.connect(_focus_own_farm)
	rail.add_child(home_button)

func _focus_own_farm(highlight := true) -> void:
	if _relocation_mode:
		if _relocation_session != null and FarmPlacement.is_valid(_relocation_session.location):
			fly_to(float(_relocation_session.location.lat), float(_relocation_session.location.lng))
		return
	if farm_markers == null or not farm_markers.points.has("self"): return
	_clear_city_player()
	var point: Dictionary = farm_markers.points.self
	var own_region_id: String = point.bp.region_id
	if city_map:
		var own_city := FarmRegions.load_default().region(own_region_id)
		var farm_center: Vector2 = point.bp.overlay.center
		var far := not city_detail_visible() or MapGeoMath.geo_to_world(farm_center.x, farm_center.y, center_lat, center_lng).length() > 50000.0
		if CityMapData.has_city(own_region_id) and not own_city.is_empty(): _switch_city(own_city)
		if far:
			UiState.write({"selected_farm_id": ""})
			farm_markers.selected_id = ""
			# 飞行途中会跨过低 zoom 门槛（那里清选中），高亮等落地再给。
			_fly_to(farm_center.x, farm_center.y, 16.0, city_bearing, func():
				if highlight and farm_markers: farm_markers.selected_id = "self")
			return
	elif own_region_id != str(region.get("id", "")):
		var own_region := FarmRegions.load_default().region(own_region_id)
		if not own_region.is_empty():
			FarmRegions.save_choice(own_region_id)
			enter_street_mode(own_region)
	if nearby_panel:
		nearby_panel.clear_focus()
		nearby_panel.show_group([])
	UiState.write({"selected_farm_id": ""})
	farm_markers.selected_id = "self" if highlight else ""
	_focus_blueprint(point.bp)
	if not highlight and farm_overlay: farm_overlay.hide()

func _journey_area() -> Rect2:
	var root := $HUD/SafeArea/Root as Control
	var top := maxf(130, top_panel.position.y + top_panel.size.y + 16)
	var bottom := journey_footer.position.y - 48 if journey_footer else root.size.y - 96
	return Rect2(4, top, root.size.x - 8, maxf(0, bottom - top))

func _focus_journey_map(animate: bool) -> void:
	if not journey_map or not journey_map.streets: return
	var area := _journey_area()
	if area.size.x < 120 or area.size.y < 100: return
	_reset_gesture()
	_zoom_elastic = 0.0
	var origin := MapGeoMath.geo_to_world(home_lat, home_lng, anchor_lat, anchor_lng)
	var bounds := AABB(origin, Vector3.ZERO)
	for id in journey_map.streets.entrances:
		bounds = bounds.expand(origin + journey_map.streets.offset_for(id))
	var previous_transform := cam.transform
	var previous_fov := cam.fov
	var distance := MapGeoMath.cam_distance_m(_map_logical_height(), MAP_FOV_DEG, home_lat, 16.0)
	var heading := Vector3(sin(deg_to_rad(bearing)), 0, -cos(deg_to_rad(bearing)))
	cam.position = origin - heading * distance * sin(deg_to_rad(pitch)) + Vector3.UP * distance * cos(deg_to_rad(pitch))
	cam.look_at(origin, heading)
	cam.fov = MAP_FOV_DEG
	# Fit the complete labels; derive the geographic pose before touching the map bridge.
	var inset := Rect2(area.position + Vector2(54, 28), area.size - Vector2(108, 88))
	preload("res://modules/farm/farm_camera.gd").fit(cam, bounds, Rect2(inset.position + journey_map.global_position, inset.size))
	var target: Vector3 = Plane(Vector3.UP, 0).intersects_ray(cam.position, -cam.basis.z)
	var fitted_distance := cam.position.distance_to(target)
	cam.transform = previous_transform
	cam.fov = previous_fov
	var target_lat := anchor_lat - target.z / MapGeoMath.M_PER_DEG_LAT
	var target_lng := anchor_lng + target.x / (MapGeoMath.M_PER_DEG_LAT * cos(deg_to_rad(anchor_lat)))
	var target_zoom := clampf(16.0 + log(distance / fitted_distance) / log(2.0), STREET_ZOOM_MIN, STREET_ZOOM_MAX)
	var from_lat := center_lat
	var from_lng := center_lng
	var from_zoom := zoom
	set_pan_bounds(home_lat, home_lng, 450)
	if animate:
		center_lat = from_lat
		center_lng = from_lng
		_focus_tween = create_tween()
		_focus_tween.tween_method(func(t: float):
			center_lat = lerpf(from_lat, target_lat, t)
			center_lng = lerpf(from_lng, target_lng, t)
			_set_zoom(lerpf(from_zoom, target_zoom, t)), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		center_lat = target_lat
		center_lng = target_lng
		_set_zoom(target_zoom)

func _focus_blueprint(bp: FarmBlueprint) -> void:
	if bp.overlay.is_empty(): return
	var center: Vector2 = bp.overlay.center
	if farm_markers and journey_footer and city_map == null:
		var root := $HUD/SafeArea/Root as Control
		var bottom := nearby_panel.position.y - 8 if nearby_panel.visible else journey_footer.position.y - 8
		var desired := root.global_position + Vector2(root.size.x * 0.5, (110 + bottom) * 0.5 + 22)
		var under_center = _ground_point(get_viewport().get_visible_rect().size * 0.5)
		var under_marker = _ground_point(desired)
		if under_center is Vector3 and under_marker is Vector3:
			var shift: Vector3 = under_center - under_marker
			center += Vector2(-shift.z / MapGeoMath.M_PER_DEG_LAT, shift.x / (MapGeoMath.M_PER_DEG_LAT * cos(deg_to_rad(center.x))))
	var from_lat := center_lat
	var from_lng := center_lng
	# Browsing bounds are independent of placement / relocation bounds.
	if city_map: _city_bounds(); _set_zoom(16.0)
	else: set_pan_bounds(center.x, center.y, 450)
	center_lat = from_lat
	center_lng = from_lng
	_fling_vel = Vector3.ZERO
	if _focus_tween: _focus_tween.kill()
	_focus_tween = create_tween()
	_focus_tween.tween_method(func(t: float):
		center_lat = lerpf(from_lat, center.x, t)
		center_lng = lerpf(from_lng, center.y, t)
		_camera_dirty = true, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _sync_farm_markers() -> void:
	if _relocation_mode: return
	if farm_markers == null: return
	if farm_markers.points.has("self") and Net and Net.session:
		farm_markers.points.self.plots = (Net.session.state.get("cells", {}) as Dictionary).size()
	var root := $HUD/SafeArea/Root as Control
	_setup_journey_map()
	var bottom := nearby_panel.position.y - 8 if nearby_panel and nearby_panel.visible else journey_footer.position.y - 8 if journey_footer else root.size.y - 24
	if city_map:
		farm_markers.city_zoom = zoom
		farm_markers.low_detail = not city_detail_visible()
		if not farm_markers.projector.is_valid(): farm_markers.projector = geo_to_screen
		bottom = city_map.info.position.y - 8 if city_map.info.visible else city_map.dock.position.y - 8
		if nearby_panel and nearby_panel.visible: bottom = minf(bottom, nearby_panel.position.y - 8)
	var marker_top := CityMapView.CONTENT_TOP if city_map else 110.0
	farm_markers.sync(cam, anchor_lat, anchor_lng, Rect2(0, marker_top, root.size.x, maxf(0, bottom - marker_top)))
	if journey_map:
		side_toolbar.hide()
		journey_map.hide()
		farm_markers.show()
		var fallback := map == null or _header_locked
		for control in journey_camera_controls: control.visible = city_map == null
		journey_backdrop.hide()
		if fallback:
			get_viewport().transparent_bg = false
			var environment: Environment = $WorldEnvironment.environment
			if environment:
				environment.background_mode = Environment.BG_COLOR
				environment.background_color = Color("d9e7d3")
			farm_overlay.hide()
			region_title.text = str(region.get("name", "Neighbourhood"))
			location_status.text = "Farm map"
			_zoom_label.hide()
	_update_pawns(_cam_distance())

func _connect_farm_service() -> bool:
	if not Net or not Net.session: return false
	if Net.booting: await Net.booted
	if not Net.logged_in(): await Net.boot()
	return Net.logged_in()

func _open_my_farm() -> void:
	if _relocation_mode: return
	if _opening_farm or AppRouter.top_instance() != null: return
	_opening_farm = true
	if my_farm_btn: my_farm_btn.disabled = true
	var connected := await _connect_farm_service()
	if connected and (not Net.session.has_farm() or Net.session.offline):
		connected = await Net.session.refresh()
	_opening_farm = false
	if my_farm_btn: my_farm_btn.disabled = false
	if _server_has_no_farm():
		_show_farm_selection()
		return
	if not connected or not Net.session.has_farm():
		location_status.text = "Could not connect. Try again."
		return
	if AppRouter.top_instance() != null: return
	_farm_choice = _resolve_farm_choice()
	_clear_farm_selection()
	AppRouter.open_instance(AppRouter.FARM, _farm_choice)


## 服务端拿不到就落到随包样例（PRD §11.2）：D4 所需的两座系统农场不能被断网卡住。
func _refresh_nearby() -> void:
	if _relocation_mode: return
	_nearby_generation += 1
	var generation := _nearby_generation
	var region_id := str(region.get("id", ""))
	_nearby_region = region_id
	var res := {"ok": false}
	if Net and Net.logged_in():
		res = await Net.nearby(region_id)
	if farm_markers == null or generation != _nearby_generation:
		return
	if res.get("ok", false):
		_nearby_from_presets = false
		_nearby_entries = res.entries
		if nearby_panel: nearby_panel.set_entries(_nearby_entries, int(res.count), false)
	else:
		_nearby_from_presets = true
		var fallback := PresetSnapshots.entries(region_id)
		_nearby_entries = fallback
		if nearby_panel: nearby_panel.set_entries(fallback, fallback.size(), true)
	_clear_missing_farms(_nearby_entries.map(func(entry): return str(entry.farm_id)))
	_load_farm_locations(generation)

func _load_farm_locations(generation: int) -> void:
	for entry in _nearby_entries:
		var id := str(entry.farm_id)
		var snap: Dictionary = _snapshots.get(id, {})
		if snap.is_empty() and not _nearby_from_presets and Net and Net.logged_in():
			var response: Dictionary = await Net.snapshot(id)
			if response.get("ok", false): snap = response.snapshot
		if snap.is_empty(): snap = PresetSnapshots.snapshot(id)
		if generation != _nearby_generation or not is_inside_tree(): return
		if not snap.is_empty() and str(snap.get("farm_id", "")) == id:
			_snapshots[id] = snap
			_place_farm(id, snap)
			if nearby_panel: nearby_panel.set_thumbnail(snap)

func _clear_missing_farms(ids: Array) -> void:
	if farm_markers: farm_markers.remove_missing(ids)
	for pawn in _pawns.duplicate():
		if str(pawn.cohort).begins_with("farm:") and not ids.has(str(pawn.cohort).trim_prefix("farm:")):
			pawn.node.queue_free()
			_pawns.erase(pawn)
	_spawn_queue = _spawn_queue.filter(func(pawn): return not str(pawn.cohort).begins_with("farm:") or ids.has(str(pawn.cohort).trim_prefix("farm:")))

func _place_farm(id: String, snap: Dictionary) -> void:
	if not snap.has("region_id") or str(snap.region_id) != str(region.get("id", "")):
		if farm_markers:
			farm_markers.remove_missing(farm_markers.points.keys().filter(func(key): return key != id))
		return
	if farm_markers == null or farm_markers.points.has(id): return
	var bp := FarmBlueprint.load_choice(snap)
	if bp == null or bp.overlay.is_empty(): return
	bp = bp.with_location(snap.get("location", {}))
	var ref := str(snap.get("avatar_ref", "seed:unknown"))
	farm_markers.put(id, bp, SeededOutfit.short_name(ref), false, ref)
	farm_markers.points[id].plots = (snap.unlocked_cell_ids as Array).size() if snap.has("unlocked_cell_ids") else 12 if int(snap.get("beds_unlocked", 3)) == 4 else 9
	# Owners start as cached portraits. Only an explicit selection builds a rig.

func _select_city_player(id: String) -> void:
	if not city_map or not farm_markers or id == "self" or not farm_markers.points.has(id): return
	var was_selected := farm_markers.selected_id == id
	_clear_farm_selection()
	city_map.dismiss_overlays()
	if was_selected: return
	farm_markers.selected_id = id
	var entry: Dictionary = farm_markers.points[id]
	var point: Vector2 = entry.center
	_spawn_queue.push_front({"lat": point.x, "lng": point.y,
		"cfg": SeededOutfit.config_for(str(entry.avatar_ref)), "anim": "idle", "cohort": "farm:" + id})
	# 与 POI 一致的底部详情卡：头像 + 名字 + “拜访农场”跳转按钮（反馈 round 9）。
	var owner := str(entry.owner_name) if str(entry.avatar_ref).is_empty() else SeededOutfit.short_name(str(entry.avatar_ref))
	city_map.select_player({"id": "player:" + id, "farm_id": id, "kind": "player", "name": owner},
		farm_markers.portrait_texture(id))
	_camera_dirty = true

## 城市地图玩家卡上的“拜访农场”：拉快照进只读访客实例（空间跳转）。
func _on_city_visit_requested(farm_id: String) -> void:
	if farm_id.is_empty(): return
	var snap: Dictionary = _snapshots.get(farm_id, {})
	if snap.is_empty() and not _nearby_from_presets and Net and Net.logged_in():
		var r: Dictionary = await Net.snapshot(farm_id)
		if r.get("ok", false): snap = r.snapshot
	if snap.is_empty(): snap = PresetSnapshots.snapshot(farm_id)
	if snap.is_empty() or str(snap.get("farm_id", "")) != farm_id:
		if city_map: city_map.status.text = L10n.text("Farm unavailable right now")
		return
	_snapshots[farm_id] = snap
	var bp := FarmBlueprint.load_choice(snap)
	if bp == null:
		if city_map: city_map.status.text = L10n.text("Farm unavailable right now")
		return
	bp = bp.with_location(snap.get("location", {}))
	AppRouter.open_instance(AppRouter.FARM, {"visitor": true, "snapshot": snap, "blueprint": bp})

func _clear_city_player() -> void:
	_spawn_queue = _spawn_queue.filter(func(p): return not str(p.cohort).begins_with("farm:"))
	for pawn in _pawns.duplicate():
		if str(pawn.cohort).begins_with("farm:"):
			pawn.node.hide()
			pawn.node.queue_free()
			_pawns.erase(pawn)
	if farm_markers: farm_markers.expanded_avatar_id = ""

## 选中一张卡：先要线上快照，失败再看随包有没有这座；都没有就明说不可用。
func _on_farm_focused(farm_id: String) -> void:
	UiState.write({"selected_farm_id": farm_id})
	if farm_markers: farm_markers.selected_id = farm_id
	if farm_overlay: farm_overlay.visible = false
	var snap: Dictionary = _snapshots.get(farm_id, {})
	if snap.is_empty() and not _nearby_from_presets and Net and Net.logged_in():
		var r: Dictionary = await Net.snapshot(farm_id)
		if r.get("ok", false):
			snap = r.snapshot
	if snap.is_empty():
		snap = PresetSnapshots.snapshot(farm_id)
	if nearby_panel == null or nearby_panel.focused_id != farm_id:
		return   # 等待期间用户换了卡
	if snap.is_empty() or str(snap.get("farm_id", "")) != farm_id:
		nearby_panel.set_preview_unavailable()
	else:
		_snapshots[farm_id] = snap
		nearby_panel.set_preview(snap)
		_place_farm(farm_id, snap)
		if farm_markers and farm_markers.points.has(farm_id):
			farm_markers.selected_id = farm_id
			_focus_blueprint(farm_markers.points[farm_id].bp)

var _snapshots: Dictionary = {}

## 进独立访客实例：只读、挥手、印章；不复用主人的耕作工具栏（PRD §3.3）。
func _on_visit_requested(farm_id: String) -> void:
	if nearby_panel == null or nearby_panel.focused_id != farm_id: return
	var snap: Dictionary = _snapshots.get(farm_id, {})
	if snap.is_empty() or str(snap.get("farm_id", "")) != farm_id:
		return
	var bp := FarmBlueprint.load_choice(snap)
	if bp == null:
		nearby_panel.set_preview_unavailable()
		return
	bp = bp.with_location(snap.get("location", {}))
	AppRouter.open_instance(AppRouter.FARM, {"visitor": true, "snapshot": snap, "blueprint": bp})

func _on_street_visit_requested(farm_id: String) -> void:
	_on_visit_requested(farm_id)


func _minimum_zoom() -> float:
	return CITY_MIN_ZOOM if city_map else STREET_ZOOM_MIN if street_mode else 3.0

static func city_view_factor(z: float) -> float:
	return clampf((z - PITCH_FLAT_ZOOM) / (PITCH_FULL_ZOOM - PITCH_FLAT_ZOOM), 0.0, 1.0)

static func city_pitch_for(z: float) -> float:
	return CITY_PITCH * city_view_factor(z)

## 城市地图细节层（地标/POI/其他玩家/3D 角色）是否可见；低于门槛只剩城市气泡与自己的头像。
func city_detail_visible() -> bool:
	return city_map == null or zoom + _zoom_elastic >= CITY_DETAIL_ZOOM

func _city_bounds() -> void:
	# 城市地图可以无缝缩放到国家级、自由拖到任何地方：不钳平移范围（纬度 ±85° 由
	# _apply_world_delta 保证）。选址/搬家模式各自设置自己的范围，与此无关。
	if city_map: pan_bounds = Rect2()

## 地理坐标 → 视口像素（与 cam.unproject_position 同一坐标系；背后返回 null）。
## pitch=0 时用精确 Web Mercator：局部等距近似只在城市尺度准确，国家级会与底图错位。
## 全程标量 f64 运算——Vector2 是 float32，高 zoom 下 Mercator 差值会丢到十几像素。
func geo_to_screen(lat: float, lng: float) -> Variant:
	if pitch <= 0.01:
		var vp := get_viewport().get_visible_rect().size
		var scale := vp.y / _map_logical_height() * 512.0 * pow(2.0, zoom + _zoom_elastic)
		var dx := fposmod(MapGeoMath.mercator_x(lng) - MapGeoMath.mercator_x(center_lng) + 0.5, 1.0) - 0.5
		var dy := MapGeoMath.mercator_y(lat) - MapGeoMath.mercator_y(center_lat)
		var b := deg_to_rad(bearing)
		var sx := (dx * cos(b) + dy * sin(b)) * scale
		var sy := (-dx * sin(b) + dy * cos(b)) * scale
		return vp * 0.5 + Vector2(sx, sy)
	var world := MapGeoMath.geo_to_world(lat, lng, anchor_lat, anchor_lng)
	if cam.is_position_behind(world): return null
	return cam.unproject_position(world)

## —— 城市切换（spec 2026-09-23）——————————————————————————————————

## 已开通城市（regions.json 里有城市地图配置的）。
func city_regions() -> Array:
	var regions := FarmRegions.load_default()
	if regions == null: return []
	return regions.regions.filter(func(r): return CityMapData.has_city(str(r.get("id", ""))))

static func _bounds_contain(r: Dictionary, lat: float, lng: float, margin: float) -> bool:
	var b: Array = r.get("placement_bounds", [])
	if b.size() != 4: return false
	var dlat := (float(b[2]) - float(b[0])) * margin
	var dlng := (float(b[3]) - float(b[1])) * margin
	return lat >= float(b[0]) - dlat and lat <= float(b[2]) + dlat and lng >= float(b[1]) - dlng and lng <= float(b[3]) + dlng

## 中心点所在的已开通城市 id；当前城市享有外扩边界（滞回）。都不在就返回 ""。
static func city_at(regions: Array, lat: float, lng: float, current_id: String) -> String:
	for r in regions:
		if str(r.get("id", "")) == current_id and _bounds_contain(r, lat, lng, CITY_EXIT_MARGIN): return current_id
	for r in regions:
		if _bounds_contain(r, lat, lng, 0.0): return str(r.get("id", ""))
	return ""

## 屏幕中心当前是否落在（已激活的）城市里——标题据此决定显示城市名还是瓦片地名。
func in_active_city() -> bool:
	return zoom >= AUTO_SWITCH_ZOOM and city_at(city_regions(), center_lat, center_lng, str(region.get("id", ""))) == str(region.get("id", ""))

func _update_active_city(force := false) -> void:
	if _relocation_mode or _placement_mode or zoom < AUTO_SWITCH_ZOOM: return
	if _touch_count == 0 and _focus_tween and _focus_tween.is_running(): return # 飞行途中不切，落地再判
	if not force and Engine.get_process_frames() % 10 != 0: return
	var regions := city_regions()
	var id := city_at(regions, center_lat, center_lng, str(region.get("id", "")))
	if id.is_empty() or id == str(region.get("id", "")): return
	for r in regions:
		if str(r.id) == id: _switch_city(r)

## 进入国家/省级视野：清掉选中（其标记已让出），拉一次各城农场数给城市气泡。
func _update_city_detail() -> void:
	var detail := city_detail_visible()
	if detail == _last_city_detail: return
	_last_city_detail = detail
	if detail: return
	# 缩放/飞行途中跨过门槛：只清选中，不打断正在进行的相机动画。
	_hold_motion = true
	_clear_farm_selection()
	city_map.clear_selection()
	_hold_motion = false
	_refresh_city_counts()

func _refresh_city_counts() -> void:
	if _counts_fetched_ms >= 0 and Time.get_ticks_msec() - _counts_fetched_ms < 60000: return
	_counts_fetched_ms = Time.get_ticks_msec()
	var own_region := ""
	if farm_markers and farm_markers.points.has("self"): own_region = str(farm_markers.points.self.bp.region_id)
	for r in city_regions():
		var id := str(r.id)
		var count := PresetSnapshots.entries(id).size()
		if Net and Net.logged_in():
			var res: Dictionary = await Net.nearby(id)
			if not is_inside_tree(): return
			if res.get("ok", false): count = int(res.count)
		# 气泡口径 = 该城全部农场（含自己的）。
		city_farm_counts[id] = count + (1 if own_region == id else 0)

## 轻量切城：相机不动，只换 region、标题、地标居民与附近农场；写入城市选择（下次启动落在这里）。
func _switch_city(r: Dictionary) -> void:
	if not city_map or str(r.get("id", "")) == str(region.get("id", "")): return
	_clear_farm_selection()
	city_map.dismiss_overlays()
	region = r
	FarmRegions.save_choice(str(r.get("id", "")))
	city_map.region_changed()
	_refresh_nearby()

## 城市面板/城市气泡：飞到该城总览。
func fly_to_city(id: String) -> void:
	for r in city_regions():
		if str(r.id) != id: continue
		var overview: Dictionary = CityMapData.city(id).get("overview", {})
		_clear_farm_selection()
		if city_map: city_map.dismiss_overlays()
		_switch_city(r)
		_fly_to(float(overview.get("lat", r.center[0])), float(overview.get("lng", r.center[1])),
			float(overview.get("zoom", 11.0)), float(overview.get("bearing", 0.0)))
		return

## van Wijk 飞行：先拉远、平移、再拉近。任何新触摸都会打断（_focus_tween 被按下事件 kill）。
func _fly_to(lat: float, lng: float, target_zoom: float, target_bearing: float, on_land := Callable()) -> void:
	_reset_gesture()
	_city_bounds()
	if _focus_tween: _focus_tween.kill()
	var vp := get_viewport().get_visible_rect().size
	var view_w := vp.x * _map_logical_height() / maxf(1.0, vp.y)
	var flight := MapFlight.plan(center_lat, center_lng, zoom, lat, lng, target_zoom, view_w)
	var from_bearing := city_bearing
	var turn := wrapf(target_bearing - from_bearing, -180.0, 180.0)
	_focus_tween = create_tween()
	_focus_tween.tween_method(func(t: float):
		var p := flight.sample(t)
		center_lat = lat if t >= 1.0 else p.x
		center_lng = lng if t >= 1.0 else p.y
		city_bearing = from_bearing + turn * t
		bearing = city_bearing
		_set_zoom(target_zoom if t >= 1.0 else p.z)
		_camera_dirty = true, 0.0, 1.0, flight.duration()).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if on_land.is_valid(): _focus_tween.tween_callback(on_land)

func _install_city_map() -> void:
	if _relocation_mode or _placement_mode or not CityMapData.has_city(str(region.get("id", ""))): return
	if city_map: return
	_clear_farm_selection()
	# The city uses geographic markers directly, with no nearby list or visit route.
	for control in [nearby_panel, journey_footer, journey_map, journey_backdrop]:
		if is_instance_valid(control):
			control.get_parent().remove_child(control)
			control.queue_free()
	nearby_panel = null
	journey_footer = null
	journey_map = null
	journey_backdrop = null
	neighbours_toggle = null
	journey_camera_controls.clear()
	city_map = CityMapView.new()
	city_map.host = self
	$HUD/SafeArea/Root.add_child(city_map)
	city_map.sheet_opened.connect(_clear_farm_selection)
	city_map.action_requested.connect(_city_action)
	city_map.focus_requested.connect(func(entry):
		_reset_gesture()
		_city_bounds()
		fly_to(float(entry.lat), float(entry.lng))
		_set_zoom(14.7 if entry.kind == "landmark" else 16.0))
	city_map.resident_requested.connect(func(entry):
		if Net and Net.session and ResidentCast.present(str(entry.place), Net.session.state).has(str(entry.id)):
			AppRouter.open_instance(AppRouter.PLACE, {"place_id": str(entry.place), "resident_id": str(entry.id), "target": "resident", "session": Net.session}))
	city_map.player_visit_requested.connect(_on_city_visit_requested)
	city_map.city_requested.connect(fly_to_city)
	city_map.player_deselected.connect(_clear_farm_selection)
	for control in [top_panel, side_toolbar, my_farm_btn, journey_footer]:
		if is_instance_valid(control):
			_city_hidden[control] = control.visible
			control.hide()
	farm_markers.city_mode = true
	for child in $HUD/SafeArea/Root.get_children():
		if child is LanguageButton:
			_city_hidden[child] = child.visible
			child.hide()
	_city_action("map")
	_layout_journey_drawer()

func _remove_city_map() -> void:
	if city_map:
		_clear_farm_selection()
		city_map.queue_free()
		city_map = null
		if map: map.set_city_style(false)
		for control in _city_hidden:
			if is_instance_valid(control): control.visible = bool(_city_hidden[control])
		_city_hidden.clear()
		if farm_markers:
			farm_markers.city_mode = false
			farm_markers.projector = Callable()
			farm_markers.low_detail = false

func _city_action(action: String) -> void:
	_reset_gesture()
	match action:
		"map":
			_clear_farm_selection()
			if city_map: city_map.dismiss_overlays()
			_city_bounds()
			var overview: Dictionary = CityMapData.city(str(region.get("id", ""))).get("overview", {})
			city_bearing = float(overview.get("bearing", 0.0))
			bearing = city_bearing
			pitch = 35.0
			fly_to(float(overview.get("lat", region.get("center", [0, 0])[0])), float(overview.get("lng", region.get("center", [0, 0])[1])))
			_set_zoom(float(overview.get("zoom", 11.0)))
		"north":
			city_bearing = 0.0
			bearing = 0.0
			_camera_dirty = true
		"farm": _open_my_farm()
		"outfit": AppRouter.go_to_dressing()
		"city":
			if city_map: city_map.toggle_city_panel()
			else: AppRouter.go_to_city_select()
		"recenter": _focus_own_farm(false)
