class_name P0BlackjackPage
extends Control
## The Barbary Card Room's Blackjack table (SGODOT-351; q(240), §9.18.7; 不知火舞 on 351 7cdf40a9; server 后裔 on 351
## b610f98a), full screen over the room, opened by Lou's `Play` (P0Ui.open_blackjack). On the cream page: PageHeader
## `‹` `Blackjack` with the text key `Rules`, the coins pill under it (the HUD's number), the felt with the dealer on top,
## the two printed lines, the player's hand(s) and the bet circle; under the felt the keys of the phase:
##   BET     the tray of six ChipTokens, `Clear` and `Deal · 120` (`Place a bet` at 0). Tap a chip: it flies into the
##           circle (MOTION_RADIAL_PETAL_IN_MS). Drag it: a Dragging chip follows the finger, the tray's stays; over the
##           circle the ring lights, let go there and it adds, anywhere else it flies back and adds nothing. Tap and drag
##           part as GestureArbiter does (TAP_SLOP, TAP_MAX_MS); no double tap anywhere. A chip that would take the
##           wallet under the floor greys and ignores both. Not even 5 fits: `Low on coins` instead of the circle and
##           `Need N more coins` on the key (the only closed state).
##   PLAY    `Hit` / `Stand` equal (both primary), `Double · 120` / `Split · 120` always there, grey with the server's
##           reason. Split hands side by side, the one in play outlined, the other dimmed. An expired hand shows no keys.
##   RESULT  a tag over each hand, `+N coins` floats for wins, the pill rolls; `Deal again · 120` / `Change bet`.
## The page sends intents only (bj_open on opening, bj_intro, bj_deal {bet}, bj_act {action}); the server deals and
## settles. A reply's bj_dealt / bj_card / bj_result events play in order (cards fly from the shoe, the hole card turns
## over, the dealer draws), then the page matches the view; a view with no events (opening mid-hand, a refusal) is
## laid out at once. First open: the centred card `Barbary Card Room` / `You bet coins here. You always keep at least
## 40.` / `Got it` (bj_intro). A hand the server settled away: `Last hand settled · You win +20 coins` for 3 s.
## Card, chip and felt drawings stand in until 安其拉's frames (351 bd0fced2) land.

signal back_pressed
signal command(cmd: Dictionary)

enum Phase { BET, PLAY, RESULT }

const FELT := Color("2F6A3A")          # color/table/felt (VariableID:172:165539) until the token export adds it
const FELT_INK := Color("FBF8F1")
const _HEADER_H := 48.0
const _HEADER_Y := P0ProfilePage._TOP - (_HEADER_H - UiTokens.SIZE_CLOSE) * 0.5
const _PILL_H := 26.0
const _KEY_H := 48.0
const _ROW_GAP := 8.0
const _CHIP_GAP := 8.0
# BJ-BET 172:198798 at 360 × 800: header band to 76 (8 under the PageHeader), coins pill 12 under it at the right, the
# felt's print arc (520 across, centre 410) and lines at 236 / 260, the bet circle 104 across at (180, 430) with the
# amount 12 right of it, the tray sheet from 616 (184 high, top corners 24) with the chips 20 in and the keys 84 in.
const _BAND_BELOW_HEADER := 8.0
const _PILL_BELOW_BAND := 12.0
const _LINES_BELOW_BAND := 160.0
const _ARC_BELOW_BAND := 334.0         # the print arc's centre
const _ARC_R := 260.0
const _TRAY_H := 184.0
const _TRAY_CHIPS := 20.0
const _TRAY_KEYS := 84.0
const _CLEAR_W := 88.0
const _CIRCLE_R := 52.0
const _CIRCLE_ABOVE_TRAY := 186.0      # the circle's centre above the tray's top
const _CIRCLE_HIT := 12.0              # the circle takes a drop this far outside its ring
const _CARDS_BELOW_BAND := 40.0        # the dealer's cards
const _HAND_GAP := 8.0                 # the player's cards end this far above the circle
const _SPLIT_GAP := 24.0               # between split hands (BJ-SPEC-CARDS)
const _SETTLED_S := 3.0
const ICON_COIN := preload("res://assets/p0/icons/coin.svg")

var view: Dictionary = {}
var phase := Phase.BET
var safe_top := 0.0
var safe_bottom := 0.0
## Tests and shots turn motion off: every step lands at once.
var animate := true
## Says why a refused command did not go (P0Ui.toast_error).
var toast := Callable()

var bet := 0                 # the stake being stacked (BET), or on the table
var stack: Array = []        # the chips drawn in the circle, in the order they landed
var _result := {}            # the bj_result on show (RESULT)
var _waiting := false        # a command is out: keys and chips wait for its answer
var _steps: Array = []       # queued motion: Callables returning seconds to wait
var _running := false
var _pending: Array = []     # bj events of the reply whose view just came
var _seen := 0               # hash of what the last refresh laid out
var _coins_shown := 0
var _coins_tween: Tween

var header: UiPageHeader
var rules_key: Button
var coins_pill: PanelContainer
var coins_label: Label
var felt: Panel
var arc: Control
var band: ColorRect
var tray_sheet: Panel
var lines: VBoxContainer
var circle: _Circle
var bet_label: Label
var low_label: Label
var settled_pill: PanelContainer
var settled_label: Label
var dealer_box: Control
var dealer_badge: PanelContainer
var hands_box: Control
var tray: Control
var chips: Array = []        # UiChipToken in the tray
var clear_key: UiDismissButton
var deal_key: UiCommandButton
var hit_key: UiCommandButton
var stand_key: UiCommandButton
var double_key: UiCommandButton
var split_key: UiCommandButton
var again_key: UiCommandButton
var change_key: UiCommandButton
var intro_layer: Control
var intro_card: UiSystemCard
var rules_layer: Control
var rules_sheet: UiDrawer

