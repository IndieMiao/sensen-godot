class_name UiWorldIconButton
extends Control
## World prompt icon button (SGODOT-250; WorldIconButton 1674:101157, LOCK-07 v2): a facility within view and about
## 8 m shows only this. Visual 28 — a color/surface disc with a 1 px color/border edge and a soft shadow, the 22 px
## facility icon — inside an invisible 44 px touch area. State Near (seats and other sit-on places that grow but never
## open a name strip): 2 px color/primary edge and 1.1× scale. With a state (LOCK-11) the whole button becomes the
## StatusBadge World 28 instead: the state outranks the facility icon. Display only: a tap on it is a tap on the
## facility (the host checks hit_rect(), as for UiEntryCard). Count (Show count, 1749:0): a small tag at the disc's
## bottom right, like a cell's quantity pill (the Warming Cabinet's 4/6 / Full, q(31); C21); it stays over a state
## badge too (the cooking stove's +1 while a pot is queued, q(71)). At least the pill's 24;
## a wider word grows it to the left, its right edge kept (Count tag: right-anchored, padding 4 — the Mailbox's
## `Parcel`, WORLD-HINT-6a 1822:123663, 不知火舞 on 234).
## Progress (a pond's gathering point cooling, SGODOT-475; 不知火舞's gather-compact spec ① 1): the same disc, the icon
## at PROGRESS_ICON and dimmed as a name strip's, a PROGRESS_STROKE arc on the border track from 12 o'clock clockwise
## for the part grown back, in NEED-TILE's green — the HUD buff circle's drawing, filling instead of running down. No
## words; full, the host shows the plain button again.

const _VISUAL := 28.0
const _ICON := 22.0
const _NEAR_SCALE := 1.1
const _COUNT_AT := Vector2(14, 20)   # the count tag in the 28 disc, overhanging its bottom right
const _COUNT_PAD := 4.0              # the tag's text inset either side once it is wider than the pill
const PROGRESS_ICON := 16.0
const PROGRESS_STROKE := 2.5
const PROGRESS_DIM := 0.45   # UiWorldNameBar's dimmed icon

## The facility icon (i-home, i-stall, i-seat …).
var icon: Texture2D: set = set_icon
## Near: primary edge and 1.1× (seats; LOCK-30 v2).
var near := false: set = set_near
## A UiStatusBadge.State to show instead of the icon, or -1 for none.
var status := -1: set = set_status
## The count tag's text, e.g. "4/6" or "Full"; "" hides it (an empty cabinet hangs none).
var count := "": set = set_count
## A one-off nudge on top of the near scale (the kitchen's heat reminder, b84a5e01 ④): pulse() animates it.
var pulse_k := 1.0: set = set_pulse_k
## 0..1 grown back while cooling, or -1 for none (the plain button).
var progress := -1.0: set = set_progress
var _pulse_tween: Tween

var _disc: Panel
var _glyph: TextureRect
var _badge: UiStatusBadge
var _count: Panel
var _count_label: Label
var _ring: _ProgressRing

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_TOUCH)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	_disc = Panel.new()
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.size = Vector2(_VISUAL, _VISUAL)
	_disc.position = (size - _disc.size) * 0.5
	add_child(_disc)
	_glyph = UiKit.icon(null, _ICON)
	_glyph.size = Vector2(_ICON, _ICON)
	_glyph.position = (_disc.size - _glyph.size) * 0.5
	_disc.add_child(_glyph)
	_ring = _ProgressRing.new()
	_ring.size = _disc.size
	_disc.add_child(_ring)
	_disc.move_child(_ring, 0)   # under the icon
	_count = Panel.new()
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.position = _COUNT_AT
	_count.size = Vector2(UiTokens.SIZE_QTY_PILL_W, UiTokens.SIZE_QTY_PILL_H)
	_count.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, UiTokens.SIZE_QTY_PILL_H * 0.5))
	_count_label = UiKit.label("", UiTokens.STYLE_C10_XB)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_count.add_child(_count_label)
	_count_label.minimum_size_changed.connect(_fit_count)
	_disc.add_child(_count)
	_refresh()

# Hosts set these every frame (P0Ui.world_icon): an unchanged value does nothing.
func set_icon(v: Texture2D) -> void:
	if v == icon: return
	icon = v; _refresh()
func set_near(v: bool) -> void:
	if v == near: return
	near = v; _refresh()
func set_status(v: int) -> void:
	if v == status: return
	status = v; _refresh()
func set_count(v: String) -> void:
	if v == count: return
	count = v; _refresh()

