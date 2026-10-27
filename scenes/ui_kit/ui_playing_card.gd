class_name UiPlayingCard
extends Control
## PlayingCard (SGODOT-351, 不知火舞 on 351 bd0fced2): one card on the Blackjack table. Face: rank and suit in the
## top-left and bottom-right corners and one large suit in the middle; hearts and diamonds red, spades and clubs ink;
## A, 2–10, J, Q, K share one layout (no court figures, the letter only). Back: the felt green with an inset frame.
## `card` is the two-character code ("TH", "QS"); "" is face down. flip_to(code) turns it over in place. Suits are
## drawn as shapes (Nunito has no suit glyphs). Size until 安其拉's master gives it: 52 × 74, hands overlap by OVERLAP.

const SIZE := Vector2(52, 74)
## A hand's cards step this far right: five cards are 52 + 4 × 20 = 132, two split hands fit in 360.
const OVERLAP := 20.0
const _RADIUS := 6.0
const _RED := Color("C0413A")
const _INK := Color("2F3A33")
const FELT := Color("1F5A3A")

var card := "": set = set_card

var _rank: Label
var _rank_b: Label

func _init(card_ := "") -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank = _corner()
	_rank.position = Vector2(4, 1)
	_rank_b = _corner()
	_rank_b.position = SIZE - Vector2(4, 1) - _rank_b.size
	_rank_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card = card_

func _corner() -> Label:
	var l := UiKit.label("", UiTokens.STYLE_C14_XB)
	l.size = Vector2(22, 18)
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
	sb.set_corner_radius_all(int(_RADIUS))
	sb.shadow_color = UiTokens.COLOR_SHADOW_KEY
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	if card == "":
		sb.bg_color = FELT
		sb.border_color = UiTokens.COLOR_SURFACE
		sb.set_border_width_all(2)
		draw_style_box(sb, r)
		var inner := StyleBoxFlat.new()
		inner.bg_color = Color(0, 0, 0, 0)
		inner.border_color = UiKit.alpha(UiTokens.COLOR_SURFACE, 0.55)
		inner.set_border_width_all(1)
		inner.set_corner_radius_all(3)
		draw_style_box(inner, r.grow(-6))
		_suit(Vector2(SIZE.x * 0.5, SIZE.y * 0.5), 9.0, "S", UiKit.alpha(UiTokens.COLOR_SURFACE, 0.4))
		return
	sb.bg_color = UiTokens.COLOR_SURFACE_RAISED
	sb.border_color = UiTokens.COLOR_BORDER
	sb.set_border_width_all(1)
	draw_style_box(sb, r)
	var ink := _RED if P0Blackjack.is_red(card) else _INK
	var s := P0Blackjack.suit(card)
	_suit(Vector2(10, 26), 4.5, s, ink)
	_suit(SIZE - Vector2(10, 26), 4.5, s, ink)
	_suit(SIZE * 0.5 + Vector2(0, 2), 11.0, s, ink)

## One suit shape centred on c, about 2r across.
func _suit(c: Vector2, r: float, s: String, col: Color) -> void:
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
