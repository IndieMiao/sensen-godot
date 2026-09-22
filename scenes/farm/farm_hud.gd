class_name FarmHud
extends Control
## Status at the top, a clear playfield, and one bottom action dock.

signal work_mode_changed(enabled: bool)
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
	"VERSION_MISMATCH": "Farm update is incomplete. Please reconnect after the server upgrade.",
	"PLOT_LIMIT_REACHED": "Too many open plots. Finish your existing plots first.",
	"BAG_FULL": "Your bag is full. Make room before harvesting.",
	"CELL_NOT_CULTIVABLE": "That plot can't be farmed", "NOT_PREDICTED": "Action unavailable"}
## 天气只报天气：照料动作不再随天气变（自由种植下浇水是播种后的一次性启动动作），
## 再写「今天要浇水」就是在教玩家一套已经不存在的规则。
const CONDITION_TEXT := {"sunny": "Sunny", "rain": "Rain", "wind": "Wind"}

## 概览行右侧要空出来的宽度：在线徽章宽 116 + 右边距 16，再减去本行自身的 16 内边距，
## 另留 8 的呼吸位。徽章不归本布局管，只能按它的绝对坐标反推。
const ONLINE_BADGE_CLEARANCE := 60.0

var visitor := false
var selected_crop := "R"
var offline := false
var seed_space_needed := false
var _mode_row: HBoxContainer
var _mode_toggle: Button
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
var _field_goal: Label
var _cta_busy := false
var _cta_enabled := false
var _cta: Button
var _cancel: Button
var _seed_scroll: TouchScrollContainer
var _seed_row: GridContainer
var _seed_buttons: Dictionary = {}
var _stall: Button
var _bottom: VBoxContainer
var _visitor_bar: HBoxContainer
var _scrim: ColorRect
var _modal: Control
var _last_action_text := ""
var _coin_icon: TextureRect
var _currency_divider: ColorRect
var _action := ""
var _work_backing: Panel
var _reconnect: Button
var _top_right: PanelContainer
var _overview: PanelContainer
var _timer_icon: TextureRect
var _overview_divider: ColorRect
var _life_button: Button
var _bag_dot: Panel
var _quick_actions: PanelContainer
var _quick_action_list: VBoxContainer
var _actions_title: Label
var _work_mode := false
var _seeds_requested := false

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
	var extent := Control.new()
	extent.name = "StatusBacking"
	extent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	extent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	extent.offset_bottom = 100
	add_child(extent)
	_top_right = PanelContainer.new()
	_top_right.name = "TopRight"
	_top_right.custom_minimum_size = Vector2(112, 44)
	_top_right.mouse_filter = Control.MOUSE_FILTER_STOP
	_top_right.add_theme_stylebox_override("panel", GameUi.panel_style(6))
	add_child(_top_right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	_top_right.add_child(top)
	_weather_icon = _small_icon("sun", GameUi.GOLD)
	_weather_icon.custom_minimum_size = Vector2(22, 22)
	top.add_child(_weather_icon)
	_condition = GameUi.label(L10n.text("Sunny"), 11)
	_condition.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_condition.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_condition.custom_minimum_size.x = 30
	top.add_child(_condition)
	_currency_divider = ColorRect.new()
	_currency_divider.color = GameUi.BORDER
	_currency_divider.custom_minimum_size = Vector2(1, 18)
	_currency_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_currency_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_currency_divider)
	_coin_icon = _small_icon("coins", GameUi.GOLD)
	_coin_icon.custom_minimum_size = Vector2(22, 22)
	top.add_child(_coin_icon)
	_coins = GameUi.label("0", 15)
	_coins.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_coins.custom_minimum_size.x = 28
	top.add_child(_coins)
	_overview = PanelContainer.new()
	_overview.name = "Overview"
	_overview.add_theme_stylebox_override("panel", GameUi.panel_style(0))
	_overview.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overview)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	_overview.add_child(meta)
	_goals_header = GameUi.button("list-checks", L10n.text("Goals"), L10n.text("Chapter goals"))
	_goals_header.custom_minimum_size = Vector2(96, 44)
	_goals_header.add_theme_font_size_override("font_size", 12)
	_goals_header.add_theme_constant_override("icon_max_width", 20)
	var clear := StyleBoxEmpty.new()
	clear.content_margin_left = 8
	clear.content_margin_right = 4
	for state in ["normal", "hover", "pressed", "disabled", "focus"]: _goals_header.add_theme_stylebox_override(state, clear)
	_goals_header.pressed.connect(func(): show_modal(_goals))
	meta.add_child(_goals_header)
	_overview_divider = ColorRect.new()
	_overview_divider.color = GameUi.BORDER
	_overview_divider.custom_minimum_size = Vector2(1, 18)
	_overview_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_overview_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_overview_divider)
	_timer_icon = _small_icon("sprout", GameUi.GREEN)
	_timer_icon.custom_minimum_size = Vector2(18, 18)
	meta.add_child(_timer_icon)
	_timer_label = GameUi.label("", 11, GameUi.INK)
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_child(_timer_label)
	_reconnect = GameUi.button("rotate-ccw", "", L10n.text("Check connection and last action"))
	_reconnect.name = "ReconnectFarm"
	_reconnect.visible = false
	_reconnect.pressed.connect(func():
		if not _reconnect.disabled: reconnect_pressed.emit())
	meta.add_child(_reconnect)
	_field_goal = GameUi.label("", 12, GameUi.GREEN)
	_field_goal.name = "FieldGrowthGoal"
	_field_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_field_goal.hide()
	add_child(_field_goal)

