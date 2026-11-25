extends RefCounted
## UI v3 look of the account panel (C-106), after the owner-approved page ④ Sign in of C-85 (D-201, Q-124) with the
## C-105 tokens: the scene blurred under a light scrim, one paper card with a `surface/header` band, the sign-post hero
## and the step's name in a tag pill, 46 high white fields, lime primary keys, text links, the 6-box code entry and a
## white toast with a red bar for errors that are not about a field. Only the dynamic farm map opens the panel in this
## look (AccountPanel.open(..., true)); the main farm's screens keep theirs.
##   field    46 high, radius 14, white, 1.5 → 2 px `#DDD9CD`-like edge; focus: `action/primary` edge and a 3 px glow;
##            error: `action/danger` edge on the danger tint (C-85 README §2.7)
##   card     312 wide (24 in on a 360 screen), radius xl, e2; band 40, hero 80 over its top edge 12 in, ✕ at the right

const CARD_W := 312.0          # C-85 ④: the card 24 in from each side of the 360 screen
const FIELD_H := 46.0          # C-85 README §2.7
const FIELD_RADIUS := 14       # C-85 README §2.7
const FIELD_EDGE := 2          # 1.5 in the README, whole pixels in StyleBoxFlat
const FOCUS_GLOW := 3          # C-85 README §2.7: 3 px glow in the edge colour
const CODE_GAP := 8.0
const SHOW_W := 56.0           # the in-field "Show" key
const HERO_OVER := 32.0        # the hero's top above the card's (as UiModalPanel)

static func field_box(edge: Color, fill: Color, glow := false, right := UiTokens.SPACE_S6) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_corner_radius_all(FIELD_RADIUS)
	b.border_color = edge
	b.set_border_width_all(FIELD_EDGE)
	if glow:
		b.shadow_color = Color(edge, 0.35)
		b.shadow_size = FOCUS_GLOW
	b.content_margin_left = UiTokens.SPACE_S6
	b.content_margin_right = right
	b.content_margin_top = UiTokens.SPACE_S3
	b.content_margin_bottom = UiTokens.SPACE_S3
	return b

## The field look (LineEdit or OptionButton); `error` paints it red until the next step or keystroke.
static func style_field(c: Control, error := false, right := UiTokens.SPACE_S6) -> void:
	var edge := UiTokens.COLOR_ACTION_DANGER if error else UiTokens.COLOR_SECONDARY_EDGE
	var fill := UiTokens.COLOR_DANGER_TINT if error else UiTokens.COLOR_SURFACE_RAISED
	c.add_theme_stylebox_override(&"normal", field_box(edge, fill, false, right))
	c.add_theme_stylebox_override(&"hover", field_box(edge, fill, false, right))
	c.add_theme_stylebox_override(&"read_only", field_box(UiTokens.COLOR_SECONDARY_EDGE, UiTokens.COLOR_SURFACE_SUNKEN, false, right))
	c.add_theme_stylebox_override(&"focus", field_box(UiTokens.COLOR_ACTION_DANGER if error else UiTokens.COLOR_ACTION_PRIMARY, fill, true, right))
	if c is OptionButton:
		c.add_theme_stylebox_override(&"pressed", field_box(UiTokens.COLOR_ACTION_PRIMARY, fill, true, right))
		c.add_theme_stylebox_override(&"disabled", field_box(UiTokens.COLOR_SECONDARY_EDGE, UiTokens.COLOR_SURFACE_SUNKEN, false, right))
		c.add_theme_stylebox_override(&"hover_pressed", field_box(UiTokens.COLOR_ACTION_PRIMARY, fill, true, right))
	var size := UiKit.theme().get_font_size(&"font_size", UiTokens.STYLE_TYPE_BODY)
	c.add_theme_font_override(&"font", UiKit.font(&"bold") if c is OptionButton else UiKit.font())
	c.add_theme_font_size_override(&"font_size", size)
	for slot in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		c.add_theme_color_override(slot, UiTokens.COLOR_TEXT)
	if c is LineEdit:
		c.add_theme_color_override(&"font_placeholder_color", UiTokens.COLOR_TEXT_MUTED)
		c.add_theme_color_override(&"caret_color", UiTokens.COLOR_PRIMARY_INK)
		c.add_theme_color_override(&"selection_color", Color(UiTokens.COLOR_ACTION_PRIMARY, 0.35))
	c.custom_minimum_size.y = FIELD_H

## The card surface: paper, radius xl, e2; content under the band.
static func card_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_SURFACE_PAPER
	b.set_corner_radius_all(UiTokens.RADIUS_XL)
	b.shadow_color = UiTokens.ELEVATION_E2_COLOR
	b.shadow_size = UiTokens.ELEVATION_E2_BLUR
	b.shadow_offset = Vector2(0, UiTokens.ELEVATION_E2_OFFSET_Y)
	b.content_margin_top = UiTokens.SIZE_PANEL_HEADER_H + UiTokens.SIZE_PANEL_PAD_TOP - UiTokens.SPACE_S4
	b.content_margin_left = UiTokens.SIZE_PANEL_PAD
	b.content_margin_right = UiTokens.SIZE_PANEL_PAD
	b.content_margin_bottom = UiTokens.SPACE_S8
	return b

