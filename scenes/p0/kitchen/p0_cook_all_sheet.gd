class_name P0CookAllSheet
extends UiDrawer
## Cook All (Cooking Lv8; COOK-P1-4 482:369 / COOK-EMPTY 482:399, q(4) / q(124), SGODOT-282): the sheet the Cookbook
## strip's `Cook All` opens over the kitchen drawer, from P0KitchenLogic.cook_all (the server's preview).
##   plan   ObjectHeader `Cook All`; a row per pot in firing order — dish icon 24, name (12 ExtraBold), rarity dot and
##          word (10 Bold, secondary), `Stove 1 · now` / `Stove 1 · next` (10 Bold, secondary, right); the rule caption;
##          `Uses` (11 ExtraBold) and the slots summed as NeedTiles S (have/need). The fixed decision area:
##          `6 pots on 3 stoves · ingredients come out of your Bag now` (14 Bold) and `Cook All · 6 pots`.
##   empty  every stove and queue taken: `Cook All` / `No space` / `Wait for a stove or collect a ready dish.`, the stoves
##          (Busy, Queue full), Stoves 3/3 · Queues 3/3; a grey `All stoves busy` and `Kitchen` to go back. No `Details ›`
##          on either (不知火舞 on #289: Uses and the reason line already say it).
## Confirming sends nothing itself: `confirmed` goes to the kitchen, which sends cook_all and closes this sheet back to
## the Cookbook. `Kitchen` closes it too.

signal confirmed
signal back
signal unavailable(reason: String)   # the grey `All stoves busy` tapped: the kitchen toasts it

const HEIGHT_MAX := 659.0     # COOK-P1-4's sheet: 141 → 800
const ROW_H := 30.0
const WHERE_W := 84.0
const DOT := 7.0

var model := {}
var cook_button: UiCommandButton

func _init(model_: Dictionary = {}) -> void:
	super(0.0)
	model = model_
	pad = UiTokens.SPACE_PAGE
	_build()

func _build() -> void:
	body.add_theme_constant_override(&"separation", 12)
	var empty := bool(model.get("empty", false))
	body.add_child(UiObjectHeader.new({"title": "Cook All", "state": "No space" if empty else "",
		"effect": "Wait for a stove or collect a ready dish." if empty else ""}))
	if empty: _build_empty()
	else: _build_plan()
	var area := VBoxContainer.new()   # the fixed decision area, 8 apart, 12 under the content
	area.add_theme_constant_override(&"separation", 8)
	if empty:
		var busy := UiCommandButton.new("All stoves busy")
		busy.reason = "All stoves busy"
		busy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		busy.unavailable_pressed.connect(func(r: String): unavailable.emit(r))
		area.add_child(busy)
		var kitchen := UiDismissButton.new("Kitchen")
		kitchen.pressed.connect(func(): back.emit())
		area.add_child(kitchen)
	else:
		var line := UiKit.label(str(model.get("body", "")), UiTokens.STYLE_BODY_B14)
		line.name = "Body"
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		area.add_child(line)
		cook_button = UiCommandButton.new(str(model.get("label", "Cook All")))
		cook_button.sends = true   # cook_all: Offline while offline (§10.7.1)
		cook_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cook_button.activated.connect(func(): confirmed.emit())
		area.add_child(cook_button)
	body.add_child(area)
	body.minimum_size_changed.connect(_fit)
	_fit()

func _build_plan() -> void:
	var rows := VBoxContainer.new()
	rows.name = "Plan"
	rows.add_theme_constant_override(&"separation", 2)
	for r in model.get("rows", []): rows.add_child(_plan_row(r))
	body.add_child(rows)
	body.add_child(UiKit.label(str(model.get("rule", "")), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	body.add_child(UiKit.label("Uses", UiTokens.STYLE_C11_XB))
	var tiles: Array = []
	for u in model.get("uses", []):
		tiles.append(UiNeedTile.new(str(u.name), int(u.have), int(u.need), UiNeedTile.Size.S, u.icon))
	var group := UiNeedTile.group(tiles)
	group.name = "Uses"
	group.add_theme_constant_override(&"h_separation", 8)
	group.add_theme_constant_override(&"v_separation", 6)
	body.add_child(group)

## One pot: icon 24 · name · rarity dot and word · `Stove 1 · now` (Plan row, 1228:111132).
func _plan_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row"
	row.custom_minimum_size.y = ROW_H
	row.add_theme_constant_override(&"separation", 8)
	var icon := UiKit.icon(r.icon, 24)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var name := UiKit.label(str(r.name), UiTokens.STYLE_C12_XB)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name)
	var dot := _Dot.new()
	dot.color = rarity_color(int(r.rarity))
	dot.custom_minimum_size = Vector2(DOT, DOT)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var word := UiKit.label(str(r.rarity_word), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(word)
	var where := UiKit.label(str(r.where), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	where.name = "Where"
	where.custom_minimum_size.x = WHERE_W
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	where.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(where)
	return row

## COOK-EMPTY: `Stoves`, a compact card per stove (Busy · Queue full), then the two facts.
func _build_empty() -> void:
	body.add_child(UiKit.label("Stoves", UiTokens.STYLE_ROW_TITLE_B15))
	var cards := HBoxContainer.new()
	cards.name = "Stoves"
	cards.add_theme_constant_override(&"separation", 2)
	for s in model.get("stoves", []): cards.add_child(_stove_card(s))
	body.add_child(cards)
	for f in model.get("facts", []): body.add_child(UiFactRow.new(str(f[0]), str(f[1])))

## FacilityMarker compact (534:13658) without its action: `Stove 1` (14 ExtraBold), `Busy` (12 Bold, secondary), the
## queue (12 Regular, secondary) on the cream card with the border.
func _stove_card(s: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 108
	card.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER,
		UiTokens.STROKE_DEFAULT).with_margins(8, 8, 8, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 3)
	card.add_child(col)
	col.add_child(UiKit.label(str(s.title), UiTokens.STYLE_BODY_XB14))
	col.add_child(UiKit.label(str(s.state), UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY))
	if str(s.get("detail", "")) != "": col.add_child(UiKit.label(str(s.detail), UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY))
	return card

func _fit() -> void:
	height = minf(HEIGHT_MAX, body.get_combined_minimum_size().y + pad * 2.0)

static func rarity_color(r: int) -> Color:
	return [UiTokens.COLOR_RARITY_COMMON, UiTokens.COLOR_RARITY_FINE, UiTokens.COLOR_RARITY_RARE, UiTokens.COLOR_RARITY_LEGENDARY][clampi(r - 1, 0, 3)]

## The 7 px rarity dot (Rarity · Rare / Fine / Common).
class _Dot extends Control:
	var color := Color.WHITE
	func _draw() -> void: draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, color)
