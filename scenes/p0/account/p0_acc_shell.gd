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
## The maintenance and update screens (P0SysScreen) stand on the same cream (the user 11-11 bot 733); a page here may
## still take another art (`backdrop`).

const BACKDROP := preload("res://assets/p0/ui/acc_backdrop_cream.png")   # 1080 × 2400, the 360 × 800 frame ×3
const GROUND := Color("F6F4EA")   # the art's cream, on up past its top (as HOME-WELCOME's land)
const SIDE := 16.0
const CARD_TOP := 170.0
## Left, top, right, bottom from the card's outer edge: the frame's 20 / 24 / 20 / 20 plus its 1 px edge (ACC-AGE
## 633:197016: the title at x 21, y 25; the key's bottom 21 above the card's).
const PAD := Vector4(21, 25, 21, 21)
const RADIUS := 24.0
const KEY_H := 48.0
const LINK_SIZE := 15
const _MARK_TOP := 84.0

var backdrop: Texture2D = BACKDROP:
	set(t):
		backdrop = t
		if _art:
			_art.texture = t
			_layout()
## The card's top on the frame: 170 (AGE, NAME, …); a page with a short card sits lower (AGE-BLOCK's 220).
var card_top := CARD_TOP:
	set(v):
		card_top = v
		if card: _layout()
var card: PanelContainer
var col: VBoxContainer
var mark: UiWordmark
var _art: TextureRect

## The keyboard (spec v1.1 §1.5; the test code and email pages too): it comes up only for a tapped field; while it is up
## the wordmark fades out, and only if it covers the page's primary key the card moves up till that key's foot is 12
## over the keyboard's top (Skip and the card's foot may go under it); down, all back. 250 ms, ease-out. `keyboard_height`
## stands in for the system's in tests (viewport units).
const KEY_CLEAR := 12.0
const KEYBOARD_S := 0.25
var keyboard_height := Callable()
## What must stay over the keyboard when not the primary key (a page without one: the email code's six cells, 盘古).
var keep_above_keyboard: Control
var lift := 0.0:                      # how far up the card is now
	set(v):
		lift = v
		if card: _layout()
var _lift_to := 0.0
var _keyboard_up := false
var _lift_tween: Tween
var _mark_hidden := {}                # why the wordmark is out: "keyboard", "banner" (the flow's SYS-CMD-FAIL line)
var _mark_tween: Tween

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

## A line under it: Body Bold 14 (the frames' body on every page: NAME, AGE-BLOCK, No farm found; 不知火舞 on 491),
## secondary unless `color` says, wrapping.
func add_body(text: String, color := UiTokens.COLOR_SECONDARY) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_BODY_B14, color)
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

## A text link in the card, centred, 44 high: info blue, Bold 15 (`Privacy Policy ›`, AGE-BLOCK; q(281)'s link).
func add_link(text: String) -> UiDismissButton:
	var b := UiDismissButton.new(text)
	b.name = "Link"
	b.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	b.add_theme_font_override(&"font", UiKit.font(&"bold"))
	b.add_theme_font_size_override(&"font_size", LINK_SIZE)
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.COLOR_INFO)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	col.add_child(b)
	return b

## The page's primary key, the card's width, 48 high.
func add_primary(text: String) -> UiCommandButton:
	var b := UiCommandButton.new(text)
	b.name = "Primary"
	b.custom_minimum_size.y = KEY_H
	col.add_child(b)
	return b

## The wordmark out (250 ms) while any reason holds, back once none does.
func hide_mark(why: String, on: bool) -> void:
	if on: _mark_hidden[why] = true
	else: _mark_hidden.erase(why)
	var to := 0.0 if not _mark_hidden.is_empty() else 1.0
	if is_equal_approx(mark.modulate.a, to) and (_mark_tween == null or not _mark_tween.is_running()): return
	if _mark_tween: _mark_tween.kill()
	if not is_inside_tree():
		mark.modulate.a = to
		return
	_mark_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_mark_tween.tween_property(mark, ^"modulate:a", to, KEYBOARD_S)

func _process(_delta: float) -> void:
	var kb := _keyboard()
	var up := kb > 0.0 and _field_focused()
	if up != _keyboard_up:
		_keyboard_up = up
		hide_mark("keyboard", up)
	var want := key_lift(kb) if up else 0.0
	if not is_equal_approx(want, _lift_to):
		_lift_to = want
		if _lift_tween: _lift_tween.kill()
		_lift_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_lift_tween.tween_property(self, ^"lift", want, KEYBOARD_S)

## How far the card must go up so the primary key's foot (or keep_above_keyboard's) is KEY_CLEAR over a keyboard `kb`
## tall; 0 when it is clear.
func key_lift(kb: float) -> float:
	var key := keep_above_keyboard if is_instance_valid(keep_above_keyboard) else col.find_child("Primary", false, false) as Control
	if key == null or kb <= 0.0: return 0.0
	var foot := key.get_global_rect().end.y - global_position.y + lift   # where it sits with the card down
	return maxf(0.0, foot - (size.y - kb - KEY_CLEAR))

func _field_focused() -> bool:
	if not is_inside_tree(): return false
	var focus := get_viewport().gui_get_focus_owner()
	return (focus is LineEdit or focus is TextEdit) and card.is_ancestor_of(focus)

func _keyboard() -> float:
	if keyboard_height.is_valid(): return float(keyboard_height.call())
	if not is_inside_tree() or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): return 0.0
	var px := DisplayServer.virtual_keyboard_get_height()
	if px <= 0: return 0.0
	return float(px) * get_viewport().get_visible_rect().size.y / maxf(1.0, float(DisplayServer.window_get_size().y))

## Over the page under it instead of on its own ground (spec v2 §9's updated-terms card): no cream, no art, no wordmark —
## the modal scrim, the card where it is. It still takes every touch.
func as_overlay() -> void:
	for id in ["Surface", "Backdrop"]: (get_node(id) as CanvasItem).visible = false
	mark.visible = false
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UiTokens.COLOR_SCRIM_MODAL
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	move_child(scrim, 0)

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
	card.position = Vector2(SIDE, card_top - lift)
	card.size = Vector2(w - SIDE * 2.0, 0.0)   # as tall as what is in it
