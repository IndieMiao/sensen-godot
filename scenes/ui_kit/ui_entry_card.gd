class_name UiEntryCard
extends Control
## EntryCard (MINE-P0-5; SGODOT-266, 不知火舞's structure 2e580bed / reply 9ce583a8, copy 李白 q(102)): the small card
## over a mine facility the player tapped and walked up to — only where using it costs Energy; the free moves go at
## once. Main and secondary read apart, never two equal halves. From the top:
##   title   `The mine · Runs today 1/2`: C12 bold, the fact after the dot in secondary. "" hides it — a ladder's card
##           has none, its destination is on the button;
##   main    the fee button, the map card's Go (CmdPrimary, 48 high, full card width): `Enter mine · 2 Energy`,
##           `Continue run · Free`, `Floor 2 · 2 Energy`. Short of Energy it turns amber with the whole line
##           (`Floor 2 · Need 2 Energy`) and its tap opens the Energy card; unavailable it is grey with the reason and
##           still takes the tap, the owner toasts why (LOCK-10);
##   second  an optional text button in secondary, 44 touch high: `New run · 2 Energy` (amber short of Energy, grey
##           with its reason when it can't);
##   note    C10 secondary right under the second: `Current run will end`, only while the second can be done.
## Width follows the content, at least MIN_WIDTH. Placement: WorldAnchor puts the pointer tip on the facility;
## point_at() keeps the pointer on it near the screen edges. `passive` cards take no touches on the P0 scene (苏烈 on
## #45): the scene layer under them sees the press, so the joystick can start on the card, and the owner resolves a
## real tap with tap_at().

signal pressed            # the main button
signal second_pressed     # the secondary text button

enum State { AVAILABLE, UNAVAILABLE }

const MIN_WIDTH := 200.0
const _PAD := 12.0                # card padding (engineering default until the frame lands, 不知火舞 9ce583a8)
const _TITLE_GAP := 8
const _RADIUS := 16.0
const _POINTER_INSET := 21.0      # Pointer=Right: the pointer box sits 21 px in from the right edge
const _SEP := " · "

var title := "": set = set_title
var title_fact := "": set = set_title_fact
var action := "": set = set_action
var state: State = State.AVAILABLE: set = set_state
var amber := false: set = set_amber
var second := "": set = set_second
var second_state: State = State.AVAILABLE: set = set_second_state
var second_amber := false: set = set_second_amber
var note := "": set = set_note
var passive := false: set = set_passive

var _card: PanelContainer
var _title_row: HBoxContainer
var _title: Label
var _title_sep: Label
var _title_fact: Label
var _main: Button
var _second_row: VBoxContainer
var _second: Label
var _note: Label
var _pointer: UiPointer
var _aim := NAN
var _down_at := Vector2.INF
var _down_ms := 0
var _down_on := ""

