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

func _init() -> void:
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
	value_label.text = "%d/%d" % [roundi(shown) if shown >= 0.0 else energy, energy_max]
	var ink := UiTokens.COLOR_TEXT
	if e == UiHud.Energy.LOW: ink = UiTokens.COLOR_WARNING
	elif e == UiHud.Energy.EMPTY: ink = UiTokens.COLOR_DANGER
	value_label.add_theme_color_override(&"font_color", ink)
	_regen.text = regen
	_track.queue_redraw()

func regen_text() -> String: return _regen.text

func margin_y() -> float: return maxf(0.0, (UiTokens.SIZE_TOUCH - UiTokens.SIZE_ENERGY_CHIP_H) * 0.5)

## The drawn 42 px box, centred in the 44 px hit area.
func visual_rect() -> Rect2:
	var r := get_global_rect()
	if r.size.y > UiTokens.SIZE_ENERGY_CHIP_H:
		r.position.y += (r.size.y - UiTokens.SIZE_ENERGY_CHIP_H) * 0.5
		r.size.y = UiTokens.SIZE_ENERGY_CHIP_H
	return r

func _get_minimum_size() -> Vector2:
	return body.get_combined_minimum_size() if body != null else Vector2.ZERO

## The 84 × 3 bar: the border colour under a fill to the share of the pool, amber when short (LOCK-06), none at 0.
class _Track extends Control:
	var chip: UiEnergyChip

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var radius := size.y * 0.5
		draw_style_box(UiStyleBox.make(UiTokens.COLOR_BORDER, radius), rect)
		var e := chip.state()
		if e == UiHud.Energy.EMPTY: return
		var mx := maxf(1.0, float(chip.energy_max))
		var pct := clampf(float(chip.energy) / mx, 0.0, 1.0)
		var fill := UiTokens.COLOR_ENERGY_HUD_FILL if e == UiHud.Energy.LOW else UiTokens.COLOR_PRIMARY
		draw_style_box(UiStyleBox.make(fill, radius), Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * pct), size.y)))
		if e == UiHud.Energy.BONUS:
			var over := clampf((float(chip.energy) - mx) / mx, 0.0, 1.0)
			var w := maxf(size.y, size.x * over)
			draw_rect(Rect2(Vector2(size.x - w, 0.0), Vector2(w, size.y)), UiTokens.COLOR_ENERGY_BONUS)