# the table as drawn
var _dealer_cards: Array = []      # UiPlayingCard
var _hands: Array = []             # [{cards: [UiPlayingCard], node: Control, badge, bet, tag}]
var _active := 0

# a chip under the finger
var _press := {}
var _ghost: UiChipToken

func _init(view_: Dictionary = {}, safe_top_ := 0.0, safe_bottom_ := 0.0) -> void:
	safe_top = safe_top_
	safe_bottom = safe_bottom_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTokens.COLOR_SURFACE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_header()
	_build_felt()
	_build_keys()
	_build_overlays()
	resized.connect(_layout)
	view = view_
	_coins_shown = P0Blackjack.coins_of(view)
	coins_label.text = P0Blackjack.comma(_coins_shown)
	_enter_bet(P0Blackjack.deal_again_bet(view, int(P0Blackjack.info(view).get("last_bet", 0))))
	_reconcile()

# ---------------------------------------------------------------- build

func _build_header() -> void:
	band = ColorRect.new()
	band.color = UiTokens.COLOR_SURFACE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	header = UiPageHeader.new("Blackjack")
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = UiTokens.SIZE_QUICK_BAR_X
	header.offset_right = -UiTokens.SIZE_QUICK_BAR_X
	header.offset_top = _HEADER_Y + safe_top
	header.offset_bottom = header.offset_top + _HEADER_H
	header.back_pressed.connect(func(): back_pressed.emit())
	# PageHeader Kind=Back + Action (q(240) ②): the text key `Rules`, no ⓘ.
	rules_key = Button.new()
	rules_key.name = "Rules"
	rules_key.text = "Rules"
	rules_key.focus_mode = Control.FOCUS_NONE
	rules_key.theme_type_variation = UiTokens.BUTTON_DISMISS
	rules_key.add_theme_color_override(&"font_color", UiTokens.COLOR_PRIMARY)
	rules_key.add_theme_color_override(&"font_pressed_color", UiTokens.COLOR_PRIMARY_PRESSED)
	rules_key.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_TOUCH)
	rules_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rules_key.pressed.connect(open_rules)
	header.add_child(rules_key)
	add_child(header)
	coins_pill = PanelContainer.new()
	coins_pill.name = "Coins"
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.COLOR_SURFACE_RAISED
	sb.border_color = UiTokens.COLOR_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(_PILL_H * 0.5))
	sb.content_margin_left = 9
	sb.content_margin_right = 7
	coins_pill.add_theme_stylebox_override(&"panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	coins_label = UiKit.label("", UiTokens.STYLE_C14_XB, UiTokens.COLOR_GOLD_INK)
	coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coins_label)
	var coin := UiKit.icon(ICON_COIN, 16)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	coins_pill.add_child(row)
	coins_pill.custom_minimum_size.y = _PILL_H

func _build_felt() -> void:
	felt = Panel.new()
	felt.name = "Felt"
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	felt.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = FELT
	felt.add_theme_stylebox_override(&"panel", sb)
	add_child(felt)
	arc = _Arc.new()
	felt.add_child(arc)
	lines = VBoxContainer.new()
	lines.add_theme_constant_override(&"separation", 2)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in ["Blackjack pays 3 to 2", "Dealer stands on all 17s"]:
		var l := UiKit.label(t, UiTokens.STYLE_BODY_XB14 if t.begins_with("Blackjack") else UiTokens.STYLE_C13_B, UiKit.alpha(FELT_INK, 0.6 if t.begins_with("Blackjack") else 0.5))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lines.add_child(l)
	felt.add_child(lines)
	dealer_box = Control.new()
	dealer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	felt.add_child(dealer_box)
	dealer_badge = _badge()
	felt.add_child(dealer_badge)
	hands_box = Control.new()
	hands_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	felt.add_child(hands_box)
	circle = _Circle.new()
	felt.add_child(circle)
	bet_label = UiKit.label("", UiTokens.STYLE_TITLE_XB20, FELT_INK)
	felt.add_child(bet_label)
	low_label = UiKit.label("Low on coins", UiTokens.STYLE_TITLE_XB20, FELT_INK)
	low_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	felt.add_child(low_label)

	settled_pill = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = UiTokens.COLOR_SURFACE_RAISED
	ps.set_corner_radius_all(UiTokens.RADIUS_CAPTION_PILL + 6)
	ps.content_margin_left = 12
	ps.content_margin_right = 12
	ps.content_margin_top = 6
	ps.content_margin_bottom = 6
	settled_pill.add_theme_stylebox_override(&"panel", ps)
	settled_label = UiKit.label("", UiTokens.STYLE_C13_B)
	settled_pill.add_child(settled_label)
	settled_pill.visible = false
	settled_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	felt.add_child(settled_pill)
	add_child(coins_pill)   # on the felt's top-right, over it

func _badge() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiKit.alpha(Color.BLACK, 0.35)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override(&"panel", sb)
	var l := UiKit.label("", UiTokens.STYLE_C13_XB, FELT_INK)
	l.name = "Text"
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	return p

