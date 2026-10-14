class_name UiEntryCard
extends Control
## EntryCard v2 (Figma 1468:94344 Kind=Gate / Gate run / Ladder; SGODOT-266, 不知火舞 2e580bed / 9ce583a8 and her
## walkthrough on #190, copy 李白 q(102)): the small card over a mine facility the player tapped and walked up to — only
## where using it costs Energy; the free moves go at once. 240 wide, surface, radius 16, border and the float shadow,
## items 8 apart; padding 12 with a title (the mine mouth), 8 without (a ladder: the destination is on its button).
##   title   `The mine` `· Runs today 1/2`: C12 ExtraBold, 4 apart, the fact in secondary; "" hides the row;
##   main    the fee button, CommandButton across the card, 44 high, radius 22, 15 ExtraBold: green `Enter mine ·
##           2 Energy` / `Continue run · Free` / `Floor 2 · 2 Energy`; Kind=need-energy (warning tint, warning label,
##           the whole line `Floor 2 · Need 2 Energy`) whose tap opens the Energy card; Kind=unavailable (grey, the
##           reason as the label) still takes the tap and the owner toasts the line (LOCK-10, 5181bba0);
##   second  an optional Dismiss-style text button, 44 high, 15 Bold secondary: `New run · 2 Energy` (warning short
##           of Energy; the reason, still secondary, when it can't);
##   pill    instead of the second, a grey CommandButton (Kind=unavailable) as big as the main: the mine mouth's
##           `Resets in 9h 12m` under `Continue run · Free` at 2/2 (MINE-GATE-EXPRESS-4); its tap is the second's;
##   third   an optional second Dismiss-style button under it, the same look: the mine mouth's `Floor 5 · Express ·
##           Free` (P1, MINE-GATE-EXPRESS row 58; q(108): with a run open it stacks under New run);
##   note    C10 secondary under the second (and third): `Current run will end`, only while one of them can be done.
## Placement: WorldAnchor puts the pointer tip on the facility; point_at() keeps the pointer on it near the screen
## edges; the owner lifts the card clear of the player (WorldAnchor.lift_clear). `passive` cards take no touches on the P0 scene (苏烈 on
## #45): the scene layer under them sees the press, so the joystick can start on the card, and the owner resolves a
## real tap with tap_at().

signal pressed            # the main button
signal second_pressed     # the secondary text button
signal third_pressed      # the second text button under it (Express)

enum State { AVAILABLE, UNAVAILABLE }

const WIDTH := 240.0
const _PAD := 12.0                # with a title (Kind=Gate / Gate run)
const _PAD_LADDER := 8.0          # without (Kind=Ladder)
const _GAP := 8
const _TITLE_SEP := 4
const _BUTTON_H := 44.0
const _RADIUS := 16.0
const _POINTER_INSET := 21.0      # Pointer=Right: the pointer box sits 21 px in from the right edge

var title := "": set = set_title
var title_fact := "": set = set_title_fact
var action := "": set = set_action
var state: State = State.AVAILABLE: set = set_state
var amber := false: set = set_amber
var second := "": set = set_second
var second_state: State = State.AVAILABLE: set = set_second_state
var second_amber := false: set = set_second_amber
var pill := "": set = set_pill
var third := "": set = set_third
var third_state: State = State.AVAILABLE: set = set_third_state
var note := "": set = set_note
var passive := false: set = set_passive

var _card: PanelContainer
var _box: UiStyleBox
var _title_row: HBoxContainer
var _title: Label
var _title_fact: Label
var _main: Button
var _pill: Button
var _second_row: CenterContainer
var _second: Label
var _third_row: CenterContainer
var _third: Label
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
	_box = UiStyleBox.make(UiTokens.COLOR_SURFACE, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	_box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	_box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	_box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	_box.with_margins(_PAD, _PAD, _PAD, _PAD)
	_card.add_theme_stylebox_override(&"panel", _box)
	_card.custom_minimum_size.x = WIDTH
	_card.gui_input.connect(_on_input)
	add_child(_card)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", _GAP)
	_card.add_child(col)
	_title_row = HBoxContainer.new()
	_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_row.add_theme_constant_override(&"separation", _TITLE_SEP)
	col.add_child(_title_row)
	_title = UiKit.label("", UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT)
	_title_fact = UiKit.label("", UiTokens.STYLE_C12_XB, UiTokens.COLOR_SECONDARY)
	for l in [_title, _title_fact]: _title_row.add_child(l)
	# CommandButton's look in its CmdPrimary / CmdBlocked variations at the card's 44. A plain Button, not a
	# UiCommandButton, which drops every outside style on each theme change and so could not wear need-energy.
	_main = Button.new()
	_main.focus_mode = Control.FOCUS_NONE
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the card resolves its taps (passive or not): one path
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, _BUTTON_H)
	col.add_child(_main)
	_pill = Button.new()   # the main's CommandButton look, always CmdBlocked (Kind=unavailable)
	_pill.name = "Pill"
	_pill.focus_mode = Control.FOCUS_NONE
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pill.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, _BUTTON_H)
	_pill.theme_type_variation = UiTokens.BUTTON_CMD_BLOCKED
	_pill.visible = false
	col.add_child(_pill)
	_second_row = CenterContainer.new()   # Dismiss: 44 high, the text centred
	_second_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_second_row.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	col.add_child(_second_row)
	_second = UiKit.label("", UiTokens.STYLE_BUTTON_B15, UiTokens.COLOR_SECONDARY)
	_second.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_second_row.add_child(_second)
	_third_row = CenterContainer.new()   # the same Dismiss row
	_third_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_third_row.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	col.add_child(_third_row)
	_third = UiKit.label("", UiTokens.STYLE_BUTTON_B15, UiTokens.COLOR_SECONDARY)
	_third.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_third_row.add_child(_third)
	_note = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_note)
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
func set_pill(v: String) -> void:
	if v != pill: pill = v; _refresh()
