class_name BagSheet
extends Control

signal closed()

var session: FarmSession
var active: BagPanel
var panel: PanelContainer

func setup(value: FarmSession) -> void:
	session = value

func _ready() -> void:
	name = "BagSheet"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 20
	theme = GameUi.theme()
	GameUi.register_modal(self)
	var scrim := ColorRect.new()
	scrim.color = Color(0.11, 0.10, 0.24, 0.14)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(event):
		if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.is_pressed():
			close()
			accept_event())
	add_child(scrim)
	panel = PanelContainer.new()
	panel.name = "BagSurface"
	panel.theme_type_variation = &"BottomSheet"
	panel.add_theme_stylebox_override("panel", GameUi.panel_style(10))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	active = BagPanel.new()
	active.setup(session)
	active.close_requested.connect(close)
	active.minimum_size_changed.connect(_layout.call_deferred)
	active.goal_requested.connect(func(goal): BagNavigation.follow(active, goal))
	panel.add_child(active)
	resized.connect(_layout)
	_layout.call_deferred()
	hide()

func _layout() -> void:
	if panel == null: return
	var width := minf(620, maxf(1, size.x - 8))
	var fraction := 0.68 if size.y < 620 else 0.62
	if active != null and active.page == "character": fraction = 0.70
	var height := minf(650, maxf(280, size.y * fraction))
	height = minf(height, maxf(1, size.y - 80))
	panel.position = Vector2((size.x - width) * 0.5, size.y - height - 4)
	panel.size = Vector2(width, height)

func open(page := "") -> void:
	show()
	if not page.is_empty(): active.select_page(page)
	active.refresh()
	_layout()

func is_busy() -> bool:
	return active != null and active.busy

func close() -> void:
	if is_busy(): return
	if active.search: active.search.release_focus()
	hide()
	closed.emit()

func consume_back() -> bool:
	if not visible: return false
	if is_busy(): return true
	if active.consume_back(): return true
	close()
	return true
