class_name P0BlackjackPage
extends Control
## The Barbary Card Room's Blackjack table (SGODOT-351; q(238)–(240), C13 by 不知火舞 on 351 37022a3c / d835ac7e; server
## 后裔 on 351 b610f98a + 9cb4e561), full screen over the room, opened by Lou's `Play` (P0Ui.open_blackjack).
## A photoreal table (background ①, table_bg.jpg) fills the screen, bottom-aligned and cropped from the top; everything on
## it lives in `table`, a 360 × 800 layer in the design's own coordinates scaled with the picture: the dealer's cards
## (zone 110–250), the two printed rule lines, the player's hand(s) (360–500), the bet circle (centre 570, 96 across),
## the printed actions (620–680) and six ChipStacks in the rail's groove (690–800). Floating over the felt: the round
## back `‹` top-left and the coins pill top-right; `Rules` is printed on the felt left of the shoe. No panel, no buttons:
## every action is a FeltAction printed on the felt, faded with its reason printed under it when it cannot be done.
##   BET    tap a stack: one chip flies into the circle (MOTION_RADIAL_PETAL_IN_MS); drag from a stack: a Dragging chip
##          follows the finger and the circle's ring brightens over it; let go there to add, anywhere else it flies back.
##          Tap and drag part as GestureArbiter does (TAP_SLOP, TAP_MAX_MS); no double tap anywhere. A stack the wallet
##          cannot put down (it would leave under the floor) greys and takes neither. The stake sits in the circle with
##          its amount printed once to its right; tapping the stake takes it all back (no Clear). Empty, the circle
##          reads `Place a bet` and `Deal` fades with no reason. Not even 5 fits: `Low on coins` / `Need N more coins`
##          where the circle is, every stack grey, `Deal` faded.
##   PLAY   `Hit` / `Stand` Large, side by side, equal; `Double` / `Split` Small beside the circle, faded with the
##          server's reason; no amounts on any action. Split hands side by side (24 apart), the one in play outlined, the
##          other dimmed. An expired hand shows no actions.
##   after  a result tag over each hand, `+N coins` floats for wins, the pill rolls; then last hand's stake sets itself
##          in the circle again (stepped down to keep the floor, never climbing back) and `Deal` deals again — no Deal
##          again / Change bet. The cards stay until the next deal.
## The page sends intents only (bj_open on opening, bj_intro, bj_deal {bet}, bj_act {action}); the server deals and
## settles. A reply's bj_dealt / bj_card (hole: true turns the hole card over) / bj_result play in order, then the page
## matches the view; a view with no events (opening mid-hand, a refusal) is laid out at once. First open: the centred card
## (bj_intro on Got it). A hand the server settled away: `Last hand settled · …` for 3 s under the coins pill.

signal back_pressed
signal command(cmd: Dictionary)

enum Phase { BET, PLAY, RESULT }

const BG := preload("res://assets/p0/art/casino/table_bg.jpg")
const DESIGN := Vector2(360, 800)
const INK := Color("FBF8F1")
const ICON_COIN := preload("res://assets/p0/icons/coin.svg")
# C13 zones in the table's 1× coordinates (d835ac7e; background ①: shoe top-right to y≈90, rail groove x 28–332).
# BJ-BET-T 187:167298 (1d226acd): back 44 at (16, 28), Rules (Small) centred (173, 50), coins pill 225–276 at y 37
# (left of the shoe), rail stacks from x 26 every 52 with their top chip's top at 687.
const _RULES_AT := Vector2(173, 50)          # the top-left light takes no print
const _LINES_Y := 284.0                      # the two lines' tops: 284 / 308, cream 62% / 50%
const _DEALER_TOP := 140.0                   # cards 80 high in 110–250
const _PLAYER_TOP := 372.0                   # ACT-T 189:168498
const _CIRCLE := Vector2(180, 570)
const _CIRCLE_R := 48.0
const _CIRCLE_HIT := 12.0                    # a drop counts this far outside the ring
const _ACTIONS_Y := 650.0                    # the printed actions' row (620–680)
# ACT-T: Hit / Stand Large 140 wide under the circle; Double / Split Small between the hand and the circle (y 486).
const _HIT_X := 102.0
const _STAND_X := 258.0
const _HIT_W := 140.0
const _DOUBLE_AT := Vector2(100, 486)
const _SPLIT_AT := Vector2(260, 486)
const _BADGE_GAP := 12.0                     # a points badge sits this far right of its cards
const _SPLIT_X := [24.0, 196.0]              # SPLIT-T 190:169341: each hand's first card
const _SPLIT_STACK_DX := 16.0                # each hand's stake, either side of the circle's centre
const _PLATE_GAP := 8.0                      # RESULT-T: the result plate this far above the cards
const _FLOAT_AT := Vector2(122, 516)         # RESULT-T: `+180 coins` left of the circle
const _WINNINGS_FROM := Vector2(250, 236)    # the dealer's side, where winnings slide in from
const _RAIL_X := 26.0
const _RAIL_GAP := 4.0                       # 6 × 48 + 5 × 4 = 308 in the groove's 304 + rims
const _RAIL_Y := 693.0                       # stacks' bottom chip top (the top chip's top 6 higher, at 687)
const _STACK_DEPTH := 4                      # chips in a rail stack
const _BACK_AT := Vector2(16, 28)
const _COINS_RIGHT := 276.0                  # the coins pill's right edge, on the table (left of the shoe)
const _COINS_TOP := 37.0
const _SETTLED_S := 3.0

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
var _result := {}            # the last bj_result shown (its tags stay until the next deal)
var _waiting := false        # a command is out: actions and chips wait for its answer
var _steps: Array = []       # queued motion: Callables returning seconds to wait
var _running := false
var _pending: Array = []     # bj events of the reply whose view just came
var _seen := 0               # hash of what the last refresh laid out
var _coins_shown := 0
var _coins_tween: Tween

