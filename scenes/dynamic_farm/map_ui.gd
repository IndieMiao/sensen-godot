extends RefCounted
## UI v3 pieces of the dynamic farm map (C-106), after the owner-approved page ⑤ Map of C-85 (D-201, Q-124) with the
## C-105 tokens and kit. Only looks: the map script keeps every state, action and line it had.
##   glass pill   34 high in a 44 hit area, `glass/fill`, white label 13 (city chip, Market / Carpenter, the account)
##   primary pill the same in `action/primary` with the §2.1 outline (signed out: "Sign in")
##   hint         32 high `glass/fillStrong` capsule under the top row: the map's one guide / progress line
##   card         `surface/paper`, radius xl 20, e2 shadow, 44 / 16 / 16 in, a 34 high `surface/header` band with a
##                68 hero over its top edge and a tag pill right of it (parcel card, the claim / sign-out dialogs)
##   toast        white, radius md 12, a 4 px bar on the left (red failure, amber kept account), e2 shadow
## Text, hit areas and colours come from UiTokens / the kit theme; sizes not in the tokens cite the C-85 board.

const PILL_H := 34.0           # C-85 ⑤ .titlep / .acct height
const HINT_H := 32.0           # C-85 ⑤ .hint height
const BAND_H := 34.0           # C-85 ⑤ .pcard .hd2
const HERO := 68.0             # C-85 ⑤ .pcard .hero
const TAG_LEFT := 86.0         # C-85 ⑤ .pcard .tag left
const CARD_PAD_TOP := 44.0     # C-85 ⑤ .pcard padding-top
const AVATAR := 26.0           # C-85 ⑤ .acct i
const DOT := 10.0              # C-85 ⑤ .own i
const TOAST_BAR := 4.0         # C-84 §2 feedback: a 4 px bar
const DIALOG_W := 288.0        # UiTokens.SIZE_PANEL_W, the bag-type panel width

static func theme() -> Theme: return UiKit.theme()

## A Label of a kit type style, never auto-translated (the dynamic farm package is English only, C-82#48).
static func label(text: String, style: StringName, color := UiTokens.COLOR_TEXT) -> Label:
	var l := UiKit.label(text, style, color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l

static func wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func _pill_box(fill: Color) -> UiStyleBox:
	var b := UiStyleBox.make(fill, PILL_H * 0.5)
	b.visual_height = PILL_H
	return b.with_margins(UiTokens.SPACE_S5 + 2, 0, UiTokens.SPACE_S5 + 2, 0)

## The glass pill button (city chip, Market / Carpenter, the signed-in account): white label 13, an optional 16 icon.
static func glass_pill(text: String, icon: Texture2D = null) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.theme = theme()
	b.custom_minimum_size.y = UiTokens.SIZE_TOUCH_MIN
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var normal := _pill_box(UiTokens.COLOR_GLASS_FILL)
	var pressed := _pill_box(UiTokens.COLOR_GLASS_FILL_STRONG)
	for state in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(state, normal)
	for state in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(state, pressed)
	_pill_text(b, UiTokens.COLOR_TEXT_ON_DARK, UiTokens.COLOR_TEXT_ON_DARK_MUTED)
	if icon != null: set_icon(b, icon, 16)
	UiMotion.press_feedback(b)
	return b

## The primary pill ("Sign in" on the account chip): `action/primary`, white ExtraBold with the §2.1 outline.
static func primary_pill(b: Button) -> void:
	var normal := _pill_box(UiTokens.COLOR_ACTION_PRIMARY)
	var pressed := _pill_box(UiTokens.COLOR_ACTION_PRIMARY_PRESSED)
	for state in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(state, normal)
	for state in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(state, pressed)
	b.add_theme_color_override(&"font_outline_color", UiTokens.COLOR_ON_ACTION_OUTLINE)
	b.add_theme_constant_override(&"outline_size", 2)

## Back to the glass look after primary_pill (signed in again).
static func glass_look(b: Button) -> void:
	var normal := _pill_box(UiTokens.COLOR_GLASS_FILL)
	var pressed := _pill_box(UiTokens.COLOR_GLASS_FILL_STRONG)
	for state in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(state, normal)
	for state in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(state, pressed)
	b.remove_theme_color_override(&"font_outline_color")
	b.remove_theme_constant_override(&"outline_size")

static func _pill_text(b: Button, color: Color, disabled: Color) -> void:
	b.add_theme_font_override(&"font", UiKit.font(&"extrabold"))
	b.add_theme_font_size_override(&"font_size", theme().get_font_size(&"font_size", UiTokens.STYLE_TYPE_LABEL))
	for slot in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		b.add_theme_color_override(slot, color)
	b.add_theme_color_override(&"font_disabled_color", disabled)
	b.add_theme_constant_override(&"h_separation", int(UiTokens.SPACE_S3))

## An icon drawn as it is (white glyphs, the C-86 art), `side` px.
static func set_icon(b: Button, icon: Texture2D, side: int) -> void:
	b.icon = icon
	b.expand_icon = false
	b.add_theme_constant_override(&"icon_max_width", side)
	for slot in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_hover_pressed_color",
			&"icon_focus_color", &"icon_disabled_color"]:
		b.add_theme_color_override(slot, Color.WHITE)

