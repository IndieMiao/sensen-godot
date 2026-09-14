extends CanvasLayer
var progress: ProgressBar
var message: Label
var close_button: Button

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := ColorRect.new()
	background.color = GameUi.PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.theme = GameUi.theme()
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(220, 0)
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	var symbol := GameUi.picture(GameUi.icon("sprout"), 36)
	symbol.modulate = GameUi.GREEN
	column.add_child(symbol)
	message = GameUi.label(L10n.text("Loading..."), 16)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(message)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(220, 4)
	progress.show_percentage = false
	progress.indeterminate = true
	column.add_child(progress)
	close_button = GameUi.button("arrow-left", L10n.text("Go back"), "", true)
	close_button.hide()
	column.add_child(close_button)

func failed() -> void:
	message.text = L10n.text("Could not open this place")
	progress.hide()
	close_button.show()

func _input(event: InputEvent) -> void:
	if not close_button.visible:
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		get_viewport().set_input_as_handled()
