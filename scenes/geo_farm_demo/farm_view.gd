extends Control
## Independent demo view. Parent owns networking, selection and claims.
signal back_requested

const GridView = preload("res://scenes/geo_farm_demo/farm_grid.gd")
const BlockData = preload("res://scenes/geo_farm_demo/farm_block.gd")
const INK := Color("243d32")
const MUTED := Color("596b61")
const NAMES := {"water": "Water", "residential": "Residential", "public": "Public", "green": "Green space", "mixed": "Mixed use", "commercial": "Commercial", "unknown": "Unknown", "path": "Path"}
var _title: Label
var _stats: Label
var _status: Label
var _grid: Control
var _legend: HFlowContainer
var _back: Button
var _built := false

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("f5f6f0")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + edge, 18)
	margins.add_theme_constant_override("margin_top", 24)
	margins.add_theme_constant_override("margin_bottom", 16)
	add_child(margins)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margins.add_child(column)
	var tag := _label("SAN FRANCISCO · FARM DEMO", 12, MUTED)
	column.add_child(tag)
	_title = _label("Block farm", 24, INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)
	_stats = _label("", 14, MUTED)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stats)
	_grid = GridView.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.custom_minimum_size = Vector2(0, 120)
	_grid.cell_selected.connect(_on_cell_selected)
	column.add_child(_grid)
	_legend = HFlowContainer.new()
	_legend.add_theme_constant_override("h_separation", 14)
	_legend.add_theme_constant_override("v_separation", 6)
	column.add_child(_legend)
	_status = _label("Select a block on the map.", 13, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_back = Button.new()
	_back.text = "Back to map"
	_back.custom_minimum_size.y = 48
	_back.add_theme_font_size_override("font_size", 17)
	_back.add_theme_color_override("font_color", INK)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("dce9d6")
	style.set_corner_radius_all(12)
	_back.add_theme_stylebox_override("normal", style)
	_back.pressed.connect(func(): back_requested.emit())
	column.add_child(_back)
	var source := _label("Mapped land use, not a ground survey.\nData: US Census / DataSF / SF Planning · PDDL / CC0", 10, MUTED)
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(source)

func show_loading(block_name: String = "Block farm") -> void:
	_build()
	_title.text = block_name
	_stats.text = ""
	_grid.set_cells([])
	_clear_legend()
	_status.text = "Loading farm…"

func show_error(message: String = "Farm could not be loaded. Please try again from the map.") -> void:
	show_loading()
	_status.text = message

func show_block(data: Dictionary) -> bool:
	var decoded := BlockData.decode(data)
	if not decoded.ok:
		show_error(decoded.error)
		return false
	_show_prepared(decoded.name, decoded.area_m2, decoded.cells, decoded.palette)
	return true

func load_block_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 2 * 1024 * 1024:
		show_error()
		return false
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		show_error("Farm data could not be read. Please return to the map.")
		return false
	return show_block(data)

func _show_prepared(block_name: String, area_m2: float, cells: Array, palette: Dictionary) -> void:
	_build()
	_title.text = block_name
	_stats.text = "%d cells · %.0f m² inset area" % [cells.size(), area_m2]
	_grid.set_cells(cells, palette)
	_clear_legend()
	var present := {}
	for cell: Dictionary in cells:
		present[cell.kind] = true
	for kind: String in NAMES:
		if not present.has(kind):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var swatch := ColorRect.new()
		swatch.color = palette[kind]
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		row.add_child(_label(NAMES[kind], 12, MUTED))
		_legend.add_child(row)
	_status.text = "North ↑ · Tap a cell for land use."

func _clear_legend() -> void:
	for child in _legend.get_children():
		_legend.remove_child(child)
		child.queue_free()

func _on_cell_selected(kind: String) -> void:
	_status.text = "North ↑ · " + str(NAMES.get(kind, "Unknown")) + " (mapped land use)"

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
