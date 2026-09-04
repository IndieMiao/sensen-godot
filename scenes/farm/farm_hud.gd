class_name FarmHud
extends Control
## 农场 HUD v2：不再有「工具」。玩家只面对三样东西——
##   · 一个大按钮：现在最该做的一件事（Clear 9 plots / Water 3 plots / Sell 2 at the stall）
##   · 一张今日目标清单：知道自己在往哪走
##   · 田况与金币
## 直接点田块也行：它自己知道下一步。所有新元素在底部与右侧，不碰顶栏（360 宽已无余量）。
## 界面文案一律英文。

signal cta_pressed()
signal seed_selected(crop: String)
signal stall_pressed()
signal wave_pressed()
signal stamp_pressed()

const BUTTON_H := 48.0
const TOAST_S := 2.5
const REJECT_TEXT := {
	"WRONG_STATE": "That plot isn't ready for this step",
	"NOT_RIPE": "Not ripe yet",
	"WRONG_CARE": "Wrong care for today's weather",
	"INSUFFICIENT_ITEMS": "Not enough seeds",
	"INSUFFICIENT_FUNDS": "Not enough coins",
	"CELL_LOCKED": "This bed isn't unlocked yet",
	"CHAPTER_LOCKED": "Not available in this chapter yet",
	"STALL_BUDGET": "The stall is sold out for today",
	"OFFLINE": "You're offline",
	"UNKNOWN_CELL": "That plot isn't part of this farm",
	"CELL_NOT_CULTIVABLE": "That plot can't be farmed",
	"NOT_PREDICTED": "Rejected",
}
const CONDITION_TEXT := {"sunny": "Sunny · water today", "rain": "Rain · drain today", "wind": "Wind · shelter today"}

var visitor := false
var selected_crop := "R"
var offline := false

var _coins: Label
var _condition: Label
var _timer_label: Label
var _status: PanelContainer
var _status_label: Label
var _status_bar: ProgressBar
var _last_action_text := ""
var _banner: PanelContainer
var _toast: PanelContainer
var _toast_label: Label
var _toast_left := 0.0
var _goals: PanelContainer
var _goals_header: Button
var _goals_list: VBoxContainer
var _goals_open := true
var _goals_auto_collapsed := false
var _cta_busy := false
var _cta: Button
var _seed_row: HBoxContainer
var _seed_buttons: Dictionary = {}
var _stall: Button
var _bottom: VBoxContainer
var _visitor_bar: HBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_top_right()
	_build_goals()
	_build_banner_and_toast()
	_build_bottom()

# —— 右上：金币 / 田况 / 倒计时 / 进度 ——————————————————————————————————————

func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.name = "TopRight"
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# Root 只有 328 宽（360 减两侧 16 安全边距）：目标卡占 8..158，右上列占 166..320。
	# 最宽的 chip「Sunny · water today」148，正好装下。
	box.offset_left = -162.0
	box.offset_top = 60.0
	box.offset_right = -8.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_coins = _chip(box, "Coins 0")
	_condition = _chip(box, "Sunny · water today")
	_timer_label = _chip(box, "Next ripe --:--")
	_status = PanelContainer.new()
	_status.name = "ActionStatus"
	_status.theme_type_variation = &"ChipPanel"
	_status.size_flags_horizontal = Control.SIZE_SHRINK_END
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_status.add_child(v)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", DesignTokens.FONT_MICRO + 1)   # 「Clearing… 92% · 8 left」要装进 126 宽
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 固定宽：省略号模式下 Label 最小宽是 1，SHRINK_END 的 chip 会缩成 29 px 的空白小丸；
	# 不固定又会被长句撑到和左边的目标卡相撞。
	_status_label.custom_minimum_size.x = 126.0
	v.add_child(_status_label)
	_status_bar = ProgressBar.new()
	_status_bar.show_percentage = false
	_status_bar.custom_minimum_size.y = 6.0
	_status_bar.max_value = 1.0
	v.add_child(_status_bar)
	box.add_child(_status)

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

# —— 左上：今日目标 ——————————————————————————————————————————————————————