func _init(action_ := "", state_: State = State.AVAILABLE) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	box.with_margins(_PAD, _PAD, _PAD, _PAD)
	_card.add_theme_stylebox_override(&"panel", box)
	_card.custom_minimum_size.x = MIN_WIDTH
	_card.gui_input.connect(_on_input)
	add_child(_card)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 0)
	_card.add_child(col)
	_title_row = HBoxContainer.new()
	_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_row.add_theme_constant_override(&"separation", 0)
	col.add_child(_title_row)
	_title = UiKit.label("", UiTokens.STYLE_C12_B, UiTokens.COLOR_TEXT)
	_title_sep = UiKit.label(_SEP, UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	_title_fact = UiKit.label("", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	for l in [_title, _title_sep, _title_fact]: _title_row.add_child(l)
	var gap := Control.new()   # title → main
	gap.name = "TitleGap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size.y = _TITLE_GAP
	col.add_child(gap)
	# The map card's Go: CmdPrimary (CmdBlocked with the reason), 48 high. A plain Button in those variations, not a
	# UiCommandButton, which drops every outside style on each theme change and so could not wear the amber.
	_main = Button.new()
	_main.focus_mode = Control.FOCUS_NONE
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the card resolves its taps (passive or not): one path
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_COMMAND)
	col.add_child(_main)
	_second_row = VBoxContainer.new()
	_second_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_second_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_second_row.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	_second_row.add_theme_constant_override(&"separation", 0)
	col.add_child(_second_row)
	_second = UiKit.label("", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	_second.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_second_row.add_child(_second)
	_note = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_second_row.add_child(_note)
	_pointer = UiPointer.new()
	add_child(_pointer)
	_card.resized.connect(_layout)
	_card.minimum_size_changed.connect(_layout)
	action = action_
	state = state_
	_refresh()   # the setters skip values equal to the defaults

# The owner sets these every frame: only a change restyles and relayouts (苏烈 on #45).
func set_title(v: String) -> void:
	if v != title: title = v; _refresh()
func set_title_fact(v: String) -> void:
	if v != title_fact: title_fact = v; _refresh()
func set_action(v: String) -> void:
	if v != action: action = v; _refresh()
func set_state(v: State) -> void:
	if v != state: state = v; _refresh()
func set_amber(v: bool) -> void:
	if v != amber: amber = v; _refresh()
func set_second(v: String) -> void:
	if v != second: second = v; _refresh()
func set_second_state(v: State) -> void:
	if v != second_state: second_state = v; _refresh()
func set_second_amber(v: bool) -> void:
	if v != second_amber: second_amber = v; _refresh()
func set_note(v: String) -> void:
	if v != note: note = v; _refresh()

func set_passive(v: bool) -> void:
	passive = v
	if _card: _card.mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP

func _refresh() -> void:
	if _main == null: return
	_title.text = title
	_title_fact.text = title_fact
	_title_row.visible = title != ""
	_title_sep.visible = title_fact != ""
	_title_fact.visible = title_fact != ""
	_card.get_child(0).get_node("TitleGap").visible = title != ""
	# Grey (LOCK-10): CmdBlocked with the reason as its label; the card still takes the tap and the owner toasts why.
	_main.text = action
	_main.theme_type_variation = UiTokens.BUTTON_CMD_BLOCKED if state == State.UNAVAILABLE else UiTokens.BUTTON_CMD_PRIMARY
	_restyle()
	_second_row.visible = second != ""
	_second.text = second
	var ink := UiTokens.COLOR_DISABLED_INK if second_state == State.UNAVAILABLE \
		else UiTokens.COLOR_WARNING if second_amber else UiTokens.COLOR_SECONDARY
	_second.add_theme_color_override(&"font_color", ink)
	_note.text = note
	_note.visible = note != "" and second_state == State.AVAILABLE   # the consequence only when it can be done

## Short of Energy: the button's own shape with the main key's amber fill and warning ring (UiSceneAction
## INSUFFICIENT), text in ink. Off: back to the theme's CmdPrimary. Styled from the theme the button has now, so the
## card must be themed (in the tree) — _ready / a theme change restyle it.
func _style_amber(b: Button, on: bool) -> void:
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		b.remove_theme_stylebox_override(st)
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		b.remove_theme_color_override(c)
	if not on: return
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		var sb := b.get_theme_stylebox(st)
		if sb == null: continue
		var t := sb.duplicate() as StyleBox
		if t is UiStyleBox:
			(t as UiStyleBox).bg_color = UiTokens.COLOR_AMBER
			(t as UiStyleBox).border_color = UiTokens.COLOR_WARNING
			(t as UiStyleBox).border_width = UiTokens.STROKE_DEFAULT
		elif t is StyleBoxFlat:
			(t as StyleBoxFlat).bg_color = UiTokens.COLOR_AMBER
			(t as StyleBoxFlat).border_color = UiTokens.COLOR_WARNING
			(t as StyleBoxFlat).set_border_width_all(int(UiTokens.STROKE_DEFAULT))
		b.add_theme_stylebox_override(st, t)
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		b.add_theme_color_override(c, UiTokens.COLOR_TEXT)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _main != null: _restyle.call_deferred()

## Once the card has its theme: the amber from it, as the card is then (not as it was when the theme arrived).
func _restyle() -> void:
	if _main != null: _style_amber(_main, amber and state == State.AVAILABLE)

func is_amber() -> bool: return _main.has_theme_stylebox_override(&"normal")
func main_text() -> String: return _main.text
func second_shown() -> bool: return _second_row.visible
func note_shown() -> bool: return _note.visible

## The card's touch area in global space, grown to the 44 px touch height when the card is shorter.
func hit_rect() -> Rect2:
	var r := _card.get_global_rect()
	var grow := maxf(0.0, (UiTokens.SIZE_TOUCH - r.size.y) * 0.5)
	return r.grow_individual(0, grow, 0, grow)

## The main button's and the second row's touch areas in global space (the second row is already 44 high; the
## button's height is the CommandButton's).
func main_rect() -> Rect2: return _main.get_global_rect()
func second_rect() -> Rect2: return _second_row.get_global_rect() if _second_row.visible else Rect2()

## What a real tap at a global point hits: "main", "second", "card" (the card around them: nothing happens) or ""
## (off the card). Emits the button's signal.
func tap_at(global_pos: Vector2) -> String:
	if not visible or not hit_rect().has_point(global_pos): return ""
	var on := _part_at(global_pos)
	if on == "main": pressed.emit()
	elif on == "second": second_pressed.emit()
	return on

func _part_at(global_pos: Vector2) -> String:
	if main_rect().has_point(global_pos): return "main"
	if second_rect().has_point(global_pos): return "second"
	return "card"

func _get_minimum_size() -> Vector2:
	if _card == null: return Vector2.ZERO
	var c := _card.get_combined_minimum_size()
	return Vector2(c.x, c.y + UiTokens.SIZE_POINTER_H)

## Local x of the facility inside this card; the pointer's tip goes there, kept clear of the rounded corners.
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

## One event family only (mouse buttons; raw touches only without touchscreen emulation). A real tap
## (GestureArbiter TAP_SLOP / TAP_MAX_MS) that starts and ends on the same part.
func _on_input(e: InputEvent) -> void:
	var is_mouse: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT
	var is_touch: bool = e is InputEventScreenTouch and not DisplayServer.is_touchscreen_available()
	if not (is_mouse or is_touch): return
	accept_event()
	var at: Vector2 = _card.get_global_transform() * e.position
	if e.pressed:
		_down_at = e.position
		_down_ms = Time.get_ticks_msec()
		_down_on = _part_at(at)
		return
	var tap: bool = _down_at != Vector2.INF and e.position.distance_to(_down_at) <= GestureArbiter.TAP_SLOP \
		and Time.get_ticks_msec() - _down_ms <= GestureArbiter.TAP_MAX_MS
	_down_at = Vector2.INF
	if tap and _part_at(at) == _down_on:
		if _down_on == "main": pressed.emit()
		elif _down_on == "second": second_pressed.emit()
