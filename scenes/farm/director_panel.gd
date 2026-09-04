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

const HOLD_S := 3.0
## 480 倍 = 3 分钟走完一个玩家日（24×60÷480）。
const SCALES := [1, 60, 480]
const CONDITIONS := ["sunny", "rain", "wind"]
const DENIED_TEXT := "This farm is not a QA instance"

var _status: Label

func _ready() -> void:
	theme_type_variation = &"BottomSheet"
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -168.0
	offset_left = 8.0
	offset_right = -8.0
	offset_bottom = -8.0
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Director"
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	box.add_child(title)
	box.add_child(_row("Speed", SCALES.map(func(s): return "%dx" % s),
		func(i): _send("qa_set_clock", {"scale": SCALES[i]})))
	box.add_child(_row("Skip", ["+1 day", "+2 days"],
		func(i): _send("qa_skip_days", {"days": i + 1})))
	box.add_child(_row("Weather", ["Sunny", "Rain", "Wind"],
		func(i): _send("qa_set_weather", {"day": CONDITIONS[i]})))
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

func _row(label: String, options: Array, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = label
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 68.0
	l.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	row.add_child(l)
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.theme_type_variation = &"RailButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.custom_minimum_size.y = 40.0
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		b.pressed.connect(func(): on_pick.call(i))
		row.add_child(b)
	return row

func _send(type: String, payload: Dictionary) -> void:
	_status.text = ""
	emit_signal("command_requested", type, payload)

## 把服务端的答复显示出来。403 必须明说，否则 QA 会以为面板坏了。
func report(ok: bool, code: String) -> void:
	if ok:
		_status.text = "Applied"
	elif code == "QA_ONLY":
		_status.text = DENIED_TEXT
	else:
		_status.text = "Rejected: %s" % code

func toggle() -> void:
	visible = not visible
	if visible:
		_status.text = ""
