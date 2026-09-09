class_name FarmHud
extends Control
## Status at the top, a clear playfield, and one bottom action dock.

signal cta_pressed()
signal cancel_pressed()
signal seed_selected(crop: String)
signal stall_pressed()
signal life_pressed()
signal reconnect_pressed()
signal wave_pressed()
signal stamp_pressed()

const BUTTON_H := 48.0
const TOAST_S := 3.0
const REJECT_TEXT := {"WRONG_STATE": "That plot isn't ready for this step", "NOT_RIPE": "Not ripe yet",
	"WRONG_CARE": "This crop needs different care", "INSUFFICIENT_ITEMS": "Not enough of that item",
	"INSUFFICIENT_FUNDS": "Not enough coins", "CELL_LOCKED": "This bed isn't unlocked yet",
	"CHAPTER_LOCKED": "Not available in this chapter yet", "STALL_BUDGET": "The stall is sold out for today",
	"OFFLINE": "You're offline", "UNKNOWN_CELL": "That plot isn't part of this farm",
	"PENDING_ACTION": "Check your previous visit, kitchen, project or trade first",
	"CELL_NOT_CULTIVABLE": "That plot can't be farmed", "NOT_PREDICTED": "Action unavailable"}
const CONDITION_TEXT := {"sunny": "Sunny · water today", "rain": "Rain · drain today", "wind": "Wind · shelter today"}

var visitor := false
var selected_crop := "R"
var offline := false
var _coins: Label
var _condition: Label
var _weather_icon: TextureRect
var _weather := "sunny"
var _timer_label: Label
var _status: VBoxContainer
var _status_label: Label
var _status_bar: ProgressBar
var _banner: PanelContainer
var _toast: PanelContainer
var _toast_label: Label
var _toast_left := 0.0
var _goals: PanelContainer
var _goals_header: Button
var _goals_list: VBoxContainer
var _goals_count: Label
var _goals_title: Label
var _goals_feedback: Label
var _goals_open := false
var _cta_busy := false
var _cta_enabled := false
var _cta: Button
var _cancel: Button
var _seed_row: GridContainer
var _seed_buttons: Dictionary = {}
var _stall: Button
var _bottom: VBoxContainer
var _visitor_bar: HBoxContainer
var _scrim: ColorRect
var _modal: Control
var _last_action_text := ""
var _coin_icon: TextureRect
var _action := ""
var _work_backing: Panel
var _reconnect: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_status()
	_build_bottom()
	_build_modals()
	_build_messages()
	resized.connect(_layout)
	call_deferred("_layout")

func _small_icon(symbol: String, color: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = GameUi.icon(symbol)
	t.custom_minimum_size = Vector2(18, 18)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _build_status() -> void:
	var backing := Panel.new()
	backing.name = "StatusBacking"
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.z_index = -1
	backing.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	backing.offset_left = -32
	backing.offset_right = 32
	backing.offset_top = -80
	backing.offset_bottom = 138
	var style := GameUi.surface(Color(GameUi.PAPER, 0.94), 0, 0)
	style.set_border_width_all(0)
	backing.add_theme_stylebox_override("panel", style)
	add_child(backing)
	var top := HBoxContainer.new()
	top.name = "TopRight"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 54
	top.offset_bottom = 86
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	add_child(top)
	_weather_icon = _small_icon("sun", GameUi.BLUE)
	top.add_child(_weather_icon)
	_condition = GameUi.label("Sunny · water today", 12)
	_condition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_condition)
	_coin_icon = _small_icon("coins", Color("b58728"))
	top.add_child(_coin_icon)
	_coins = GameUi.label("0", 14)
	top.add_child(_coins)
	var meta := HBoxContainer.new()
	meta.name = "Overview"
	meta.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	meta.offset_top = 90
	meta.offset_bottom = 134
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(meta)
	_goals_header = GameUi.button("list-checks", "Goals", "Chapter goals")
	_goals_header.add_theme_font_size_override("font_size", 12)
	_goals_header.pressed.connect(func(): show_modal(_goals))
	meta.add_child(_goals_header)
	var bag := GameUi.button("shopping-bag", "", "Harvest and supplies")
	bag.name = "LifeButton"
	bag.pressed.connect(func(): life_pressed.emit())
	meta.add_child(bag)
	_reconnect = GameUi.button("rotate-ccw", "", "Check connection and last action")
	_reconnect.name = "ReconnectFarm"
	_reconnect.visible = false
	_reconnect.pressed.connect(func():
		if not _reconnect.disabled: reconnect_pressed.emit())
	meta.add_child(_reconnect)
	_timer_label = GameUi.label("", 12, GameUi.MUTED)
	_timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(_timer_label)