static func _badge_set(p: PanelContainer, text: String) -> void:
	var l := p.get_node("Text") as Label
	l.text = text
	(p.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color = UiTokens.COLOR_DANGER if text == "Bust" else UiKit.alpha(Color.BLACK, 0.35)
	p.visible = text != ""
	p.reset_size()

func _build_keys() -> void:
	tray_sheet = Panel.new()
	tray_sheet.name = "TraySheet"
	tray_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = UiTokens.COLOR_SURFACE
	ts.corner_radius_top_left = UiTokens.RADIUS_SHEET
	ts.corner_radius_top_right = UiTokens.RADIUS_SHEET
	tray_sheet.add_theme_stylebox_override(&"panel", ts)
	add_child(tray_sheet)
	tray = Control.new()
	tray.name = "Tray"
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tray)
	for v in P0Blackjack.CHIPS:
		var c := UiChipToken.new(v)
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.gui_input.connect(_chip_input.bind(chips.size()))
		tray.add_child(c)
		chips.append(c)
	clear_key = UiDismissButton.new("Clear")
	clear_key.size_flags_horizontal = Control.SIZE_FILL
	clear_key.pressed.connect(clear_bet)
	add_child(clear_key)
	deal_key = _key("Deal", UiCommandButton.Kind.PRIMARY, func(): deal(bet))
	hit_key = _key("Hit", UiCommandButton.Kind.PRIMARY, func(): act("hit"))
	stand_key = _key("Stand", UiCommandButton.Kind.PRIMARY, func(): act("stand"))
	double_key = _key("Double", UiCommandButton.Kind.SECONDARY, func(): act("double"))
	split_key = _key("Split", UiCommandButton.Kind.SECONDARY, func(): act("split"))
	again_key = _key("Deal again", UiCommandButton.Kind.PRIMARY, deal_again)
	change_key = _key("Change bet", UiCommandButton.Kind.SECONDARY, change_bet)
	change_key.sends = false

func _key(text: String, kind: UiCommandButton.Kind, on: Callable) -> UiCommandButton:
	var k := UiCommandButton.new(text, kind)
	k.sends = true
	k.activated.connect(on)
	add_child(k)
	return k