func _build_goals() -> void:
	_goals = PanelContainer.new()
	_goals.name = "Goals"
	_goals.theme_type_variation = &"ChipPanel"
	_goals.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_goals.offset_left = 8.0
	_goals.offset_top = 60.0
	_goals.offset_right = 150.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_goals.add_child(v)
	_goals_header = Button.new()
	_goals_header.text = "Day 1 goals · 0/7"
	_goals_header.flat = true
	_goals_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_goals_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_goals_header.custom_minimum_size.y = 28.0
	_tighten(_goals_header)   # 默认 16 px 内边距会把整张卡撑到 159 宽、碰到右上列
	_goals_header.pressed.connect(func():
		_goals_open = not _goals_open
		_goals_list.visible = _goals_open
		_goals_header.text = _goals_header.text.trim_suffix("▾").trim_suffix("▸") + ("▾" if _goals_open else "▸"))
	v.add_child(_goals_header)
	_goals_list = VBoxContainer.new()
	_goals_list.add_theme_constant_override("separation", 0)
	v.add_child(_goals_list)
	add_child(_goals)

## goals: [{id, label, done}]。完成的打勾变灰，第一条未完成的加亮——那就是「现在做什么」。
## 行节点复用：_refresh_hud 每次回包都会调用，重建 Label 会留一堆等帧末释放的孤儿。
func set_goals(goals: Array, day_index: int) -> void:
	var done := DayGoals.done_count(goals)
	_goals_header.text = "Day %d goals · %d/%d %s" % [day_index + 1, done, goals.size(), "▾" if _goals_open else "▸"]
	# 第一条完成后自动折叠成一行：整张卡展开着会一直挡住左上那一畦；点标题随时展开。
	if done > 0 and not _goals_auto_collapsed:
		_goals_auto_collapsed = true
		_goals_open = false
		_goals_list.visible = false
		_goals_header.text = "Day %d goals · %d/%d ▸" % [day_index + 1, done, goals.size()]
	var rows: Array = []
	var highlighted := false
	for g in goals:
		var is_done := bool(g.done)
		var color := DesignTokens.INK_MUTED if is_done else (DesignTokens.INK if highlighted else DesignTokens.ACCENT_DEEP)
		if not is_done:
			highlighted = true
		rows.append([("✓ " if is_done else "○ ") + str(g.label), color])
	if done == goals.size() and goals.size() > 0:
		rows.append(["Day complete — come back tomorrow", DesignTokens.ACCENT_DEEP])
	while _goals_list.get_child_count() < rows.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true   # 长句不能把整张卡撑宽到和右上列相撞
		_goals_list.add_child(l)
	var i := 0
	for c in _goals_list.get_children():
		var l := c as Label
		if i < rows.size():
			l.visible = true
			l.text = rows[i][0]
			l.add_theme_color_override("font_color", rows[i][1])
		else:
			l.visible = false
		i += 1

func goal_labels() -> Array:
	var out := []
	for c in _goals_list.get_children():
		if (c as Label).visible:
			out.append((c as Label).text)
	return out

# —— 顶部横幅 / toast ——————————————————————————————————————————————————————

func _build_banner_and_toast() -> void:
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
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.theme_type_variation = &"ToastPanel"
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 100.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	_toast_label.add_theme_color_override("font_color", DesignTokens.SURFACE)
	_toast.add_child(_toast_label)
	add_child(_toast)

# —— 底部：种子行 + 大按钮 + 摊位 ——————————————————————————————————————————

func _build_bottom() -> void:
	_bottom = VBoxContainer.new()
	_bottom.name = "BottomBar"
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.offset_left = 8.0
	_bottom.offset_right = -8.0
	_bottom.offset_top = -296.0
	_bottom.offset_bottom = -188.0
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	_bottom.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	add_child(_bottom)
	_seed_row = HBoxContainer.new()
	_seed_row.name = "SeedRow"
	_seed_row.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	_seed_row.visible = false
	_bottom.add_child(_seed_row)
	for id in CropInfo.ORDER:
		var b := Button.new()
		b.text = CropInfo.name_of(id)
		b.theme_type_variation = &"ChoiceButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 40.0
		b.clip_text = true
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		_tighten(b)
		b.pressed.connect(func():
			selected_crop = id
			_refresh_seed_buttons()
			emit_signal("seed_selected", id))
		_seed_row.add_child(b)
		_seed_buttons[id] = b
	_cta = Button.new()
	_cta.name = "CTA"
	_cta.text = "Loading…"
	_cta.theme_type_variation = &"AccentButton"
	_cta.custom_minimum_size.y = 52.0
	_cta.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_cta.pressed.connect(func(): emit_signal("cta_pressed"))
	_bottom.add_child(_cta)
	# 摊位在右下，和左下摇杆对称。
	_stall = Button.new()
	_stall.name = "Stall"
	_stall.text = "Stall"
	_stall.theme_type_variation = &"SecondaryButton"
	_stall.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_stall.offset_left = -128.0
	_stall.offset_right = -8.0
	_stall.offset_top = -84.0
	_stall.offset_bottom = -24.0
	_stall.pressed.connect(func(): emit_signal("stall_pressed"))
	add_child(_stall)

