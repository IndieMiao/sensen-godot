class_name UiEnergyChip
extends BaseButton
## The HUD's Energy chip (SGODOT-222; Gensen Refactor/HUD 1143:103373, LOCK-06) on its own, so a world without the
## two-row HUD shows the same bar (C-148: the dynamic farm's top bar). UiHud's row 1 is built with it.
## A 44 px hit area with the 42 px surface box: the bolt and `142/200`, the 84 × 3 track, and `+1 in 2:41` / `Full`.
## Colour is never by percentage (user 2026-10-07): ink number and green bar normally and full (bonus adds a
## light-green over-cap segment), amber number and bar only when Energy is short of the next action (`next_cost`),
## red number at 0 (UiHud.energy_state_for). Tapping it emits `pressed` (the owner opens the Energy panel, LOCK-09).

const ICON_ENERGY := preload("res://assets/p0/icons/energy.svg")
const _PAD := Vector2(8, 2)   # Figma 8 / 3 with 2 px gaps; Godot line boxes are taller, so 2 / 1 keeps 42
const _GAP := 1
const _ICON := 12

var energy := 0
var energy_max := 200
## The third line: `+1 in 2:41`, `Full` or `Bonus +30`.
var regen := "Full"
## Energy the next action needs (0: none); short of it the chip turns amber.
var next_cost := 0
## A number rolling towards `energy` (UiHud.roll_energy_from); -1 shows `energy`.
var shown := -1.0

var body: MarginContainer
var value_label: Label
var _track: _Track
var _regen: Label
## C-186 (C-185 §3.1 A, the owner's attachment-1820): the farm's cream clay capsule — 112 × 40, radius 14, `200/200`
## in `hud/clay/ink` ExtraBold 14 over a 46 × 6 `hud/energyBar` bar beside the regen line (grey 9), hung on the avatar's
## right by two small clay links. Colour rules unchanged: `hud/energyLow` only when short of the next action (q(11)).
var clay := false
var _rolling := -1.0

func _init(clay_ := false) -> void:
	clay = clay_
	if clay:
		_build_clay()
		return
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.x = UiTokens.SIZE_ENERGY_CHIP_W
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_HUD_CHIP)
	box.visual_height = UiTokens.SIZE_ENERGY_CHIP_H
	bg.add_theme_stylebox_override(&"panel", box)
	add_child(bg)
	body = MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override(&"margin_left", int(_PAD.x))
	body.add_theme_constant_override(&"margin_top", int(margin_y() + _PAD.y))
	body.add_theme_constant_override(&"margin_bottom", int(margin_y()))
	add_child(body)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", _GAP)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", _GAP)
	var bolt := UiKit.icon(ICON_ENERGY, _ICON)
	bolt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(bolt)
	value_label = UiKit.label("", UiTokens.STYLE_C14_XB)
	value_label.name = "Value"
	top.add_child(value_label)
	col.add_child(top)
	_track = _Track.new()
	_track.chip = self
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.custom_minimum_size = Vector2(UiTokens.SIZE_ENERGY_TRACK_W, UiTokens.SIZE_ENERGY_TRACK_H)
	_track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_track)
	_regen = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_regen.name = "Regen"
	col.add_child(_regen)
	refresh()

## Sets what the chip shows; unchanged values cost nothing (owners may call it every frame).
func show_energy(energy_: int, energy_max_: int, regen_: String, next_cost_: int, shown_ := -1.0) -> void:
	if energy_ == energy and energy_max_ == energy_max and regen_ == regen and next_cost_ == next_cost and shown_ == shown \
			and value_label.text != "":
		return
	energy = energy_
	energy_max = energy_max_
	regen = regen_
	next_cost = next_cost_
	shown = shown_
	refresh()

func state() -> UiHud.Energy:
	return UiHud.energy_state_for(energy, energy_max, next_cost)

func refresh() -> void:
	var e := state()
	var fmt := "%d/" + str(energy_max)
	if clay and _rolling >= 0.0 and _rolling != float(energy) and shown < 0.0 and is_visible_in_tree():
		UiMotion.roll(value_label, _rolling, energy, fmt)   # MS-03
	elif not (clay and UiMotion.rolling(value_label) and shown < 0.0):
		value_label.text = "%d/%d" % [roundi(shown) if shown >= 0.0 else energy, energy_max]
	_rolling = float(energy)
	var ink := UiTokens.COLOR_HUD_CLAY_INK if clay else UiTokens.COLOR_TEXT
	if e == UiHud.Energy.LOW: ink = UiTokens.COLOR_HUD_ENERGY_LOW if clay else UiTokens.COLOR_WARNING
	elif e == UiHud.Energy.EMPTY: ink = UiTokens.COLOR_DANGER
	value_label.add_theme_color_override(&"font_color", ink)
	_regen.text = regen
	_track.queue_redraw()