func _build_overlays() -> void:
	intro_layer = _scrim()
	intro_card = UiSystemCard.new()
	intro_card.show_card({"title": "Barbary Card Room", "body": "You bet coins here. You always keep at least 40.",
		"primary": "Got it"})
	intro_card.primary_pressed.connect(func():
		intro_layer.visible = false
		command.emit({"type": "bj_intro"}))
	intro_card.set_anchors_preset(Control.PRESET_CENTER)
	intro_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	intro_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	intro_layer.add_child(intro_card)
	rules_layer = _scrim()
	(rules_layer as ColorRect).gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed): close_rules())
	rules_sheet = UiDrawer.new(0.0)
	rules_sheet.safe_bottom = safe_bottom
	rules_sheet.close_requested.connect(close_rules)
	rules_sheet.body.add_theme_constant_override(&"separation", 8)
	var title := UiKit.label("Rules", UiTokens.STYLE_TITLE_XB20)
	rules_sheet.body.add_child(title)
	for t in RULES:
		var l := UiKit.label(t, UiTokens.STYLE_BODY_R14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules_sheet.body.add_child(l)
	var foot := UiKit.label("Bets are coins. You always keep at least 40 coins.", UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_MUTED)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_sheet.body.add_child(foot)
	rules_sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	rules_sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	rules_layer.add_child(rules_sheet)

const RULES := ["Get closer to 21 than the dealer without going over.",
	"2–10 count as shown. J, Q and K count 10. A counts 1 or 11.",
	"Blackjack (an A and a 10-value card) pays 3 to 2, rounded down to whole coins.",
	"The dealer draws to 16 and stands on all 17s.",
	"Double: your bet doubles and you get one more card. First two cards only.",
	"Split: a pair becomes two hands, once per hand. Split aces get one card each.",
	"Wins pay 1 to 1. A tie returns your bet.",
	"4 decks, shuffled every hand."]

func _scrim() -> ColorRect:
	var s := ColorRect.new()
	s.color = UiTokens.COLOR_SCRIM_MODAL
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	s.visible = false
	add_child(s)
	return s

# ---------------------------------------------------------------- layout

## Sizes follow the theme's fonts: lay out again once it applies (the first layout runs before the page is in the tree).
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE: _layout.call_deferred()

func felt_rect() -> Rect2: return Rect2(felt.position, felt.size)
func circle_center() -> Vector2: return felt.position + circle.position + circle.size * 0.5

func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0: return
	var pad := float(UiTokens.SPACE_PAGE)
	var band_h := header.offset_bottom + _BAND_BELOW_HEADER
	band.position = Vector2.ZERO
	band.size = Vector2(w, band_h)
	var tray_top := h - safe_bottom - _TRAY_H
	tray_sheet.position = Vector2(0, tray_top)
	tray_sheet.size = Vector2(w, h - tray_top)
	felt.position = Vector2(0, band_h)
	felt.size = Vector2(w, tray_top - band_h + UiTokens.RADIUS_SHEET)   # under the tray's round corners too
	coins_pill.size = coins_pill.get_combined_minimum_size()
	coins_pill.position = Vector2(w - pad - coins_pill.size.x, band_h + _PILL_BELOW_BAND)
	var fw := felt.size.x
	arc.position = Vector2(fw * 0.5 - _ARC_R, _ARC_BELOW_BAND - _ARC_R)
	arc.size = Vector2(_ARC_R * 2.0, _ARC_R * 2.0)
	lines.position = Vector2(0, _LINES_BELOW_BAND)
	lines.size = Vector2(fw, 0)
	circle.size = Vector2(_CIRCLE_R * 2.0, _CIRCLE_R * 2.0)
	circle.position = Vector2(fw * 0.5 - _CIRCLE_R, tray_top - _CIRCLE_ABOVE_TRAY - band_h - _CIRCLE_R)
	bet_label.reset_size()
	bet_label.position = Vector2(circle.position.x + _CIRCLE_R * 2.0 + 12.0, circle.position.y + _CIRCLE_R - bet_label.size.y * 0.5)
	low_label.size = Vector2(fw, 28)
	low_label.position = Vector2(0, circle.position.y + _CIRCLE_R - 14.0)
	settled_pill.reset_size()
	settled_pill.position = Vector2((fw - settled_pill.size.x) * 0.5, 12.0)
	# the tray: six 48 chips 8 apart, 16 in at 360
	var tray_w := P0Blackjack.CHIPS.size() * UiChipToken.SIZE + (P0Blackjack.CHIPS.size() - 1) * _CHIP_GAP
	tray.position = Vector2((w - tray_w) * 0.5, tray_top + _TRAY_CHIPS)
	tray.size = Vector2(tray_w, UiChipToken.SIZE)
	for i in chips.size():
		(chips[i] as Control).position = Vector2(i * (UiChipToken.SIZE + _CHIP_GAP), 0)
	var full := w - pad * 2.0
	var half := (full - _ROW_GAP) * 0.5
	var row1 := tray_top + _TRAY_CHIPS
	var row2 := tray_top + _TRAY_KEYS
	_place(clear_key, pad, row2, _CLEAR_W)
	clear_key.size.y = UiTokens.SIZE_TOUCH
	clear_key.position.y = row2 + (_KEY_H - UiTokens.SIZE_TOUCH) * 0.5
	_place(deal_key, pad + _CLEAR_W + _ROW_GAP, row2, full - _CLEAR_W - _ROW_GAP)
	_place(hit_key, pad, row1, half)
	_place(stand_key, pad + half + _ROW_GAP, row1, half)
	_place(double_key, pad, row2, half)
	_place(split_key, pad + half + _ROW_GAP, row2, half)
	_place(change_key, pad, row2, half)
	_place(again_key, pad + half + _ROW_GAP, row2, half)
	_lay_cards(false)

func _place(c: Control, x: float, y: float, width: float) -> void:
	c.position = Vector2(x, y)
	c.size = Vector2(width, _KEY_H)
	if c is UiCommandButton: (c as UiCommandButton).min_width = width

## Where card i of a hand of n goes, in felt coordinates, the cards' bottom _HAND_GAP above the bet circle: one hand
## centred stepping OVERLAP; split hands (BJ-SPEC-CARDS) 16 in from each side and 24 apart, stepping SPLIT_OVERLAP,
## each laid out from its left edge.
func card_pos(hand_index: int, i: int, hand_count: int, n: int) -> Vector2:
	var fw := felt.size.x
	var y := circle.position.y - _HAND_GAP - UiPlayingCard.SIZE.y
	if hand_count <= 1:
		var width := UiPlayingCard.SIZE.x + (n - 1) * UiPlayingCard.OVERLAP
		return Vector2(fw * 0.5 - width * 0.5 + i * UiPlayingCard.OVERLAP, y)
	var lane := (fw - float(UiTokens.SPACE_PAGE) * 2.0 - _SPLIT_GAP) * 0.5
	var x0 := float(UiTokens.SPACE_PAGE) + hand_index * (lane + _SPLIT_GAP)
	return Vector2(x0 + i * UiPlayingCard.SPLIT_OVERLAP, y)

func hand_width(hand_count: int, n: int) -> float:
	return UiPlayingCard.SIZE.x + (n - 1) * (UiPlayingCard.OVERLAP if hand_count <= 1 else UiPlayingCard.SPLIT_OVERLAP)

func dealer_pos(i: int, n: int) -> Vector2:
	var width := UiPlayingCard.SIZE.x + (n - 1) * UiPlayingCard.OVERLAP
	return Vector2(felt.size.x * 0.5 - width * 0.5 + i * UiPlayingCard.OVERLAP, _CARDS_BELOW_BAND)

func shoe_pos() -> Vector2: return Vector2(felt.size.x - UiPlayingCard.SIZE.x - 12.0, -UiPlayingCard.SIZE.y * 0.6)

## Every card to its place (instantly, or sliding when `slide`), with the badges, tags and highlight.
func _lay_cards(slide: bool) -> void:
	for i in _dealer_cards.size():
		_move(_dealer_cards[i], dealer_pos(i, _dealer_cards.size()), slide)
	var n := _hands.size()
	for k in n:
		var hand: Dictionary = _hands[k]
		var cards: Array = hand.cards
		for i in cards.size():
			_move(cards[i], card_pos(k, i, n, cards.size()), slide)
		var first := card_pos(k, 0, n, maxi(1, cards.size()))
		var width := hand_width(n, cards.size())
		var badge: PanelContainer = hand.badge
		_badge_set(badge, P0Blackjack.badge(_codes(cards)))
		if n > 1: badge.position = Vector2(first.x + (width - badge.size.x) * 0.5, first.y + UiPlayingCard.SIZE.y + 4.0)
		else: badge.position = Vector2(first.x + width + 8.0, first.y + (UiPlayingCard.SIZE.y - badge.size.y) * 0.5)
		var tag: PanelContainer = hand.tag
		tag.reset_size()
		tag.position = Vector2(first.x + (width - tag.size.x) * 0.5, first.y - tag.size.y * 0.5)   # over the cards' top edge
		var stake: Label = hand.stake
		stake.visible = n > 1
		stake.text = P0Blackjack.comma(int(hand.bet))
		stake.reset_size()
		stake.position = Vector2(first.x + (width - stake.size.x) * 0.5, badge.position.y + badge.size.y + 2.0)
		var outline: Panel = hand.outline
		outline.visible = n > 1 and k == _active and phase == Phase.PLAY
		outline.position = first - Vector2(6, 6)
		outline.size = Vector2(width + 12, UiPlayingCard.SIZE.y + 12)
		for c in cards: (c as Control).modulate.a = 0.55 if n > 1 and k != _active and phase == Phase.PLAY else 1.0
	var dw := UiPlayingCard.SIZE.x + (_dealer_cards.size() - 1) * UiPlayingCard.OVERLAP
	var d0 := dealer_pos(0, maxi(1, _dealer_cards.size()))
	_badge_set(dealer_badge, P0Blackjack.badge(_codes(_dealer_cards)) if not _dealer_cards.is_empty() else "")
	dealer_badge.position = Vector2(d0.x + dw + 8.0, d0.y + (UiPlayingCard.SIZE.y - dealer_badge.size.y) * 0.5)

func _move(c: Control, to: Vector2, slide: bool) -> void:
	if slide and animate and c.position != to:
		create_tween().tween_property(c, "position", to, UiKit.secs(UiTokens.MOTION_RADIAL_PETAL_IN_MS)).set_ease(Tween.EASE_OUT)
	else:
		c.position = to

static func _codes(cards: Array) -> Array: return cards.map(func(c): return (c as UiPlayingCard).card)

# ---------------------------------------------------------------- state from the view

## Every new view (P0Ui.set_view, which may run each frame): only a change in the table or the coins counts. The
## events of the same reply arrive right after (on_events), so the work waits for the end of the frame.
func refresh(v: Dictionary) -> void:
	view = v
	var key := [P0Blackjack.info(v), P0Blackjack.coins_of(v)].hash()
	if key == _seen: return
	_seen = key
	_sync.call_deferred()

## The reply's events (P0Runtime._on_state after set_view): the table's own play in order.
func on_events(events: Array) -> void:
	var mine := events.filter(func(e): return str(e.get("kind", "")) in ["bj_dealt", "bj_card", "bj_result"])
	if mine.is_empty(): return
	_pending.append_array(mine)
	_sync.call_deferred()

## A command came back refused: wait no more, say why when it is the player's to fix, lay out the view.
func refused(code: String, detail: Dictionary) -> void:
	_waiting = false
	if code == "bj_no_coins" and toast.is_valid(): toast.call(P0Blackjack.need_text(int(detail.get("need", 0))))
	if not _running: _reconcile()

var _synced_frame := -1
func _sync() -> void:
	if _synced_frame == Engine.get_process_frames() and _pending.is_empty(): return
	_synced_frame = Engine.get_process_frames()
	_waiting = false
	var events := _pending
	_pending = []
	var paid := 0
	for e in events:
		if str(e.kind) == "bj_result":
			for hh in e.get("hands", []): paid += int(hh.get("payout", 0))
	if events.is_empty():
		if _running: _steps.append(func(): _reconcile(); return 0.0)
		else: _reconcile()
		return
	_roll_coins(P0Blackjack.coins_of(view) - paid)   # the stake leaves now; a payout comes with its result
	var target := maxi(1, (P0Blackjack.hand(view).get("hands", []) as Array).size())
	for e in events:
		for hh in [e]:
			if str(hh.kind) == "bj_result": target = maxi(target, (hh.get("hands", []) as Array).size())
	for e in events:
		match str(e.kind):
			"bj_dealt": _steps.append(_step_dealt.bind(e))
			"bj_card": _steps.append(_step_card.bind(e, target))
			"bj_result": _steps.append(_step_result.bind(e))
	_steps.append(func(): _reconcile(); return 0.0)
	_run()

func _run() -> void:
	if _running: return
	_running = true
	_refresh_keys()
	while not _steps.is_empty():
		var step: Callable = _steps.pop_front()
		var wait := float(step.call())
		if animate and wait > 0.0 and is_inside_tree(): await get_tree().create_timer(wait).timeout
		if not is_inside_tree() and animate: break
	_running = false
	_refresh_keys()

## Lay the table out as the view has it, with no motion: a resumed hand, a refusal, the end of a reply's play.
func _reconcile() -> void:
	var h := P0Blackjack.hand(view)
	if not h.is_empty():
		phase = Phase.PLAY
		_active = int(h.get("active", 0))
		var want_hands: Array = (h.get("hands", []) as Array).map(func(x): return x.get("cards", []))
		var want_dealer: Array = h.get("dealer", [])
		var have_hands: Array = _hands.map(func(x): return _codes(x.cards))
		if have_hands != want_hands or _codes(_dealer_cards) != want_dealer:
			_clear_table()
			for c in want_dealer: _dealer_cards.append(_new_card(str(c)))
			for k in want_hands.size():
				var hd := _new_hand(int((h.hands[k] as Dictionary).get("bet", 0)))
				for c in want_hands[k]: hd.cards.append(_new_card(str(c)))
		var total := 0
		for x in h.get("hands", []): total += int(x.get("bet", 0))
		_set_stack(total)
	elif phase == Phase.PLAY:   # the hand went without a result shown (refused, settled elsewhere)
		_clear_table()
		_enter_bet(P0Blackjack.deal_again_bet(view, int(P0Blackjack.info(view).get("last_bet", 0))))
	if phase == Phase.BET and bet > 0 and not P0Blackjack.can_add(view, bet, 0): _enter_bet(0)
	if not _running: _roll_coins(P0Blackjack.coins_of(view))
	_lay_cards(false)
	_refresh_keys()

# ---------------------------------------------------------------- motion steps (each returns seconds to wait)

func _fly() -> float: return UiKit.secs(UiTokens.MOTION_RADIAL_PETAL_IN_MS)

func _step_dealt(e: Dictionary) -> float:
	_clear_table()
	_result = {}
	phase = Phase.PLAY
	var h: Dictionary = e.get("hand", {})
	_set_stack(int(e.get("bet", 0)))
	_active = 0
	var p: Array = (h.get("hands", [{}])[0] as Dictionary).get("cards", [])
	var d: Array = h.get("dealer", [])
	var hand := _new_hand(int(e.get("bet", 0)))
	_lay_cards(false)
	var order := [[hand, p[0] if p.size() > 0 else ""], [null, d[0] if d.size() > 0 else ""],
		[hand, p[1] if p.size() > 1 else ""], [null, d[1] if d.size() > 1 else ""]]
	var t := 0.0
	for k in order.size():
		var code := str(order[k][1])
		var card := _new_card(code, shoe_pos())
		if order[k][0] == null: _dealer_cards.append(card)
		else: (hand.cards as Array).append(card)
		card.visible = not animate
		if animate:
			var delay := t
			get_tree().create_timer(delay).timeout.connect(func():
				if is_instance_valid(card): card.visible = true
				_lay_cards(true))
		t += _fly()
	if not animate: _lay_cards(false)
	return t + 0.05

func _step_card(e: Dictionary, target_hands: int) -> float:
	if str(e.get("to", "")) == "dealer":
		var code := str(e.get("card", ""))
		if bool(e.get("hole", false)) and _dealer_cards.size() > 1:
			var hole: UiPlayingCard = _dealer_cards[1]
			if animate:
				hole.flip_to(code)
				return UiKit.secs(UiTokens.MOTION_RADIAL_RETRACT_MS * 2 + UiTokens.MOTION_PENDING_DELAY_MS)
			hole.card = code
			_lay_cards(false)
			return 0.0
		_dealer_cards.append(_new_card(code, shoe_pos()))
		_lay_cards(true)
		return _fly() + UiKit.secs(UiTokens.MOTION_PENDING_DELAY_MS)
	var k := int(e.get("hand_index", 0))
	if _hands.size() < target_hands and _hands.size() == 1 and (_hands[0].cards as Array).size() == 2:
		# Split: the pair's second card moves over to become the second hand.
		var moved: UiPlayingCard = (_hands[0].cards as Array).pop_back()
		var second := _new_hand(int(_hands[0].bet))
		(second.cards as Array).append(moved)
		_set_stack(int(_hands[0].bet) * 2)
	while _hands.size() <= k: _new_hand(int(_hands[0].bet) if not _hands.is_empty() else bet)
	var card := _new_card(str(e.get("card", "")), shoe_pos())
	(_hands[k].cards as Array).append(card)
	var ev_hands: Array = P0Blackjack.hand(view).get("hands", [])
	if k < ev_hands.size(): _hands[k].bet = int(ev_hands[k].get("bet", _hands[k].bet))
	_lay_cards(true)
	return _fly() + 0.08

func _step_result(e: Dictionary) -> float:
	if str(e.get("why", "")) == "expired":
		_clear_table()
		show_settled(P0Blackjack.settled_line(e))
		_roll_coins(P0Blackjack.coins_of(view))
		_enter_bet(P0Blackjack.deal_again_bet(view, int(P0Blackjack.info(view).get("last_bet", 0))))
		return 0.0
	# the dealer's cards as settled (when the reply left some unplayed: a peek)
	var dealer: Array = e.get("dealer", [])
	for i in dealer.size():
		if i < _dealer_cards.size():
			if (_dealer_cards[i] as UiPlayingCard).card != str(dealer[i]): (_dealer_cards[i] as UiPlayingCard).card = str(dealer[i])
		else: _dealer_cards.append(_new_card(str(dealer[i])))
	phase = Phase.RESULT
	_result = e
	var hands: Array = e.get("hands", [])
	for k in mini(hands.size(), _hands.size()):
		var tag: PanelContainer = _hands[k].tag
		(tag.get_node("Text") as Label).text = P0Blackjack.result_word(str(hands[k].get("result", "")))
		tag.visible = true
		_hands[k].bet = int(hands[k].get("bet", _hands[k].bet))
	_lay_cards(false)
	for k in mini(hands.size(), _hands.size()):
		var f := P0Blackjack.float_text(int(hands[k].get("net", 0)))
		if f != "": _float(f, _hand_top(k))
	_roll_coins(P0Blackjack.coins_of(view))
	return UiKit.secs(UiTokens.MOTION_FLOAT_TEXT_MS) * 0.5

func _hand_top(k: int) -> Vector2:
	var cards: Array = _hands[k].cards
	var first := card_pos(k, 0, _hands.size(), maxi(1, cards.size()))
	var width := hand_width(_hands.size(), cards.size())
	return felt.position + first + Vector2(width * 0.5, -30.0)

func _float(text: String, at: Vector2) -> void:
	var f := UiFloatText.new(text, UiFloatText.Tone.COINS, ICON_COIN)
	f.theme = UiKit.theme()
	add_child(f)
	f.play(at)

func _set_coins_text(t: String) -> void:
	coins_label.text = t
	if coins_pill.is_inside_tree():
		coins_pill.size = coins_pill.get_combined_minimum_size()
		coins_pill.position.x = size.x - UiTokens.SPACE_PAGE - coins_pill.size.x

func _roll_coins(to: int) -> void:
	if _coins_tween != null and _coins_tween.is_valid(): _coins_tween.kill()
	if not animate or to == _coins_shown:
		_coins_shown = to
		_set_coins_text(P0Blackjack.comma(to))
		return
	var from := _coins_shown
	_coins_shown = to
	_coins_tween = create_tween()
	_coins_tween.tween_method(func(x: float): _set_coins_text(P0Blackjack.comma(int(round(x)))), float(from), float(to),
		UiKit.secs(UiTokens.MOTION_QUICK_BAR_REFILL_MS))

# ---------------------------------------------------------------- the table's pieces

func _new_card(code: String, at := Vector2.INF) -> UiPlayingCard:
	var c := UiPlayingCard.new(code)
	felt.add_child(c)
	if at.is_finite(): c.position = at
	return c

func _new_hand(stake: int) -> Dictionary:
	var outline := Panel.new()
	var os := StyleBoxFlat.new()
	os.bg_color = Color(0, 0, 0, 0)
	os.border_color = UiTokens.COLOR_GOLD
	os.set_border_width_all(2)
	os.set_corner_radius_all(10)
	outline.add_theme_stylebox_override(&"panel", os)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.visible = false
	hands_box.add_child(outline)
	var tag := _badge()
	var ts := tag.get_theme_stylebox(&"panel") as StyleBoxFlat
	ts.bg_color = UiTokens.COLOR_SURFACE_RAISED
	(tag.get_node("Text") as Label).add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT)
	hands_box.add_child(tag)
	var badge := _badge()
	hands_box.add_child(badge)
	var stake_l := UiKit.label("", UiTokens.STYLE_C12_B, UiKit.alpha(FELT_INK, 0.8))
	stake_l.visible = false
	hands_box.add_child(stake_l)
	var hand := {"cards": [], "bet": stake, "badge": badge, "tag": tag, "stake": stake_l, "outline": outline}
	_hands.append(hand)
	return hand