func attach_status_to(top_bar: HBoxContainer) -> void:
	if _top_right.get_parent() == top_bar: return
	_top_right.reparent(top_bar)
	top_bar.add_theme_constant_override("separation", 8)
	_top_right.size_flags_horizontal = Control.SIZE_SHRINK_END

func set_field_goal(text: String) -> void:
	_field_goal.text = text
	_field_goal.visible = not text.is_empty()
	if _quick_actions: _layout()

func top_content_bottom() -> float:
	var bottom := global_position.y + 48
	if _overview and _overview.visible: bottom = maxf(bottom, _overview.get_global_rect().end.y)
	return bottom

func _build_bottom() -> void:
	_work_backing = Panel.new()
	_work_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_work_backing.hide()
	add_child(_work_backing)
	_bottom = VBoxContainer.new()
	_bottom.name = "BottomBar"
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_theme_constant_override("separation", 8)
	add_child(_bottom)
	_status = VBoxContainer.new()
	_status.visible = false
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label = GameUi.label("", 11)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.add_child(_status_label)
	_status_bar = ProgressBar.new()
	_status_bar.show_percentage = false
	_status_bar.max_value = 1
	_status_bar.custom_minimum_size.y = 3
	_status.add_child(_status_bar)
	_bottom.add_child(_status)
	_seed_scroll = TouchScrollContainer.new()
	_seed_scroll.name = "SeedStrip"
	_seed_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_seed_scroll.custom_minimum_size.y = 56
	_seed_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_seed_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_seed_scroll.visible = false
	_bottom.add_child(_seed_scroll)
	_seed_row = GridContainer.new()
	_seed_row.name = "SeedRow"
	_seed_row.columns = 2
	_seed_row.add_theme_constant_override("h_separation", 6)
	_seed_row.visible = false
	_seed_scroll.add_child(_seed_row)
	for id in CropInfo.ORDER:
		var button := GameUi.button("sprout", CropInfo.name_of(id), L10n.format_text("Plant %s", CropInfo.name_of(id)))
		button.icon = GameUi.crop_art(id)
		button.custom_minimum_size.y = 56
		button.add_theme_constant_override("icon_max_width", 28)
		for state in ["normal", "hover", "pressed", "focus"]: button.add_theme_color_override("icon_%s_color" % state, Color.WHITE)
		button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.45))
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func():
			selected_crop = id
			_refresh_seed_buttons()
			seed_selected.emit(id))
		_seed_buttons[id] = button
		_seed_row.add_child(button)
	_mode_row = HBoxContainer.new()
	_mode_row.name = "InteractionMode"
	_mode_row.add_theme_constant_override("separation", 8)
	_bottom.add_child(_mode_row)
	_mode_toggle = GameUi.button("footprints", L10n.text("Walk"), L10n.text("Walking · tap to farm"))
	_mode_toggle.name = "FarmModeToggle"
	_mode_toggle.toggle_mode = true
	_mode_toggle.custom_minimum_size = Vector2(52, 52)
	_mode_toggle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_toggle.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	_mode_toggle.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_toggle.expand_icon = true
	_mode_toggle.add_theme_constant_override("icon_max_width", 20)
	_mode_toggle.add_theme_constant_override("h_separation", 0)
	_mode_toggle.add_theme_font_size_override("font_size", 11)
	_mode_row.add_child(_mode_toggle)
	_mode_toggle.toggled.connect(func(enabled: bool): work_mode_changed.emit(enabled))
	_cta = GameUi.button("sprout", L10n.text("Loading..."), L10n.text("Work the ready plots"), true)
	_cta.name = "CTA"
	_cta.custom_minimum_size = Vector2(116, 52)
	_cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cta.add_theme_font_size_override("font_size", 14)
	_cta.add_theme_constant_override("icon_max_width", 24)
	_cta.clip_text = true
	_cta.pressed.connect(func(): cta_pressed.emit())
	_mode_row.add_child(_cta)
	_cancel = GameUi.button("x", "", L10n.text("Cancel remaining work"))
	_cancel.custom_minimum_size = Vector2(44, 52)
	_cancel.visible = false
	_cancel.pressed.connect(func(): cancel_pressed.emit())
	_mode_row.add_child(_cancel)
	_life_button = GameUi.button("shopping-bag", "", L10n.text("Harvest and supplies"))
	_life_button.name = "LifeButton"
	_life_button.custom_minimum_size = Vector2(52, 52)
	_life_button.add_theme_constant_override("icon_max_width", 28)
	_life_button.pressed.connect(func(): life_pressed.emit())
	_mode_row.add_child(_life_button)
	_bag_dot = Panel.new()
	_bag_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_dot.add_theme_stylebox_override("panel", GameUi.surface(GameUi.GOLD, 5, 0))
	_life_button.add_child(_bag_dot)
	_bag_dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_bag_dot.offset_left = -12
	_bag_dot.offset_right = -2
	_bag_dot.offset_top = 2
	_bag_dot.offset_bottom = 12
	_bag_dot.hide()
	_stall = GameUi.button("store", L10n.text("Roadside stall"), L10n.text("Roadside stall"))
	_stall.name = "Stall"
	_stall.custom_minimum_size.y = 48
	_stall.pressed.connect(func():
		close_modal()
		stall_pressed.emit())
	_visitor_bar = HBoxContainer.new()
	_visitor_bar.name = "VisitorBar"
	_visitor_bar.add_theme_constant_override("separation", 10)
	_visitor_bar.visible = false
	add_child(_visitor_bar)
	for spec in [["hand", L10n.text("Wave"), "wave_pressed"], ["heart", L10n.text("Stamp"), "stamp_pressed"]]:
		var button := GameUi.button(spec[0], "", spec[1], spec[0] == "hand")
		button.custom_minimum_size = Vector2(56, 52)
		button.pressed.connect(func(): emit_signal(spec[2]))
		_visitor_bar.add_child(button)
	set_work_mode(false)

