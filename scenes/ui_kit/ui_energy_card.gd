class_name UiEnergyCard
extends PanelContainer
## The ONE Energy interface (SGODOT-222; Gensen Refactor/Energy 1094:77504 + EnergyTile 1093:77292, LOCK-09).
## Kind CARD: the same centred card for not enough (Short) and zero (Empty); only the headline number colour
## and the fact line differ. Facts only (`Sow 1 plot needs 2 Energy · you have 1`, `Wait · Full in 13h 20m`),
## never a predicted gain. RECOVER tiles only guide (Open bag / Show kitchen / Show on map / Show bench), never
## act; unavailable tiles are greyed with the reason (away from home Cook / Rest read `At home`). The ONLY
## button is the primary pill `Free to do now`, which closes the card: no ×, no Back, no Details.
## Kind PANEL: tapping the HUD Energy chip opens the small panel under the chip (Max, today's use as S
## NeedTiles, Newcomer Blessing). It is the same interface, not a second Energy card.
## Data in: card(facts) / panel(facts); signals out: `free_pressed`, `tile_pressed(go)`.

signal free_pressed
signal tile_pressed(go: String)

enum Kind { CARD, PANEL }

const ICON_ENERGY := preload("res://assets/p0/icons/energy.svg")
const ICON_CLOCK := preload("res://assets/p0/icons/clock.svg")
const ICON_STAR := preload("res://assets/ui/kit_icons/star.svg")

const _CARD_PAD := 16            # Energy Card main: padding 16, gap 14
const _CARD_GAP := 14
const _PANEL_PAD := Vector2(14, 12)   # Energy Panel main: padding 14 / 12, gap 12
const _PANEL_GAP := 12
const _HEAD_GAP := 4
const _TITLE_ICON := 20
const _WAIT_ICON := 14
const _MAX_ICON := 16
const _TILE_GAP := 8
const _BLESS_PAD := Vector2(10, 8)
const _BLESS_ICON := 14
const _POINTER := Vector2(18, 9)     # panel pointer towards the HUD Energy chip
const _POINTER_X := 65.0             # its tip in the main (frame at x 56, 18 wide)
const _BLESS_GAP := 2

var kind: Kind
var pointer_x := 0.0: set = set_pointer_x


## facts: {have, max, regen ("+1 in 2:41" or ""), zero, fact, wait, tiles: [{icon, label, fact, guide, go, on}]}
## (P0Logic.energy_card builds it).
static func card(facts: Dictionary) -> UiEnergyCard:
	var c := UiEnergyCard.new(Kind.CARD)
	c._build_card(facts)
	return c

## facts: {max, level ("" hides), uses: [{name, have, need, icon}], blessing: {title, detail} or {}}.
static func panel(facts: Dictionary) -> UiEnergyCard:
	var c := UiEnergyCard.new(Kind.PANEL)
	c._build_panel(facts)
	return c

func _init(kind_: Kind = Kind.CARD) -> void:
	kind = kind_
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_CARD
	box.shadow_size = UiTokens.SIZE_SHADOW_CARD_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_CARD_OFFSET_Y)
	if kind == Kind.CARD:
		box.with_margins(_CARD_PAD, _CARD_PAD, _CARD_PAD, _CARD_PAD)
		custom_minimum_size.x = UiTokens.SIZE_ENERGY_CARD_W
	else:
		box.with_margins(_PANEL_PAD.x, _PANEL_PAD.y, _PANEL_PAD.x, _PANEL_PAD.y)
		custom_minimum_size.x = UiTokens.SIZE_ENERGY_PANEL_W
	add_theme_stylebox_override(&"panel", box)

## Panel only: x of the pointer tip inside the panel, so it points at the HUD Energy chip.
func set_pointer_x(v: float) -> void:
	pointer_x = v
	queue_redraw()

## Panel only: the little pointer up to the Energy chip, drawn over the panel's top border.
func _draw() -> void:
	if kind != Kind.PANEL: return
	var base := UiTokens.STROKE_DEFAULT
	var pts := PackedVector2Array([Vector2(pointer_x - _POINTER.x * 0.5, base), Vector2(pointer_x, base - _POINTER.y),
		Vector2(pointer_x + _POINTER.x * 0.5, base)])
	draw_colored_polygon(pts, UiTokens.COLOR_SURFACE)
	draw_polyline(pts, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT, true)

# ------------------------------------------------------------------ card

