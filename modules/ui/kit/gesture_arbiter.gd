class_name GestureArbiter
extends RefCounted
## One place for touch thresholds and gesture decisions (SGODOT-211, WP7-B F-04). Each instance tracks
## one surface in one mode and turns pointer input into outcome dictionaries {kind = …}:
##   SCENE  (Z2 scene band, LOCK-01 / 07): joystick_show / joystick_move {vector} / joystick_end,
##          tap {pos, double}, pinch_start / pinch {factor, center} / pinch_end
##   SLOT   (quick bar slot, LOCK-04 / 05 v1.11): tap, lift, drag_start / drag_move {pos} / drop {pos} (where it
##          lands: drop_on_bar), swipe_up, cancel (released while only lifted, a second finger, or moving past the
##          slop before the lift). A lifted slot drags at once.
##   CELL   (bag grid cell inside a TouchScrollContainer, LOCK-12): tap, lift, long_press, drag_start /
##          drag_move / drop, cancel (a vertical drag before the lift belongs to the scroll container)
##   HANDLE (drawer grab handle): close, cancel
## Feed InputEvents with feed(event, now_ms) and call tick(now_ms) every frame so long presses fire
## without movement. Times are injected, so tests drive it with synthetic events.

enum Mode { SCENE, SLOT, CELL, HANDLE }

const TAP_SLOP := 12.0          ## px: movement that still counts as a tap (shipped _TouchPad value)
const TAP_MAX_MS := 350         ## scene tap must release within this
const DOUBLE_TAP_MS := 320      ## second scene tap within this recenters (§10.1)
const LONG_PRESS_MS := 450      ## slot / cell lift
const SWIPE_UP := 24.0          ## px upward on the quick bar opens the bag (§10.3.4)
const DROP_SLOT_GROW := 6.0     ## the finger point within another slot grown by this drops on it (LOCK-04 v1.11)
const DROP_ZONE_ABOVE := 96.0   ## BarDropZone centres above the quick bar's top edge (scene y 612 of 800)
const PIN_ZONE_X := 60.0        ## Pin / Unpin centre from the bar's left edge (x 72 on 360)
const REMOVE_ZONE_X := 156.0    ## Remove centre from the bar's left edge (x 168 on 360)
const DROP_ZONE_HIT := 44.0     ## finger within this of a zone centre hovers it and drops on it
const EDGE_AUTOSCROLL := 24.0   ## px band at grid edges that scrolls while dragging
const DRAWER_CLOSE := 48.0      ## px downward drag on a drawer handle closes it
const DRAWER_FLING := 800.0     ## px/s downward release speed that also closes it
const STICK_DEADZONE := 0.15    ## joystick vector length treated as zero (shipped _TouchPad value)

enum _S { IDLE, PRESSED, MOVED, JOYSTICK, LIFTED, DRAGGING, PINCH, DONE }

var mode: Mode
## Joystick travel for a full-speed vector: half the outer ring.
var stick_radius: float = UiTokens.SIZE_JOYSTICK_OUTER * 0.5
## Desktop: treat the left mouse button as the first finger when there is no touchscreen.
var mouse_as_touch := true

var _state := _S.IDLE
var _id := -1
var _start := Vector2.ZERO
var _pos := Vector2.ZERO
var _t0 := 0
var _touches := {}
var _spread := 0.0
var _last_tap_ms := -100000
var _last_tap_consumed := false
var _vel := Vector2.ZERO
var _last_move_ms := 0

func _init(m: Mode = Mode.SCENE) -> void:
	mode = m

func is_active() -> bool: return _state != _S.IDLE and _state != _S.DONE
func is_dragging() -> bool: return _state == _S.DRAGGING
## A slot or cell floats after its long press and has not been dragged yet.
func is_lifted() -> bool: return _state == _S.LIFTED
func is_joystick() -> bool: return _state == _S.JOYSTICK
## A single finger is down in SCENE mode and steering (not pinching).
func is_steering() -> bool: return _state == _S.PRESSED or _state == _S.JOYSTICK
## Two fingers are down in SCENE mode (between pinch_start and pinch_end).
func is_pinching() -> bool: return _state == _S.PINCH
## Current press origin and finger position (for drawing a joystick or a lifted slot).
func origin() -> Vector2: return _start
func position() -> Vector2: return _pos

## The caller tells the arbiter that the last scene tap hit a facility, so it cannot start a double tap.
func consume_tap() -> void: _last_tap_consumed = true

func reset() -> void:
	_state = _S.IDLE
	_id = -1
	_touches.clear()
	_spread = 0.0

# ---------------------------------------------------------------- input

func feed(e: InputEvent, now_ms: int) -> Array:
	if e is InputEventScreenTouch:
		return press(e.index, e.position, now_ms) if e.pressed else release(e.index, e.position, now_ms)
	if e is InputEventScreenDrag:
		return move(e.index, e.position, now_ms)
	if mouse_as_touch and not DisplayServer.is_touchscreen_available():
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			return press(0, e.position, now_ms) if e.pressed else release(0, e.position, now_ms)
		if e is InputEventMouseMotion and _id == 0:
			return move(0, e.position, now_ms)
	return []