var bg: TextureRect
var table: Control
var back_key: Button
var coins_pill: PanelContainer
var coins_label: Label
var rules_key: UiFeltAction
var lines: Array = []
var circle: _Circle
var bet_label: Label
var empty_label: Label
var low_label: Label
var low_need: Label
var settled_pill: PanelContainer
var settled_label: Label
var dealer_badge: PanelContainer
var hands_box: Control
var stacks: Array = []       # UiChipStack on the rail, one per value
var deal_key: UiFeltAction
var hit_key: UiFeltAction
var stand_key: UiFeltAction
var double_key: UiFeltAction
var split_key: UiFeltAction
var intro_layer: Control
var intro_card: UiSystemCard
var rules_layer: Control
var rules_sheet: UiDrawer

var _dealer_cards: Array = []      # UiPlayingCard
var _hands: Array = []             # [{cards: [UiPlayingCard], bet, badge, tag, stake, outline}]
var _active := 0

var _acted := ""                   # the last bj_act sent (a double's card doubles the stake shown)
var _press := {}                   # a stack under the finger
var _ghost: UiChipToken

func _init(view_: Dictionary = {}, safe_top_ := 0.0, safe_bottom_ := 0.0) -> void:
	safe_top = safe_top_
	safe_bottom = safe_bottom_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var under := ColorRect.new()   # what a picture cropped narrower than the screen would leave
	under.color = Color("2F6A3A")
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(under)
	bg = TextureRect.new()
	bg.texture = BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	table = Control.new()
	table.name = "Table"
	table.size = DESIGN
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(table)
	_build_table()
	_build_overlay()
	_build_layers()
	resized.connect(_layout)
	view = view_
	_coins_shown = P0Blackjack.coins_of(view)
	coins_label.text = P0Blackjack.comma(_coins_shown)
	_enter_bet(P0Blackjack.deal_again_bet(view, int(P0Blackjack.info(view).get("last_bet", 0))))
	_reconcile()

# ---------------------------------------------------------------- build