static func band() -> Panel:
	var p := Panel.new()
	p.name = "Band"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_SURFACE_HEADER
	b.corner_radius_top_left = UiTokens.RADIUS_XL
	b.corner_radius_top_right = UiTokens.RADIUS_XL
	p.add_theme_stylebox_override(&"panel", b)
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	p.offset_bottom = UiTokens.SIZE_PANEL_HEADER_H
	return p

## White toast, red 4 px bar (C-84 §2 feedback) for errors that are not about one field.
static func toast_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_SURFACE_RAISED
	b.set_corner_radius_all(UiTokens.RADIUS_MD)
	b.border_color = UiTokens.COLOR_ACTION_DANGER
	b.border_width_left = 4
	b.shadow_color = UiTokens.ELEVATION_E2_COLOR
	b.shadow_size = UiTokens.ELEVATION_E1_BLUR * 2
	b.shadow_offset = Vector2(0, UiTokens.ELEVATION_E1_OFFSET_Y)
	b.content_margin_left = UiTokens.SPACE_S5 + 4
	b.content_margin_right = UiTokens.SPACE_S5
	b.content_margin_top = UiTokens.SPACE_S5
	b.content_margin_bottom = UiTokens.SPACE_S5
	return b

## A kit command key (CmdPrimary / CmdSecondary / CmdDestructive), 48 high.
static func command(text: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.theme = UiKit.theme()
	b.theme_type_variation = variation
	b.custom_minimum_size.y = 48.0
	UiMotion.press_feedback(b)
	return b

## A text link: ExtraBold 13 in `color` ("Create an account", "Forgot password?", "Send a new code").
static func link(text: String, color := UiTokens.COLOR_PRIMARY_INK) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = UiTokens.SIZE_TOUCH_MIN
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_font_override(&"font", UiKit.font(&"extrabold"))
	b.add_theme_font_size_override(&"font_size", UiKit.theme().get_font_size(&"font_size", UiTokens.STYLE_TYPE_LABEL))
	for slot in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		b.add_theme_color_override(slot, color)
	b.add_theme_color_override(&"font_disabled_color", UiTokens.COLOR_ACTION_DISABLED_INK)
	return b

## The scene behind the card, blurred once on the CPU: shrunk 16×, then grown back to half size in bilinear doublings.
static func blurred(texture: Texture2D) -> Texture2D:
	if texture == null: return null
	var image := texture.get_image()
	if image == null or image.is_empty(): return texture
	if image.is_compressed() and image.decompress() != OK: return texture
	var w := image.get_width()
	var h := image.get_height()
	image.resize(maxi(1, w / 16), maxi(1, h / 16), Image.INTERPOLATE_BILINEAR)
	for step in 3: # back up in doublings: one large cubic step leaves the small image's grid showing
		image.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(image)

## The 6-digit code as six boxes (C-85 ④ C) over the panel's own code field, which still takes the typing: its text,
## caret and box are hidden and `canvas` (a plain Control over it) draws the digits, the next box to fill outlined in the
## action colour. Called from the canvas's draw signal.
static func draw_code(canvas: Control, field: LineEdit) -> void:
	var n := 6
	var w := (canvas.size.x - CODE_GAP * (n - 1)) / n
	var font := UiKit.font(&"extrabold")
	var font_size := UiKit.theme().get_font_size(&"font_size", UiTokens.STYLE_TYPE_TITLE)
	var next := field.text.length()
	for i in n:
		var rect := Rect2(Vector2(i * (w + CODE_GAP), 0), Vector2(w, canvas.size.y))
		var active := field.has_focus() and i == mini(next, n - 1)
		var box := field_box(UiTokens.COLOR_ACTION_PRIMARY if active else UiTokens.COLOR_SECONDARY_EDGE, UiTokens.COLOR_SURFACE_RAISED, active)
		box.set_corner_radius_all(UiTokens.RADIUS_MD)
		canvas.draw_style_box(box, rect)
		if i < next:
			var digit := field.text.substr(i, 1)
			var s := font.get_string_size(digit, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var base := rect.position + Vector2((w - s.x) * 0.5, (canvas.size.y - s.y) * 0.5 + font.get_ascent(font_size))
			canvas.draw_string(font, base, digit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTokens.COLOR_TEXT)

## ✕ in the close-glyph colour in a 44 hit area (as UiModalPanel's), from the lucide x glyph.
static func close_glyph() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH_MIN, UiTokens.SIZE_TOUCH_MIN)
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.icon = load("res://assets/ui/icons/lucide/x.svg")
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override(&"icon_max_width", 20)
	for slot in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_hover_pressed_color", &"icon_focus_color", &"icon_disabled_color"]:
		b.add_theme_color_override(slot, UiTokens.COLOR_CLOSE_GLYPH)
	UiMotion.press_feedback(b)
	return b
