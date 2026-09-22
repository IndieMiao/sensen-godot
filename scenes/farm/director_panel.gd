class_name DirectorPanel
extends PanelContainer
## 导演模式 v1：时间倍率、跳日、指定田况。
##
## 三者都**发命令给服务端**，客户端不本地加速时间——本地跑快会让玩家看到作物熟了、
## 服务端却说没熟。
##
## 入口是长按标题三秒，不额外占屏幕：QA 面板不该在正式玩家的界面上留按钮。
## 服务端对非白名单农场返回 403 QA_ONLY，面板据此明说「此农场非 QA 实例」，
## 而不是静默什么都不发生。

signal command_requested(type: String, payload: Dictionary)
signal closed()

const HOLD_S := 3.0
## 480 倍 = 3 分钟走完一个玩家日（24×60÷480）。
const SCALES := [1, 60, 480]
const CONDITIONS := ["sunny", "rain", "wind"]
const DENIED_TEXT := "This farm is not a QA instance"

var _status: Label
var _speed_buttons: Array[Button] = []
var _weather_buttons: Array[Button] = []

func _ready() -> void:
	theme_type_variation = &"BottomSheet"
	GameUi.register_modal(self)
	add_theme_stylebox_override("panel", GameUi.panel_style(14))
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -168.0
	offset_left = 8.0
	offset_right = -8.0
	offset_bottom = -8.0
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := GameUi.label(L10n.text("Director"), 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := GameUi.button("x", "", L10n.text("Close director"))
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)
	box.add_child(_row(L10n.text("Time rate"), SCALES.map(func(s): return "%dx" % s),
		func(i): _send("qa_set_clock", {"scale": SCALES[i]})))
	box.add_child(HSeparator.new())
	box.add_child(_row(L10n.text("Day skip"), [L10n.text("+1 day"), L10n.text("+2 days")],
		func(i): _send("qa_skip_days", {"days": i + 1})))
	box.add_child(HSeparator.new())
	box.add_child(GameUi.label(L10n.text("Weather"), 13))
	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 8)
	box.add_child(weather_row)
	for i in CONDITIONS.size():
		var b := GameUi.button(["sun", "cloud-rain", "wind"][i], [L10n.text("Sunny"), L10n.text("Rain"), L10n.text("Wind")][i], L10n.text("Set weather"))
		b.custom_minimum_size.y = 64
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _send("qa_set_weather", {"day": CONDITIONS[i]}))
		_weather_buttons.append(b)
		weather_row.add_child(b)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

func fit_height(area: Vector2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(minf(520, maxf(1, area.x - 8)), minf(maxf(348, get_combined_minimum_size().y), area.y - 72))
	position = Vector2((area.x - size.x) * 0.5, area.y - size.y - 4)

func _row(label: String, options: Array, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = label
	row.add_theme_constant_override("separation", 6)
	var symbol := GameUi.picture(GameUi.icon("clock-3" if label == L10n.text("Time rate") else "calendar-days"), 18)
	symbol.modulate = GameUi.INK
	row.add_child(symbol)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 60.0
	l.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	row.add_child(l)
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.theme_type_variation = &"RailButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.custom_minimum_size.y = 44.0
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		b.pressed.connect(func(): on_pick.call(i))
		row.add_child(b)
		if label == L10n.text("Time rate"): _speed_buttons.append(b)
	return row

func sync_state(state: Dictionary) -> void:
	var clock: Dictionary = state.get("clock", {})
	var scale := int((state.get("qa", {}) as Dictionary).get("scale", 1))
	var condition := str(clock.get("field_condition", "sunny"))
	for i in _speed_buttons.size():
		_speed_buttons[i].theme_type_variation = &"AccentButton" if SCALES[i] == scale else &"SecondaryButton"
	for i in _weather_buttons.size():
		_weather_buttons[i].theme_type_variation = &"ChoiceSelectedButton" if CONDITIONS[i] == condition else &"ChoiceButton"

func _send(type: String, payload: Dictionary) -> void:
	_status.text = ""
	emit_signal("command_requested", type, payload)

## 把服务端的答复显示出来。403 必须明说，否则 QA 会以为面板坏了。
## 403 时顺带把 player_id 亮出来：这是 QA 把自己加进服务器白名单的唯一途径——App 里
## 别处看不到它，而去库里翻「最近注册的匿名玩家」在多台测试机同时在线时根本分不清。
func report(ok: bool, code: String, player_id := "") -> void:
	if ok:
		_status.text = L10n.text("Applied")
	elif code == "QA_ONLY":
		_status.text = DENIED_TEXT if player_id.is_empty() else L10n.format_text("%s · player %s", [DENIED_TEXT, player_id])
	else:
		_status.text = L10n.format_text("Rejected: %s", code)

func toggle() -> void:
	visible = not visible
	if visible:
		_status.text = ""
