class_name UiDrawer
extends PanelContainer
## Bottom drawer (SGODOT-225; the Bag and counter drawers of LOCK-12 / 15, "Bag drawer · source proportions" on
## BAG-2-2 and FARM-6, built on Sheet 483:190). Full width, pinned to the bottom, 24 top corners (radius/sheet),
## cream surface; content goes in `body`, inset 12 at the sides and top like the Bag layout, and clears the
## bottom safe inset. Put it in ModalStack.open_drawer (or the P0 modal host): the scrim, Back and scrim taps
## belong to the stack. The drawer itself adds the drag down to close (SGODOT-265, 不知火舞's spec, user-approved):
## - Where: the handle band, its top HANDLE_H px full width (the handle and the title row), always moves it; a tap on
##   the title row's buttons still acts. A vertical scroll (the bag grid, a page grid, a profile column, a list) moves it
##   only when its content is at the top as this very press starts and the drag goes down from there; started lower, the
##   gesture only scrolls, stopping at the top. Other content (filter strips, cards, button rows) does not close it.
##   A sideways strip keeps its sideways drags; a mostly-vertical one (< 30° from vertical) counts where it starts.
##   A subtree marked with the meta KEEP_INPUT (the docked quick bar) is left alone, and a bag cell's long press
##   (450 ms, LOCK-12 v1.11) lifts it before a drag counts.
## - How: 1:1 with the finger, only down; the host's `scrim` fades with it. Released past a quarter of its height (at
##   least 80 px), or past 24 px at ≥ 900 px/s down, it goes on down from there (0.18 s, ease-in) and emits
##   `close_requested`, as × and a scrim tap do; otherwise it springs back (0.22 s, ease-out, no overshoot).
## - The handle: 36 × 4, radius 2, color/border, 8 from the top; color/secondary while the band is pressed.
## Like TouchScrollContainer, the drawer lets its plain content pass presses on, and its buttons act on release, so
## a drag that moved the drawer never fires the button it started on.

signal close_requested

## Meta on a content node whose subtree keeps its own input: the drawer neither swipes from it nor changes it.
const KEEP_INPUT := &"ui_drawer_keep_input"

const _PAD := 12.0            # Bag layout inset in the drawer: x 12, y 12 (BAG-2-2)
## The handle band: the drawer's top 44 px, full width (the handle and the title row).
const HANDLE_H := 44.0
const _HANDLE := Vector2(36.0, 4.0)   # the handle: 36 × 4, radius 2, 8 from the top
const _HANDLE_TOP := 8.0
const _DRAG_SLOP := 10.0      # moved this far, mostly down (and before a long press, in a scroll): a drag
const _VERTICAL := 0.577      # tan 30°: a drag within 30° of vertical counts as vertical
const _CLOSE_SHARE := 0.25    # released past a quarter of the height closes …
const _CLOSE_MIN := 80.0      # … but at least this far
const _FLING_MIN := 24.0      # or past this far …
const _FLING_SPEED := 900.0   # … at least this fast down (px/s, 360 × 800 base)
const _SPEED_MS := 100        # the release speed is measured over the last this many ms
const _CLOSE_SECS := 0.18
const _BACK_SECS := 0.22

## Visible height in 360-wide logical px (the bag drawer is 546 of 800). Above the host height it is clipped
## to it.
var height := 0.0: set = set_height
## Bottom safe inset (gesture bar), added under the content.
var safe_bottom := 0.0: set = set_safe_bottom
## Content inset at the sides, top and bottom: 12 for the Bag layout, 16 for profile sheets (RES-PIP).
var pad := _PAD: set = set_pad

## The drawer's fixed decision area, which a toast sits above (q(16): the counter's sell card, the kitchen's Cook row);
## null for a drawer without one, where the toast sits at the drawer's foot. Drawers that have one override it.
func action_area() -> Control: return null
## Slide up over MOTION_DRAWER_MS when entering the tree.
var animate := true
## Content column; separation 0, the caller adds its own gaps (the Bag layout uses explicit spacers).
var body: VBoxContainer

## Milliseconds for the long-press window and the release speed; tests inject a fake clock.
var clock := Callable(Time, &"get_ticks_msec")
## The host's scrim behind the drawer: it fades with the drag (P0Ui._open_modal, ModalStack).
var scrim: CanvasItem
## Whether the handle is drawn (every drawer has one; a full-screen page is no drawer).
var handle := true: set = set_handle