func set_work_mode(enabled: bool) -> void:
	_work_mode = enabled
	_mode_toggle.set_pressed_no_signal(enabled)
	_mode_toggle.theme_type_variation = &"ChoiceSelectedButton" if enabled else &"ChoiceButton"
	_mode_toggle.icon = GameUi.icon("sprout" if enabled else "footprints")
	_mode_toggle.text = L10n.text("Work" if enabled else "Walk")
	_mode_toggle.tooltip_text = L10n.text("Farming · tap to walk" if enabled else "Walking · tap to farm")
	_refresh_seed_visibility()
	call_deferred("_layout")

func _refresh_seed_visibility() -> void:
	seed_space_needed = _seeds_requested and _work_mode and not visitor
	_seed_row.visible = seed_space_needed and not _cta_busy
	_seed_scroll.visible = _seed_row.visible

func set_bag_alert(needed: bool) -> void:
	_bag_dot.visible = needed

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
	_goals.add_theme_stylebox_override("panel", GameUi.panel_style(14))
	# Wrapped labels can briefly inflate the first layout before their width is known.
	_goals.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	add_child(_goals)
	GameUi.register_modal(_goals)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_goals.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_goals_title = GameUi.label(L10n.text("Chapter goals"), 18)
	_goals_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goals_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_goals_title)
	var close := GameUi.button("x", "", L10n.text("Close goals"))
	close.pressed.connect(close_modal)
	head.add_child(close)
	var scroll := TouchScrollContainer.new()
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
	_goals_feedback = GameUi.label(L10n.text("Progress pending"), 12, GameUi.MUTED)
	_goals_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goals_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_goals_feedback)
	_field_goal.reparent(v)
	_quick_actions = PanelContainer.new()
	_quick_actions.name = "FarmActions"
	_quick_actions.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	_quick_actions.visible = false
	_quick_actions.add_theme_stylebox_override("panel", GameUi.panel_style(14))
	add_child(_quick_actions)
	GameUi.register_modal(_quick_actions)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_quick_actions.add_child(actions)
	var actions_head := HBoxContainer.new()
	actions.add_child(actions_head)
	_actions_title = GameUi.label(L10n.text("My Farm"), 18)
	_actions_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions_head.add_child(_actions_title)
	var actions_close := GameUi.button("x", "", L10n.text("Close"))
	actions_close.pressed.connect(close_modal)
	actions_head.add_child(actions_close)
	_quick_action_list = VBoxContainer.new()
	_quick_action_list.add_theme_constant_override("separation", 8)
	actions.add_child(_quick_action_list)
	_quick_action_list.add_child(_stall)