func press(index: int, pos: Vector2, now_ms: int) -> Array:
	_touches[index] = pos
	if mode == Mode.SCENE and _touches.size() >= 2:
		var out := []
		if _state in [_S.PRESSED, _S.JOYSTICK]: out.append({kind = &"joystick_end"})
		if _state != _S.PINCH:
			_state = _S.PINCH
			_spread = _current_spread()
			out.append({kind = &"pinch_start", center = _center()})
		return out
	if _id >= 0:
		# A second finger cancels a slot / cell press, lift or drag (LOCK-04 v1.10); on a handle it is ignored.
		if mode in [Mode.SLOT, Mode.CELL] and _state in [_S.PRESSED, _S.MOVED, _S.LIFTED, _S.DRAGGING]:
			_state = _S.DONE
			return [{kind = &"cancel"}]
		return []
	_id = index
	_start = pos
	_pos = pos
	_t0 = now_ms
	_last_move_ms = now_ms
	_vel = Vector2.ZERO
	_state = _S.PRESSED
	if mode == Mode.SCENE: return [{kind = &"joystick_show", pos = pos}]
	return []

func move(index: int, pos: Vector2, now_ms: int) -> Array:
	if not _touches.has(index): return []
	_touches[index] = pos
	if _state == _S.PINCH:
		var d := _current_spread()
		var out := []
		if _spread > 0.0 and d > 0.0: out.append({kind = &"pinch", factor = _spread / d, center = _center()})
		_spread = d
		return out
	if index != _id: return []
	var dt := maxi(1, now_ms - _last_move_ms)
	_vel = (pos - _pos) / (float(dt) / 1000.0)
	_last_move_ms = now_ms
	_pos = pos
	var travel := pos - _start
	match mode:
		Mode.SCENE: return _scene_move(travel)
		Mode.SLOT: return _slot_move(travel)
		Mode.CELL: return _cell_move(travel)
		Mode.HANDLE: return []
	return []

func release(index: int, pos: Vector2, now_ms: int) -> Array:
	_touches.erase(index)
	if _state == _S.PINCH:
		if _touches.is_empty():
			reset()
			return [{kind = &"pinch_end"}]
		return []
	if index != _id: return []
	_pos = pos
	_id = -1
	var held := now_ms - _t0
	var still := pos.distance_to(_start) <= TAP_SLOP
	var state := _state
	_state = _S.IDLE
	match mode:
		Mode.SCENE: return _scene_release(state, held, still, pos, now_ms)
		Mode.SLOT, Mode.CELL: return _press_release(state, held, still, pos)
		Mode.HANDLE: return _handle_release(pos)
	return []

## Long presses fire on time alone; call every frame while a press is active.
func tick(now_ms: int) -> Array:
	if mode in [Mode.SLOT, Mode.CELL] and _state == _S.PRESSED and now_ms - _t0 >= LONG_PRESS_MS:
		_state = _S.LIFTED
		return [{kind = &"lift", pos = _start}]
	return []

# ---------------------------------------------------------------- modes

func _scene_move(travel: Vector2) -> Array:
	# Like the shipped _TouchPad, the stick steers from the first pixel past its dead zone; the tap slop
	# only decides whether the release can still be a tap (and when the ring is drawn).
	if _state == _S.PRESSED and travel.length() > TAP_SLOP: _state = _S.JOYSTICK
	if _state not in [_S.PRESSED, _S.JOYSTICK]: return []
	return [{kind = &"joystick_move", vector = stick_vector(travel, stick_radius)}]

func _scene_release(state: int, held: int, still: bool, pos: Vector2, now_ms: int) -> Array:
	var out := [{kind = &"joystick_end"}]
	if state == _S.PRESSED and still and held <= TAP_MAX_MS:
		var double := now_ms - _last_tap_ms <= DOUBLE_TAP_MS and not _last_tap_consumed
		out.append({kind = &"tap", pos = pos, double = double})
		# A double tap ends the chain; a third quick tap starts a new one.
		_last_tap_ms = -100000 if double else now_ms
		_last_tap_consumed = false
	return out

func _slot_move(travel: Vector2) -> Array:
	if _state in [_S.PRESSED, _S.MOVED]:
		if -travel.y >= SWIPE_UP and absf(travel.y) > 2.0 * absf(travel.x):
			_state = _S.DONE
			return [{kind = &"swipe_up"}]
		if travel.length() > TAP_SLOP: _state = _S.MOVED
		return []
	return _lifted_move(travel)

func _cell_move(travel: Vector2) -> Array:
	if _state == _S.PRESSED and travel.length() > TAP_SLOP:
		_state = _S.DONE   # the scroll container owns this drag
		return [{kind = &"cancel"}]
	return _lifted_move(travel)

