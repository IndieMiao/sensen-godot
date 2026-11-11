class_name P0AccShell
extends Control
## ACC-SHELL (SGODOT-491; 不知火舞's account spec v1.1 §0.1, C): the one look the first launch's pages share — AGE, AGE-BLOCK,
## NAME, Sign in, No farm found, the old account's consent card, Signed out — and the account's system pages (§6:
## SYS-SESSION, CLAIMED, DELETED, SUSPENDED). On the 360 × 800 frame: the brand cream (scheme 3, the user 11-11 bot 728;
## row 159 661:199003 / 661:199027 / 661:199048) — #F6F4EA with a faint green in its last fifth, the art the screen's
## width and on its bottom, the cream on up past it on a tall screen; the `Gensen` wordmark at y 84; and a card 16 from
## the sides (328 wide), its top at y 170, radius 24, surface + border + shadow as HOME-WELCOME's — as 安其拉's frames
## have it (row 155 633:197011): 24 in at the top, 20 at the sides and the bottom, inside its 1 px edge (PAD, from the
## card's outer edge). In the card a page puts its title (XB20), its line (Body 14, secondary), what it asks and its
## primary key (48): add_title, add_body, add_gap, add_primary, or its own nodes into `col`. No HUD, no ✕: it takes
## every touch. A page made of it sits on its own layer before there is a world (tech plan §2.3: no viewport is read till
## it is in the tree).
## The game's other system screens (P0SysScreen: Can't connect, maintenance, update) keep their farm art (奕星 11-11:
## the user's word was the sign-up's art); a page here may still take another (`backdrop`).

const BACKDROP := preload("res://assets/p0/ui/acc_backdrop_cream.png")   # 1080 × 2400, the 360 × 800 frame ×3
const GROUND := Color("F6F4EA")   # the art's cream, on up past its top (as HOME-WELCOME's land)
const SIDE := 16.0
const CARD_TOP := 170.0
## Left, top, right, bottom from the card's outer edge: the frame's 20 / 24 / 20 / 20 plus its 1 px edge (ACC-AGE
## 633:197016: the title at x 21, y 25; the key's bottom 21 above the card's).
const PAD := Vector4(21, 25, 21, 21)
const RADIUS := 24.0
const KEY_H := 48.0
const _MARK_TOP := 84.0

var backdrop: Texture2D = BACKDROP:
	set(t):
		backdrop = t
		if _art:
			_art.texture = t
			_layout()
var card: PanelContainer
var col: VBoxContainer
var mark: UiWordmark
var _art: TextureRect

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	var bg := ColorRect.new()
	bg.name = "Surface"
	bg.color = GROUND
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_art = TextureRect.new()
	_art.name = "Backdrop"
	_art.texture = backdrop
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	mark = UiWordmark.new()
	add_child(mark)
	card = PanelContainer.new()
	card.name = "Card"
	var sb := UiStyleBox.make(UiTokens.COLOR_SURFACE, RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(PAD.x, PAD.y, PAD.z, PAD.w)
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

## The card's title: Title ExtraBold 20, wrapping; centred where the frame has it so (AGE, NOFARM), NAME's on the left.
func add_title(text: String, centred := false) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_TITLE_XB20)
	l.name = "Title"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centred: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	var h := size.y
	# the screen's width, on its bottom: a tall screen shows the cream above it, a short one loses some of its cream top
	var art_h := roundf(w * backdrop.get_height() / backdrop.get_width()) if backdrop else 0.0
	_art.position = Vector2(0, h - art_h)
	_art.size = Vector2(w, art_h)
	var m := mark.get_combined_minimum_size()
	mark.position = Vector2(roundf((w - m.x) * 0.5), _MARK_TOP)
	mark.size = m
	card.position = Vector2(SIDE, CARD_TOP)
	card.size = Vector2(w - SIDE * 2.0, 0.0)   # as tall as what is in it
