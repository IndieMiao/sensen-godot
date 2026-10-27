class_name UiPlayingCard
extends Control
## PlayingCard 175:165903 (SGODOT-351; 安其拉, accepted by 不知火舞): one card on the Blackjack table, 56 × 80,
## radius 6. Face: the rank with a small suit under it in the top-left, the same turned over in the bottom-right, one
## large suit in the middle; hearts and diamonds red #C0563F, spades and clubs ink #2F3A33; A, 2–10, J, Q, K share one
## layout (no court figures, the letter only). Back (the dealer's hole card): ink with a fine lattice and a gold frame.
## `card` is the two-character code ("TH", "QS"); "" is the back. flip_to(code) turns it over in place. Suits are drawn
## as shapes (Nunito has no suit glyphs). Stacking (BJ-SPEC-CARDS 176:165791): a hand steps OVERLAP (5 cards 184 wide),
## split hands SPLIT_OVERLAP (152 each, 24 apart, 16 in at each side of 360).

const SIZE := Vector2(56, 80)
const OVERLAP := 32.0
const SPLIT_OVERLAP := 24.0
const _RADIUS := 6
const _RED := Color("C0563F")
const _INK := Color("2F3A33")
const _GOLD := Color("F0D75E")

var card := "": set = set_card

var _rank: Label
var _rank_b: Label

func _init(card_ := "") -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank = _corner()
	_rank.position = Vector2(2, 2)
	_rank_b = _corner()
	_rank_b.position = SIZE - Vector2(2, 2) - _rank_b.size
	_rank_b.pivot_offset = _rank_b.size * 0.5
	_rank_b.rotation = PI   # the bottom-right corner reads upside down
	card = card_

func _corner() -> Label:
	var l := UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15)
	l.add_theme_font_size_override(&"font_size", 16)   # ExtraBold 16 in a 20 column
	l.size = Vector2(20, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func set_card(v: String) -> void:
	card = v
	if _rank == null: return
	var face := card != ""
	var ink := _RED if face and P0Blackjack.is_red(card) else _INK
	for l in [_rank, _rank_b]:
		l.visible = face
		l.text = P0Blackjack.rank_text(card) if face else ""
		l.add_theme_color_override(&"font_color", ink)
	queue_redraw()

## Turn over to `code` (a hole card revealed): squeeze to a line, swap, open again — MOTION_RADIAL_RETRACT_MS each way.
func flip_to(code: String) -> Tween:
	var t := create_tween()
	var half := UiKit.secs(UiTokens.MOTION_RADIAL_RETRACT_MS)
	t.tween_property(self, "scale:x", 0.0, half).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): card = code)
	t.tween_property(self, "scale:x", 1.0, half).set_ease(Tween.EASE_OUT)
	return t

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(_RADIUS)
	sb.shadow_color = UiTokens.COLOR_SHADOW_KEY
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	if card == "":
		sb.bg_color = UiTokens.COLOR_SURFACE_RAISED
		draw_style_box(sb, r)
		var inner := r.grow(-3)
		var back := StyleBoxFlat.new()
		back.bg_color = _INK
		back.border_color = UiKit.alpha(_GOLD, 0.7)
		back.set_border_width_all(1)
		back.set_corner_radius_all(4)
		draw_style_box(back, inner)
		var lattice := UiKit.alpha(Color.WHITE, 0.14)
		var area := inner.grow(-3)
		var step := 7.0
		var k := -area.size.y
		while k < area.size.x:   # diagonals both ways, clipped to the inner rect
			_diag(area, k, step, lattice)
			k += step
		return
	sb.bg_color = UiTokens.COLOR_SURFACE_RAISED
	sb.border_color = UiTokens.COLOR_BORDER
	sb.set_border_width_all(1)
	draw_style_box(sb, r)
	var ink := _RED if P0Blackjack.is_red(card) else _INK
	var s := P0Blackjack.suit(card)
	_suit(Vector2(12, 28), 5.5, s, ink)              # 11 under the rank
	_suit(SIZE - Vector2(12, 28), 5.5, s, ink, true)
	_suit(SIZE * 0.5 + Vector2(0, 2), 13.0, s, ink)   # 26 in the middle

func _diag(area: Rect2, k: float, step: float, col: Color) -> void:
	for dir in [1.0, -1.0]:
		var a := Vector2(area.position.x + k, area.position.y) if dir > 0 else Vector2(area.end.x - k, area.position.y)
		var b := a + Vector2(area.size.y * dir, area.size.y)
		var seg := _clip(a, b, area)
		if seg.size() == 2: draw_line(seg[0], seg[1], col, 1.0, true)

## The part of segment a–b inside rect (Liang–Barsky); [] when outside.
static func _clip(a: Vector2, b: Vector2, rect: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for pq in [[-d.x, a.x - rect.position.x], [d.x, rect.end.x - a.x], [-d.y, a.y - rect.position.y], [d.y, rect.end.y - a.y]]:
		var p: float = pq[0]
		var q: float = pq[1]
		if is_zero_approx(p):
			if q < 0.0: return []
			continue
		var t := q / p
		if p < 0.0: t0 = maxf(t0, t)
		else: t1 = minf(t1, t)
		if t0 > t1: return []
	return [a + d * t0, a + d * t1]

## One suit shape centred on c, about 2r across.
func _suit(c: Vector2, r: float, s: String, col: Color, flip := false) -> void:
	if flip:   # the bottom-right corner's small suit, upside down: drawn about its centre turned half round
		draw_set_transform(c, PI, Vector2.ONE)
		c = Vector2.ZERO
	_suit_shape(c, r, s, col)
	if flip: draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _suit_shape(c: Vector2, r: float, s: String, col: Color) -> void:
	match s:
		"H":
			draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.55, col)
			draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.55, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, -r * 0.05), c + Vector2(r * 1.02, -r * 0.05), c + Vector2(0, r * 1.0)]), col)
		"D":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0)]), col)
		"S":
			draw_circle(c + Vector2(-r * 0.5, r * 0.2), r * 0.55, col)
			draw_circle(c + Vector2(r * 0.5, r * 0.2), r * 0.55, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, r * 0.1), c + Vector2(r * 1.02, r * 0.1), c + Vector2(0, -r * 0.95)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.3), c + Vector2(r * 0.35, r), c + Vector2(-r * 0.35, r)]), col)
		"C":
			draw_circle(c + Vector2(0, -r * 0.45), r * 0.48, col)
			draw_circle(c + Vector2(-r * 0.5, r * 0.15), r * 0.48, col)
			draw_circle(c + Vector2(r * 0.5, r * 0.15), r * 0.48, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0), c + Vector2(r * 0.35, r), c + Vector2(-r * 0.35, r)]), col)
