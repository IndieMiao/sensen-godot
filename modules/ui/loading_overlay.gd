extends CanvasLayer
var progress: ProgressBar
var message: Label
var close_button: Button
## open_instance's args key: true gives AppRouter's default layer in English (C-144: the dynamic farm opens its parcel
## and Washington Square room with it; other callers' layers keep translating).
const ENGLISH_UI := "english_ui"
## English only (C-144): the dynamic farm's scenes show no 中文 (English-only UI copy), while the main farm keeps its
## translated layer. Set before the layer enters the tree (AppRouter, from open_instance's english_ui).
var english := false
## open_instance's args key: a Color the layer stands on instead of its paper and map picture (C-188: the dynamic farm map's
## iris colour, so a scene still loading after the trip's iris has closed shows Loading on the same colour).
const BACKDROP := "loading_backdrop"
var backdrop := Color.TRANSPARENT

func _ready() -> void:
	layer = 120
	if english: auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	GameUi.register_modal(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := ColorRect.new()
	background.color = backdrop if backdrop.a > 0.0 else GameUi.PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.theme = GameUi.theme()
	add_child(background)
	var scenery := TextureRect.new()
	# Same quiet 3D map as the city picker and account panel (2026-09-28).
	scenery.texture = load("res://assets/ui/backgrounds/map-social.png")
	scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scenery.visible = backdrop.a <= 0.0
	background.add_child(scenery)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", GameUi.panel_style(20))
	center.add_child(card)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(220, 0)
	column.add_theme_constant_override("separation", 16)
	card.add_child(column)
	var symbol := GameUi.picture(GameUi.icon("sprout"), 36)
	symbol.modulate = GameUi.GREEN
	column.add_child(symbol)
	message = GameUi.label(_text("Loading..."), 16)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(message)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(220, 8)
	progress.show_percentage = false
	progress.indeterminate = true
	column.add_child(progress)
	close_button = GameUi.button("arrow-left", _text("Go back"), "", true)
	close_button.hide()
	column.add_child(close_button)

func _text(source: String) -> String:
	return source if english else L10n.text(source)

func failed() -> void:
	message.text = _text("Could not open this place")
	progress.hide()
	close_button.show()

func _input(event: InputEvent) -> void:
	if not close_button.visible:
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		get_viewport().set_input_as_handled()