func _build_card(f: Dictionary) -> void:
	var v := _column(_CARD_GAP)
	var head := _column(_HEAD_GAP)
	var title := HBoxContainer.new()
	title.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	title.add_child(_icon(ICON_ENERGY, _TITLE_ICON))
	title.add_child(UiKit.label("Energy", UiTokens.STYLE_TITLE_XB20))
	var value := UiKit.label("%d/%d" % [int(f.get("have", 0)), int(f.get("max", 0))], UiTokens.STYLE_TITLE_XB20,
		UiTokens.COLOR_DANGER if bool(f.get("zero", false)) else UiTokens.COLOR_WARNING)
	value.name = "Value"
	title.add_child(value)
	if str(f.get("regen", "")) != "":
		var regen := UiKit.label("· " + str(f.regen), UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
		regen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.add_child(regen)
	head.add_child(title)
	var fact := UiKit.label(str(f.get("fact", "")), UiTokens.STYLE_BODY_XB14)
	fact.name = "Fact"
	fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(fact)
	var wait := HBoxContainer.new()
	wait.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	wait.add_child(_icon(ICON_CLOCK, _WAIT_ICON))
	wait.add_child(UiKit.label(str(f.get("wait", "")), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
	head.add_child(wait)
	v.add_child(head)
	var recover := _column(_TILE_GAP)
	recover.add_child(UiKit.label("RECOVER", UiTokens.STYLE_CAPTION_XB12, UiTokens.COLOR_SECONDARY))
	var rule := ColorRect.new()
	rule.color = UiTokens.COLOR_BORDER
	rule.custom_minimum_size.y = UiTokens.STROKE_DEFAULT
	recover.add_child(rule)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", _TILE_GAP)
	grid.add_theme_constant_override(&"v_separation", _TILE_GAP)
	for t in f.get("tiles", []):
		var tile := UiEnergyTile.new(t)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.go_pressed.connect(func(go: String): tile_pressed.emit(go))
		grid.add_child(tile)
	recover.add_child(grid)
	v.add_child(recover)
	var foot := _column(_TILE_GAP)
	var free_now := UiCommandButton.new("Free to do now")
	free_now.name = "Free"
	free_now.activated.connect(func(): free_pressed.emit())
	foot.add_child(free_now)
	var hint := UiKit.label("Closes this card · tiles only guide you, nothing is used automatically", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(hint)
	v.add_child(foot)
	add_child(v)

# ------------------------------------------------------------------ panel

func _build_panel(f: Dictionary) -> void:
	var v := _column(_PANEL_GAP)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	top.add_child(_icon(ICON_ENERGY, _MAX_ICON))
	top.add_child(UiKit.label("Max %d" % int(f.get("max", 0)), UiTokens.STYLE_BODY_XB14))
	if str(f.get("level", "")) != "":
		var level := UiKit.label("· " + str(f.level), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(level)
	v.add_child(top)
	var uses: Array = f.get("uses", [])
	if not uses.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_theme_constant_override(&"separation", int(UiTokens.SIZE_NEED_TILE_GAP_X))
		for u in uses:
			row.add_child(UiNeedTile.new(str(u.get("name", "")), int(u.get("have", 0)), int(u.get("need", 1)),
				UiNeedTile.Size.S, u.get("icon", null), true))
		v.add_child(row)
	var blessing: Dictionary = f.get("blessing", {})
	if not blessing.is_empty():
		var box := PanelContainer.new()
		box.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_WARM, UiTokens.RADIUS_CELL)
			.with_margins(_BLESS_PAD.x, _BLESS_PAD.y, _BLESS_PAD.x, _BLESS_PAD.y))
		var col := _column(_BLESS_GAP)
		var head := HBoxContainer.new()
		head.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
		head.add_child(_icon(ICON_STAR, _BLESS_ICON, UiTokens.COLOR_TEXT))   # ink star, as the main draws it
		head.add_child(UiKit.label(str(blessing.get("title", "")), UiTokens.STYLE_CAPTION_XB12))
		col.add_child(head)
		var detail := UiKit.label(str(blessing.get("detail", "")), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(detail)
		box.add_child(col)
		v.add_child(box)
	add_child(v)
	pointer_x = _POINTER_X

# ------------------------------------------------------------------ helpers

static func _column(gap: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", int(gap))
	return v

static func _icon(tex: Texture2D, side: float, tint := Color.WHITE) -> TextureRect:
	var r := UiKit.icon(tex, side)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if tint != Color.WHITE: r.self_modulate = tint
	return r