func _clear_table() -> void:
	for c in _dealer_cards: (c as Node).free()
	_dealer_cards = []
	for hd in _hands:
		for c in hd.cards: (c as Node).free()
		for n in ["badge", "tag", "stake", "outline"]: (hd[n] as Node).free()
	_hands = []
	_badge_set(dealer_badge, "")

## The chips drawn in the circle: the player's own stack while betting, else the stake in its largest chips.
func _set_stack(total: int) -> void:
	bet = total
	if P0Blackjack.chips_for(total) != stack and stack.reduce(func(a, b): return a + b, 0) != total:
		stack = P0Blackjack.chips_for(total)
	circle.set_stack(stack)
	bet_label.text = P0Blackjack.comma(total) if total > 0 else ""

func _enter_bet(preset: int) -> void:
	phase = Phase.BET
	_result = {}
	stack = P0Blackjack.chips_for(preset)
	_set_stack(preset)

# ---------------------------------------------------------------- keys

func _busy() -> bool: return _waiting or _running

func _refresh_keys() -> void:
	var low := phase == Phase.BET and P0Blackjack.low_on_coins(view) and bet == 0
	var expired := bool(P0Blackjack.hand(view).get("expired", false))
	tray.visible = phase == Phase.BET
	clear_key.visible = phase == Phase.BET
	deal_key.visible = phase == Phase.BET
	for k in [hit_key, stand_key, double_key, split_key]: (k as Control).visible = phase == Phase.PLAY and not expired and not _running
	again_key.visible = phase == Phase.RESULT and not _running
	change_key.visible = phase == Phase.RESULT and not _running
	circle.visible = not low
	low_label.visible = low
	bet_label.visible = not low and bet > 0
	lines.visible = true
	if phase == Phase.BET:
		for i in chips.size():
			var c: UiChipToken = chips[i]
			if not (_press.get("index", -1) == i and _ghost != null):
				c.state = UiChipToken.State.DEFAULT if P0Blackjack.can_add(view, bet, c.value) else UiChipToken.State.DISABLED
		var dk := P0Blackjack.deal_key(view, bet)
		deal_key.label = str(dk.label)
		deal_key.reason = str(dk.reason)
		clear_key.disabled = bet == 0
	elif phase == Phase.PLAY:
		var keys := P0Blackjack.action_keys(view)
		for pair in [[hit_key, "hit"], [stand_key, "stand"], [double_key, "double"], [split_key, "split"]]:
			var k: UiCommandButton = pair[0]
			var spec: Dictionary = keys[pair[1]]
			k.label = str(spec.label)
			k.reason = str(spec.reason)
			k.disabled = not bool(spec.enabled) and str(spec.reason) == ""
	elif phase == Phase.RESULT:
		var again := P0Blackjack.deal_again_bet(view, _last_bet())
		again_key.label = "Deal again · " + P0Blackjack.comma(again) if again > 0 else "Deal again"
		again_key.reason = "" if again > 0 else P0Blackjack.need_text(P0Blackjack.need(P0Blackjack.coins_of(view), P0Blackjack.min_bet_of(view), P0Blackjack.floor_of(view)))

