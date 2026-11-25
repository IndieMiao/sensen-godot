class_name UiGlassButton
extends Button
## UI v3 round glass button (C-R1 / C-R2, C-105): a Ø36 `glass/fill` disc in a 44 hit area with a white 24 icon or a
## drawn glyph (‹ Back). Pressed raises the glass to 0.75 and plays M-01 (×0.94). An optional Ø14 `badge/notify` dot
## sits on its top right. Emits `pressed`.

enum Glyph { NONE, BACK }

const _ICON := 24.0
const _BADGE := 14.0
const _GLYPH_STROKE := 2.5

var glyph: Glyph = Glyph.NONE
var badge := false: set = set_badge

func _init(icon_: Texture2D = null, glyph_: Glyph = Glyph.NONE) -> void:
	glyph = glyph_
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = UiTokens.BUTTON_GLASS_ROUND
	custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH_MIN, UiTokens.SIZE_TOUCH_MIN)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if icon_ != null:
		icon = icon_
		expand_icon = true
		icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_theme_constant_override(&"icon_max_width", int(_ICON))
		for slot in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_hover_pressed_color",
				&"icon_focus_color", &"icon_disabled_color"]:
			add_theme_color_override(slot, UiTokens.COLOR_TEXT_ON_DARK)
	UiMotion.press_feedback(self)

func set_badge(v: bool) -> void:
	badge = v
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	if glyph == Glyph.BACK:
		draw_polyline(PackedVector2Array([c + Vector2(3, -7), c + Vector2(-4, 0), c + Vector2(3, 7)]),
			UiTokens.COLOR_TEXT_ON_DARK, _GLYPH_STROKE, true)
	if badge:
		var r := UiTokens.SIZE_HUD_SIDE_BUTTON * 0.5
		draw_circle(c + Vector2(r, -r) * 0.72, _BADGE * 0.5, UiTokens.COLOR_BADGE_NOTIFY, true, -1.0, true)
