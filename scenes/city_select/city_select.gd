extends Control
## 首次进入：手选城市为默认路径；「使用当前城市」只请求一次前台大致定位（PRD §4.3 / §11.3）。

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
	regions = FarmRegions.load_default()
	if regions == null:
		status.text = "缺少城市配置"
		return
	for r in regions.regions:
		var b := Button.new()
		b.text = str(r.name)
		b.custom_minimum_size = Vector2(0, DesignTokens.BTN_PAD_V * 2 + DesignTokens.FONT_BODY)
		b.pressed.connect(choose.bind(str(r.id)))
		buttons.add_child(b)
	use_current.pressed.connect(locate)
	status.text = ""

func region_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in buttons.get_children():
		if c is Button:
			out.append(c)
	return out

func choose(id: String) -> void:
	FarmRegions.save_choice(id)
	AppRouter.go_to_map()

func locate() -> void:
	if _locating: # 请求进行中：吞掉重复点击/重复调用，不重复 connect
		return
	if _bridge == null:
		_bridge = MapBridgeFactory.make()
	if _bridge == null:
		status.text = "此设备无法定位，请手选城市"
		return
	_locating = true
	_located = false
	use_current.disabled = true
	status.text = "正在定位…"
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
	status.text = "定位超时，请手选城市"
	_cancel_locate()

## 断开定位订阅并把 UI 收回到可再次点按的状态。is_connected 判断是因为迟到的
## 信号可能在同一帧已经靠 ONE_SHOT 自动断开，这里不能无条件 disconnect。
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