## 主题给 Button 的左右内边距是 16，一行四五个按钮时长词会被裁。收到 6，高度另有兜底。
static func _tighten(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := b.get_theme_stylebox(state)
		if sb == null:
			continue
		var dup := sb.duplicate() as StyleBox
		dup.content_margin_left = 6.0
		dup.content_margin_right = 6.0
		b.add_theme_stylebox_override(state, dup)

## 大按钮：bulk = NextStep.bulk() 的结果。调用它即视为忙碌结束。
func set_cta(bulk: Dictionary) -> void:
	_cta_busy = false
	_cta.text = str(bulk.get("label", ""))
	_cta.disabled = offline or not bool(bulk.get("enabled", true))
	_cta.theme_type_variation = &"AccentButton" if bulk.get("action", "") != "stall" else &"SecondaryButton"

## 队列在跑：大按钮改成禁用的「Working… N plots left」。原来它仍显示可点的下一步，再按一下
## 就把同一批格再排一遍，然后一格格被拒。
func set_cta_busy(pending: int) -> void:
	_cta_busy = true
	_cta.text = "Working…" if pending <= 0 else "Working… %d %s left" % [pending, "plot" if pending == 1 else "plots"]
	_cta.disabled = true
	_cta.theme_type_variation = &"SecondaryButton"

## 种子行：只在能播种时出现；每颗作物显示还剩几颗；锁着的不出现。
func set_seeds(inventory: Dictionary, unlocked: Array, show: bool) -> void:
	_seed_row.visible = show and not visitor
	for id in _seed_buttons:
		var b: Button = _seed_buttons[id]
		var n := NextStep.seeds_of(inventory, id)
		b.visible = unlocked.has(id)
		b.text = "%s ×%d" % [CropInfo.name_of(id), n]
		b.disabled = n == 0 or offline
	if not unlocked.has(selected_crop) or NextStep.seeds_of(inventory, selected_crop) == 0:
		for id in CropInfo.ORDER:
			if unlocked.has(id) and NextStep.seeds_of(inventory, id) > 0:
				selected_crop = id
				break
	_refresh_seed_buttons()

func _refresh_seed_buttons() -> void:
	for id in _seed_buttons:
		(_seed_buttons[id] as Button).theme_type_variation = \
			&"ChoiceSelectedButton" if id == selected_crop else &"ChoiceButton"

func set_offline(v: bool) -> void:
	offline = v
	_banner.visible = v
	_cta.disabled = v or _cta.disabled
	_stall.disabled = v

func set_coins(n: int) -> void:
	_coins.text = "Coins %d" % n

func set_condition(cond: String) -> void:
	_condition.text = str(CONDITION_TEXT.get(cond, cond))

## 下一次成熟的倒计时。`now_ms` 必须是服务端时间。
func set_next_ripe(cells: Dictionary, now_ms: int) -> void:
	_timer_label.text = "Next ripe %s" % format_countdown(next_ripe_ms(cells, now_ms))

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

func set_hint(text: String) -> void:
	_status_bar.visible = false
	_status_label.text = text
	_status.visible = not text.is_empty()

## 每帧：有动作在跑就显示动词与进度；空闲时不改提示（提示由 set_hint 管）。
func set_action(text: String, progress: float, pending: int) -> void:
	if text.is_empty():
		if not _last_action_text.is_empty():
			_last_action_text = ""
			_status.visible = false
		return
	var full := text
	if pending > 1:
		full += " · %d left" % (pending - 1)
	_last_action_text = full
	_status_label.text = full
	_status_bar.visible = true
	_status_bar.value = progress
	_status.visible = true

static func reject_text(code: String) -> String:
	return str(REJECT_TEXT.get(code, "Rejected: %s" % code))

func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast_left = TOAST_S

func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0:
			_toast.visible = false

## 访客模式：只剩田况 chip 与 Wave / Stamp。
func set_visitor_mode(on: bool) -> void:
	visitor = on
	_bottom.visible = not on
	_stall.visible = not on
	_goals.visible = not on
	_coins.get_parent().visible = not on
	_timer_label.get_parent().visible = not on
	if on and _visitor_bar == null:
		_visitor_bar = HBoxContainer.new()
		_visitor_bar.name = "VisitorBar"
		_visitor_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_visitor_bar.offset_left = 8.0
		_visitor_bar.offset_right = -8.0
		_visitor_bar.offset_top = -240.0
		_visitor_bar.offset_bottom = -188.0
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
