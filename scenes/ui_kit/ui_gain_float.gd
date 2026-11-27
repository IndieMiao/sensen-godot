class_name UiGainFloat
extends HBoxContainer
## UI v3 harvest float (C-W5 / M-10, C-105): the item's 24 icon and its line (`+3 Carrot Seeds`) in `TypeFloat`, white
## ExtraBold 14 with a 2 px `float/outline`, over the scene with no backing. Other tones take the v3 float colours
## (coins, energy cost / gain, XP, affinity). play(at, index): pops ×0.6 → 1 in 120, rises 40 over 800, holds to 480
## and fades in 320; a group's lines start 90 ms apart with ±6 px of x, at most 4 (UiMotion.float_text). Frees itself.
## Never takes input. The main farm's floats (UiFloatText, cream pills) are unchanged.
## C-186 (C-185 MS-06): the 2 px outline reads OUTLINE_ALPHA (0.75, the token's 0.55 was faint over bright sand, C-185
## §7); the farm merges the same item into a line still up (`+3 Carrot`) and a fifth kind into the newest line.

enum Tone { ITEM, COINS, ENERGY_COST, ENERGY_GAIN, XP, AFFINITY }

const TONE_COLORS := {
	Tone.ITEM: UiTokens.COLOR_FLOAT_DEFAULT, Tone.COINS: UiTokens.COLOR_FLOAT_COINS_V3,
	Tone.ENERGY_COST: UiTokens.COLOR_FLOAT_ENERGY_COST_V3, Tone.ENERGY_GAIN: UiTokens.COLOR_FLOAT_ENERGY_GAIN_V3,
	Tone.XP: UiTokens.COLOR_FLOAT_XP_V3, Tone.AFFINITY: UiTokens.COLOR_FLOAT_AFFINITY_V3,
}
const _ICON := 24.0
## The float outline's opacity over the scene (C-185 §7 suggested 0.55 → 0.75; a value, not a new style).
const OUTLINE_ALPHA := 0.75

var text := "": set = set_text
var _label: Label
var _icon: TextureRect

func _init(text_ := "", tone := Tone.ITEM, icon_: Texture2D = null) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", int(UiTokens.SPACE_S2))
	_icon = UiKit.icon(icon_, _ICON)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.visible = icon_ != null
	add_child(_icon)
	_label = UiKit.label("", UiTokens.STYLE_TYPE_FLOAT, TONE_COLORS[tone])
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_outline_color", Color(UiTokens.COLOR_FLOAT_OUTLINE, OUTLINE_ALPHA))
	add_child(_label)
	text = text_

func set_text(v: String) -> void:
	text = v
	if _label != null: _label.text = v

func label() -> Label: return _label

## The icon showing beside the line (null without one).
func icon() -> Texture2D: return _icon.texture if _icon.visible else null

## Still up (it frees itself when its fade ends): a merge may change its text.
func showing() -> bool: return is_inside_tree() and not is_queued_for_deletion()

## `at` = the bottom centre of where it shows, in the parent's space (the caller puts it 40 above the object).
## Lines past the fourth of a group (index ≥ 4) are not shown: the caller merges them (M-10).
func play(at: Vector2, index := 0) -> Tween:
	if index >= UiMotion.FLOAT_STACK_MAX:
		queue_free()
		return null
	size = get_combined_minimum_size()
	return UiMotion.float_text(self, at, index)