func _print_label(text: String, font_size: int, alpha := 0.7) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_BODY_XB14, UiKit.alpha(INK, alpha))
	l.add_theme_font_size_override(&"font_size", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_table() -> void:
	rules_key = UiFeltAction.new("Rules", UiFeltAction.Size.SMALL)
	rules_key.name = "Rules"
	rules_key.activated.connect(open_rules)
	table.add_child(rules_key)
	for t in ["Blackjack pays 3 to 2", "Dealer stands on all 17s"]:
		var l := _print_label(t, 15 if t.begins_with("Blackjack") else 12, 0.62 if t.begins_with("Blackjack") else 0.5)
		table.add_child(l)
		lines.append(l)
	hands_box = Control.new()
	hands_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_child(hands_box)
	dealer_badge = _badge()
	table.add_child(dealer_badge)
	circle = _Circle.new()
	circle.tapped.connect(take_back)
	table.add_child(circle)
	empty_label = _print_label("Place a bet", 13, 0.75)
	table.add_child(empty_label)
	bet_label = _print_label("", 20, 1.0)
	bet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	table.add_child(bet_label)
	low_label = _print_label("Low on coins", 20, 1.0)
	table.add_child(low_label)
	low_need = _print_label("", 12, 0.75)
	table.add_child(low_need)
	deal_key = _action("Deal", UiFeltAction.Size.LARGE, func(): deal(bet))
	hit_key = _action("Hit", UiFeltAction.Size.LARGE, func(): act("hit"))
	stand_key = _action("Stand", UiFeltAction.Size.LARGE, func(): act("stand"))
	double_key = _action("Double", UiFeltAction.Size.SMALL, func(): act("double"))
	split_key = _action("Split", UiFeltAction.Size.SMALL, func(): act("split"))
	hit_key.min_frame = _HIT_W
	stand_key.min_frame = _HIT_W
	for v in P0Blackjack.CHIPS:
		var vals: Array = []
		for i in _STACK_DEPTH: vals.append(v)
		var s := UiChipStack.new(vals)
		s.mouse_filter = Control.MOUSE_FILTER_STOP
		s.gui_input.connect(_chip_input.bind(stacks.size()))
		table.add_child(s)
		stacks.append(s)

func _action(text: String, size_: UiFeltAction.Size, on: Callable) -> UiFeltAction:
	var a := UiFeltAction.new(text, size_)
	a.activated.connect(on)
	table.add_child(a)
	return a

func _build_overlay() -> void:
	back_key = UiProfileTopBar._Round.new(UiProfileTopBar._Round.Glyph.BACK)
	back_key.name = "Back"
	back_key.pressed.connect(func(): back_pressed.emit())
	add_child(back_key)
	coins_pill = PanelContainer.new()
	coins_pill.name = "Coins"
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.COLOR_SURFACE_RAISED
	sb.set_corner_radius_all(13)
	sb.content_margin_left = 9
	sb.content_margin_right = 7
	sb.shadow_color = UiTokens.COLOR_SHADOW_KEY
	sb.shadow_size = 3
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
	coins_pill.custom_minimum_size.y = 26
	coins_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coins_pill)
	settled_pill = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = UiTokens.COLOR_SURFACE_RAISED
	ps.set_corner_radius_all(14)
	ps.content_margin_left = 12
	ps.content_margin_right = 12
	ps.content_margin_top = 6
	ps.content_margin_bottom = 6
	settled_pill.add_theme_stylebox_override(&"panel", ps)
	settled_label = UiKit.label("", UiTokens.STYLE_C13_B)
	settled_pill.add_child(settled_label)
	settled_pill.visible = false
	settled_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(settled_pill)

## A points badge / result plate (StateBadge on ACT-T / RESULT-T): a 32-high pill, primary tint with primary ink;
## `Bust` in Tone=Danger.
func _badge() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.COLOR_PRIMARY_TINT
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override(&"panel", sb)
	var l := UiKit.label("", UiTokens.STYLE_C13_XB, UiTokens.COLOR_PRIMARY)
	l.name = "Text"
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	return p

