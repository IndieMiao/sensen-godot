extends Control
## 首次进入：手选城市为默认路径；「使用当前城市」只请求一次前台大致定位（PRD §4.3 / §11.3）。

const LOCATE_TIMEOUT_S := 3.0

var regions: FarmRegions
var _bridge: MapBridge = null
var _located := false

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
	if _bridge == null:
		_bridge = MapBridgeFactory.make()
	if _bridge == null:
		status.text = "此设备无法定位，请手选城市"
		return
	use_current.disabled = true
	status.text = "正在定位…"
	_bridge.location_update.connect(_on_location, CONNECT_ONE_SHOT)
	_bridge.start_location()
	get_tree().create_timer(LOCATE_TIMEOUT_S).timeout.connect(func():
		if not _located:
			use_current.disabled = false
			status.text = "定位超时，请手选城市")

func _on_location(lat: float, lng: float, _accuracy: float) -> void:
	if _located:
		return
	_located = true
	choose(pick_region(regions.regions, lat, lng, true))

func _process(_dt: float) -> void:
	if _bridge:
		_bridge.poll()