func set_farm_title(value: String) -> void:
	_actions_title.text = value

func add_farm_action(button: Button) -> void:
	button.custom_minimum_size.y = 48
	_quick_action_list.add_child(button)
	_quick_action_list.move_child(button, maxi(0, _quick_action_list.get_child_count() - 2))

func open_farm_actions() -> void:
	if modal_open(): return
	show_modal(_quick_actions)

func _build_messages() -> void:
	_banner = PanelContainer.new()
	_banner.name = "OfflineBanner"
	_banner.theme_type_variation = &"ToastPanel"
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(GameUi.label(L10n.text("Offline · reconnecting"), 12, GameUi.PAPER))
	add_child(_banner)
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.theme_type_variation = &"ToastPanel"
	_toast.z_index = 20
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Hidden wrapped labels can initially report one line per character. Refit once
	# their actual width resolves, including when a long notice becomes a short one.
	_toast.minimum_size_changed.connect(_fit_toast, CONNECT_DEFERRED)
	_toast_label = GameUi.label("", 13, GameUi.PAPER)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	add_child(_toast)

func _layout() -> void:
	if _bottom == null or _goals == null: return
	_layout_seed_row()
	var dock_width := minf(size.x, 340.0)
	var height := _bottom.get_combined_minimum_size().y
	_bottom.position = Vector2((size.x - dock_width) * 0.5, size.y - height - 4)
	_bottom.size = Vector2(dock_width, height)
	_work_backing.hide()
	_visitor_bar.size = _visitor_bar.get_combined_minimum_size()
	_visitor_bar.position = Vector2((size.x - _visitor_bar.size.x) * 0.5, size.y - _visitor_bar.size.y - 4)
	var show_timer := not _timer_label.text.is_empty() and not _reconnect.visible
	_timer_label.visible = show_timer
	_timer_icon.visible = show_timer
	_overview_divider.visible = show_timer and _goals_header.visible
	_overview.visible = not visitor or show_timer or _reconnect.visible
	_overview.position = Vector2(0, 56)
	var desired_width := _goals_header.get_combined_minimum_size().x if _goals_header.visible else 0.0
	if show_timer:
		desired_width += minf(118, _timer_label.get_theme_font("font").get_string_size(_timer_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _timer_label.get_theme_font_size("font_size")).x) + 37
	if _reconnect.visible: desired_width += 50
	_overview.size = Vector2(minf(maxf(96, desired_width + 8), maxf(96, size.x - ONLINE_BADGE_CLEARANCE)), 44)
	var width := minf(size.x, 440.0)
	var goals_height := clampf(_goals.get_combined_minimum_size().y + _goals_list.get_combined_minimum_size().y, 260, maxf(260, size.y * 0.68))
	_goals.position = Vector2((size.x - width) * 0.5, maxf(60, size.y - goals_height - 4))
	_goals.size = Vector2(width, goals_height)
	var actions_height := _quick_actions.get_combined_minimum_size().y
	_quick_actions.position = Vector2((size.x - width) * 0.5, maxf(60, size.y - actions_height - 4))
	_quick_actions.size = Vector2(width, actions_height)
	_banner.position = Vector2(0, 104)
	_banner.size = Vector2(minf(size.x, 260), 30)
	_fit_toast()
	if _modal and _modal not in [_goals, _quick_actions] and _modal.has_method("fit_height"):
		_modal.fit_height(size)

