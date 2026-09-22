extends PanelContainer
## Reuses command panels and the shared scroll/close contract inside the farm.

signal closed
var active: SessionPanel
var _scroll: ScrollContainer
var _heading: Label
var _symbol: TextureRect

func _init() -> void:
	name = "FarmActivitySheet"
	visible = false
	GameUi.register_modal(self)
	add_theme_stylebox_override("panel", GameUi.panel_style(14))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 9)
	column.add_child(header)
	_symbol = GameUi.picture(GameUi.icon("sprout"), 28)
	header.add_child(_symbol)
	var title := GameUi.label(L10n.text("Farm"), 18)
	_heading = title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := GameUi.button("x", "", L10n.text("Close"))
	close.pressed.connect(func(): if not is_busy(): closed.emit())
	header.add_child(close)
	_scroll = TouchScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)

func show_panel(panel: SessionPanel) -> void:
	if active:
		_scroll.remove_child(active)
		active.queue_free()
	active = panel
	_scroll.add_child(panel)
	_scroll.scroll_vertical = 0
	var context := str(panel.get("target")) if panel is JourneyActivityPanel else ""
	var heading := "Farm"
	var symbol := "sprout"
	if context == "workbench": heading = "Workbench"; symbol = "hammer"
	elif context == "counter" or context == "table": heading = "Kitchen"; symbol = "utensils"
	elif context.begins_with("resident") or context.begins_with("street_offer"):
		heading = "Residents"; symbol = "users-round"
	elif context.begins_with("project_"): heading = "Project basket"; symbol = "hammer"
	elif panel is JourneyGatheringPanel:
		heading = str(JourneyGatherings.themes().get((panel as JourneyGatheringPanel).theme_id, {}).get("name", "Farm"))
		symbol = "users-round"
	_heading.text = L10n.text(heading)
	_symbol.texture = GameUi.icon(symbol)

func fit_height(view: Vector2) -> void:
	var width := minf(620, maxf(1, view.x - 8))
	var height := minf(460, maxf(160, view.y * 0.64))
	height = minf(height, maxf(1, view.y - 92))
	position = Vector2((view.x - width) * 0.5, maxf(0, view.y - height - 4))
	size = Vector2(width, height)

func is_busy() -> bool:
	return active != null and active.busy
