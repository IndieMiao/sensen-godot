extends Control
## 首次进入：手选城市为默认路径；「使用当前城市」只请求一次前台大致定位（PRD §4.3 / §11.3）。

## 3s 短于 Android 系统定位权限弹窗：新装机第一次点「使用当前城市」，
## start_location() 会先弹出系统权限对话框，没人能在 3s 内点掉它，超时会先显示
## 「定位超时，请手选城市」而对话框其实还开着——可恢复（弹窗关掉后再点一次就好），
## 但人工验收容易把这个误判成定位失败（2026-09-04 终审 I1）。不改这个值、也不碰
## MapBridge 接口：MapBridge 没有暴露"权限弹窗中"这个状态给上层（只有
## MapBridgeAndroid 内部私有的 _awaiting_permission），改了就要么破坏平台抽象，
## 要么让 city_select 反向依赖具体子类，两者都不值得为这条时序换。
const LOCATE_TIMEOUT_S := 3.0

var regions: FarmRegions
var _bridge: MapBridge = null
var _located := false
var _locating := false

@onready var buttons: VBoxContainer = %Buttons
@onready var use_current: Button = %UseCurrent
@onready var status: Label = %Status

static func pick_region(p_regions: Array, lat: float, lng: float, has_fix: bool, fallback := "") -> String:
	return FarmRegions.nearest_region_id(p_regions, lat, lng) if has_fix else fallback

func _ready() -> void:
	theme = GameUi.theme()
	var backdrop := ColorRect.new()
	backdrop.color = GameUi.PAPER
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	move_child(backdrop, 0)
	var background_path := "res://assets/ui/backgrounds/city-garden.png"
	if ResourceLoader.exists(background_path):
		var scenery := TextureRect.new()
		scenery.name = "Scenery"
		scenery.texture = load(background_path)
		scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scenery)
		move_child(scenery, 1)
	$SafeArea/VBox.add_theme_constant_override("separation", 12)
	$SafeArea/VBox/Title.text = "Choose a city"
	$SafeArea/VBox/Title.add_theme_font_size_override("font_size", 20)
	$SafeArea/VBox/Title.custom_minimum_size.y = 48
	buttons.add_theme_constant_override("separation", 12)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_outline_color", GameUi.PAPER)
	status.add_theme_constant_override("outline_size", 4)
	status.custom_minimum_size.y = 32
	regions = FarmRegions.load_default()
	if regions == null:
		status.text = "Missing city configuration"
		return
	for r in regions.regions:
		var b := Button.new()
		b.text = str(r.name)
		b.icon = GameUi.icon("map-pin")
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(choose.bind(str(r.id)))
		buttons.add_child(b)
	use_current.pressed.connect(locate)
	use_current.icon = GameUi.icon("locate-fixed")
	use_current.custom_minimum_size.y = 54
	status.text = ""

func region_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in buttons.get_children():
		if c is Button:
			out.append(c)
	return out

func choose(id: String) -> void:
	if _locating: _cancel_locate()
	FarmRegions.save_choice(id)
	AppRouter.go_to_map()

func locate() -> void:
	if _locating: # 请求进行中：吞掉重复点击/重复调用，不重复 connect
		return
	if _bridge == null:
		_bridge = MapBridgeFactory.make()
	if _bridge == null:
		status.text = "This device can't locate you — please choose a city manually"
		return
	_locating = true
	_located = false
	use_current.disabled = true
	status.text = "Locating…"
	_bridge.location_update.connect(_on_location, CONNECT_ONE_SHOT)
	_bridge.start_location()
	# CONNECT_ONE_SHOT 只在信号真正触发后才会自动断开；UI 层「放弃」（超时）
	# 不会断开订阅——迟到的定位仍会静默把用户带走，所以超时必须走 _cancel_locate()
	# 手动断开，不能只改 UI 文案。
	get_tree().create_timer(LOCATE_TIMEOUT_S).timeout.connect(_on_locate_timeout)

## 定位超时：还没等到 _on_location 就放弃。真正取消订阅（不是只改 UI），
## 否则迟到的信号仍会触发 _on_location 把用户带走，且重新点按会重复 connect 报错。
func _on_locate_timeout() -> void:
	if _located:
		return
	status.text = "Location timed out — please choose a city manually"
	_cancel_locate()

## 断开定位订阅并把 UI 收回到可再次点按的状态。is_connected 判断是因为迟到的
## 信号可能在同一帧已经靠 ONE_SHOT 自动断开，这里不能无条件 disconnect。
## MapBridge 按设计没有 stop_location()（见 map_bridge.gd），所以这里只能停止
## 监听，停不掉底层平台真的还在跑的定位请求——名字叫"cancel"但做的是"unsubscribe"。
func _cancel_locate() -> void:
	if _bridge and _bridge.location_update.is_connected(_on_location):
		_bridge.location_update.disconnect(_on_location)
	_locating = false
	use_current.disabled = false

func _on_location(lat: float, lng: float, _accuracy: float) -> void:
	if _located:
		return
	_located = true
	_locating = false
	choose(pick_region(regions.regions, lat, lng, true))

func _process(_dt: float) -> void:
	if _bridge:
		_bridge.poll()