func set_progress(v: float) -> void:
	v = clampf(v, 0.0, 1.0) if v >= 0.0 else -1.0
	if v == progress: return
	var was := progress >= 0.0
	progress = v
	if (progress >= 0.0) != was: _refresh()
	else: _ring.queue_redraw()   # only the arc moves

func set_pulse_k(v: float) -> void:
	pulse_k = v
	_apply_scale()

func _apply_scale() -> void:
	pivot_offset = size * 0.5
	scale = Vector2.ONE * (_NEAR_SCALE if near else 1.0) * pulse_k

## 1.15× in 0.12 s, held 0.6 s, back in 0.2 s (b84a5e01 ④: another stove's heat ring is a second away).
func pulse(peak := 1.15) -> void:
	if _pulse_tween and _pulse_tween.is_valid(): _pulse_tween.kill()
	if not is_inside_tree(): return
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "pulse_k", peak, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_interval(0.6)
	_pulse_tween.tween_property(self, "pulse_k", 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

## The 44 px touch area in global coordinates (the host's _tap_at tests it).
func hit_rect() -> Rect2: return get_global_rect()

## What it draws, in its own coordinates (before its near scale): the 28 disc (or the state badge in its place) and the
## count tag when one hangs off it. The host keeps this off the screen's sides; the touch area is the whole button.
func drawn_rect() -> Rect2:
	var r := Rect2((size - Vector2(_VISUAL, _VISUAL)) * 0.5, Vector2(_VISUAL, _VISUAL))
	if _count and _count.visible: r = r.merge(Rect2(_disc.position + _count.position, _count.size))
	return r

## Where the facility is: the button centres on this point (its local parent's coordinates).
func place_at(center: Vector2) -> void:
	position = center - size * 0.5

## The tag's width from its text, measured again once the theme's 10 px font reaches the label (a count set before the
## button is in the tree measures in the default font).
func _fit_count() -> void:
	_count.size.x = maxf(UiTokens.SIZE_QTY_PILL_W, ceilf(_count_label.get_minimum_size().x) + _COUNT_PAD * 2.0)
	_count.position.x = _COUNT_AT.x + UiTokens.SIZE_QTY_PILL_W - _count.size.x

func _refresh() -> void:
	if _disc == null: return
	var cooling := progress >= 0.0
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _VISUAL * 0.5,
		UiTokens.COLOR_PRIMARY if near else UiTokens.COLOR_BORDER,
		0 if cooling else (UiTokens.STROKE_SELECTED if near else UiTokens.STROKE_DEFAULT))   # the ring is its edge
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	_disc.add_theme_stylebox_override(&"panel", box)
	_glyph.texture = icon
	var side := PROGRESS_ICON if cooling else _ICON
	_glyph.custom_minimum_size = Vector2(side, side)
	_glyph.size = Vector2(side, side)
	_glyph.position = (_disc.size - _glyph.size) * 0.5
	_glyph.modulate.a = PROGRESS_DIM if cooling else 1.0
	_ring.visible = cooling
	_ring.queue_redraw()
	_count.visible = count != ""
	_count_label.text = count
	_fit_count()
	_apply_scale()
	var badged := status >= 0
	# A state takes the disc's place; a count stays on it (Queue ×2: the cooking stove's countdown with +1, q(71)), so
	# the disc then stays in the tree drawing nothing itself and the badge goes under it.
	_disc.visible = not badged or count != ""
	_disc.self_modulate.a = 0.0 if badged else 1.0
	_glyph.visible = not badged
	if badged:
		if _badge == null:
			_badge = UiStatusBadge.new(status, UiStatusBadge.Size.WORLD)
			add_child(_badge)
			move_child(_badge, _disc.get_index())   # under the disc and its count tag
		_badge.state = status
		_badge.icon = icon
		_badge.visible = true
		var b := float(UiTokens.SIZE_STATUS_BADGE_WORLD)
		_badge.position = (size - Vector2(b, b)) * 0.5
	elif _badge != null:
		_badge.visible = false

## The cooling ring: the border track all round, the part grown back from 12 o'clock clockwise.
class _ProgressRing extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var p := float((get_parent().get_parent() as UiWorldIconButton).progress)
		var c := size * 0.5
		var r := size.x * 0.5 - PROGRESS_STROKE * 0.5
		draw_arc(c, r, 0.0, TAU, 64, UiTokens.COLOR_BORDER, PROGRESS_STROKE, true)
		if p > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * p, maxi(8, int(64 * p)), UiTokens.COLOR_PRIMARY, PROGRESS_STROKE, true)
