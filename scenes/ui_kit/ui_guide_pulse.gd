class_name UiGuidePulse
extends Control
## GuidePulse 1407:113987 (A-03, SGODOT-232 U6; 不知火舞 on 232): a one-shot ring that tells the player "here is your
## new next step" — the Today chip when its focus row changes, A-03's first Today row after accepting. A 2 px
## color/primary outline grows from the target's edge out to +10 px while fading 100 → 0 %, over
## MOTION_NEW_UNLOCK_FLASH_MS (600 ms) ease-out. Plays once, never loops, takes no touches (MOUSE_FILTER_IGNORE) and
## frees itself. Shapes as the main: Pill (Today rows and chips), Circle (icon buttons), Card (radius given).
## The ring geometry is not a token yet (PENDING "guidePulse"): constants here until the next token export adds them.

enum Shape { PILL, CIRCLE, CARD }

const _STROKE := 2.0      # GuidePulse main: 2 px outline (no token yet)
const _GROW := 10.0       # grows from the target edge to +10 px
const _INSET := 4.0       # the main's frame is the target plus 4 px on every side

var shape: Shape = Shape.PILL
var card_radius := 16.0
## The ring's width, opening opacity, growth and where its fade starts (in the eased progress): the main's 2 px from full,
## out to +10 px, fading all the way. One caller may tune them where the main reads faint (the mine mouth's main key over
## the fields, 不知火舞 on #156 / #160); the other callers keep the main.
var stroke := _STROKE
var start_alpha := 1.0
var grow_px := _GROW
var fade_from := 0.0
## 0 → 1 over the pulse; drives the ring's offset and fade.
var progress := 0.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		queue_redraw()
var _target_size := Vector2.ZERO

## Plays one pulse around `rect` (local to `parent`; empty = the parent's whole rect) and returns it.
static func play(parent: Control, rect := Rect2(), pulse_shape: Shape = Shape.PILL, radius := 16.0, ring := _STROKE,
		alpha := 1.0, grow := _GROW, fade := 0.0) -> UiGuidePulse:
	var r := rect if rect.has_area() else Rect2(Vector2.ZERO, parent.size)
	var p := UiGuidePulse.new()
	p.shape = pulse_shape
	p.card_radius = radius
	p.stroke = ring
	p.start_alpha = alpha
	p.grow_px = grow
	p.fade_from = fade
	p._target_size = r.size
	# Room for the whole growth; the ring is drawn relative to the target's edge in the middle.
	p.position = r.position - Vector2.ONE * (grow + ring)
	p.size = r.size + Vector2.ONE * 2.0 * (grow + ring)
	parent.add_child(p)
	var tw := p.create_tween()
	tw.tween_property(p, "progress", 1.0, UiKit.secs(UiTokens.MOTION_NEW_UNLOCK_FLASH_MS)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(p.queue_free)
	return p

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

## The frame the main draws: the target plus _INSET on each side (for checks against the Figma frame).
func frame_size() -> Vector2: return _target_size + Vector2.ONE * 2.0 * _INSET

## The ring's opacity now: full until fade_from, then down to 0 at the end (the main fades from the start).
func ring_alpha() -> float:
	return start_alpha * (1.0 - clampf((progress - fade_from) / maxf(1.0 - fade_from, 0.001), 0.0, 1.0))

func _draw() -> void:
	if progress >= 1.0: return
	var grow := grow_px * progress
	var rect := Rect2(Vector2.ONE * (grow_px + stroke - grow), _target_size + Vector2.ONE * 2.0 * grow)
	var radius := card_radius + grow
	if shape == Shape.PILL: radius = rect.size.y * 0.5
	elif shape == Shape.CIRCLE: radius = minf(rect.size.x, rect.size.y) * 0.5
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(int(round(stroke)))
	box.border_color = Color(UiTokens.COLOR_PRIMARY, ring_alpha())
	box.set_corner_radius_all(int(round(radius)))
	box.anti_aliasing = true
	draw_style_box(box, rect)
