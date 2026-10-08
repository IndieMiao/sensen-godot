class_name UiEnergyTile
extends BaseButton
## RECOVER guidance tile in the Energy card (SGODOT-222; Gensen Refactor/EnergyTile 1093:77292, LOCK-09).
## Facts only (counts and states), never a predicted gain. A tap only guides (Open bag / Show kitchen /
## Show on map / Show bench): it never eats, cooks, buys or rests for the player. Unavailable: greyed, the
## reason replaces the fact (No dishes in bag · Rested today · At home), no guide link, a tap does nothing.
## Data in: {icon, label, fact, guide, go, on}; signal out: `go_pressed(go)`.

signal go_pressed(go: String)

const _PAD := 10       # EnergyTile main: padding 10, gap 2
const _GAP := 2
const _DISC := 24      # icon disc 24 with a 16 icon
const _ICON := 16

var available := true
var go := ""

func _init(t: Dictionary = {}) -> void:
	focus_mode = Control.FOCUS_NONE
	available = bool(t.get("on", true))
	go = str(t.get("go", ""))
	custom_minimum_size.y = UiTokens.SIZE_ENERGY_TILE_H
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_TILE_CORE, UiTokens.RADIUS_ENERGY_TILE, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
	add_child(bg)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]: pad.add_theme_constant_override(side, _PAD)
	add_child(pad)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", _GAP)
	pad.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.custom_minimum_size = Vector2(_DISC, _DISC)
	disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _DISC * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
	var icon := UiKit.icon(t.get("icon", null) if t.get("icon", null) is Texture2D else null, _ICON)
	icon.position = Vector2(_DISC - _ICON, _DISC - _ICON) * 0.5
	icon.size = Vector2(_ICON, _ICON)
	disc.add_child(icon)
	if not available: disc.modulate.a = UiTokens.OPACITY_UNAVAILABLE_ICON
	head.add_child(disc)
	var name_ := UiKit.label(str(t.get("label", "")), UiTokens.STYLE_BODY_XB14, UiTokens.COLOR_TEXT if available else UiTokens.COLOR_SECONDARY)
	name_.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(name_)
	col.add_child(head)
	var fact := UiKit.label(str(t.get("fact", "")), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(fact)
	if available and str(t.get("guide", "")) != "":
		col.add_child(UiKit.label("%s ›" % str(t.guide), UiTokens.STYLE_CAPTION_XB12, UiTokens.COLOR_INFO))
	pressed.connect(func(): if available and go != "": go_pressed.emit(go))

func _get_minimum_size() -> Vector2:
	if get_child_count() < 2: return Vector2.ZERO
	return (get_child(1) as Control).get_combined_minimum_size()
