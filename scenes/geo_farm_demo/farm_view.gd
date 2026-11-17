extends Control
## Independent demo view. Parent owns networking, selection and claims.
signal back_requested

const GridView = preload("res://scenes/geo_farm_demo/farm_grid.gd")
const BlockData = preload("res://scenes/geo_farm_demo/farm_block.gd")
const INK := Color("243d32")
const MUTED := Color("596b61")
const NAMES := {"water": "Water", "residential": "Residential", "public": "Public", "green": "Green space", "mixed": "Mixed use", "commercial": "Commercial", "unknown": "Unknown", "path": "Path", "building": "House"}
var _title: Label
var _stats: Label
var _status: Label
var _grid: Control
var _legend: HFlowContainer
var _back: Button
var _zoom_in: Button
var _zoom_out: Button
var _fit: Button
var _source: Label
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
	margins.add_theme_constant_override("margin_top", 16)
	margins.add_theme_constant_override("margin_bottom", 14)
	add_child(margins)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margins.add_child(column)
	var tag := _label("SAN FRANCISCO · FARM DEMO", 12, MUTED)
	column.add_child(tag)
	_title = _label("Parcel farm", 22, INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.max_lines_visible = 2
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)
	_stats = _label("", 13, MUTED)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stats)
	_grid = GridView.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.custom_minimum_size = Vector2(0, 96)
	_grid.cell_selected.connect(_on_cell_selected)
	_grid.view_changed.connect(_on_view_changed)
	column.add_child(_grid)
	_legend = HFlowContainer.new()
	_legend.add_theme_constant_override("h_separation", 14)
	_legend.add_theme_constant_override("v_separation", 6)
	column.add_child(_legend)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	column.add_child(actions)
	_status = _label("North ↑", 12, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_status)
	_zoom_out = _small_button("−", func(): _grid.zoom_at(_grid._zoom / 1.4, _grid.size * 0.5))
	_fit = _small_button("Fit", func(): _grid.fit())
	_zoom_in = _small_button("+", func(): _grid.zoom_at(_grid._zoom * 1.4, _grid.size * 0.5))
	for button in [_zoom_out, _fit, _zoom_in]:
		actions.add_child(button)
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
	_source = _label("Pinch to zoom · Drag to move\nDataSF / SF Planning · PDDL / CC0", 10, MUTED)
	_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_source)
	_on_view_changed(1.0)

func show_loading(block_name: String = "Parcel farm") -> void:
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
	_show_prepared(decoded)
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

func _show_prepared(decoded: Dictionary) -> void:
	_build()
	var cells: Array = decoded.cells
	var palette: Dictionary = decoded.palette
	_title.text = decoded.address if not decoded.address.strip_edges().is_empty() else decoded.name
	var area_label := "parcel area" if decoded.schema == 2 else "inset area"
	_stats.text = "%d cells · %.0f m² %s" % [cells.size(), decoded.area_m2, area_label]
	if decoded.schema == 2:
		_stats.text += "\nHouse %d · Yard %d · Water %d · Path %d" % [decoded.counts.house, decoded.counts.yard, decoded.counts.water, decoded.counts.path]
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
	_status.text = "North ↑"
	if decoded.schema == 2 and decoded.counts.house == 0:
		_status.text = "North ↑\nHouse footprint not mapped"
	_source.text = "Pinch to zoom · Drag to move\nDataSF / SF Planning · PDDL / CC0" if decoded.schema == 2 else "Mapped land use, not a ground survey.\nData: US Census / DataSF / SF Planning · PDDL / CC0"

func _clear_legend() -> void:
	for child in _legend.get_children():
		_legend.remove_child(child)
		child.queue_free()

func _on_cell_selected(kind: String) -> void:
	_status.text = "North ↑ · " + str(NAMES.get(kind, "Unknown"))

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _small_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	return button

func _on_view_changed(zoom: float) -> void:
	if _zoom_in == null:
		return
	var empty: bool = _grid._cells.is_empty()
	_zoom_in.disabled = empty or zoom >= GridView.MAX_ZOOM
	_zoom_out.disabled = empty or zoom <= GridView.MIN_ZOOM
	_fit.disabled = empty