enum _Grab { OFF, HANDLE, SCROLL }

var _press_at := Vector2.ZERO
var _press_ms := 0
var _pressing := false
var _grab := _Grab.OFF
var _pull_scroll: ScrollContainer   # the vertical scroll a SCROLL grab started on, at its top
var _from_scroll := false      # this press started on a vertical scroll's content
var _dragging := false
var _drag_from := 0.0          # the finger's drop when the drawer started following it
var _drop := 0.0               # how far below its place the drawer is
var _samples: Array = []       # [ms, finger y] over the last _SPEED_MS
var _settle_tween: Tween
var _band_down := false        # the handle band is pressed: the handle shows it
var _sent := false
var _swallow := false   # after a drag moved the drawer: eat the gesture's release so the button under it stays quiet

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
		var elapsed := maxf(0.0, _slide.get_total_elapsed_time())
		_slide.kill()
		_place()
		_slide_in(drop, maxf(0.05, UiKit.secs(UiTokens.MOTION_DRAWER_MS) - elapsed))
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
		# A strip that only scrolls sideways passes vertical drags on; its own content is its business. A vertical
		# scroll says when a press starts on it: at its top, a drag down there moves the drawer (SGODOT-265).
		if node.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED: node.mouse_filter = Control.MOUSE_FILTER_PASS
		elif not node.gui_input.is_connected(_on_scroll_input): node.gui_input.connect(_on_scroll_input.bind(node))
		return
	if node is Range or node is LineEdit or node is TextEdit: return
	if node is Control and node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	if node is BaseButton: node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	if not node.child_entered_tree.is_connected(_watch_content):
		node.child_entered_tree.connect(_watch_content)
	for child in node.get_children(): _watch_content(child)

func _gui_input(e: InputEvent) -> void:
	if _is_press(e) == 1: _begin(e.position, null)

## A press on a vertical scroll's content (it stops the press there): where it started, in the drawer.
func _on_scroll_input(e: InputEvent, sc: ScrollContainer) -> void:
	if _is_press(e) == 1: _begin(get_global_transform().affine_inverse() * (sc.get_global_transform() * e.position), sc)

func _begin(at: Vector2, sc: ScrollContainer) -> void:
	# The finger is followed in the parent's frame: the drawer itself moves under it.
	var at_parent := get_transform() * at
	if _pressing and int(clock.call()) == _press_ms and at_parent.is_equal_approx(_press_at): return   # one press, seen twice
	_press_at = at_parent
	_press_ms = int(clock.call())
	_pressing = true
	_dragging = false
	_sent = false
	_swallow = false
	_samples = []
	_pull_scroll = null
	_from_scroll = sc != null
	if at.y < HANDLE_H: _grab = _Grab.HANDLE
	elif sc != null and sc.scroll_vertical <= 0:
		_grab = _Grab.SCROLL
		_pull_scroll = sc
	else: _grab = _Grab.OFF   # other content, or a scroll not at its top: no drag closes from there
	_set_band_down(_grab == _Grab.HANDLE)
	if is_inside_tree(): set_process_input(true)   # follow the rest before the child under the finger does

## While a press that started on the drawer is down, its motion and release are read here first: the finger may
## leave the drawer's own controls (a touch drag goes to whatever is under it), and a drag must take the gesture
## before the button or scroll it started on does.
func _input(e: InputEvent) -> void:
	var down := _is_press(e)
	if _swallow:
		# Both the touch and its emulated mouse twin: a new press ends the gesture, any release of it is eaten.
		var touch: bool = e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)
		if touch and e.pressed: _swallow = false
		elif touch: get_viewport().set_input_as_handled()
	if _pressing and down != 1:
		var parent := get_parent() as CanvasItem
		_track(parent.make_input_local(e) if parent != null else make_input_local(e), down)
	if not _pressing and not _swallow: set_process_input(false)