func regen_text() -> String: return _regen.text

func margin_y() -> float:
	var h := UiTokens.SIZE_HUD_CLAY_ENERGY_H if clay else UiTokens.SIZE_ENERGY_CHIP_H
	return maxf(0.0, (UiTokens.SIZE_TOUCH - h) * 0.5)

## The drawn 42 px box, centred in the 44 px hit area.
func visual_rect() -> Rect2:
	var r := get_global_rect()
	var h := float(UiTokens.SIZE_HUD_CLAY_ENERGY_H if clay else UiTokens.SIZE_ENERGY_CHIP_H)
	if r.size.y > h:
		r.position.y += (r.size.y - h) * 0.5
		r.size.y = h
	return r

## The clay capsule (see `clay`): the face, two links reaching left to the avatar, `200/200` over the bar and the regen.
func _build_clay() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(UiTokens.SIZE_HUD_CLAY_ENERGY_W, UiTokens.SIZE_TOUCH)
	for k in 2:
		var link := Panel.new()
		link.name = "Link%d" % k
		link.mouse_filter = Control.MOUSE_FILTER_IGNORE
		link.add_theme_stylebox_override(&"panel", UiClay.face(2.0))
		link.size = Vector2(UiTokens.SPACE_S3 + 6.0, 6.0)
		link.position = Vector2(-UiTokens.SPACE_S3 - 3.0, margin_y() + 9.0 + 16.0 * k)
		add_child(link)
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := UiClay.face(UiTokens.SIZE_HUD_CLAY_RADIUS)
	box.expand_margin_top = -margin_y()
	box.expand_margin_bottom = -margin_y()
	bg.add_theme_stylebox_override(&"panel", box)
	add_child(bg)
	body = MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override(&"margin_left", 12)
	body.add_theme_constant_override(&"margin_top", int(margin_y() + 3.0))
	body.add_theme_constant_override(&"margin_bottom", int(margin_y() + 3.0))
	add_child(body)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(col)
	value_label = UiKit.label("", UiTokens.STYLE_C14_XB, UiTokens.COLOR_HUD_CLAY_INK)
	value_label.name = "Value"
	col.add_child(value_label)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 5)
	col.add_child(row)
	_track = _Track.new()
	_track.chip = self
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.custom_minimum_size = Vector2(UiTokens.SIZE_HUD_CLAY_BAR_W, UiTokens.SIZE_HUD_CLAY_BAR_H)
	_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_track)
	_regen = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_HUD_CLAY_INK_SOFT)
	_regen.name = "Regen"
	_regen.add_theme_font_size_override(&"font_size", UiTokens.SIZE_HUD_CLAY_REGEN_FONT)
	row.add_child(_regen)
	refresh()
	_rolling = -1.0   # the first real value shows at once; later changes roll

func _get_minimum_size() -> Vector2:
	if clay: return Vector2(UiTokens.SIZE_HUD_CLAY_ENERGY_W, UiTokens.SIZE_TOUCH)
	return body.get_combined_minimum_size() if body != null else Vector2.ZERO

## The 84 × 3 bar: the border colour under a fill to the share of the pool, amber when short (LOCK-06), none at 0.
class _Track extends Control:
	var chip: UiEnergyChip

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var radius := size.y * 0.5
		draw_style_box(UiStyleBox.make(UiTokens.COLOR_HUD_CLAY_EDGE if chip.clay else UiTokens.COLOR_BORDER, radius), rect)
		var e := chip.state()
		if e == UiHud.Energy.EMPTY: return
		var mx := maxf(1.0, float(chip.energy_max))
		var pct := clampf(float(chip.energy) / mx, 0.0, 1.0)
		var fill := UiTokens.COLOR_ENERGY_HUD_FILL if e == UiHud.Energy.LOW else UiTokens.COLOR_PRIMARY
		if chip.clay: fill = UiTokens.COLOR_HUD_ENERGY_LOW if e == UiHud.Energy.LOW else UiTokens.COLOR_HUD_ENERGY_BAR
		draw_style_box(UiStyleBox.make(fill, radius), Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * pct), size.y)))
		if e == UiHud.Energy.BONUS:
			var over := clampf((float(chip.energy) - mx) / mx, 0.0, 1.0)
			var w := maxf(size.y, size.x * over)
			draw_rect(Rect2(Vector2(size.x - w, 0.0), Vector2(w, size.y)), UiTokens.COLOR_ENERGY_BONUS)
