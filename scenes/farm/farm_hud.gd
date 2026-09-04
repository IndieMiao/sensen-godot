class_name FarmHud
extends Control
## 农场 HUD。**全部新元素都在底部与右侧**——顶栏只有 Leave Farm 与路名，在 360 宽的
## 安全区里已经没有余量，再塞东西就会重演 2026-09-04 真机上标题被按钮盖住那次。
##
## 顶部长期只显示**金币**：XP 与关系不进 HUD（PRD §7.1 L472），它们属于手账。
##
## 界面文案一律英文。

signal tool_selected(tool: String)
signal crop_selected(crop: String)
signal row_tool_toggled(on: bool)
signal wave_pressed()
signal stamp_pressed()

const CROPS := ["R", "L", "C", "H"]
## 底栏一行放 4 个 → 每个约 86 px，"Lettuce" 这样的 7 字词正好放得下。
const CROP_LABEL := {"R": "Radish", "L": "Lettuce", "C": "Carrot", "H": "Chamom"}
## 触摸目标：主题给 Button 定的是 48 单位，RailButton 更紧凑，这里显式兜到 44。
const BUTTON_H := 44.0
## 标签一律 ≤5 字符：360 宽的一行放 5 个按钮，长词会把同行的邻居挤出屏幕。
const TOOLS := [
	{"id": "clear", "label": "Clear"},
	{"id": "till", "label": "Till"},
	{"id": "sow", "label": "Sow"},
	{"id": "care", "label": "Care"},
	{"id": "harvest", "label": "Reap"},
]
const CONDITION_LABEL := {"sunny": "Sunny", "rain": "Rain", "wind": "Wind"}
const ACTION_VERB := {"clear": "Clearing", "till": "Tilling", "sow": "Sowing", "care": "Tending", "harvest": "Harvesting"}
## 服务端拒绝码 → 玩家能懂的一句话。没列的直接显示码，至少不是静默。
const REJECT_TEXT := {
	"WRONG_STATE": "That plot isn't ready for this step",
	"NOT_RIPE": "Not ripe yet",
	"WRONG_CARE": "Wrong care for today's weather",
	"INSUFFICIENT_ITEMS": "Not enough seeds",
	"INSUFFICIENT_FUNDS": "Not enough coins",
	"CELL_LOCKED": "This bed isn't unlocked yet",
	"CHAPTER_LOCKED": "Not available in this chapter yet",
	"OFFLINE": "You're offline",
	"UNKNOWN_CELL": "That plot isn't part of this farm",
	"CELL_NOT_CULTIVABLE": "That plot can't be farmed",
	"NOT_PREDICTED": "Rejected",
}
const TOAST_S := 2.5
const CARE_LABEL := {"sunny": "Water", "rain": "Drain", "wind": "Shelter"}

var tool := ""
var crop := "R"
var row_tool := false
var offline := false

var _coins: Label
var _condition: Label
var _timer_label: Label
var _banner: PanelContainer
var _tool_buttons: Dictionary = {}
var _crop_buttons: Dictionary = {}
var _row_button: Button
var _bottom: VBoxContainer
var _visitor_bar: HBoxContainer
var visitor := false
var _status: PanelContainer
var _status_label: Label
var _status_bar: ProgressBar
var _toast: PanelContainer
var _toast_label: Label
var _toast_left := 0.0
var _last_action_text := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_top_right()
	_build_banner()
	_build_bottom()
	_build_status()
	_refresh_buttons()

## 金币与田况靠**右上**，避开顶栏左侧的 Leave Farm 与居中的路名。
func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.name = "TopRight"
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -140.0
	box.offset_top = 60.0
	box.offset_right = -8.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_coins = _chip(box, "Coins 0")
	_condition = _chip(box, "Sunny · Water")
	_timer_label = _chip(box, "Next ripe --:--")
	# Row 是常驻模式开关，不是逐格工具。塞进工具行会变成 6 个按钮挤 344 px，
	# 于是每个只剩 57 px，"Clear" 就被省略号吃掉——所以它归到右上模式区。
	_row_button = Button.new()
	_row_button.text = "Row tool"
	_row_button.theme_type_variation = &"RailButton"
	_row_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	# 不加 clip_text：SHRINK_END 下它会把最小宽压到 0，按钮塌成 8 px 的一条。
	_row_button.custom_minimum_size = Vector2(96.0, BUTTON_H)
	_row_button.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_row_button.pressed.connect(_on_row)
	box.add_child(_row_button)

