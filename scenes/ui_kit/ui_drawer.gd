class_name UiDrawer
extends PanelContainer
## Bottom drawer (SGODOT-225; the Bag and counter drawers of LOCK-12 / 15, "Bag drawer · source proportions" on
## BAG-2-2 and FARM-6, built on Sheet 483:190). Full width, pinned to the bottom, 24 top corners (radius/sheet),
## cream surface; content goes in `body`, inset 12 at the sides and top like the Bag layout, and clears the
## bottom safe inset. Put it in ModalStack.open_drawer (or the P0 modal host): the scrim, Back and scrim taps
## belong to the stack. The drawer itself only adds the swipe-down close (WP7-B F-04 §4): a downward drag of
## 48 px, or a quick flick, that starts on the drawer and is not taken by a child (a grid scroll keeps its own
## drags) emits `close_requested`.

signal close_requested

const _PAD := 12.0            # Bag layout inset in the drawer: x 12, y 12 (BAG-2-2)
const _SWIPE_CLOSE := 48.0    # WP7-B F-04 §4: swipe down ≥ 48 px from the handle area
const _FLICK_MIN := 16.0      # a shorter downward flick still closes when it is this fast …
const _FLICK_MS := 160        # … i.e. released within this many ms of the press

## Visible height in 360-wide logical px (the bag drawer is 546 of 800). Above the host height it is clipped
## to it.
var height := 0.0: set = set_height
## Bottom safe inset (gesture bar), added under the content.
var safe_bottom := 0.0: set = set_safe_bottom
## Slide up over MOTION_DRAWER_MS when entering the tree.
var animate := true
## Content column; separation 0, the caller adds its own gaps (the Bag layout uses explicit spacers).
var body: VBoxContainer

## Milliseconds for the flick test; tests inject a fake clock.
var clock := Callable(Time, &"get_ticks_msec")

var _press_at := Vector2.ZERO
var _press_ms := 0
var _pressing := false
var _sent := false

func _init(height_: float = 0.0) -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 0)
	add_child(body)
	height = height_
	_restyle()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_place()
	if animate:
		var h := _shown_height()
		offset_top += h
		offset_bottom += h
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var secs := UiKit.secs(UiTokens.MOTION_DRAWER_MS)
		t.tween_property(self, ^"offset_top", offset_top - h, secs)
		t.tween_property(self, ^"offset_bottom", offset_bottom - h, secs)

func set_height(v: float) -> void:
	height = v
	if is_inside_tree(): _place()

func set_safe_bottom(v: float) -> void:
	safe_bottom = v
	_restyle()

## Height actually used: `height`, at most the parent's height.
func _shown_height() -> float:
	var parent := get_parent_control()
	var room := parent.size.y if parent != null and parent.size.y > 0.0 else height
	return minf(height, room)

func _place() -> void:
	offset_left = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	offset_top = -_shown_height()

func _restyle() -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 0.0)
	box.corner_radius = Vector4(UiTokens.RADIUS_SHEET, UiTokens.RADIUS_SHEET, 0.0, 0.0)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD, _PAD, _PAD, _PAD + safe_bottom))

# ------------------------------------------------------------------ swipe-down close

func _gui_input(e: InputEvent) -> void:
	var down := _is_press(e)
	if down == 1:
		_press_at = e.position
		_press_ms = int(clock.call())
		_pressing = true
		_sent = false
	elif down == 0 and _pressing:
		_pressing = false
		var d: Vector2 = e.position - _press_at
		if _downward(d) and d.y >= _FLICK_MIN and int(clock.call()) - _press_ms <= _FLICK_MS: _close()
	elif _pressing and (e is InputEventMouseMotion or e is InputEventScreenDrag):
		var d: Vector2 = e.position - _press_at
		if _downward(d) and d.y >= _SWIPE_CLOSE: _close()

## 1 press, 0 release, -1 anything else. Touch is used on touch screens; elsewhere the mouse (Godot emulates
## one from the other), so a single physical touch is never counted twice.
static func _is_press(e: InputEvent) -> int:
	var touch := DisplayServer.is_touchscreen_available()
	if touch and e is InputEventScreenTouch: return 1 if e.pressed else 0
	if not touch and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT: return 1 if e.pressed else 0
	return -1

static func _downward(d: Vector2) -> bool:
	return d.y > 0.0 and d.y > absf(d.x) * 2.0

func _close() -> void:
	if _sent: return
	_sent = true
	_pressing = false
	accept_event()
	close_requested.emit()