func _fit_toast() -> void:
	if _toast == null or _toast_label == null: return
	var width := maxf(1, size.x - 16)
	var padding := _toast.get_theme_stylebox("panel").get_minimum_size()
	_toast_label.size.x = maxf(1, width - padding.x)
	_toast.position = Vector2(8, 108 if not offline else 144)
	_toast.size = Vector2(width, 0)

func show_modal(panel: Control) -> void:
	if _modal and _modal.has_method("is_busy") and _modal.is_busy(): return
	close_modal()
	_modal = panel
	GameUi.register_modal(panel)
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
	_goals_header.text = L10n.format_text("Goals · %d/%d", [done, goals.size()])
	_goals_title.text = L10n.format_text("Chapter %d · %s", [day_index + 1, str(progress.get("title", L10n.text("Goals")))])
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
	_goals_count.text = L10n.format_text("%d/%d", [done, goals.size()])
	_goals_feedback.text = L10n.text("Progress pending") if progress.is_empty() or bool(progress.get("pending", false)) else L10n.text("Chapter in progress")
	if complete:
		_goals_feedback.text = L10n.text("Week complete") if bool(progress.get("last_chapter", false)) else L10n.text("Chapter complete")
		var remaining := int(progress.get("next_open_in_ms", -1))
		if remaining >= 0 and not bool(progress.get("last_chapter", false)):
			_goals_feedback.text = L10n.text("Checking next chapter...") if remaining == 0 else L10n.format_text("Chapter complete · next in %s", format_countdown(remaining))
	_goals_feedback.add_theme_color_override("font_color", GameUi.GREEN if complete else GameUi.MUTED)
	if bool(progress.get("journey", false)):
		_goals_title.text = str(progress.title)
		_goals_header.tooltip_text = _goals_title.text
		_goals_feedback.text = L10n.text("A corner in bloom") if complete else str(progress.title)
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
	_cta.tooltip_text = _cta.text
	_cta.icon = GameUi.icon(GameUi.action_icon(str(bulk.get("action", "")), str(bulk.get("weather", _weather))))
	_cta.disabled = offline or not _cta_enabled
	_cta.theme_type_variation = &"AccentButton"
	_cancel.visible = false
	_status.visible = false
	_refresh_seed_visibility()
	call_deferred("_layout")

func set_cta_busy(pending: int) -> void:
	_cta_busy = true
	_cta.disabled = true
	_cta.text = _last_action_text if not _last_action_text.is_empty() else L10n.text("Working...")
	_status_label.text = L10n.format_text("%d %s remaining", [pending, L10n.text("plot" if pending == 1 else "plots")]) if pending > 0 else L10n.text("Finishing...")
	_status.visible = true
	_cancel.visible = true
	_seed_row.visible = false
	_seed_scroll.visible = false
	_cta.add_theme_stylebox_override("disabled", _cta.get_theme_stylebox("normal").duplicate())
	_cta.add_theme_color_override("font_disabled_color", GameUi.PAPER)
	_cta.add_theme_color_override("icon_disabled_color", GameUi.PAPER)
	call_deferred("_layout")