func _chip(parent: Node, text: String) -> Label:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ChipPanel"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	panel.add_child(label)
	parent.add_child(panel)
	return label

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.name = "OfflineBanner"
	_banner.theme_type_variation = &"ToastPanel"
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 60.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	var l := Label.new()
	l.text = "Offline — read only"
	l.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	l.add_theme_color_override("font_color", DesignTokens.SURFACE)   # ToastPanel 是深底
	_banner.add_child(l)
	add_child(_banner)

## 底栏摆在**摇杆上方**、占满整宽。
##
## 先试过让底栏与摇杆并排（从 x=184 起），结果 168 px 塞六个按钮直接溢出屏幕右边——
## 和 2026-09-04 真机上标题被按钮盖住是同一类错误：横向预算不够却硬塞。摇杆在 Root
## 底部占 160×160（offset_top = -176），所以底栏的下沿必须停在 -180。
func _build_bottom() -> void:
	var box := VBoxContainer.new()
	box.name = "BottomBar"
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 8.0
	box.offset_right = -8.0
	box.offset_top = -280.0
	box.offset_bottom = -180.0
	box.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	add_child(box)
	_bottom = box

	var seeds := HBoxContainer.new()
	seeds.name = "SeedBar"
	seeds.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	box.add_child(seeds)
	for id in CROPS:
		var b := Button.new()
		b.text = CROP_LABEL[id]
		b.custom_minimum_size.y = BUTTON_H
		b.theme_type_variation = &"ChoiceButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true   # 兜底：字号/字体一变，宁可省略号也不要溢出屏幕
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		_tighten(b)
		b.pressed.connect(_on_crop.bind(id))
		seeds.add_child(b)
		_crop_buttons[id] = b

	var tools := HBoxContainer.new()
	tools.name = "ToolBar"
	tools.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	box.add_child(tools)
	for spec in TOOLS:
		var b := Button.new()
		b.text = spec.label
		b.custom_minimum_size.y = BUTTON_H
		b.theme_type_variation = &"RailButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		_tighten(b)
		b.pressed.connect(_on_tool.bind(str(spec.id)))
		tools.add_child(b)
		_tool_buttons[spec.id] = b


