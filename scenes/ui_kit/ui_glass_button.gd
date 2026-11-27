class_name UiGlassButton
extends Button
## UI v3 round glass button (C-R1 / C-R2, C-105): a Ø36 `glass/fill` disc in a 44 hit area with a white 24 icon or a
## drawn glyph (‹ Back, the gear of Settings). Pressed raises the glass to 0.75 and plays M-01 (×0.94). An optional Ø14 `badge/notify` dot
## sits on its top right. Emits `pressed`.

enum Glyph { NONE, BACK, GEAR }

const _ICON := 24.0
const _BADGE := 14.0
const _GLYPH_STROKE := 2.5
const _GEAR_RING := 5.0    # the gear: a 10 ring, its teeth out to 18 across (in a 24 icon box)
const _GEAR_TOOTH := 9.0

var glyph: Glyph = Glyph.NONE
var badge := false: set = set_badge
## The glyph's and icon's colour: white on glass; the farm's clay buttons draw it in `hud/clay/ink` (UiClay.round_button).
var ink := UiTokens.COLOR_TEXT_ON_DARK:
	set(v):
		ink = v
		for slot in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_hover_pressed_color",
				&"icon_focus_color", &"icon_disabled_color"]:
			if icon != null: add_theme_color_override(slot, v)
		queue_redraw()

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
			ink, _GLYPH_STROKE, true)
	elif glyph == Glyph.GEAR:
		# A ring with eight teeth, all strokes: no filled hole that would show the glass darker than the disc around it.
		draw_arc(c, _GEAR_RING, 0.0, TAU, 32, ink, _GLYPH_STROKE, true)
		for i in 8:
			var d := Vector2.from_angle(TAU * float(i) / 8.0)
			draw_line(c + d * (_GEAR_RING + 1.0), c + d * _GEAR_TOOTH, ink, _GLYPH_STROKE + 0.5, true)
		draw_circle(c, 1.6, ink, true, -1.0, true)
	if badge:
		var r := UiTokens.SIZE_HUD_SIDE_BUTTON * 0.5
		draw_circle(c + Vector2(r, -r) * 0.72, _BADGE * 0.5, UiTokens.COLOR_BADGE_NOTIFY, true, -1.0, true)
