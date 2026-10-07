class_name UiCloseButton
extends Button
## Close 483:336 (SGODOT-212): 44 round button with the 20 px close glyph. Emits `pressed`.

const GLYPH := preload("res://assets/ui/kit_icons/close.svg")

func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = UiTokens.BUTTON_CLOSE_ROUND
	icon = GLYPH
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE)
	for slot in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_hover_pressed_color", &"icon_focus_color"]:
		add_theme_color_override(slot, UiTokens.COLOR_TEXT)
	add_theme_color_override(&"icon_disabled_color", UiTokens.COLOR_DISABLED_INK)
