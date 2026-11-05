class_name P0CookTimer
extends Control
## The pot's countdown and progress bar in the middle of the watch (SGODOT-419, q(288); 不知火舞's spec v1 419 cd072712
## §2): on one line down the screen with the pot and its heat ring, so the eye stays there — `m:ss` in Quantity XB32 on a
## 90 % surface plate (radius 16, the text + 16 a side, 44 high), centred; under it, 8 px down, a 200 × 8 bar (radius 4)
## that fills with the time gone, primary on the border colour, and a dot (8 across) at each heat ring's time: gold
## before it, deep gold on a hit, the disabled ink on a miss — the ring's own result colours. Display only.

const BAR := Vector2(200, 8)
const BAR_GAP := 8.0
const PLATE_H := 44.0
const PLATE_PAD := 16.0
const PLATE_R := 16.0
const DOT := 8.0

var plate: Panel   # the plate the time sits on (its size the spec's, not the text's line height: 44)
var time_label: Label
var total_ms := 1.0
var elapsed_ms := 0.0
var heat_at: Array = []    # each ring's time (ms from the start)
var results: Dictionary = {}   # ring index → true hit / false miss

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate = Panel.new()
	plate.name = "Plate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override(&"panel", UiStyleBox.make(Color(UiTokens.COLOR_SURFACE, 0.9), PLATE_R))
	add_child(plate)
	time_label = UiKit.label("0:00", UiTokens.STYLE_QUANTITY_XB32)
	time_label.name = "Time"
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(time_label)

## The time left as the countdown writes it.
static func clock(left_ms: float) -> String:
	var s := int(maxf(0.0, left_ms) / 1000.0)   # as the sheet wrote it
	return "%d:%02d" % [s / 60, s % 60]

## Lays it out around `center_x`, the plate's middle at `plate_y` (screen px), the bar under it.
func place(center_x: float, plate_y: float) -> void:
	time_label.text = clock(total_ms - elapsed_ms)
	var text := time_label.get_combined_minimum_size()
	var w := text.x + PLATE_PAD * 2.0
	plate.size = Vector2(w, PLATE_H)
	plate.position = Vector2(center_x - w * 0.5, plate_y - PLATE_H * 0.5)
	time_label.size = text
	time_label.position = (plate.size - text) * 0.5   # the text's own line box, centred on the plate
	position = Vector2.ZERO
	size = get_parent_area_size() if get_parent() is Control else size
	_bar_rect = Rect2(Vector2(center_x - BAR.x * 0.5, plate_y + PLATE_H * 0.5 + BAR_GAP), BAR)
	queue_redraw()

var _bar_rect := Rect2()

## The bar, as drawn (screen px): for the hosts' and the tests' checks.
func bar_rect() -> Rect2: return _bar_rect

## Where ring `i`'s dot sits on the bar.
func dot_point(i: int) -> Vector2:
	var k := clampf(float(heat_at[i]) / maxf(total_ms, 1.0), 0.0, 1.0)
	return Vector2(_bar_rect.position.x + _bar_rect.size.x * k, _bar_rect.get_center().y)

func _draw() -> void:
	if _bar_rect.size.x <= 0.0: return
	var r := BAR.y * 0.5
	draw_style_box(UiStyleBox.make(UiTokens.COLOR_BORDER, r), _bar_rect)
	var k := clampf(elapsed_ms / maxf(total_ms, 1.0), 0.0, 1.0)
	if k > 0.0:
		draw_style_box(UiStyleBox.make(UiTokens.COLOR_PRIMARY, r), Rect2(_bar_rect.position, Vector2(maxf(BAR.y, _bar_rect.size.x * k), BAR.y)))
	for i in heat_at.size():
		var c := UiTokens.COLOR_GOLD
		if results.has(i): c = UiTokens.COLOR_GOLD_DEEP if bool(results[i]) else UiTokens.COLOR_DISABLED_INK
		draw_circle(dot_point(i), DOT * 0.5, c, true, -1.0, true)
