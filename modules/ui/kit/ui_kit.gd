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

## Colour with the alpha of an opacity token, e.g. UiKit.alpha(UiTokens.COLOR_SURFACE, UiTokens.OPACITY_SHEET_SURFACE).
static func alpha(color: Color, opacity: float) -> Color:
	return Color(color, opacity)

## Duration token (ms) in seconds, for Tweens and timers.
static func secs(ms: float) -> float:
	return ms / 1000.0
