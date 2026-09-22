extends PanelContainer

signal closed()
signal gift_requested(resident_id: String)
signal goal_requested(goal: Dictionary)

var session: FarmSession
var active: SessionPanel
var section := "supplies"
var _scroll: ScrollContainer
var _tabs: Dictionary = {}
var _starting_journey := false
var _journey_button: Button
var _tabs_row: HBoxContainer
var _title: Label
var _column: VBoxContainer
var _header: HBoxContainer

func setup(value: FarmSession) -> void:
	session = value

func _ready() -> void:
	visible = false
	GameUi.register_modal(self)
	add_theme_stylebox_override("panel", GameUi.panel_style(14))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_column = col
	add_child(col)
	var head := HBoxContainer.new()
	_header = head
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(GameUi.picture(GameUi.icon("backpack"), 28))
	var journey := GameUi.button("compass", L10n.text("Explore the neighbourhood"), L10n.text("Begin your neighbourhood journey"), true)
	_journey_button = journey
	journey.pressed.connect(func():
		if is_busy(): return
		_starting_journey = true
		journey.disabled = true
		var accepted := await session.send("start_journey", {})
		_starting_journey = false
		journey.disabled = false
		if accepted: closed.emit()
		else: journey.text = SessionPanel.error_text(session.last_error_code))
	col.add_child(journey)
	var title := GameUi.label(L10n.text("Harvest & home"), 18)
	_title = title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := GameUi.button("x", "", L10n.text("Close"))
	close.pressed.connect(_close)
	head.add_child(close)
	var tabs := HBoxContainer.new()
	_tabs_row = tabs
	col.add_child(tabs)
	for spec in [["supplies", "shopping-bag", L10n.text("Supplies")], ["choices", "heart", L10n.text("Harvest uses")],
		["project", "shopping-basket", L10n.text("Project basket")], ["growth", "shovel", L10n.text("Growth")],
		["journal", "book-open", L10n.text("Handbook")]]:
		var button := GameUi.button(spec[1], "", spec[2])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): select_section(spec[0]))
		_tabs[spec[0]] = button
		tabs.add_child(button)
	_scroll = TouchScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	select_section(section)

func select_section(value: String) -> void:
	if is_busy(): return
	var journey := JourneyProgress.active(session.state) if session else false
	section = "supplies" if journey else value
	_journey_button.visible = not journey
	_tabs_row.visible = not journey
	_title.text = L10n.text("Your bag") if journey else L10n.text("Harvest & home")
	if active:
		active.get_parent().remove_child(active)
		active.queue_free()
	var unified_bag := journey or section == "supplies"
	_header.visible = not unified_bag
	_scroll.visible = not unified_bag
	if unified_bag:
		active = BagPanel.new()
		active.goal_requested.connect(func(goal): goal_requested.emit(goal))
		(active as BagPanel).close_requested.connect(_close)
		active.minimum_size_changed.connect(_refit.call_deferred)
	else:
		active = load("res://scenes/place/kitchen_panel.gd" if section == "journal" else "res://scenes/place/economy_panel.gd").new()
		active.section = section
	active.setup(session)
	if active.has_signal("gift_requested"):
		active.connect("gift_requested", func(id): gift_requested.emit(id))
	if unified_bag: _column.add_child(active)
	else: _scroll.add_child(active)
	_scroll.scroll_vertical = 0
	for id in _tabs:
		_tabs[id].theme_type_variation = &"TabSelectedButton" if id == section else &"TabButton"

func is_busy() -> bool:
	return _starting_journey or active != null and active.busy

func consume_back() -> bool:
	return active != null and active.consume_back()

func fit_height(area: Vector2) -> void:
	var width := minf(660, maxf(1, area.x - 8))
	var fraction := 0.68 if area.y < 620 else 0.62
	if active is BagPanel and (active as BagPanel).page == "character": fraction = 0.70
	var height := minf(600, area.y * fraction) if active is BagPanel else minf(460, area.y * 0.64)
	height = clampf(height, 1, maxf(1, area.y - 64))
	position = Vector2((area.x - width) * 0.5, area.y - height - 4)
	size = Vector2(width, height)

func _refit() -> void:
	if visible and is_inside_tree() and get_parent() is Control:
		fit_height((get_parent() as Control).size)

func _close() -> void:
	if is_busy(): return
	if active is BagPanel and (active as BagPanel).search: (active as BagPanel).search.release_focus()
	closed.emit()
