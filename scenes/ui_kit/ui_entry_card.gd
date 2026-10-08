class_name UiEntryCard
extends Control
## EntryCard 1468:94344 (SGODOT-231, LOCK-21 / §13.3.1): the small card over the mine gate while the player is near
## it, beside the main action key. It carries only the choice the key can't: `New run · 2 Energy` with its consequence
## under it (`Current run will end · Runs today 1/2`). The whole card is the button (`pressed`, a real tap only:
## GestureArbiter TAP_SLOP / TAP_MAX_MS). Unavailable = the reason on the action line in secondary, no caption, and it
## still takes the tap so its owner can toast the reason (LOCK-10, 不知火舞 on 231). Placement: WorldAnchor puts the
## pointer tip on the gate; point_at() keeps the pointer on it near the screen edges (the main's Pointer=Right).
## `passive` cards take no touches on the P0 scene (苏烈 on #45): the scene layer under them sees the press, so the
## joystick can start on the card, and the owner resolves a real tap on hit_rect() itself.

signal pressed

enum State { AVAILABLE, UNAVAILABLE }

const _PAD_X := 14.0              # EntryCard main: padding 8 / 14 / 9 / 14, gap 2, radius 16 (no token yet)
const _PAD_TOP := 8.0
const _PAD_BOTTOM := 9.0
const _GAP := 2
const _RADIUS := 16.0
const _POINTER_INSET := 21.0      # Pointer=Right: the pointer box sits 21 px in from the right edge

var action := "": set = set_action
var caption := "": set = set_caption
var state: State = State.AVAILABLE: set = set_state
## Available but short of Energy (`New run · Need 2 Energy`, LOCK-09): the action line in the warning colour, the
## consequence kept; the tap opens the Energy card (不知火舞 on #45; 安其拉 adds it to the main).
var amber := false: set = set_amber
var passive := false: set = set_passive

var _card: PanelContainer
var _action: Label
var _caption: Label
var _pointer: UiPointer
var _aim := NAN
var _down_at := Vector2.INF
var _down_ms := 0

func _init(action_ := "", caption_ := "", state_: State = State.AVAILABLE) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	box.with_margins(_PAD_X, _PAD_TOP, _PAD_X, _PAD_BOTTOM)
	_card.add_theme_stylebox_override(&"panel", box)
	_card.gui_input.connect(_on_input)
	add_child(_card)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", _GAP)
	_card.add_child(col)
	_action = UiKit.label("", UiTokens.STYLE_C13_XB)
	_action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_action)
	_caption = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_caption)
	_pointer = UiPointer.new()
	add_child(_pointer)
	_card.resized.connect(_layout)
	_card.minimum_size_changed.connect(_layout)
	action = action_
	caption = caption_
	state = state_
	_refresh()   # the setters skip values equal to the defaults

# The owner sets these every frame: only a change restyles and relayouts (苏烈 on #45).
func set_action(v: String) -> void:
	if v != action: action = v; _refresh()
func set_caption(v: String) -> void:
	if v != caption: caption = v; _refresh()
func set_state(v: State) -> void:
	if v != state: state = v; _refresh()
func set_amber(v: bool) -> void:
	if v != amber: amber = v; _refresh()

func set_passive(v: bool) -> void:
	passive = v
	if _card: _card.mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP

func _refresh() -> void:
	if _action == null: return
	_action.text = action
	var color := UiTokens.COLOR_SECONDARY if state == State.UNAVAILABLE \
		else UiTokens.COLOR_WARNING if amber else UiTokens.COLOR_PRIMARY
	_action.add_theme_color_override(&"font_color", color)
	_caption.text = caption
	_caption.visible = state == State.AVAILABLE and caption != ""   # the consequence only when it can be done

## The card's touch area in global space, grown to the 44 px touch height when the card is shorter.
func hit_rect() -> Rect2:
	var r := _card.get_global_rect()
	var grow := maxf(0.0, (UiTokens.SIZE_TOUCH - r.size.y) * 0.5)
	return r.grow_individual(0, grow, 0, grow)

func _get_minimum_size() -> Vector2:
	if _card == null: return Vector2.ZERO
	var c := _card.get_combined_minimum_size()
	return Vector2(c.x, c.y + UiTokens.SIZE_POINTER_H)

## Local x of the gate inside this card; the pointer's tip goes there, kept clear of the rounded corners.
func point_at(local_x: float) -> void:
	_aim = local_x
	_aim_pointer()

func _aim_pointer() -> void:
	var w := _card.size.x
	var half := UiTokens.SIZE_POINTER_W * 0.5
	var local_x := w * 0.5 if is_nan(_aim) else _aim
	var tip := clampf(local_x, _POINTER_INSET + half, maxf(_POINTER_INSET + half, w - _POINTER_INSET - half))
	_pointer.position = Vector2(tip - half, _card.size.y)

func pointer_tip_x() -> float: return _pointer.position.x + UiTokens.SIZE_POINTER_W * 0.5

func _layout() -> void:
	if _pointer == null: return
	_card.position = Vector2.ZERO
	_card.size = _card.get_combined_minimum_size()
	_aim_pointer()
	update_minimum_size()

## One event family only (mouse buttons; raw touches only without touchscreen emulation).
func _on_input(e: InputEvent) -> void:
	var is_mouse: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT
	var is_touch: bool = e is InputEventScreenTouch and not DisplayServer.is_touchscreen_available()
	if not (is_mouse or is_touch): return
	accept_event()
	if e.pressed:
		_down_at = e.position
		_down_ms = Time.get_ticks_msec()
		return
	var tap: bool = _down_at != Vector2.INF and e.position.distance_to(_down_at) <= GestureArbiter.TAP_SLOP \
		and Time.get_ticks_msec() - _down_ms <= GestureArbiter.TAP_MAX_MS
	_down_at = Vector2.INF
	if tap: pressed.emit()