func _last_bet() -> int:
	var lb := int(P0Blackjack.info(view).get("last_bet", 0))
	if lb > 0: return lb
	var hands: Array = _result.get("hands", [])
	return int((hands[0] as Dictionary).get("bet", 0)) if not hands.is_empty() else 0

## Open: the first-open card if this account has not seen it, and the opening command (settles an expired hand).
func opened() -> void:
	intro_layer.visible = not bool(P0Blackjack.info(view).get("intro", true))
	command.emit({"type": "bj_open"})

func deal(amount: int) -> void:
	if _busy() or amount <= 0: return
	if P0Blackjack.need(P0Blackjack.coins_of(view), amount, P0Blackjack.floor_of(view)) > 0: return
	_waiting = true
	command.emit({"type": "bj_deal", "bet": amount})

func act(action: String) -> void:
	if _busy() or phase != Phase.PLAY: return
	_waiting = true
	command.emit({"type": "bj_act", "action": action})

func deal_again() -> void:
	var b := P0Blackjack.deal_again_bet(view, _last_bet())
	if b <= 0:
		change_bet()
		return
	stack = P0Blackjack.chips_for(b)
	deal(b)

func change_bet() -> void:
	if _busy(): return
	_clear_table()
	_enter_bet(P0Blackjack.deal_again_bet(view, _last_bet()))
	_lay_cards(false)
	_refresh_keys()

