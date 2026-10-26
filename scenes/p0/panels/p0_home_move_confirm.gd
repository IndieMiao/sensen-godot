extends Control
## HOME-CHANGE-CONFIRM (2563:131785, SGODOT-303 PR-4; q(161), q(173)): over the spot page, a full-screen scrim and a
## card 328 wide in the middle — surface, a 1 px border, radius 24, the soft lift (0 10 28, 14 %), 16 in, 10 apart:
## `Move your farm to Tokyo?` (ExtraBold 20), `Everything on your farm moves with you. You can't change your home city
## again.` (14, text), the day line — i-clock 16, 6, `Your day resets Thu 4 AM, Tokyo time.` (Bold 13, secondary;
## none without one) — then `Move farm` (primary) and `Cancel` (secondary), 48 each.
## HOME-PIN-CONFIRM (57:160928, q(216) ③, SGODOT-342): a first pick's card in the same frame — `Build your farm here?`,
## the spot line (Bold 14, text: `San Francisco · 0.8 km to Fern Pond`), `You can move it once while your farm is new.`
## (Regular 14, secondary; q(216) B), then `Build farm` and `Cancel`; no day line.
## A tap on the scrim cancels, as Cancel does. Emits move_pressed, cancelled.
## It draws over the map card's pin names: a MapDestination lifts its name to NAME_Z so other discs never cover it, which
## also put the pond's name over this card (0.2.9: `Fern` over the body, its disc under the scrim).

signal move_pressed
signal cancelled

const _CARD_W := 328.0
const _PAD := 16
const _GAP := 10
const _TITLE_SIZE := 20
const _LINE_SIZE := 13
const _CLOCK := 16.0
const _SCRIM := Color(0.184, 0.227, 0.2, 0.32)

var card: PanelContainer
var move: UiCommandButton
var cancel: UiCommandButton

## build_line: a first pick's spot line — the card is HOME-PIN-CONFIRM; "" for the change of home.
func _init(city_name := "", day_line := "", build_line := "") -> void:
	var build := build_line != ""
	name = "MoveConfirm"
	z_index = UiMapDestination.NAME_Z + 1
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = _SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e: InputEvent): if P0Ui.is_tap(e): cancelled.emit())
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size.x = _CARD_W
	var sb := UiStyleBox.make(UiTokens.COLOR_SURFACE, 24.0, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(_PAD, _PAD, _PAD, _PAD)
	sb.shadow_color = Color(0.18, 0.231, 0.2, 0.14)
	sb.shadow_size = 28.0
	sb.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override(&"panel", sb)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", _GAP)
	card.add_child(col)
	var title := UiKit.label("Build your farm here?" if build else "Move your farm to %s?" % city_name, UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	title.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	if build:
		var spot := UiKit.label(build_line, UiTokens.STYLE_BODY_B14)
		spot.name = "SpotLine"
		spot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(spot)
	var body := UiKit.label("You can move it once while your farm is new.", UiTokens.STYLE_BODY_R14, UiTokens.COLOR_SECONDARY) if build \
		else UiKit.label("Everything on your farm moves with you. You can't change your home city again.", UiTokens.STYLE_BODY_B14)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	if day_line != "" and not build:
		var day := HBoxContainer.new()
		day.name = "Day"
		day.add_theme_constant_override(&"separation", 6)
		var clock := UiKit.icon(GameUi.icon("i-clock"), _CLOCK)
		clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		day.add_child(clock)
		var l := UiKit.label(day_line, UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
		l.name = "DayLine"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		day.add_child(l)
		col.add_child(day)
	move = UiCommandButton.new("Build farm" if build else "Move farm")
	move.name = "Move"
	move.custom_minimum_size.y = 48
	move.activated.connect(func(): move_pressed.emit())
	col.add_child(move)
	cancel = UiCommandButton.new("Cancel", UiCommandButton.Kind.SECONDARY)
	cancel.name = "Cancel"
	cancel.custom_minimum_size.y = 48
	cancel.activated.connect(func(): cancelled.emit())
	col.add_child(cancel)