## A kit command button (48 high; `compact` 34 in a 44 hit area) as a plain Button: the map sets its text and
## disabled state itself, as before. Kinds: CmdPrimary / CmdSecondary / CmdDestructive.
static func command(text: String, variation: StringName, compact := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.theme = theme()
	b.theme_type_variation = StringName(String(variation) + ("Compact" if compact else ""))
	b.custom_minimum_size.y = UiTokens.SIZE_TOUCH_MIN if compact else 48.0
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiMotion.press_feedback(b)
	return b

## A text link (the internal "Give up and choose again" in the danger colour, under the card's main action).
static func link(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.theme = theme()
	b.custom_minimum_size.y = UiTokens.SIZE_TOUCH_MIN
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_font_override(&"font", UiKit.font(&"extrabold"))
	b.add_theme_font_size_override(&"font_size", theme().get_font_size(&"font_size", UiTokens.STYLE_TYPE_LABEL))
	for slot in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		b.add_theme_color_override(slot, color)
	b.add_theme_color_override(&"font_disabled_color", UiTokens.COLOR_ACTION_DISABLED_INK)
	return b

## The hint capsule: `glass/fillStrong`, a pill 32 high (taller when the line wraps), white label 13 centred.
static func hint_box() -> UiStyleBox:
	var b := UiStyleBox.make(UiTokens.COLOR_GLASS_FILL_STRONG, HINT_H * 0.5)
	return b.with_margins(UiTokens.SPACE_S6, UiTokens.SPACE_S3 + 1, UiTokens.SPACE_S6, UiTokens.SPACE_S3 + 1)

## The card and dialog surface: paper, radius xl, e2.
static func card_box(pad_top := CARD_PAD_TOP, pad := UiTokens.SPACE_S6) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_SURFACE_PAPER
	b.set_corner_radius_all(UiTokens.RADIUS_XL)
	b.shadow_color = UiTokens.ELEVATION_E2_COLOR
	b.shadow_size = UiTokens.ELEVATION_E2_BLUR
	b.shadow_offset = Vector2(0, UiTokens.ELEVATION_E2_OFFSET_Y)
	b.content_margin_left = pad
	b.content_margin_right = pad
	b.content_margin_bottom = pad
	b.content_margin_top = pad_top
	return b

## The card's header band: `surface/header`, top corners only.
static func band() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_SURFACE_HEADER
	b.corner_radius_top_left = UiTokens.RADIUS_XL
	b.corner_radius_top_right = UiTokens.RADIUS_XL
	p.add_theme_stylebox_override(&"panel", b)
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	p.offset_bottom = BAND_H
	return p

## White toast with a coloured 4 px bar on its left (C-84 §2 feedback): red failure, amber warning.
static func toast_box(bar: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_SURFACE_RAISED
	b.set_corner_radius_all(UiTokens.RADIUS_MD)
	b.border_color = bar
	b.border_width_left = int(TOAST_BAR)
	b.shadow_color = UiTokens.ELEVATION_E2_COLOR
	b.shadow_size = UiTokens.ELEVATION_E1_BLUR * 2
	b.shadow_offset = Vector2(0, UiTokens.ELEVATION_E1_OFFSET_Y)
	b.content_margin_left = UiTokens.SPACE_S5 + TOAST_BAR
	b.content_margin_right = UiTokens.SPACE_S4
	b.content_margin_top = UiTokens.SPACE_S4
	b.content_margin_bottom = UiTokens.SPACE_S4
	return b

## A coloured status dot (the card's owner line): a round Panel; set_dot() recolours it. No script of its own.
static func dot() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(DOT, DOT)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_dot(p, UiTokens.COLOR_ACTION_DISABLED_INK)
	return p

static func set_dot(p: Panel, color: Color) -> void:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(int(DOT))
	b.anti_aliasing = true
	p.add_theme_stylebox_override(&"panel", b)

## A round avatar (the account chip's 26): the texture clipped by a white disc. No script of its own.
static func avatar(texture: Texture2D) -> Panel:
	var disc := Panel.new()
	disc.custom_minimum_size = Vector2(AVATAR, AVATAR)
	disc.size = disc.custom_minimum_size
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var b := StyleBoxFlat.new()
	b.bg_color = UiTokens.COLOR_SURFACE_RAISED
	b.set_corner_radius_all(int(AVATAR))
	b.anti_aliasing = true
	disc.add_theme_stylebox_override(&"panel", b)
	var face := UiKit.icon(texture, AVATAR)
	face.name = "Face"
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disc.add_child(face)
	return disc
