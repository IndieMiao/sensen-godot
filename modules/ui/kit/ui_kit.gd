class_name UiKit
## Shared helpers for the P0 UI kit (SGODOT-211). Kit code reads UiTokens and the theme variations of
## assets/ui/gensen_theme.tres only: no Color literals, no numeric font sizes (tests/ui_kit guards this).

static var _theme: Theme
static var _fonts := {}

static func theme() -> Theme:
	if _theme == null: _theme = load(UiTokens.THEME_PATH)
	return _theme

## weight: &"regular" (400), &"bold" (700) or &"extrabold" (800).
static func font(weight: StringName = &"regular") -> Font:
	if not _fonts.has(weight):
		var path := {&"regular": UiTokens.FONT_REGULAR_PATH, &"bold": UiTokens.FONT_BOLD_PATH,
			&"extrabold": UiTokens.FONT_EXTRABOLD_PATH}[weight] as String
		_fonts[weight] = load(path)
	return _fonts[weight]

## Bold Italic (Nunito has no italic face): the bold token's own font file and weight, slanted — the Bite Board
## keeper's line and the Postcards' Kindred lines. Not a FontVariation over the bold FontVariation: nested, the inner
## wght is lost and the line rendered thin (不知火舞 on 284).
const ITALIC_SKEW := 0.2
static var _bold_italic: FontVariation
static func bold_italic() -> FontVariation:
	if _bold_italic == null:
		var bold := font(&"bold") as FontVariation
		_bold_italic = FontVariation.new()
		_bold_italic.base_font = bold.base_font
		_bold_italic.variation_opentype = bold.variation_opentype.duplicate()
		_bold_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(-ITALIC_SKEW, 1), Vector2.ZERO)
	return _bold_italic

## A Label using one of the UiTokens.STYLE_* variations; colour defaults to the text token.
static func label(text: String, style: StringName, color := UiTokens.COLOR_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = style
	if color != UiTokens.COLOR_TEXT: l.add_theme_color_override(&"font_color", color)
	return l

## Interactive controls keep a 44 px hit area even when the drawn box is smaller (UiStyleBox.inset).
static func ensure_hit_area(c: Control, min_side: float = UiTokens.SIZE_TOUCH) -> void:
	c.custom_minimum_size = Vector2(maxf(c.custom_minimum_size.x, min_side), maxf(c.custom_minimum_size.y, min_side))

static func icon(texture: Texture2D, side: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(side, side)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Two lines break at a " · " (不知火舞 on #188, q(103)): a text wider than `width` goes to the next line after the last
## " · " that still leaves the first line inside it, the dot dropped — `Pond Catch` / `Pond Crucian 1/2`,
## `Catch 2 Pond Crucian` / `Fern Pond`. A text that fits, has no " · " or no first part that fits stays as it is
## (the label still wraps by words). Toasts that opt in and Today's rows use it, each with its own label's font.
static func break_at_dot(text: String, font: Font, font_size: int, width: float) -> String:
	if font == null or width <= 0.0 or not text.contains(" · "): return text
	var fits := func(t: String) -> bool: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width
	if fits.call(text): return text
	var parts := text.split(" · ")
	for i in range(parts.size() - 1, 0, -1):
		var first := " · ".join(parts.slice(0, i))
		if fits.call(first): return first + "\n" + " · ".join(parts.slice(i))
	return text

## Colour with the alpha of an opacity token, e.g. UiKit.alpha(UiTokens.COLOR_SURFACE, UiTokens.OPACITY_SHEET_SURFACE).
static func alpha(color: Color, opacity: float) -> Color:
	return Color(color, opacity)

## Duration token (ms) in seconds, for Tweens and timers.
static func secs(ms: float) -> float:
	return ms / 1000.0
