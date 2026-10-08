class_name UiWorldIconButton
extends Control
## World prompt icon button (SGODOT-250; WorldIconButton 1674:101157, LOCK-07 v2): a facility within view and about
## 8 m shows only this. Visual 28 — a color/surface disc with a 1 px color/border edge and a soft shadow, the 22 px
## facility icon — inside an invisible 44 px touch area. State Near (seats and other sit-on places that grow but never
## open a name strip): 2 px color/primary edge and 1.1× scale. With a state (LOCK-11) the whole button becomes the
## StatusBadge World 28 instead: the state outranks the facility icon. Display only: a tap on it is a tap on the
## facility (the host checks hit_rect(), as for UiTapCard).

const _VISUAL := 28.0
const _ICON := 22.0
const _NEAR_SCALE := 1.1

## The facility icon (i-home, i-stall, i-seat …).
var icon: Texture2D: set = set_icon
## Near: primary edge and 1.1× (seats; LOCK-30 v2).
var near := false: set = set_near
## A UiStatusBadge.State to show instead of the icon, or -1 for none.
var status := -1: set = set_status

var _disc: Panel
var _glyph: TextureRect
var _badge: UiStatusBadge

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

## The 44 px touch area in global coordinates (the host's _tap_at tests it).
func hit_rect() -> Rect2: return get_global_rect()

## Where the facility is: the button centres on this point (its local parent's coordinates).
func place_at(center: Vector2) -> void:
	position = center - size * 0.5

func _refresh() -> void:
	if _disc == null: return
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _VISUAL * 0.5,
		UiTokens.COLOR_PRIMARY if near else UiTokens.COLOR_BORDER, UiTokens.STROKE_SELECTED if near else UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	_disc.add_theme_stylebox_override(&"panel", box)
	_glyph.texture = icon
	scale = Vector2.ONE * (_NEAR_SCALE if near else 1.0)
	var badged := status >= 0
	_disc.visible = not badged
	if badged:
		if _badge == null:
			_badge = UiStatusBadge.new(status, UiStatusBadge.Size.WORLD)
			add_child(_badge)
		_badge.state = status
		_badge.icon = icon
		_badge.visible = true
		var b := float(UiTokens.SIZE_STATUS_BADGE_WORLD)
		_badge.position = (size - Vector2(b, b)) * 0.5
	elif _badge != null:
		_badge.visible = false
