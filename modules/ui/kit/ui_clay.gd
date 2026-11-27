class_name UiClay
## The farm main screen's clay and dark-glass parts (C-185 D-489 §3.1, owner reference attachment-1820; C-186):
## the player's own numbers and portrait sit on cream clay (`hud/clay/*`: face, a 2.5 darker bottom edge and a soft
## warm shadow), the place and the guide on dark glass (`glass/dark`), the quick bar on frosted white (`bar/frost*`).
## These styles are the farm main screen's only; other pages keep the v3 glass and paper (§5.5).

## Cream clay: `hud/clay/face` over a `hud/clay/edge` bottom edge, with a soft warm shadow.
static func face(radius: float, fill := UiTokens.COLOR_HUD_CLAY_FACE) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_corner_radius_all(int(round(radius)))
	b.border_color = UiTokens.COLOR_HUD_CLAY_EDGE
	b.border_width_bottom = int(ceilf(UiTokens.SIZE_HUD_CLAY_EDGE))
	b.shadow_color = UiTokens.COLOR_HUD_CLAY_SHADOW
	b.shadow_size = 6
	b.shadow_offset = Vector2(0, 3)
	b.anti_aliasing = true
	return b

## The same clay, pressed: no shadow, the edge flattened (M-01 scales the control on top).
static func face_pressed(radius: float) -> StyleBoxFlat:
	var b := face(radius, UiTokens.COLOR_HUD_CLAY_EDGE.lerp(UiTokens.COLOR_HUD_CLAY_FACE, 0.5))
	b.shadow_size = 2
	b.shadow_offset = Vector2(0, 1)
	return b

## Dark glass (`glass/dark`, 75%): the one-line place bar and the guide bar; no shadow.
static func glass_dark(radius: float) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_GLASS_DARK
	b.set_corner_radius_all(int(round(radius)))
	b.anti_aliasing = true
	return b

## Frosted white (`bar/frost` with a 1.2 `bar/frostEdge` line): the quick bar's backing.
static func frost(radius: float) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_BAR_FROST
	b.set_corner_radius_all(int(round(radius)))
	b.border_color = UiTokens.COLOR_BAR_FROST_EDGE
	b.set_border_width_all(int(round(UiTokens.SIZE_QUICK_FROST_EDGE)))
	b.anti_aliasing = true
	return b

## A frosted item slot (`bar/frostSlot`).
static func frost_slot(radius: float) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_BAR_FROST_SLOT
	b.set_corner_radius_all(int(round(radius)))
	b.anti_aliasing = true
	return b

## A Ø36 cream clay disc (`hud/clay/button`) centred in a 44 hit-area Button (the farm's Back and task buttons,
## C-185 §3.1 B); pressed flattens it (M-01 scales on top). A UiGlassButton's glyph turns `hud/clay/ink`.
## `width`: the hit area's width (the HUD row narrows it to 40 to keep inside a 360 screen; 44 high always).
static func round_button(b: Button, width := float(UiTokens.SIZE_TOUCH_MIN)) -> void:
	var d := float(UiTokens.SIZE_HUD_CLAY_BUTTON)
	var inset := (float(UiTokens.SIZE_TOUCH_MIN) - d) * 0.5
	var side := (width - d) * 0.5
	b.custom_minimum_size.x = width
	b.flat = false   # a flat Button (UiTaskButton) draws no normal/hover box: the disc would not show
	var up := face(d * 0.5)
	var down := face_pressed(d * 0.5)
	for box: StyleBoxFlat in [up, down]:
		box.expand_margin_left = -side
		box.expand_margin_right = -side
		box.expand_margin_top = -inset
		box.expand_margin_bottom = -inset
	for st in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(st, up)
	for st in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(st, down)
	if b is UiGlassButton: (b as UiGlassButton).ink = UiTokens.COLOR_HUD_CLAY_INK

## A content margin on every side of `b`, returned for chaining.
static func padded(b: StyleBox, h: float, v: float) -> StyleBox:
	b.content_margin_left = h
	b.content_margin_right = h
	b.content_margin_top = v
	b.content_margin_bottom = v
	return b

## Three short yellow strokes (`bar/sparkle`) fanning out up-right of `at`, as on the reference's icons.
static func draw_sparkle(ci: CanvasItem, at: Vector2, scale := 1.0, color := UiTokens.COLOR_BAR_SPARKLE) -> void:
	for i in 3:
		var a := deg_to_rad(-80.0 + 40.0 * i)
		var dir := Vector2(cos(a), sin(a))
		ci.draw_line(at + dir * 3.0 * scale, at + dir * (7.0 - absf(i - 1) * 1.5) * scale, color, 1.8 * scale, true)
