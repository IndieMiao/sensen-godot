extends PanelContainer

signal closed()
signal gift_requested(resident_id: String)

var session: FarmSession
var active: SessionPanel
var section := "supplies"
var _scroll: ScrollContainer
var _tabs: Dictionary = {}

func setup(value: FarmSession) -> void:
	session = value

func _ready() -> void:
	visible = false
	var col := VBoxContainer.new()
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := GameUi.label("Harvest & home", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := GameUi.button("x", "", "Close")
	close.pressed.connect(func():
		if not is_busy(): closed.emit())
	head.add_child(close)
	var tabs := HBoxContainer.new()
	col.add_child(tabs)
	for spec in [["supplies", "shopping-bag", "Supplies"], ["choices", "heart", "Harvest uses"],
		["project", "shopping-basket", "Project basket"], ["growth", "shovel", "Growth"],
		["journal", "book-open", "Handbook"]]:
		var button := GameUi.button(spec[1], "", spec[2])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): select_section(spec[0]))
		_tabs[spec[0]] = button
		tabs.add_child(button)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	select_section(section)

func select_section(value: String) -> void:
	if is_busy(): return
	section = value
	if active:
		_scroll.remove_child(active)
		active.queue_free()
	active = load("res://scenes/place/kitchen_panel.gd" if section == "journal" else "res://scenes/place/economy_panel.gd").new()
	active.section = section
	active.setup(session)
	if active.has_signal("gift_requested"):
		active.connect("gift_requested", func(id): gift_requested.emit(id))
	_scroll.add_child(active)
	_scroll.scroll_vertical = 0
	for id in _tabs:
		_tabs[id].theme_type_variation = &"TabSelectedButton" if id == section else &"TabButton"

func is_busy() -> bool:
	return active != null and active.busy

func fit_height(area: Vector2) -> void:
	var height := minf(480, area.y - 80)
	position = Vector2(0, area.y - height)
	size = Vector2(area.x, height)