func _build_bottom() -> void:
	_work_backing = Panel.new()
	_work_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_work_backing.add_theme_stylebox_override("panel", GameUi.surface(GameUi.PAPER, 0))
	_work_backing.visible = false
	add_child(_work_backing)
	_bottom = VBoxContainer.new()
	_bottom.name = "BottomBar"
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_theme_constant_override("separation", 8)
	add_child(_bottom)
	_status = VBoxContainer.new()
	_status.visible = false
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label = GameUi.label("", 12)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.add_child(_status_label)
	_status_bar = ProgressBar.new()
	_status_bar.show_percentage = false
	_status_bar.max_value = 1
	_status_bar.custom_minimum_size.y = 4
	_status.add_child(_status_bar)
	_bottom.add_child(_status)
	_seed_row = GridContainer.new()
	_seed_row.name = "SeedRow"
	_seed_row.columns = 2
	_seed_row.add_theme_constant_override("h_separation", 8)
	_seed_row.add_theme_constant_override("v_separation", 6)
	_seed_row.visible = false
	_bottom.add_child(_seed_row)
	for id in CropInfo.ORDER:
		var b := GameUi.button("sprout", CropInfo.name_of(id), "Plant %s" % CropInfo.name_of(id))
		b.icon = GameUi.crop_art(id)
		b.custom_minimum_size.y = 58
		b.add_theme_constant_override("icon_max_width", 36)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_color_override("icon_%s_color" % state, Color.WHITE)
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.45))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			selected_crop = id
			_refresh_seed_buttons()
			seed_selected.emit(id))
		_seed_buttons[id] = b
		_seed_row.add_child(b)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	_bottom.add_child(dock)
	_cta = GameUi.button("sprout", "Loading...", "Work the ready plots", true)
	_cta.name = "CTA"
	_cta.custom_minimum_size.y = 52
	_cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cta.clip_text = true
	_cta.pressed.connect(func(): cta_pressed.emit())
	dock.add_child(_cta)
	_cancel = GameUi.button("x", "", "Cancel remaining work")
	_cancel.visible = false
	_cancel.pressed.connect(func(): cancel_pressed.emit())
	dock.add_child(_cancel)
	_stall = GameUi.button("store", "", "Roadside stall")
	_stall.name = "Stall"
	_stall.custom_minimum_size = Vector2(52, 52)
	_stall.pressed.connect(func(): stall_pressed.emit())
	dock.add_child(_stall)
	_visitor_bar = HBoxContainer.new()
	_visitor_bar.name = "VisitorBar"
	_visitor_bar.add_theme_constant_override("separation", 8)
	_visitor_bar.visible = false
	add_child(_visitor_bar)
	for spec in [["hand", "Wave", "wave_pressed"], ["heart", "Stamp", "stamp_pressed"]]:
		var b := GameUi.button(spec[0], spec[1], spec[1], spec[0] == "hand")
		b.custom_minimum_size.y = 52
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): emit_signal(spec[2]))
		_visitor_bar.add_child(b)

