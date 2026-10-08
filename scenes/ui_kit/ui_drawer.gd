class_name UiDrawer
extends PanelContainer
## Bottom drawer (SGODOT-225; the Bag and counter drawers of LOCK-12 / 15, "Bag drawer · source proportions" on
## BAG-2-2 and FARM-6, built on Sheet 483:190). Full width, pinned to the bottom, 24 top corners (radius/sheet),
## cream surface; content goes in `body`, inset 12 at the sides and top like the Bag layout, and clears the
## bottom safe inset. Put it in ModalStack.open_drawer (or the P0 modal host): the scrim, Back and scrim taps
## belong to the stack. The drawer itself only adds the swipe-down close (WP7-B F-04 §4): a downward drag of
## 48 px, or a quick flick, that starts on the drawer and is not taken by a child emits `close_requested`.
## Like TouchScrollContainer, the drawer lets its plain content (header tabs, Sort, rows, buttons) pass presses
## on, so the swipe also starts on them; a button under a swipe that closed the drawer never fires. A vertical
## scroll (the bag grid, a profile column) keeps its own drags, a sideways-only strip passes vertical ones on,
## and a subtree marked with the meta KEEP_INPUT (the docked quick bar with its own slot drags) is left alone.

signal close_requested

## Meta on a content node whose subtree keeps its own input: the drawer neither swipes from it nor changes it.
const KEEP_INPUT := &"ui_drawer_keep_input"

const _PAD := 12.0            # Bag layout inset in the drawer: x 12, y 12 (BAG-2-2)
const _SWIPE_CLOSE := 48.0    # WP7-B F-04 §4: swipe down ≥ 48 px from the handle area
const _FLICK_MIN := 16.0      # a shorter downward flick still closes when it is this fast …
const _FLICK_MS := 160        # … i.e. released within this many ms of the press

## Visible height in 360-wide logical px (the bag drawer is 546 of 800). Above the host height it is clipped
## to it.
var height := 0.0: set = set_height
## Bottom safe inset (gesture bar), added under the content.
var safe_bottom := 0.0: set = set_safe_bottom
## Content inset at the sides, top and bottom: 12 for the Bag layout, 16 for profile sheets (RES-PIP).
var pad := _PAD: set = set_pad
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
var _swallow := false   # after a swipe-close: eat the gesture's release so the button under it stays quiet

func _init(height_: float = 0.0) -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 0)
	body.child_entered_tree.connect(_watch_content)
	add_child(body)
	height = height_
	_restyle()

func _ready() -> void:
	set_process_input(false)
	for child in body.get_children(): _watch_content(child)
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_place()
	if animate: _slide_in(_shown_height(), UiKit.secs(UiTokens.MOTION_DRAWER_MS))

var _slide: Tween

## Start `drop` px below its place and slide up into it.
func _slide_in(drop: float, secs: float) -> void:
	offset_top += drop
	offset_bottom += drop
	_slide = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide.tween_property(self, ^"offset_top", offset_top - drop, secs)
	_slide.tween_property(self, ^"offset_bottom", offset_bottom - drop, secs)

## A new height while sliding in keeps sliding, toward the new place (a drawer that fits itself to its content a
## couple of frames after opening, P0CounterDrawer.fit_height).
func set_height(v: float) -> void:
	height = v
	if not is_inside_tree(): return
	if _slide != null and _slide.is_running():
		var drop := offset_bottom   # how far below its place it still is
		var left := maxf(0.0, _slide.get_total_elapsed_time())
		_slide.kill()
		_place()
		_slide_in(drop, maxf(0.05, UiKit.secs(UiTokens.MOTION_DRAWER_MS) - left))
	else:
		_place()

func set_safe_bottom(v: float) -> void:
	safe_bottom = v
	_restyle()

func set_pad(v: float) -> void:
	pad = v
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
	add_theme_stylebox_override(&"panel", box.with_margins(pad, pad, pad, pad + safe_bottom))

# ------------------------------------------------------------------ swipe-down close

## Plain content passes presses and drags on to the drawer (as in TouchScrollContainer); scrolls, ranges, text
## fields and KEEP_INPUT subtrees keep theirs. Buttons act on release, so a drag can still be told from a tap.
func _watch_content(node: Node) -> void:
	if not body.is_ancestor_of(node) or node.has_meta(KEEP_INPUT): return
	if node is ScrollContainer:
		# A strip that only scrolls sideways passes vertical drags on; its own content is its business.
		if node.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED: node.mouse_filter = Control.MOUSE_FILTER_PASS
		return
	if node is Range or node is LineEdit or node is TextEdit: return
	if node is Control and node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	if node is BaseButton: node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	if not node.child_entered_tree.is_connected(_watch_content):
		node.child_entered_tree.connect(_watch_content)
	for child in node.get_children(): _watch_content(child)

func _gui_input(e: InputEvent) -> void:
	var down := _is_press(e)
	if down == 1:
		_press_at = e.position
		_press_ms = int(clock.call())
		_pressing = true
		_sent = false
		_swallow = false
		if is_inside_tree(): set_process_input(true)   # follow the rest before the child under the finger does
	else:
		_track(e, down, false)

## While a press that started on the drawer is down, its motion and release are read here first: the finger may
## leave the drawer's own controls (a touch drag goes to whatever is under it), and a flick must close before
## the button it started on sees the release.
func _input(e: InputEvent) -> void:
	var down := _is_press(e)
	if _swallow:
		# Both the touch and its emulated mouse twin: a new press ends the gesture, any release of it is eaten.
		var touch: bool = e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)
		if touch and e.pressed: _swallow = false
		elif touch: get_viewport().set_input_as_handled()
	if _pressing and down != 1: _track(make_input_local(e), down, true)
	if not _pressing and not _swallow: set_process_input(false)

func _track(e: InputEvent, down: int, from_input: bool) -> void:
	if not _pressing: return
	if down == 0:
		_pressing = false
		var d: Vector2 = e.position - _press_at
		if _downward(d) and d.y >= _FLICK_MIN and int(clock.call()) - _press_ms <= _FLICK_MS: _close(from_input)
	elif e is InputEventMouseMotion or e is InputEventScreenDrag:
		var d: Vector2 = e.position - _press_at
		if _downward(d) and d.y >= _SWIPE_CLOSE: _close(from_input)

## 1 press, 0 release, -1 anything else. Touch is used on touch screens; elsewhere the mouse (Godot emulates
## one from the other), so a single physical touch is never counted twice.
static func _is_press(e: InputEvent) -> int:
	var touch := DisplayServer.is_touchscreen_available()
	if touch and e is InputEventScreenTouch: return 1 if e.pressed else 0
	if not touch and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT: return 1 if e.pressed else 0
	return -1

static func _downward(d: Vector2) -> bool:
	return d.y > 0.0 and d.y > absf(d.x) * 2.0

func _close(from_input := false) -> void:
	if _sent: return
	_sent = true
	_pressing = false
	if is_inside_tree():
		_swallow = true   # the rest of this gesture (its release) is eaten in _input
		set_process_input(true)
		if from_input: get_viewport().set_input_as_handled()
		else: accept_event()
	close_requested.emit()
