class_name P0AccShell
extends Control
## ACC-SHELL (SGODOT-491; 不知火舞's account spec v1 §0.1): the one look the first launch's pages share — AGE, TERMS,
## NAME, Sign in — as the original ONB-AGE-2 9:119318 / ONB-CONSENT 9:119341 / ONB-NAME 9:119537 have it, and the new
## system pages (§6) too, as SYS-SESSION 9:119672. On the 360 × 800 frame: the surface; the farm art (the SYS screens'
## sys_backdrop_farm) from y 330, fading in from the top; the `Gensen` wordmark at y 84; and a card 16 from the sides
## (328 wide), its top at y 170, radius 20, 20 in, surface + border + shadow as HOME-WELCOME's. In the card a page puts
## its title (XB20), its line (Body 14, secondary), what it asks and its primary key (48): add_title, add_body, add_gap,
## add_primary, or its own nodes into `col`. No HUD, no ✕: it takes every touch. A page made of it sits on its own
## layer before there is a world (tech plan §2.3: no viewport is read till it is in the tree).

const BACKDROP := P0SysScreen.BACKDROP
const SIDE := 16.0
const CARD_TOP := 170.0
const PAD := 20
const RADIUS := 20.0
const KEY_H := 48.0
const _FRAME_H := 800.0
const _ART_TOP := 330.0    # as the SYS screens': the art at y 330 of the frame, cropped by the screen
const _MARK_TOP := 84.0

var card: PanelContainer
var col: VBoxContainer
var mark: UiWordmark
var _art: TextureRect
var _fade: TextureRect

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	var bg := ColorRect.new()
	bg.name = "Surface"
	bg.color = UiTokens.COLOR_SURFACE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_art = TextureRect.new()
	_art.name = "Backdrop"
	_art.texture = BACKDROP
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_fade = TextureRect.new()
	_fade.texture = P0SysScreen._fade_texture()
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.stretch_mode = TextureRect.STRETCH_SCALE
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	mark = UiWordmark.new()
	add_child(mark)
	card = PanelContainer.new()
	card.name = "Card"
	var sb := UiStyleBox.make(UiTokens.COLOR_SURFACE, RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(PAD, PAD, PAD, PAD)
	sb.shadow_color = Color(0.18, 0.231, 0.2, 0.14)   # HOME-WELCOME's card
	sb.shadow_size = 28.0
	sb.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override(&"panel", sb)
	card.minimum_size_changed.connect(_layout)   # a card outside a container never shrinks on its own
	add_child(card)
	col = VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override(&"separation", 0)
	card.add_child(col)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)

## The card's title: Title ExtraBold 20, wrapping.
func add_title(text: String) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_TITLE_XB20)
	l.name = "Title"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	return l

## A line under it: Body 14, secondary, wrapping.
func add_body(text: String) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_BODY_R14, UiTokens.COLOR_SECONDARY)
	l.name = "Body"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	return l

## `h` px of room between two things in the card.
func add_gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(g)
	return g

## The page's primary key, the card's width, 48 high.
func add_primary(text: String) -> UiCommandButton:
	var b := UiCommandButton.new(text)
	b.name = "Primary"
	b.custom_minimum_size.y = KEY_H
	col.add_child(b)
	return b

func _layout() -> void:
	var w := size.x
	var h := size.y if size.y > 0.0 else _FRAME_H
	_art.position = Vector2(0, roundf(_ART_TOP * h / _FRAME_H))
	_art.size = Vector2(w, h)
	var m := mark.get_combined_minimum_size()
	mark.position = Vector2(roundf((w - m.x) * 0.5), _MARK_TOP)
	mark.size = m
	card.position = Vector2(SIDE, CARD_TOP)
	card.size = Vector2(w - SIDE * 2.0, 0.0)   # as tall as what is in it
