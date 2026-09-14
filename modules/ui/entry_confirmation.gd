extends CanvasLayer
signal answered(enter: bool)
var title: Label
var cancel_button: Button
var enter_button: Button

func _ready() -> void:
	layer = 60
	var scrim := ColorRect.new()
	scrim.color = Color(0.08, 0.15, 0.12, 0.4)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.theme = GameUi.theme()
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 24)
	scrim.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 280
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	title = GameUi.label("", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(240, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	cancel_button = GameUi.button("x", L10n.text("Stay here"), "")
	enter_button = GameUi.button("arrow-right", L10n.text("Enter"), "", true)
	for button in [cancel_button, enter_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	cancel_button.pressed.connect(func(): dismiss(false))
	enter_button.pressed.connect(func(): dismiss(true))
	hide()

func ask(destination: String) -> void:
	title.text = L10n.format_text("Enter %s?", L10n.text(destination))
	show()

func dismiss(enter: bool) -> void:
	if not visible: return
	hide()
	answered.emit(enter)