func set_third(v: String) -> void:
	if v != third: third = v; _refresh()
func set_third_state(v: State) -> void:
	if v != third_state: third_state = v; _refresh()
func set_note(v: String) -> void:
	if v != note: note = v; _refresh()

func set_passive(v: bool) -> void:
	passive = v
	if _card: _card.mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP

func _refresh() -> void:
	if _main == null: return
	_title.text = title
	_title_fact.text = "· " + title_fact   # Figma's second run carries the dot
	_title_row.visible = title != ""
	_title_fact.visible = title_fact != ""
	var pad := _PAD if title != "" else _PAD_LADDER
	if _box.content_margin_left != pad: _box.with_margins(pad, pad, pad, pad)
	# Grey (LOCK-10): CmdBlocked with the reason as its label; the card still takes the tap and the owner toasts why.
	_main.text = action
	_main.theme_type_variation = UiTokens.BUTTON_CMD_BLOCKED if state == State.UNAVAILABLE else UiTokens.BUTTON_CMD_PRIMARY
	_restyle()
	_pill.visible = pill != ""
	_pill.text = pill
	_second_row.visible = second != "" and pill == ""
	_second.text = second
	var ink := UiTokens.COLOR_WARNING if second_amber and second_state == State.AVAILABLE else UiTokens.COLOR_SECONDARY
	_second.add_theme_color_override(&"font_color", ink)
	_third_row.visible = third != ""
	_third.text = third
	_note.text = note
	# only when one of them can be done
	_note.visible = note != "" and ((second != "" and second_state == State.AVAILABLE) or (third != "" and third_state == State.AVAILABLE))

## The card's 44 high pill (radius 22) over the theme's CommandButton boxes; short of Energy, Kind=need-energy: the
## warning tint and a warning label. Styled from the theme the button has now, so the card restyles once themed.
func _style_amber(b: Button, on: bool) -> void:
	const STYLES: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]
	const INKS: Array[StringName] = [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]
	for st in STYLES: b.remove_theme_stylebox_override(st)
	for c in INKS: b.remove_theme_color_override(c)
	if not b.is_inside_tree(): return   # no theme yet: restyled once it has one (_notification)
	for st in STYLES:
		var t := b.get_theme_stylebox(st).duplicate() as StyleBox
		if t is UiStyleBox:
			var u := t as UiStyleBox
			u.corner_radius = Vector4.ONE * UiTokens.RADIUS_PILL
			u.visual_height = 0.0
			u.inset = Vector4.ZERO
			if on:
				u.bg_color = UiTokens.COLOR_WARNING_TINT
				u.border_width = 0.0
		elif t is StyleBoxFlat:
			var f := t as StyleBoxFlat
			f.set_corner_radius_all(UiTokens.RADIUS_PILL)
			if on:
				f.bg_color = UiTokens.COLOR_WARNING_TINT
				f.set_border_width_all(0)
		b.add_theme_stylebox_override(st, t)
	if on:
		for c in INKS: b.add_theme_color_override(c, UiTokens.COLOR_WARNING)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _main != null: _restyle.call_deferred()

## Once the card has its theme: the amber from it, as the card is then (not as it was when the theme arrived).
func _restyle() -> void:
	if _main != null: _style_amber(_main, amber and state == State.AVAILABLE)
	if _pill != null: _style_amber(_pill, false)   # the same 44 pill shape, grey

func is_amber() -> bool: return _main.has_theme_color_override(&"font_color")
func main_text() -> String: return _main.text
func second_shown() -> bool: return _second_row.visible
func pill_text() -> String: return _pill.text if _pill.visible else ""
func third_shown() -> bool: return _third_row.visible
func note_shown() -> bool: return _note.visible

## The card's touch area in global space, grown to the 44 px touch height when the card is shorter.
func hit_rect() -> Rect2:
	var r := _card.get_global_rect()
	var grow := maxf(0.0, (UiTokens.SIZE_TOUCH - r.size.y) * 0.5)
	return r.grow_individual(0, grow, 0, grow)

## The main button's and the second row's touch areas in global space (the second row is already 44 high; the
## button's height is the CommandButton's).
func main_rect() -> Rect2: return _main.get_global_rect()
func second_rect() -> Rect2:
	if _pill.visible: return _pill.get_global_rect()   # the pill stands in the second's place and takes its tap
	return _second_row.get_global_rect() if _second_row.visible else Rect2()
func third_rect() -> Rect2: return _third_row.get_global_rect() if _third_row.visible else Rect2()

## What a real tap at a global point hits: "main", "second", "third", "card" (the card around them: nothing happens) or ""
## (off the card). Emits the button's signal.
func tap_at(global_pos: Vector2) -> String:
	if not visible or not hit_rect().has_point(global_pos): return ""
	var on := _part_at(global_pos)
	if on == "main": pressed.emit()
	elif on == "second": second_pressed.emit()
	elif on == "third": third_pressed.emit()
	return on

func _part_at(global_pos: Vector2) -> String:
	if main_rect().has_point(global_pos): return "main"
	if second_rect().has_point(global_pos): return "second"
	if third_rect().has_point(global_pos): return "third"
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
		elif _down_on == "third": third_pressed.emit()