## 主题给 Button 的左右内边距是 16，一行五个按钮时「Reap」在真机字体下被裁成「Rea」。
## 工具与作物按钮收到 6，触摸高度靠 BUTTON_H 兜着不受影响。
static func _tighten(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := b.get_theme_stylebox(state)
		if sb == null:
			continue
		var dup := sb.duplicate() as StyleBox
		dup.content_margin_left = 6.0
		dup.content_margin_right = 6.0
		b.add_theme_stylebox_override(state, dup)

## 再点一次已选工具就退回移动模式——不给「取消」单独占一个按钮位。
func _on_tool(id: String) -> void:
	tool = "" if tool == id else id
	_refresh_buttons()
	emit_signal("tool_selected", tool)

func _on_crop(id: String) -> void:
	crop = id
	_refresh_buttons()
	emit_signal("crop_selected", crop)

func _on_row() -> void:
	row_tool = not row_tool
	_refresh_buttons()
	emit_signal("row_tool_toggled", row_tool)

func _refresh_buttons() -> void:
	for id in _tool_buttons:
		var b: Button = _tool_buttons[id]
		b.theme_type_variation = &"AccentButton" if id == tool else &"RailButton"
		b.disabled = offline
	for id in _crop_buttons:
		(_crop_buttons[id] as Button).theme_type_variation = \
			&"ChoiceSelectedButton" if id == crop else &"ChoiceButton"
	if _row_button:
		_row_button.theme_type_variation = &"AccentButton" if row_tool else &"RailButton"
		_row_button.disabled = offline

func set_offline(v: bool) -> void:
	offline = v
	_banner.visible = v
	_refresh_buttons()

func set_coins(n: int) -> void:
	_coins.text = "Coins %d" % n

func set_condition(cond: String) -> void:
	_condition.text = "%s · %s" % [
		CONDITION_LABEL.get(cond, cond), CARE_LABEL.get(cond, "Care")]

## 下一次成熟的倒计时。`now_ms` 必须是**服务端时间**——本地时钟不可信。
func set_next_ripe(cells: Dictionary, now_ms: int) -> void:
	_timer_label.text = "Next ripe %s" % format_countdown(next_ripe_ms(cells, now_ms))

## 最近一个还没熟的 ready_at 距现在多少毫秒；没有则 -1。已经熟了的返回 0。
static func next_ripe_ms(cells: Dictionary, now_ms: int) -> int:
	var best := -1
	for id in cells:
		var ready = (cells[id] as Dictionary).get("ready_at")
		if ready == null:
			continue
		var delta := int(ready) - now_ms
		if delta <= 0:
			return 0
		if best < 0 or delta < best:
			best = delta
	return best

static func format_countdown(ms: int) -> String:
	if ms < 0:
		return "--:--"
	if ms == 0:
		return "ready"
	var total := int(ms / 1000.0)
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%dh%02dm" % [h, m]
	return "%02d:%02d" % [m, s]

## 访客模式（PRD §3.3 / §8.4）：不复用主人的耕作工具栏。金币、种子、工具、Row、倒计时
## 全部隐藏，只留田况 chip（来自冻结快照）与 Wave / Stamp 两个本机动画按钮。
func set_visitor_mode(on: bool) -> void:
	visitor = on
	_bottom.visible = not on
	_coins.get_parent().visible = not on
	_timer_label.get_parent().visible = not on
	_row_button.visible = not on
	if on and _visitor_bar == null:
		_visitor_bar = HBoxContainer.new()
		_visitor_bar.name = "VisitorBar"
		_visitor_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_visitor_bar.offset_left = 8.0
		_visitor_bar.offset_right = -8.0
		_visitor_bar.offset_top = -232.0
		_visitor_bar.offset_bottom = -180.0
		_visitor_bar.add_theme_constant_override("separation", DesignTokens.SPACE_2)
		add_child(_visitor_bar)
		for spec in [["Wave", "wave_pressed"], ["Stamp", "stamp_pressed"]]:
			var b := Button.new()
			b.text = spec[0]
			b.theme_type_variation = &"AccentButton"
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.y = BUTTON_H
			b.pressed.connect(func(): emit_signal(spec[1]))
			_visitor_bar.add_child(b)
	if _visitor_bar:
		_visitor_bar.visible = on

## 底栏上方的一条状态：选了工具给提示，干活时给「Clearing… 40%」+ 进度条。
## 2026-09-04 录屏：没有它，2 秒一格的劳作在玩家眼里就是「点了没反应」。
func _build_status() -> void:
	# 挂在右上那一列的末尾（金币/田况/倒计时/Row 之下），不再横在底栏上方——那里正好盖住
	# 中间那一畦（2026-09-04 真机）。
	_status = PanelContainer.new()
	_status.name = "ActionStatus"
	_status.theme_type_variation = &"ChipPanel"
	_status.size_flags_horizontal = Control.SIZE_SHRINK_END
	_status.custom_minimum_size.x = 150.0
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_status.add_child(v)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_status_label)
	_status_bar = ProgressBar.new()
	_status_bar.show_percentage = false
	_status_bar.custom_minimum_size.y = 6.0
	_status_bar.max_value = 1.0
	v.add_child(_status_bar)
	get_node("TopRight").add_child(_status)
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.theme_type_variation = &"ToastPanel"
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 100.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	# ToastPanel 是深底：2026-09-04 真机上黑底黑字，拒绝原因一个字都看不见。
	_toast_label.add_theme_color_override("font_color", DesignTokens.SURFACE)
	_toast.add_child(_toast_label)
	add_child(_toast)

func set_hint(text: String) -> void:
	if _status == null:
		return
	_status_bar.visible = false
	_status_label.text = text
	_status.visible = not text.is_empty()

## 每帧调用：有动作在跑就显示动词 + 进度；空闲时不改提示（提示由 set_hint 管）。
func set_action(action: String, progress: float, pending: int) -> void:
	if _status == null:
		return
	if action.is_empty():
		if not _last_action_text.is_empty():
			_last_action_text = ""
			_status.visible = false
		return
	var text := "%s… %d%%" % [str(ACTION_VERB.get(action, action.capitalize())), int(progress * 100.0)]
	if pending > 1:
		text += "  (+%d queued)" % (pending - 1)
	_last_action_text = text
	_status_label.text = text
	_status_bar.visible = true
	_status_bar.value = progress
	_status.visible = true

static func reject_text(code: String) -> String:
	return str(REJECT_TEXT.get(code, "Rejected: %s" % code))

func show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast_label.text = text
	_toast.visible = true
	_toast_left = TOAST_S

func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0 and _toast:
			_toast.visible = false

## 只允许选当前章节已解锁的作物；锁着的按钮禁用。当前选中被锁时换到第一个可选的。
func set_unlocked_crops(unlocked: Array) -> void:
	for id in _crop_buttons:
		(_crop_buttons[id] as Button).disabled = not unlocked.has(id)
	if not unlocked.has(crop) and not unlocked.is_empty():
		crop = str(unlocked[0])
		emit_signal("crop_selected", crop)
	_refresh_buttons()

func unlocked_crop_ids() -> Array:
	var out := []
	for id in CROPS:
		if not (_crop_buttons[id] as Button).disabled:
			out.append(id)
	return out