func _build_modals() -> void:
	_scrim = ColorRect.new()
	_scrim.name = "ModalScrim"
	_scrim.color = Color(0.06, 0.13, 0.1, 0.28)
	_scrim.z_index = 10
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.offset_left = -32
	_scrim.offset_top = -80
	_scrim.offset_right = 32
	_scrim.offset_bottom = 80
	_scrim.visible = false
	_scrim.gui_input.connect(func(e):
		if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.is_pressed():
			close_modal()
			accept_event())
	add_child(_scrim)
	_goals = PanelContainer.new()
	_goals.name = "Goals"
	_goals.z_index = 11
	_goals.visible = false
	# Wrapped labels can briefly inflate the first layout before their width is known.
	_goals.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	add_child(_goals)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_goals.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_goals_title = GameUi.label("Chapter goals", 18)
	_goals_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goals_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_goals_title)
	var close := GameUi.button("x", "", "Close goals")
	close.pressed.connect(close_modal)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_goals_list = VBoxContainer.new()
	_goals_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goals_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_goals_list)
	_goals_count = GameUi.label("", 16, GameUi.GREEN)
	_goals_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_goals_count)
	_goals_feedback = GameUi.label("Progress pending", 12, GameUi.MUTED)
	_goals_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goals_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_goals_feedback)

func _build_messages() -> void:
	_banner = PanelContainer.new()
	_banner.name = "OfflineBanner"
	_banner.theme_type_variation = &"ToastPanel"
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(GameUi.label("Offline · reconnecting", 12, GameUi.PAPER))
	add_child(_banner)
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.theme_type_variation = &"ToastPanel"
	_toast.z_index = 20
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = GameUi.label("", 13, GameUi.PAPER)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	add_child(_toast)

func _layout() -> void:
	if _bottom == null: return
	var h := _bottom.get_combined_minimum_size().y
	_bottom.position = Vector2(0, size.y - h - 4)
	_bottom.size = Vector2(size.x, h)
	_work_backing.position = _bottom.position - Vector2(8, 12)
	_work_backing.size = _bottom.size + Vector2(16, 32)
	_work_backing.visible = _cta_busy and _bottom.visible
	_visitor_bar.position = Vector2(0, size.y - 56)
	_visitor_bar.size = Vector2(size.x, 52)
	var goals_height := minf(maxf(366, _goals.get_combined_minimum_size().y + _goals_list.get_combined_minimum_size().y), size.y - 148)
	_goals.position = Vector2(0, size.y - goals_height - 4)
	_goals.size = Vector2(size.x, goals_height)
	_banner.position = Vector2(0, 138)
	_banner.size = Vector2(size.x, 38)
	_toast.position = Vector2(8, 144 if not offline else 186)
	_toast.size = Vector2(maxf(1, size.x - 16), 0)
	if _modal and _modal != _goals and _modal.has_method("fit_height"):
		_modal.fit_height(size)

func show_modal(panel: Control) -> void:
	if _modal and _modal.has_method("is_busy") and _modal.is_busy(): return
	close_modal()
	_modal = panel
	panel.z_index = 11
	panel.visible = true
	_scrim.visible = true
	_bottom.visible = false
	_work_backing.visible = false
	_visitor_bar.visible = false
	_goals_open = panel == _goals
	_layout()

func close_modal() -> void:
	if _modal and _modal.has_method("is_busy") and _modal.is_busy(): return
	if _modal: _modal.visible = false
	_modal = null
	_goals_open = false
	if _scrim: _scrim.visible = false
	if _bottom: _bottom.visible = not visitor
	if _visitor_bar: _visitor_bar.visible = visitor
	call_deferred("_layout")

func modal_open() -> bool:
	return _modal != null and _modal.visible

