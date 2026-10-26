extends Button
## BackPill (2775:162964): `‹  Change city` on a white pill, ExtraBold 14, 12 / 14 in, 12 over and under; it hugs its
## label (116 wide for Change city, 94 for Settings).
## (Moved from the three-spot page, gone with SGODOT-342 PR-2.) Preloaded, no class_name.

func _init(label: String) -> void:
	name = "Back"
	focus_mode = Control.FOCUS_NONE
	text = "‹  " + label
	theme_type_variation = UiTokens.STYLE_BODY_XB14
	add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT)
	for s in [&"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		add_theme_color_override(s, UiTokens.COLOR_TEXT)
	add_theme_font_size_override(&"font_size", 14)
	for s in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTokens.COLOR_SURFACE_RAISED.darkened(0.04) if s == &"pressed" else UiTokens.COLOR_SURFACE_RAISED
		sb.set_corner_radius_all(22)
		sb.content_margin_left = 12
		sb.content_margin_right = 14
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		add_theme_stylebox_override(s, sb)