## A badge's points; `Bust` in the danger tone (StateBadge Tone=Danger, 0c2082b7).
static func _badge_set(p: PanelContainer, text: String) -> void:
	var l := p.get_node("Text") as Label
	l.text = text
	var bust := text == "Bust"
	(p.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color = UiTokens.COLOR_DANGER if bust else UiTokens.COLOR_PRIMARY_TINT
	l.add_theme_color_override(&"font_color", UiTokens.COLOR_SURFACE if bust else UiTokens.COLOR_PRIMARY)
	p.visible = text != ""
	p.size = p.get_combined_minimum_size()

const RULES := ["Get closer to 21 than the dealer without going over.",
	"2–10 count as shown. J, Q and K count 10. A counts 1 or 11.",
	"Blackjack (an A and a 10-value card) pays 3 to 2, rounded down to whole coins.",
	"The dealer draws to 16 and stands on all 17s.",
	"Double: your bet doubles and you get one more card. First two cards only.",
	"Split: a pair becomes two hands, once per hand. Split aces get one card each.",
	"Wins pay 1 to 1. A tie returns your bet.",
	"4 decks, shuffled every hand."]
const NBSP := " "
## The first-open card (d835ac7e BJ-INTRO-T): how to bet, then the floor; `least 40` kept together.
const INTRO_BODY := "Tap or drag chips onto the circle, then tap Deal.\n\nYou bet coins here. You always keep at least" + NBSP + "40."

func _build_layers() -> void:
	intro_layer = _scrim()
	intro_card = UiSystemCard.new()
	intro_card.show_card({"title": "Barbary Card Room", "body": INTRO_BODY, "primary": "Got it"})
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
	rules_sheet.body.add_child(UiKit.label("Rules", UiTokens.STYLE_TITLE_XB20))
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

func _scrim() -> ColorRect:
	var s := ColorRect.new()
	s.color = UiTokens.COLOR_SCRIM_MODAL
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	s.visible = false
	add_child(s)
	return s

# ---------------------------------------------------------------- layout

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE: _layout.call_deferred()

## The picture covers the screen, bottom-aligned (the rail always on the bottom edge), cropped from the top or evenly
## from the sides; the table layer scales and sits with it.
func table_scale() -> float: return maxf(size.x / DESIGN.x, size.y / DESIGN.y) if size.x > 0.0 else 1.0
## A point on the table (1× design coordinates) in this page's coordinates.
func on_page(p: Vector2) -> Vector2: return table.position + p * table.scale
func circle_center() -> Vector2: return on_page(_CIRCLE)

func _layout() -> void:
	if size.x <= 0.0: return
	var k := table_scale()
	table.scale = Vector2(k, k)
	table.position = Vector2((size.x - DESIGN.x * k) * 0.5, size.y - DESIGN.y * k)
	bg.position = table.position
	bg.size = DESIGN * k
	_place(rules_key, _RULES_AT)
	for i in lines.size():
		var l: Label = lines[i]
		l.size = Vector2(DESIGN.x, 20)
		l.position = Vector2(0, _LINES_Y + i * 24.0)
	circle.size = Vector2(_CIRCLE_R * 2.0, _CIRCLE_R * 2.0)
	circle.position = _CIRCLE - circle.size * 0.5
	empty_label.size = Vector2(_CIRCLE_R * 2.0, 18)
	empty_label.position = _CIRCLE - empty_label.size * 0.5
	_layout_bet_label()
	low_label.size = Vector2(DESIGN.x, 28)
	low_label.position = Vector2(0, _CIRCLE.y - 22.0)
	low_need.size = Vector2(DESIGN.x, 18)
	low_need.position = Vector2(0, _CIRCLE.y + 8.0)
	_place(deal_key, Vector2(DESIGN.x * 0.5, _ACTIONS_Y))
	_place(hit_key, Vector2(_HIT_X, _ACTIONS_Y))
	_place(stand_key, Vector2(_STAND_X, _ACTIONS_Y))
	_place(double_key, _DOUBLE_AT)
	_place(split_key, _SPLIT_AT)
	for i in stacks.size():
		(stacks[i] as Control).position = Vector2(_RAIL_X + i * (UiChipToken.SIZE + _RAIL_GAP), _RAIL_Y)
	back_key.position = Vector2(_BACK_AT.x, safe_top + _BACK_AT.y)
	_fit_coins()
	settled_pill.size = settled_pill.get_combined_minimum_size()
	settled_pill.position = Vector2((size.x - settled_pill.size.x) * 0.5, coins_pill.position.y + coins_pill.size.y + 12.0)
	_lay_cards(false)

## Centre a printed action on a table point (its touch area may be wider than its frame).
func _place(c: Control, centre: Vector2) -> void:
	c.position = centre - c.size * 0.5

func _fit_coins() -> void:
	coins_pill.size = coins_pill.get_combined_minimum_size()
	coins_pill.position = Vector2(on_page(Vector2(_COINS_RIGHT, 0)).x - coins_pill.size.x, safe_top + _COINS_TOP)

## Where card i of a hand of n goes on the table: one hand centred stepping OVERLAP; split hands (BJ-SPEC-CARDS) 16
## in from each side and 24 apart, stepping SPLIT_OVERLAP, each from its left edge.
func card_pos(hand_index: int, i: int, hand_count: int, n: int) -> Vector2:
	if hand_count <= 1:
		var width := hand_width(1, n)
		return Vector2(DESIGN.x * 0.5 - width * 0.5 + i * UiPlayingCard.OVERLAP, _PLAYER_TOP)
	return Vector2(float(_SPLIT_X[mini(hand_index, 1)]) + i * UiPlayingCard.SPLIT_OVERLAP, _PLAYER_TOP)

func hand_width(hand_count: int, n: int) -> float:
	return UiPlayingCard.SIZE.x + (n - 1) * (UiPlayingCard.OVERLAP if hand_count <= 1 else UiPlayingCard.SPLIT_OVERLAP)

func dealer_pos(i: int, n: int) -> Vector2:
	var width := hand_width(1, n)
	return Vector2(DESIGN.x * 0.5 - width * 0.5 + i * UiPlayingCard.OVERLAP, _DEALER_TOP)

## The shoe's mouth on the background, where dealt cards come from.
func shoe_pos() -> Vector2: return Vector2(296, 30)

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
		badge.position = Vector2(first.x + width + _BADGE_GAP, first.y + (UiPlayingCard.SIZE.y - badge.size.y) * 0.5)
		var tag: PanelContainer = hand.tag
		tag.size = tag.get_combined_minimum_size()
		tag.position = Vector2(first.x + (width - tag.size.x) * 0.5, first.y - _PLATE_GAP - tag.size.y)   # above the cards
		var stake: Label = hand.stake
		stake.visible = false   # SPLIT-T: each hand's stake shows as its own stack in the circle
		stake.text = P0Blackjack.comma(int(hand.bet))
		stake.size = stake.get_combined_minimum_size()
		stake.position = Vector2(first.x + (width - stake.size.x) * 0.5, badge.position.y + badge.size.y + 2.0)
		var outline: Panel = hand.outline
		outline.visible = n > 1 and k == _active and phase == Phase.PLAY
		outline.position = first - Vector2(12, 14)
		outline.size = Vector2(width + _BADGE_GAP + badge.size.x + 22.0, UiPlayingCard.SIZE.y + 28.0)
		var dim := 0.55 if n > 1 and k != _active and phase == Phase.PLAY else 1.0
		for c in cards: (c as Control).modulate.a = dim
		badge.modulate.a = dim
	var d0 := dealer_pos(0, maxi(1, _dealer_cards.size()))
	_badge_set(dealer_badge, P0Blackjack.badge(_codes(_dealer_cards)) if not _dealer_cards.is_empty() else "")
	dealer_badge.position = Vector2(d0.x + hand_width(1, _dealer_cards.size()) + _BADGE_GAP, d0.y + (UiPlayingCard.SIZE.y - dealer_badge.size.y) * 0.5)

func _move(c: Control, to: Vector2, slide: bool) -> void:
	if slide and animate and c.position != to:
		create_tween().tween_property(c, "position", to, _fly()).set_ease(Tween.EASE_OUT)
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
	if events.is_empty():
		if _running: _steps.append(func(): _reconcile(); return 0.0)
		else: _reconcile()
		return
	var paid := 0
	var target := maxi(1, (P0Blackjack.hand(view).get("hands", []) as Array).size())
	for e in events:
		if str(e.kind) == "bj_result":
			for hh in e.get("hands", []): paid += int(hh.get("payout", 0))
			target = maxi(target, (e.get("hands", []) as Array).size())
	_roll_coins(P0Blackjack.coins_of(view) - paid)   # the stake leaves now; a payout comes with its result
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
		if animate and wait > 0.0 and is_inside_tree():
			var pause := create_tween()   # bound to the page: closed mid-play, the wait ends with it, nothing resumes
			pause.tween_interval(wait)
			await pause.finished
		if animate and not is_inside_tree(): return
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
	elif phase != Phase.BET:   # the hand went (settled, refused, elsewhere): last stake back in the circle
		if _result.is_empty(): _clear_table()
		_rebet()
	if phase == Phase.BET and bet > 0 and not P0Blackjack.can_add(view, bet, 0): _rebet()
	if not _running: _roll_coins(P0Blackjack.coins_of(view))
	_lay_cards(false)
	_refresh_keys()

# ---------------------------------------------------------------- motion steps (each returns seconds to wait)

func _fly() -> float: return UiKit.secs(UiTokens.MOTION_RADIAL_PETAL_IN_MS)

func _step_dealt(e: Dictionary) -> float:
	_clear_table()
	_result = {}
	phase = Phase.PLAY
	_refresh_keys()   # Deal goes at once: the actions wait for the cards, the stale bet line never shows
	var h: Dictionary = e.get("hand", {})
	_set_stack(int(e.get("bet", 0)))
	_active = 0
	var p: Array = (h.get("hands", [{}])[0] as Dictionary).get("cards", [])
	var d: Array = h.get("dealer", [])
	var hand := _new_hand(int(e.get("bet", 0)))
	var order := [[hand, p[0] if p.size() > 0 else ""], [null, d[0] if d.size() > 0 else ""],
		[hand, p[1] if p.size() > 1 else ""], [null, d[1] if d.size() > 1 else ""]]
	var t := 0.0
	for k in order.size():
		var card := _new_card(str(order[k][1]), shoe_pos())
		if order[k][0] == null: _dealer_cards.append(card)
		else: (hand.cards as Array).append(card)
		card.visible = not animate
		if animate:
			get_tree().create_timer(t).timeout.connect(func():
				if is_instance_valid(card): card.visible = true
				if is_inside_tree(): _lay_cards(true))
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
		# Split: the pair's second card moves over to become the second hand; a second stake joins the circle.
		var moved: UiPlayingCard = (_hands[0].cards as Array).pop_back()
		var second := _new_hand(int(_hands[0].bet))
		(second.cards as Array).append(moved)
	while _hands.size() <= k: _new_hand(int(_hands[0].bet) if not _hands.is_empty() else bet)
	var card := _new_card(str(e.get("card", "")), shoe_pos())
	(_hands[k].cards as Array).append(card)
	var ev_hands: Array = P0Blackjack.hand(view).get("hands", [])
	if k < ev_hands.size(): _hands[k].bet = int(ev_hands[k].get("bet", _hands[k].bet))
	elif _acted == "double" and _hands.size() == 1:   # doubled and settled in one reply: the view's hand is gone
		_hands[k].bet = int(_hands[k].bet) * 2
		_acted = ""
	var total := 0
	for hd in _hands: total += int(hd.bet)
	_set_stack(total)   # a split's or a double's second stake shows in the circle
	_lay_cards(true)
	return _fly() + 0.08

func _step_result(e: Dictionary) -> float:
	if str(e.get("why", "")) == "expired":
		_clear_table()
		show_settled(P0Blackjack.settled_line(e))
		_roll_coins(P0Blackjack.coins_of(view))
		phase = Phase.RESULT
		_result = {}
		_rebet()
		return 0.0
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
	var staked := 0
	for hh in hands: staked += int(hh.get("bet", 0))
	if staked > 0: _set_stack(staked)   # the stake as settled (a double's included)
	_lay_cards(false)
	var won := 0
	for hh in hands: won += maxi(0, int(hh.get("net", 0)))
	if won > 0:   # RESULT-T: winnings slide in from the dealer's side to the stake; one float left of the circle
		_float(P0Blackjack.float_text(won), on_page(_FLOAT_AT))
		_slide_winnings(won)
	_roll_coins(P0Blackjack.coins_of(view))
	# then last hand's stake sets itself in the circle again and `Deal` deals again (C13)
	_steps.push_front(func(): _rebet(); _lay_cards(false); return 0.0)
	return UiKit.secs(UiTokens.MOTION_FLOAT_TEXT_MS)

## The winnings, as chips, slide from the dealer's side to the stake, then leave with it for the rail (37022a3c D;
## RESULT-T's dashed path is a motion note, not drawn).
func _slide_winnings(amount: int) -> void:
	var w := UiChipStack.new(P0Blackjack.chips_for(amount).slice(0, 5))
	table.add_child(w)
	w.position = _WINNINGS_FROM - w.size * 0.5
	_winnings = w
	var to := _CIRCLE + Vector2(_SPLIT_STACK_DX * 2.0, -8.0) - w.size * 0.5
	if not animate:
		w.free()
		_winnings = null
		return
	var t := create_tween()
	t.tween_property(w, "position", to, UiKit.secs(UiTokens.MOTION_DRAWER_MS * 2)).set_ease(Tween.EASE_OUT)
	t.tween_interval(UiKit.secs(UiTokens.MOTION_PENDING_DELAY_MS))
	t.tween_property(w, "position", Vector2(to.x, _RAIL_Y), UiKit.secs(UiTokens.MOTION_DRAWER_MS)).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(w, "modulate:a", 0.0, UiKit.secs(UiTokens.MOTION_DRAWER_MS))
	t.tween_callback(func():
		if is_instance_valid(w): w.queue_free())

var _winnings: Control

func _float(text: String, at: Vector2) -> void:
	var f := UiFloatText.new(text, UiFloatText.Tone.COINS, ICON_COIN)
	f.theme = UiKit.theme()
	add_child(f)
	f.play(at)

func _set_coins_text(t: String) -> void:
	coins_label.text = t
	if coins_pill.is_inside_tree(): _fit_coins()

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
	table.add_child(c)
	table.move_child(c, hands_box.get_index())   # under the badges and tags
	if at.is_finite(): c.position = at
	return c

func _new_hand(stake: int) -> Dictionary:
	var outline := Panel.new()
	var os := StyleBoxFlat.new()
	os.bg_color = UiKit.alpha(Color.WHITE, 0.10)   # SPLIT-T: the hand in play boxed white, cards and badge
	os.border_color = Color.WHITE
	os.set_border_width_all(2)
	os.set_corner_radius_all(12)
	outline.add_theme_stylebox_override(&"panel", os)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.visible = false
	hands_box.add_child(outline)
	var tag := _badge()
	(tag.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color = UiTokens.COLOR_SURFACE_RAISED
	(tag.get_node("Text") as Label).add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT)
	tag.z_index = 2
	hands_box.add_child(tag)
	var badge := _badge()
	hands_box.add_child(badge)
	var stake_l := UiKit.label("", UiTokens.STYLE_C12_B, UiKit.alpha(INK, 0.8))
	stake_l.visible = false
	hands_box.add_child(stake_l)
	var hand := {"cards": [], "bet": stake, "badge": badge, "tag": tag, "stake": stake_l, "outline": outline}
	_hands.append(hand)
	return hand

func _clear_table() -> void:
	if is_instance_valid(_winnings): _winnings.free()
	_winnings = null
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
	if stack.reduce(func(a, b): return a + b, 0) != total: stack = P0Blackjack.chips_for(total)
	if phase != Phase.BET and _hands.size() > 1: circle.set_split([P0Blackjack.chips_for(int(_hands[0].bet)), P0Blackjack.chips_for(int(_hands[1].bet))])
	else: circle.set_stack(stack)
	bet_label.text = P0Blackjack.comma(total) if total > 0 else ""
	_layout_bet_label()

func _layout_bet_label() -> void:
	bet_label.size = bet_label.get_combined_minimum_size()
	bet_label.position = Vector2(_CIRCLE.x + _CIRCLE_R + 12.0, _CIRCLE.y - bet_label.size.y * 0.5)   # x 240

func _enter_bet(preset: int) -> void:
	phase = Phase.BET
	stack = P0Blackjack.chips_for(preset)
	_set_stack(preset)

## After a result (or a hand gone): last hand's stake back in the circle, stepped down to keep the floor (§3, C13).
func _rebet() -> void:
	_enter_bet(P0Blackjack.deal_again_bet(view, _last_bet()))

# ---------------------------------------------------------------- keys

func _busy() -> bool: return _waiting or _running

func _refresh_keys() -> void:
	var betting := phase == Phase.BET
	var low := betting and P0Blackjack.low_on_coins(view) and bet == 0
	var expired := bool(P0Blackjack.hand(view).get("expired", false))
	var playing := phase == Phase.PLAY and not expired and not _running
	deal_key.visible = betting
	for k in [hit_key, stand_key, double_key, split_key]: (k as Control).visible = playing
	circle.visible = not low
	empty_label.visible = betting and not low and bet == 0
	low_label.visible = low
	low_need.visible = low
	low_need.text = P0Blackjack.need_text(P0Blackjack.need(P0Blackjack.coins_of(view), P0Blackjack.min_bet_of(view), P0Blackjack.floor_of(view)))
	bet_label.visible = not low and bet > 0
	for s in stacks:
		var st: UiChipStack = s
		var v := int(st.values[0])
		# grey marks a stack the wallet cannot put down while betting; in play they stay as they are (ACT-T), inert
		st.state = UiChipToken.State.DISABLED if betting and not P0Blackjack.can_add(view, bet, v) else UiChipToken.State.DEFAULT
	if betting:
		var dk := P0Blackjack.deal_key(view, bet)
		deal_key.enabled = bet > 0 and str(dk.reason) == "" and not _busy()
		deal_key.reason = str(dk.reason) if bet > 0 else ""   # empty: the circle's `Place a bet` says it; low: printed there
	elif playing:
		var keys := P0Blackjack.action_keys(view)
		for pair in [[hit_key, "hit"], [stand_key, "stand"], [double_key, "double"], [split_key, "split"]]:
			var k: UiFeltAction = pair[0]
			var spec: Dictionary = keys[pair[1]]
			k.enabled = bool(spec.enabled)
			k.reason = str(spec.reason)

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
	if _busy() or phase != Phase.BET or amount <= 0: return
	if P0Blackjack.need(P0Blackjack.coins_of(view), amount, P0Blackjack.floor_of(view)) > 0: return
	_waiting = true
	_refresh_keys()
	command.emit({"type": "bj_deal", "bet": amount})

func act(action: String) -> void:
	if _busy() or phase != Phase.PLAY: return
	_acted = action
	_waiting = true
	command.emit({"type": "bj_act", "action": action})

## Tap the stake in the circle: it all goes back to the rail (C13, in place of Clear).
func take_back() -> void:
	if phase != Phase.BET or _busy() or bet == 0: return
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
	var s: UiChipStack = stacks[i]
	if phase != Phase.BET or _busy() or s.state == UiChipToken.State.DISABLED: return   # in play: inert
	accept_event()
	# gui_input hands the stack's own local position (0–48): into page coordinates through the stack's transform, the
	# same space _input measures the finger in (周瑜 on #525: a window-space reading put the start hundreds of px off,
	# so the first 1 px ScreenDrag of a real tap began a drag).
	var start: Vector2 = get_global_transform_with_canvas().affine_inverse() * (s.get_global_transform_with_canvas() * (event as InputEventFromWindow).position)
	_press = {"index": i, "start": start, "t0": Time.get_ticks_msec(), "touch": event is InputEventScreenTouch,
		"id": event.index if event is InputEventScreenTouch else -1}

## A window (viewport) event's position in this page's coordinates.
func _page_pos(event: InputEvent) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * (event as InputEventFromWindow).position

func _input(event: InputEvent) -> void:
	if _press.is_empty(): return
	var touch := bool(_press.touch)
	if touch and not (event is InputEventScreenTouch or event is InputEventScreenDrag): return
	if not touch and not (event is InputEventMouseButton or event is InputEventMouseMotion): return
	if touch and int(event.get("index")) != int(_press.id): return
	var pos := _page_pos(event)
	var moving: bool = event is InputEventScreenDrag or event is InputEventMouseMotion
	var up: bool = (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed)
	if moving:
		if _ghost == null and pos.distance_to(_press.start) > GestureArbiter.TAP_SLOP: _begin_drag()
		if _ghost != null:
			_ghost.position = pos - _ghost.size * 0.5 + Vector2(0, -UiChipToken.SIZE * 0.6)   # above the finger, still seen
			circle.lit = over_circle(_ghost.position + _ghost.size * 0.5)
		get_viewport().set_input_as_handled()
	elif up:
		get_viewport().set_input_as_handled()
		var i := int(_press.index)
		var quick := Time.get_ticks_msec() - int(_press.t0) <= GestureArbiter.TAP_MAX_MS
		_press = {}
		if _ghost != null: _drop(i)
		elif quick: tap_chip(i)

func over_circle(p: Vector2) -> bool: return p.distance_to(circle_center()) <= (_CIRCLE_R + _CIRCLE_HIT) * table.scale.x

## Where a chip lifted from stack i starts, on the page.
func stack_top(i: int) -> Vector2:
	var s: UiChipStack = stacks[i]
	return on_page(s.position + s.top_centre())

func _chip_token(value: int, state := UiChipToken.State.DEFAULT) -> UiChipToken:
	var t := UiChipToken.new(value, state)
	t.table_look = true
	t.scale *= table.scale.x
	add_child(t)
	return t

func _begin_drag() -> void:
	var s: UiChipStack = stacks[int(_press.index)]
	_ghost = _chip_token(int(s.values[0]), UiChipToken.State.DRAGGING)
	_ghost.position = stack_top(int(_press.index)) - _ghost.size * 0.5

func _drop(i: int) -> void:
	var g := _ghost
	_ghost = null
	var landed := circle.lit and P0Blackjack.can_add(view, bet, g.value)
	circle.lit = false
	var to := (circle_center() if landed else stack_top(i)) - g.size * 0.5
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

## A tap on stack i: one chip flies from it into the circle and the bet grows by its value.
func tap_chip(i: int) -> void:
	var s: UiChipStack = stacks[i]
	var v := int(s.values[0])
	if phase != Phase.BET or _busy() or not P0Blackjack.can_add(view, bet, v): return
	if not animate:
		add_chip(v)
		return
	var f := _chip_token(v)
	f.position = stack_top(i) - f.size * 0.5
	bet += v   # counted at once so a quick second tap sees it; drawn when it lands
	_refresh_keys()
	var t := create_tween()
	t.tween_property(f, "position", circle_center() - f.size * 0.5, _fly()).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		f.queue_free()
		bet -= v
		add_chip(v))

