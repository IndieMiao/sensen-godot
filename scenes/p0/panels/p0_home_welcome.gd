extends Control
## HOME-WELCOME (SGODOT-340 §4, 338 S0 t_city; SGODOT-342): a new player's first page when the address is near an open
## city (q(205) Near you). The card at the bottom — 16 from the sides, the safe area + 16 from the bottom, radius 20,
## 20 in: `Welcome to Gensen!` (ExtraBold 22), the city's row (as HOME-PICK's), one line (Body 14), then `Start here`
## (primary) and `Choose another city` (secondary), 48 each, 8 apart. No ×, no later. Modal: nothing under it moves.
## Behind it the map's land colour for now (§4: the colour the card shows on while the map loads; the flight from the
## globe to the city comes with the pick-a-spot map, PR-2). Copy is the draft until q(216).
## Emits start_pressed, other_pressed.

signal start_pressed
signal other_pressed

const P0CityRow := preload("res://scenes/p0/panels/p0_city_row.gd")
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const LAND := Color("F4F1E7")   # the game map's land (GodotMapPlugin applyCityStyle), as the spot page's cards
const _SIDE := 16
const _BOTTOM := 16
const _PAD := 20
const _GAP := 12
const _KEY_GAP := 8
const _TITLE_SIZE := 22
## The line under the city (李白's draft; 不知火舞 suggests `Start your farm here? It's the closest home city to you.`,
## since Near you reaches 1,500 km: q(216) decides).
const LINE := "Looks like you're near %s. Start your farm here?"

var row: Dictionary
var card: PanelContainer
var start: UiCommandButton
var other: UiCommandButton

## row_: the Near you city row ({id, name, region, climate, …}, P0HomePick.cities' `near`).
func _init(row_: Dictionary = {}, safe_bottom := 0.0) -> void:
	row = row_
	name = "HomeWelcome"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.name = "Land"
	bg.color = LAND
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	card = PanelContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = _SIDE
	card.offset_right = -_SIDE
	card.offset_bottom = -_BOTTOM - safe_bottom
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := UiStyleBox.make(UiTokens.COLOR_SURFACE, 20.0, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(_PAD, _PAD, _PAD, _PAD)
	sb.shadow_color = Color(0.18, 0.231, 0.2, 0.14)
	sb.shadow_size = 28.0
	sb.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override(&"panel", sb)
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", _GAP)
	card.add_child(col)
	var title := UiKit.label("Welcome to Gensen!", UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	title.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	col.add_child(title)
	var id := str(row.get("id", ""))
	var city := P0CityRow.new({cluster = id, name = str(row.get("name", "")), region = str(row.get("region", "")),
		climate = str(row.get("climate", "")), landmark = P0Travel.landmark_stamp(id)}, "")   # as HOME-PICK's row, not picked
	city.name = "City"
	city.custom_minimum_size.x = 0   # the card's column, not the list's 344
	city.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(city)
	var line := UiKit.label(LINE % str(row.get("name", "")), UiTokens.STYLE_BODY_R14)
	line.name = "Line"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(line)
	var keys := VBoxContainer.new()
	keys.add_theme_constant_override(&"separation", _KEY_GAP)
	col.add_child(keys)
	start = UiCommandButton.new("Start here")
	start.name = "Start"
	start.custom_minimum_size.y = 48
	start.activated.connect(func(): start_pressed.emit())
	keys.add_child(start)
	other = UiCommandButton.new("Choose another city", UiCommandButton.Kind.SECONDARY)
	other.name = "Other"
	other.custom_minimum_size.y = 48
	other.activated.connect(func(): other_pressed.emit())
	keys.add_child(other)