func clear_bet() -> void:
	if phase != Phase.BET: return
	stack = []
	_set_stack(0)
	_refresh_keys()

## Add one chip to the bet (a tap's flight or a drop has landed).
func add_chip(value: int) -> void:
	if phase != Phase.BET: return
	stack.append(value)
	_set_stack(bet + value)
	_refresh_keys()

func show_settled(text: String) -> void:
	settled_label.text = text
	settled_pill.visible = true
	settled_pill.modulate.a = 1.0
	_layout()
	var t := create_tween()
	t.tween_interval(_SETTLED_S if animate else 0.0)
	t.tween_property(settled_pill, "modulate:a", 0.0, UiKit.secs(UiTokens.MOTION_DISSOLVE_MS))
	t.tween_callback(func(): settled_pill.visible = false)

func open_rules() -> void:
	rules_layer.visible = true
	rules_sheet.height = rules_sheet.body.get_combined_minimum_size().y + 24.0 + UiDrawer.HANDLE_H * 0.5
func close_rules() -> void: rules_layer.visible = false

## Back on the page (Android Back): the rules sheet first; the first-open card stays until Got it. false = leave.
func back_inner() -> bool:
	if rules_layer.visible:
		close_rules()
		return true
	return false

# ---------------------------------------------------------------- chip gestures

