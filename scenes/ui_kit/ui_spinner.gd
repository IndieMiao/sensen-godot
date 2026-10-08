class_name UiSpinner
extends Control
## Spinner (D-10, 1237:87185; SGODOT-233): a 28 px ring — the track in disabled grey, a quarter arc in primary turning
## once a second. Shown only after MOTION_PENDING_DELAY_MS (F-08); a button in flight uses the CommandButton pending
## look instead. `spinning` off holds the arc still (gallery shots).

const SIDE := 28.0
const _STROKE := 3.0   # Track / Arc stroke 3 in the main; a constant until the next token export adds it
const _TURN_S := 1.0
const _ARC := TAU * 0.25

var spinning := true
var angle := -PI * 0.5   # the arc starts at twelve o'clock

func _init() -> void:
	custom_minimum_size = Vector2(SIDE, SIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	if not spinning or not is_visible_in_tree(): return
	angle = fmod(angle + TAU * dt / _TURN_S, TAU)
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - _STROKE * 0.5
	draw_arc(c, r, 0.0, TAU, 48, UiTokens.COLOR_DISABLED, _STROKE, true)
	draw_arc(c, r, angle, angle + _ARC, 16, UiTokens.COLOR_PRIMARY, _STROKE, true)
