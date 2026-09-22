class_name FarmRelocationPreview
extends PanelContainer
## An authoritative top-down terrain preview, with persistent explicit confirmation.

signal confirmed
signal reselected
signal cancelled

var confirm_button: Button
var reselect_button: Button
var cancel_button: Button
var status: Label
var summary: Label
var terrain_image: TextureRect
var terrain_caption: Label
var preview: Dictionary = {}

func _init() -> void:
	name = "FarmRelocationPreview"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameUi.register_modal(self)
	add_theme_stylebox_override("panel", GameUi.panel_style(16))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	header.add_child(GameUi.picture(GameUi.icon("map-pin"), 28))
	var title := GameUi.label("Preview your new farm", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	cancel_button = GameUi.button("x", "", "Keep current farm")
	cancel_button.pressed.connect(func(): cancelled.emit())
	header.add_child(cancel_button)
	var scroll := TouchScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	terrain_image = TextureRect.new()
	terrain_image.name = "TerrainMap"
	terrain_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	terrain_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	terrain_image.custom_minimum_size = Vector2(0, 170)
	var terrain_card := PanelContainer.new()
	terrain_card.add_theme_stylebox_override("panel", GameUi.card_style(false, 8))
	body.add_child(terrain_card)
	terrain_card.add_child(terrain_image)
	terrain_caption = GameUi.label("", 12, GameUi.MUTED)
	terrain_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(terrain_caption)
	for message in ["Green: farmland · tan: roads · blue: pond · H: house · M: mine"]:
		var legend := GameUi.label(message, 12, GameUi.MUTED)
		legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(legend)
	summary = GameUi.label("", 14)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(summary)
	var warning := GameUi.label("Each old farm can relocate once. Confirming replaces its terrain; crops, growth times, decorations and all assets are kept. Cancelling costs nothing.", 14)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(warning)
	status = GameUi.label("", 13, GameUi.CORAL)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	reselect_button = GameUi.button("map-pin", "Choose another area", "Choose another area")
	reselect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reselect_button.pressed.connect(func(): reselected.emit())
	actions.add_child(reselect_button)
	confirm_button = GameUi.button("check", "Confirm relocation", "Confirm relocation")
	confirm_button.theme_type_variation = &"AccentButton"
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.pressed.connect(func(): confirmed.emit())
	actions.add_child(confirm_button)

func configure(data: Dictionary, city_id: String) -> bool:
	var bp := FarmSession.relocation_blueprint(data, city_id)
	if bp == null: return false
	preview = data.duplicate(true)
	terrain_caption.text = L10n.format_text("Terrain overview · north is up · %d × %d m", [int(bp.grid.x * bp.cell_m), int(bp.grid.y * bp.cell_m)])
	var picture := Image.create(bp.grid.x, bp.grid.y, false, Image.FORMAT_RGB8)
	var palette := {"soil": Color("92ad6c"), "lawn": Color("668b59"), "path": Color("d3b48a"),
		"water": Color("67a9ba"), "rock": Color("9a9c8b"), "building": Color("bd8870")}
	for y in bp.grid.y:
		for x in bp.grid.x:
			picture.set_pixel(x, bp.grid.y - 1 - y, palette.get(FarmPlot.kind_at(bp.layout_patch_id, Vector2i(x, y)), Color("92ad6c")))
	# Named markers are drawn into a larger image so H/M remain readable.
	picture.resize(bp.grid.x * 4, bp.grid.y * 4, Image.INTERPOLATE_NEAREST)
	for marker in ["house", "mine"]:
		var cell := bp.anchor(marker)
		var origin := Vector2i(cell.x * 4 - 2, (bp.grid.y - 1 - cell.y) * 4 - 3)
		var glyph := ["101", "111", "101", "101", "101"] if marker == "house" else ["10001", "11011", "10101", "10001", "10001"]
		for y in glyph.size():
			for x in glyph[y].length():
				if glyph[y][x] == "1":
					for dy in 2:
						for dx in 2:
							var px := origin + Vector2i(x * 2 + dx, y * 2 + dy)
							if px.x >= 0 and px.y >= 0 and px.x < picture.get_width() and px.y < picture.get_height(): picture.set_pixelv(px, Color("28352e"))
	terrain_image.texture = ImageTexture.create_from_image(picture)
	summary.text = L10n.format_text("%d crop plots and %d decorations need new positions to fit this terrain.", [int(data.get("moved_cells", 0)), int(data.get("moved_decorations", 0))])
	return true

func set_busy(busy: bool, pending := false, error := "") -> void:
	confirm_button.disabled = busy
	reselect_button.disabled = busy or pending
	cancel_button.disabled = busy or pending
	confirm_button.text = "Confirming…" if busy else ("Check relocation result" if pending else "Confirm relocation")
	status.text = "The result is not confirmed yet. Check it before leaving; your request will not be applied twice." if pending else error