func _chip_input(event: InputEvent, i: int) -> void:
	var down: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available())
	if not down or not _press.is_empty(): return
	var c: UiChipToken = chips[i]
	if phase != Phase.BET or _busy() or c.state == UiChipToken.State.DISABLED: return
	accept_event()
	_press = {"index": i, "start": _local(event), "t0": Time.get_ticks_msec(), "touch": event is InputEventScreenTouch,
		"id": event.index if event is InputEventScreenTouch else -1}

func _local(event: InputEvent) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * (event as InputEventFromWindow).position \
		if event is InputEventFromWindow else Vector2.ZERO

func _input(event: InputEvent) -> void:
	if _press.is_empty(): return
	var touch := bool(_press.touch)
	if touch and not (event is InputEventScreenTouch or event is InputEventScreenDrag): return
	if not touch and not (event is InputEventMouseButton or event is InputEventMouseMotion): return
	if touch and int(event.get("index")) != int(_press.id): return
	var pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * (event as InputEventFromWindow).position
	pos = get_global_transform().affine_inverse() * pos
	var moving: bool = event is InputEventScreenDrag or event is InputEventMouseMotion
	var up: bool = (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed)
	if moving:
		if _ghost == null and pos.distance_to(_press.start) > GestureArbiter.TAP_SLOP: _begin_drag()
		if _ghost != null:
			_ghost.position = pos - _ghost.size * 0.5 + Vector2(0, -UiChipToken.SIZE * 0.6)   # under the finger, still seen
			circle.lit = over_circle(_ghost.position + _ghost.size * 0.5)
		get_viewport().set_input_as_handled()
	elif up:
		get_viewport().set_input_as_handled()
		var i := int(_press.index)
		var quick := Time.get_ticks_msec() - int(_press.t0) <= GestureArbiter.TAP_MAX_MS
		_press = {}
		if _ghost != null: _drop(i)
		elif quick: tap_chip(i)

func over_circle(p: Vector2) -> bool: return p.distance_to(circle_center()) <= _CIRCLE_R + _CIRCLE_HIT

func _begin_drag() -> void:
	var c: UiChipToken = chips[int(_press.index)]
	_ghost = UiChipToken.new(c.value, UiChipToken.State.DRAGGING)
	_ghost.position = tray.position + c.position
	add_child(_ghost)

func _drop(i: int) -> void:
	var g := _ghost
	_ghost = null
	var landed := circle.lit and P0Blackjack.can_add(view, bet, g.value)
	circle.lit = false
	var to := circle_center() - g.size * 0.5 if landed else tray.position + (chips[i] as Control).position
	var v := g.value
	if not animate:
		g.free()
		if landed: add_chip(v)
		return
	var t := create_tween()
	t.tween_property(g, "position", to, _fly()).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		g.queue_free()
		if landed: add_chip(v))

## A tap on chip i: it flies from the tray into the circle and the bet grows by its value.
func tap_chip(i: int) -> void:
	var c: UiChipToken = chips[i]
	if phase != Phase.BET or _busy() or not P0Blackjack.can_add(view, bet, c.value): return
	if not animate:
		add_chip(c.value)
		return
	var f := UiChipToken.new(c.value)
	f.position = tray.position + c.position
	add_child(f)
	bet += c.value   # counted at once so a quick second tap sees it; drawn when it lands
	_refresh_keys()
	var t := create_tween()
	t.tween_property(f, "position", circle_center() - f.size * 0.5, _fly()).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		f.queue_free()
		bet -= c.value
		add_chip(c.value))

## The felt's print arc: a faint line, the table's edge (BJ-BET "Table print arc").
class _Arc extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_arc(size * 0.5, size.x * 0.5, 0.0, TAU, 160, UiKit.alpha(Color("FBF8F1"), 0.22), 1.0, true)

## The bet circle: a ring on the felt (lit while a dragged chip is over it) and the stack, at most CIRCLE_MAX drawn.
class _Circle extends Control:
	var lit := false: set = set_lit
	var _chips: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_lit(v: bool) -> void:
		lit = v
		queue_redraw()

	func set_stack(values: Array) -> void:
		for c in _chips: (c as Node).free()
		_chips = []
		var shown := values.slice(maxi(0, values.size() - P0Blackjack.CIRCLE_MAX))
		for i in shown.size():
			var t := UiChipToken.new(int(shown[i]))
			t.position = size * 0.5 - t.size * 0.5 + Vector2(0, (shown.size() - 1) * 2.5 - i * 5.0)   # 5 up each (BJ-BET stack)
			add_child(t)
			_chips.append(t)

	## BJ-BET: a 2 px light ring on a faint fill; BJ-DRAG: a white 3 px ring with a soft glow.
	func _draw() -> void:
		var r := size.x * 0.5
		var c := size * 0.5
		if lit:
			draw_circle(c, r + 6.0, UiKit.alpha(Color.WHITE, 0.10))
			draw_circle(c, r, UiKit.alpha(Color.WHITE, 0.30))
			draw_arc(c, r - 1.5, 0.0, TAU, 64, Color.WHITE, 3.0, true)
		else:
			draw_circle(c, r, UiKit.alpha(Color.BLACK, 0.06))
			draw_arc(c, r - 1.0, 0.0, TAU, 64, UiKit.alpha(Color("FBF8F1"), 0.55), 2.0, true)