func _lifted_move(travel: Vector2) -> Array:
	# A lifted quick-bar slot drags at once (v1.11); a bag cell still waits for the tap slop.
	if _state == _S.LIFTED and travel.length() > (0.0 if mode == Mode.SLOT else TAP_SLOP):
		_state = _S.DRAGGING
		return [{kind = &"drag_start", pos = _pos}, {kind = &"drag_move", pos = _pos}]
	if _state == _S.DRAGGING: return [{kind = &"drag_move", pos = _pos}]
	return []

func _press_release(state: int, held: int, still: bool, pos: Vector2) -> Array:
	match state:
		_S.PRESSED:
			if still and held < LONG_PRESS_MS: return [{kind = &"tap", pos = pos}]
			return [{kind = &"cancel"}]
		_S.LIFTED:   # lifted and never dragged: nothing on the bar (v1.11, pins go through the Pin zone)
			return [{kind = &"cancel" if mode == Mode.SLOT else &"long_press", pos = pos}]
		_S.DRAGGING:
			return [{kind = &"drop", pos = pos}]
		_S.MOVED:
			return [{kind = &"cancel"}]
	return []

func _handle_release(pos: Vector2) -> Array:
	var dy := pos.y - _start.y
	if dy >= DRAWER_CLOSE or (dy > TAP_SLOP and _vel.y >= DRAWER_FLING): return [{kind = &"close"}]
	return [{kind = &"cancel"}]

# ---------------------------------------------------------------- helpers

func _current_spread() -> float:
	var pts: Array = _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1]) if pts.size() >= 2 else 0.0

func _center() -> Vector2:
	var pts: Array = _touches.values()
	if pts.size() < 2: return pts[0] if pts.size() == 1 else Vector2.ZERO
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5

## Joystick vector for a finger offset: full speed at `radius`, zero inside the dead zone.
static func stick_vector(offset: Vector2, radius: float) -> Vector2:
	var v := offset / radius
	if v.length() > 1.0: v = v.normalized()
	return Vector2.ZERO if v.length() < STICK_DEADZONE else v

## Where a dragged quick-bar slot lands, by the release point only (LOCK-04 / 05 v1.11, 221 b0a83924): within
## DROP_ZONE_HIT of the Pin / Unpin zone → &"pin_toggle"; of the Remove zone → &"remove"; another slot grown
## DROP_SLOT_GROW → {kind = &"swap", index}; its own slot or anywhere else → &"cancel" (it flies back).
static func drop_on_bar(pos: Vector2, from: int, slots: Array, pin_zone: Vector2, remove_zone: Vector2) -> Dictionary:
	if pos.distance_to(pin_zone) <= DROP_ZONE_HIT: return {kind = &"pin_toggle"}
	if pos.distance_to(remove_zone) <= DROP_ZONE_HIT: return {kind = &"remove"}
	for i in slots.size():
		if i != from and (slots[i] as Rect2).grow(DROP_SLOT_GROW).has_point(pos): return {kind = &"swap", index = i}
	return {kind = &"cancel"}

## The two drop zones' centres for a quick bar (its global rect): [Pin / Unpin, Remove], DROP_ZONE_ABOVE over its
## top edge at x 72 and 168 on a 360-wide screen.
## In the bag drawer (`below`) they open DROP_ZONE_ABOVE under the bar's bottom edge instead (q(61)).
static func drop_zone_centers(bar: Rect2, below := false) -> Array[Vector2]:
	var y := bar.end.y + DROP_ZONE_ABOVE if below else bar.position.y - DROP_ZONE_ABOVE
	return [Vector2(bar.position.x + PIN_ZONE_X, y), Vector2(bar.position.x + REMOVE_ZONE_X, y)]

## Scroll speed factor while dragging near a grid edge: -1..0 near the top, 0..1 near the bottom.
static func autoscroll(pos_y: float, area: Rect2) -> float:
	if pos_y < area.position.y + EDGE_AUTOSCROLL:
		return -clampf((area.position.y + EDGE_AUTOSCROLL - pos_y) / EDGE_AUTOSCROLL, 0.0, 1.0)
	if pos_y > area.end.y - EDGE_AUTOSCROLL:
		return clampf((pos_y - (area.end.y - EDGE_AUTOSCROLL)) / EDGE_AUTOSCROLL, 0.0, 1.0)
	return 0.0

## Screen zone for a press (WP7-B F-04 §1). `layout` keys: hud_bottom, bar_top (floats), actions (Array of
## Rect2: main key, switch key, tool badge), sheet (Rect2, empty when no drawer / card is open).
enum Zone { HUD, SCENE, ACTION, BAR, SHEET, SCRIM }
static func zone_at(pos: Vector2, layout: Dictionary) -> Zone:
	var sheet: Rect2 = layout.get("sheet", Rect2())
	if sheet.has_area():
		return Zone.SHEET if sheet.has_point(pos) else Zone.SCRIM
	if pos.y < float(layout.get("hud_bottom", 0.0)): return Zone.HUD
	for r in layout.get("actions", []):
		if (r as Rect2).has_point(pos): return Zone.ACTION
	if pos.y >= float(layout.get("bar_top", INF)) - 8.0: return Zone.BAR
	return Zone.SCENE