func set_seeds(inventory: Dictionary, unlocked: Array, show: bool, preserve_selection := false) -> void:
	_seeds_requested = show and not visitor
	_refresh_seed_visibility()
	for id in _seed_buttons:
		var b: Button = _seed_buttons[id]
		var n := NextStep.seeds_of(inventory, id)
		b.visible = unlocked.has(id)
		b.set_meta("seed_count", n)
		b.text = L10n.format_text("%s\n×%d", [CropInfo.name_of(id), n])
		b.disabled = n == 0 or offline or _cta_busy
	if not preserve_selection and (not unlocked.has(selected_crop) or NextStep.seeds_of(inventory, selected_crop) == 0):
		for id in CropInfo.ORDER:
			if unlocked.has(id) and NextStep.seeds_of(inventory, id) > 0:
				selected_crop = id
				break
	_refresh_seed_buttons()
	_layout_seed_row()
	call_deferred("_layout")

func _layout_seed_row() -> void:
	if _seed_row == null: return
	var visible_count := 0
	for button in _seed_buttons.values():
		if button.visible: visible_count += 1
	_seed_row.columns = maxi(1, visible_count)
	for id in _seed_buttons:
		var button: Button = _seed_buttons[id]
		if not button.has_meta("seed_count"): continue
		var count := int(button.get_meta("seed_count"))
		button.text = L10n.format_text("%s\n×%d", [CropInfo.name_of(id), count])
		button.custom_minimum_size = Vector2(104, 56)
		button.add_theme_constant_override("icon_max_width", 30)
		button.add_theme_constant_override("h_separation", 6)

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
	call_deferred("_layout")

func set_coins(n: int) -> void:
	_coins.text = str(n)
	_coins.tooltip_text = str(n)
	_coins.custom_minimum_size.x = clampf(_coins.get_theme_font("font").get_string_size(_coins.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _coins.get_theme_font_size("font_size")).x, 28, 60)

func set_condition(cond: String) -> void:
	_weather = cond
	_condition.text = L10n.text(str(CONDITION_TEXT.get(cond, cond)))
	_weather_icon.texture = GameUi.icon({"rain": "cloud-rain", "wind": "wind"}.get(cond, "sun"))
	_weather_icon.modulate = GameUi.GOLD if cond == "sunny" else GameUi.BLUE

func set_next_ripe(cells: Dictionary, now_ms: int) -> void:
	var remaining := next_ripe_ms(cells, now_ms)
	_timer_label.text = L10n.text("Harvest ready") if remaining == 0 else (L10n.format_text("Ripe in %s", format_countdown(remaining)) if remaining > 0 else "")
	call_deferred("_layout")

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
	if ms == 0: return L10n.text("ready")
	var total := int(ms / 1000.0)
	var h := total / 3600
	var m := (total % 3600) / 60
	return L10n.format_text("%dh%02dm", [h, m]) if h > 0 else L10n.format_text("%02d:%02d", [m, total % 60])

func set_hint(text: String) -> void:
	if not text.is_empty() and text != L10n.text("Tap a plot to work it"): show_toast(text)

func set_action(text: String, progress: float, _pending: int) -> void:
	_last_action_text = text
	_status_bar.value = progress
	if _cta_busy and not text.is_empty(): _cta.text = text

static func reject_text(code: String) -> String:
	if code == "FARM_RELOCATED": return L10n.text("This farm has moved. Reloading its new ground…")
	if code == "INVALID_FARM_TERRAIN": return L10n.text("The farm terrain could not be verified. Retry loading it.")
	return L10n.text(str(REJECT_TEXT.get(code, "Action unavailable")))

func show_toast(text: String, problem := false) -> void:
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
	_currency_divider.visible = not on
	_top_right.custom_minimum_size.x = 68 if on else 112
	_stall.visible = not on
	_refresh_seed_visibility()
	_timer_label.visible = not on
	_visitor_bar.visible = on
	call_deferred("_layout")