## The bet circle printed on the felt: a thin ring (brighter while a dragged chip is over it), the stake stacked in it
## (at most CIRCLE_MAX drawn). A tap on it takes the stake back.
class _Circle extends Control:
	signal tapped
	var lit := false: set = set_lit
	var _stack: UiChipStack

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_stack = UiChipStack.new()
		add_child(_stack)

	func set_lit(v: bool) -> void:
		lit = v
		queue_redraw()

	var _second: UiChipStack

	func set_stack(values: Array) -> void:
		if _second != null: _second.visible = false
		_stack.values = values.slice(maxi(0, values.size() - P0Blackjack.CIRCLE_MAX))
		_stack.position = (size - _stack.size) * 0.5 + Vector2(0, (_stack.values.size() - 1) * UiChipStack.STEP * 0.5)

	## Two hands' stakes side by side, 16 either side of the centre (SPLIT-T).
	func set_split(two: Array) -> void:
		if _second == null:
			_second = UiChipStack.new()
			add_child(_second)
		_second.visible = true
		for k in 2:
			var st: UiChipStack = _stack if k == 0 else _second
			var v: Array = two[k]
			st.values = v.slice(maxi(0, v.size() - P0Blackjack.CIRCLE_MAX))
			st.position = (size - st.size) * 0.5 + Vector2((-16.0 if k == 0 else 16.0), (st.values.size() - 1) * UiChipStack.STEP * 0.5)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED: set_stack(_stack.values)

	func _gui_input(event: InputEvent) -> void:
		var up: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) \
			or (event is InputEventScreenTouch and not event.pressed)
		if up: tapped.emit()

	func _draw() -> void:
		var r := size.x * 0.5
		var c := size * 0.5
		if lit:
			draw_circle(c, r + 6.0, UiKit.alpha(Color.WHITE, 0.10))
			draw_arc(c, r - 1.5, 0.0, TAU, 64, Color.WHITE, 3.0, true)
		else:
			draw_arc(c, r - 1.0, 0.0, TAU, 64, UiKit.alpha(Color("FBF8F1"), 0.6), 1.5, true)