func _track(e: InputEvent, down: int) -> void:
	if not _pressing: return
	if down == 0:
		_release()
		return
	if not (e is InputEventMouseMotion or e is InputEventScreenDrag): return
	var d: Vector2 = e.position - _press_at
	if not _dragging:
		if d.length() < _DRAG_SLOP: return
		# A drag on plain content closes nothing now; its release does not fire the button it began on either (a
		# scroll's content keeps its own: its drags cancel clicks, and a lifted bag cell must get its drop).
		if _grab == _Grab.OFF:
			if _pull_scroll == null and not _from_scroll: _swallow = true
			return
		var mostly_down := d.y > 0.0 and absf(d.x) <= d.y * _VERTICAL
		# In a scroll: still at its top, and before a long press lifts the cell under the finger (LOCK-12 v1.11).
		var scroll_ok := _grab != _Grab.SCROLL or (is_instance_valid(_pull_scroll) and _pull_scroll.scroll_vertical <= 0 \
			and int(clock.call()) - _press_ms < GestureArbiter.LONG_PRESS_MS)
		if not (mostly_down and scroll_ok):
			_grab = _Grab.OFF   # a scroll, a sideways strip, a lifted cell: this gesture is theirs
			_set_band_down(false)
			if not _from_scroll: _swallow = true   # a sideways drag in the band: its release taps nothing
			return
		_dragging = true
		_drag_from = 0.0   # 1:1 from the press: the drawer keeps the point under the finger
		_swallow = true   # the button it started on never fires
		if _slide != null and _slide.is_running():
			_slide.kill()
			_place()
		if _settle_tween != null and _settle_tween.is_running(): _settle_tween.kill()
	get_viewport().set_input_as_handled()   # the scroll and the content under the finger stay out of it
	_move(maxf(0.0, d.y - _drag_from))
	var now := int(clock.call())
	_samples.append([now, d.y])
	while _samples.size() > 2 and now - int(_samples[0][0]) > _SPEED_MS: _samples.pop_front()

## Released: on down from where it is, or back up into its place (SGODOT-265).
func _release() -> void:
	_pressing = false
	_set_band_down(false)
	if not _dragging: return
	_dragging = false
	var h := _shown_height()
	if _drop > maxf(h * _CLOSE_SHARE, _CLOSE_MIN) or (_drop > _FLING_MIN and _speed() >= _FLING_SPEED): _close_down()
	else: _settle_to(0.0, _BACK_SECS, Tween.EASE_OUT, Callable())

## Finger speed down at the release, px/s, over the last _SPEED_MS of motion.
func _speed() -> float:
	if _samples.size() < 2: return 0.0
	var first: Array = _samples[0]
	var last: Array = _samples[-1]
	var dt := float(int(last[0]) - int(first[0]))
	return 0.0 if dt <= 0.0 else (float(last[1]) - float(first[1])) * 1000.0 / dt

## The drawer `y` px below its place, the scrim fading with it.
func _move(y: float) -> void:
	var h := _shown_height()
	_drop = clampf(y, 0.0, h)
	offset_top = -h + _drop
	offset_bottom = _drop
	if is_instance_valid(scrim): scrim.modulate.a = 1.0 - _drop / maxf(1.0, h)

func _settle_to(y: float, secs: float, ease: Tween.EaseType, done: Callable) -> void:
	if _settle_tween != null and _settle_tween.is_running(): _settle_tween.kill()
	_settle_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(ease)
	_settle_tween.tween_method(_move, _drop, y, UiKit.secs(secs * 1000.0))
	if done.is_valid(): _settle_tween.tween_callback(done)

func _close_down() -> void:
	_settle_to(_shown_height(), _CLOSE_SECS, Tween.EASE_IN, func():
		if _sent: return
		_sent = true
		close_requested.emit())

func _set_band_down(v: bool) -> void:
	if v == _band_down: return
	_band_down = v
	queue_redraw()

func set_handle(v: bool) -> void:
	handle = v
	queue_redraw()

## The handle, in the top pad over the panel (the content starts below it).
func _draw() -> void:
	if not handle: return
	var r := Rect2(Vector2((size.x - _HANDLE.x) * 0.5, _HANDLE_TOP), _HANDLE)
	draw_style_box(UiStyleBox.make(UiTokens.COLOR_SECONDARY if _band_down else UiTokens.COLOR_BORDER, _HANDLE.y * 0.5), r)

## 1 press, 0 release, -1 anything else. Touch is used on touch screens; elsewhere the mouse (Godot emulates
## one from the other), so a single physical touch is never counted twice.
static func _is_press(e: InputEvent) -> int:
	var touch := DisplayServer.is_touchscreen_available()
	if touch and e is InputEventScreenTouch: return 1 if e.pressed else 0
	if not touch and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT: return 1 if e.pressed else 0
	return -1