func set_goals(goals: Array, day_index: int, progress: Dictionary = {}) -> void:
	var done := DayGoals.done_count(goals)
	_goals_header.text = "Goals · %d/%d" % [done, goals.size()]
	_goals_title.text = "Chapter %d · %s" % [day_index + 1, str(progress.get("title", "Goals"))]
	_goals_header.tooltip_text = _goals_title.text
	var complete := bool(progress.get("complete", false))
	_goals_header.icon = GameUi.icon("circle-check" if complete else "list-checks")
	var rows := []
	var highlighted := false
	var ordered := goals.filter(func(g): return not bool(g.done)) + goals.filter(func(g): return bool(g.done))
	for g in ordered:
		var is_done := bool(g.done)
		rows.append([str(g.label), GameUi.MUTED if is_done else (GameUi.INK if highlighted else GameUi.GREEN), is_done])
		if not is_done: highlighted = true
	_goals_count.text = "%d/%d" % [done, goals.size()]
	_goals_feedback.text = "Progress pending" if progress.is_empty() or bool(progress.get("pending", false)) else "Chapter in progress"
	if complete:
		_goals_feedback.text = "Week complete" if bool(progress.get("last_chapter", false)) else "Chapter complete"
		var remaining := int(progress.get("next_open_in_ms", -1))
		if remaining >= 0 and not bool(progress.get("last_chapter", false)):
			_goals_feedback.text = "Checking next chapter..." if remaining == 0 else "Chapter complete · next in %s" % format_countdown(remaining)
	_goals_feedback.add_theme_color_override("font_color", GameUi.GREEN if complete else GameUi.MUTED)
	if bool(progress.get("journey", false)):
		_goals_title.text = str(progress.title)
		_goals_header.tooltip_text = _goals_title.text
		_goals_feedback.text = "A corner in bloom" if complete else str(progress.title)
	while _goals_list.get_child_count() < rows.size():
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 32
		row.add_theme_constant_override("separation", 12)
		row.add_child(_small_icon("circle", GameUi.MUTED))
		var l := GameUi.label("", 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		_goals_list.add_child(row)
	for i in _goals_list.get_child_count():
		var row := _goals_list.get_child(i) as HBoxContainer
		row.visible = i < rows.size()
		if row.visible:
			var l := row.get_child(1) as Label
			l.text = rows[i][0]
			l.add_theme_color_override("font_color", rows[i][1])
			var mark := row.get_child(0) as TextureRect
			mark.texture = GameUi.icon("check" if rows[i][2] else "circle")
			mark.modulate = rows[i][1]
			row.set_meta("goal_text", ("✓ " if rows[i][2] else "○ ") + l.text)
	call_deferred("_layout")

func goal_labels() -> Array:
	var out := []
	for c in _goals_list.get_children():
		if c.visible: out.append(c.get_meta("goal_text"))
	return out

func set_cta(bulk: Dictionary) -> void:
	_cta_busy = false
	_action = str(bulk.get("action", ""))
	_cta.remove_theme_stylebox_override("disabled")
	_cta.remove_theme_color_override("font_disabled_color")
	_cta.remove_theme_color_override("icon_disabled_color")
	_cta_enabled = bool(bulk.get("enabled", true))
	_cta.text = str(bulk.get("label", ""))
	_cta.icon = GameUi.icon(GameUi.action_icon(str(bulk.get("action", "")), str(bulk.get("weather", _weather))))
	_cta.disabled = offline or not _cta_enabled
	_cta.theme_type_variation = &"AccentButton"
	_cancel.visible = false
	_status.visible = false
	call_deferred("_layout")

func set_cta_busy(pending: int) -> void:
	_cta_busy = true
	_cta.disabled = true
	_cta.text = _last_action_text if not _last_action_text.is_empty() else "Working..."
	_status_label.text = "%d %s remaining" % [pending, "plot" if pending == 1 else "plots"] if pending > 0 else "Finishing..."
	_status.visible = true
	_cancel.visible = true
	_seed_row.visible = false
	var color := GameUi.BLUE if _action == "care" else GameUi.GREEN
	_cta.add_theme_stylebox_override("disabled", GameUi.surface(color, 8))
	_cta.add_theme_color_override("font_disabled_color", GameUi.PAPER)
	_cta.add_theme_color_override("icon_disabled_color", GameUi.PAPER)
	call_deferred("_layout")

func set_seeds(inventory: Dictionary, unlocked: Array, show: bool, preserve_selection := false) -> void:
	_seed_row.visible = show and not visitor and not _cta_busy
	for id in _seed_buttons:
		var b: Button = _seed_buttons[id]
		var n := NextStep.seeds_of(inventory, id)
		b.visible = unlocked.has(id)
		b.text = "%s\n×%d" % [CropInfo.name_of(id), n]
		b.disabled = n == 0 or offline or _cta_busy
	if not preserve_selection and (not unlocked.has(selected_crop) or NextStep.seeds_of(inventory, selected_crop) == 0):
		for id in CropInfo.ORDER:
			if unlocked.has(id) and NextStep.seeds_of(inventory, id) > 0:
				selected_crop = id
				break
	_refresh_seed_buttons()
	call_deferred("_layout")

func _refresh_seed_buttons() -> void:
	for id in _seed_buttons:
		_seed_buttons[id].theme_type_variation = &"ChoiceSelectedButton" if id == selected_crop else &"ChoiceButton"

func set_offline(v: bool) -> void:
	offline = v
	_banner.visible = v
	_cta.disabled = v or _cta_busy or not _cta_enabled
	_stall.disabled = v

func set_connection_recovery(needed: bool, busy := false) -> void:
	_reconnect.visible = needed
	_reconnect.disabled = busy

func set_coins(n: int) -> void:
	_coins.text = str(n)

func set_condition(cond: String) -> void:
	_weather = cond
	_condition.text = str(CONDITION_TEXT.get(cond, cond))
	_weather_icon.texture = GameUi.icon({"rain": "cloud-rain", "wind": "wind"}.get(cond, "sun"))

func set_next_ripe(cells: Dictionary, now_ms: int) -> void:
	var remaining := next_ripe_ms(cells, now_ms)
	_timer_label.text = "Harvest ready" if remaining == 0 else ("Ripe in %s" % format_countdown(remaining) if remaining > 0 else "")

static func next_ripe_ms(cells: Dictionary, now_ms: int) -> int:
	var best := -1
	for id in cells:
		var ready = (cells[id] as Dictionary).get("ready_at")
		if ready == null: continue
		var delta := int(ready) - now_ms
		if delta <= 0: return 0
		if best < 0 or delta < best: best = delta
	return best

static func format_countdown(ms: int) -> String:
	if ms < 0: return "--:--"
	if ms == 0: return "ready"
	var total := int(ms / 1000.0)
	var h := total / 3600
	var m := (total % 3600) / 60
	return "%dh%02dm" % [h, m] if h > 0 else "%02d:%02d" % [m, total % 60]

func set_hint(text: String) -> void:
	if not text.is_empty() and text != "Tap a plot to work it": show_toast(text)

func set_action(text: String, progress: float, _pending: int) -> void:
	_last_action_text = text
	_status_bar.value = progress
	if _cta_busy and not text.is_empty(): _cta.text = text

static func reject_text(code: String) -> String:
	return str(REJECT_TEXT.get(code, "Action unavailable"))

func show_toast(text: String) -> void:
	var problem := text.begins_with("Can't") or text.begins_with("No ") or text.begins_with("That plot") or text.contains("unavailable")
	_toast.add_theme_stylebox_override("panel", GameUi.surface(GameUi.PAPER if problem else GameUi.INK, 12))
	_toast_label.add_theme_color_override("font_color", GameUi.CORAL if problem else GameUi.PAPER)
	_toast_label.text = text
	_toast.visible = true
	_toast_left = TOAST_S
	_layout()

func _process(dt: float) -> void:
	if _toast_left > 0:
		_toast_left -= dt
		if _toast_left <= 0: _toast.visible = false

func set_visitor_mode(on: bool) -> void:
	visitor = on
	_bottom.visible = not on
	_stall.visible = not on
	_goals_header.visible = not on
	_coins.visible = not on
	_coin_icon.visible = not on
	_timer_label.visible = not on
	_visitor_bar.visible = on
	call_deferred("_layout")
