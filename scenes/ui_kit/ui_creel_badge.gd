class_name UiCreelBadge
extends Control
## CreelBadge 1126:79349 (LOCK-02 HUD, FISH-1 / FISH-4; 不知火舞 on 235 B1): at fishing spots only, under the HUD's
## second row on the left — `Creel N · M free` (N fish in the creel, M free bag slots). A pill, radius 12, padding
## 8 / 10 / 4, gap 6: the i-fish 16 and the label (caption ExtraBold 12).
##   NORMAL  surface, 1 px border, text
##   LOW     one slot left: surface, 1 px amber, warning text
##   FULL    no slot left: warning tint, 1 px amber, warning text, and the 8 alert dot over the top-right corner
## The host takes the tap (`pressed`): full, the Error toast with Open bag ›; otherwise the bag on its Fish page.

signal pressed

enum State { NORMAL, LOW, FULL }

const _RADIUS := 12.0
const _PAD_L := 8.0
const _PAD_R := 10.0
const _PAD_Y := 4.0
const _GAP := 6
const _ICON := 16.0
const _DOT := 8.0
const _DOT_IN := 6.0    # the dot's left edge sits 6 in from the pill's right edge …
const _DOT_UP := 2.0    # … and 2 over its top (Alert dot at x 120, y −2 of 126)

var text := "": set = set_text
var state: State = State.NORMAL: set = set_state
var icon: Texture2D: set = set_icon

var _pill: PanelContainer
var _icon: TextureRect
var _label: Label
var _dot: Panel

func _init(icon_: Texture2D = null) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pill = PanelContainer.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pill)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", _GAP)
	_pill.add_child(row)
	_icon = UiKit.icon(icon_, _ICON)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	_label = UiKit.label("", UiTokens.STYLE_CAPTION_XB12)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(_label)
	_dot = Panel.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.size = Vector2(_DOT, _DOT)
	_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_UNREAD_BADGE, _DOT * 0.5))
	add_child(_dot)
	_pill.minimum_size_changed.connect(_layout)
	icon = icon_
	_refresh()

## The state for `free` bag slots: none FULL, one LOW, more NORMAL.
static func state_for(free: int) -> State:
	return State.FULL if free <= 0 else (State.LOW if free == 1 else State.NORMAL)

func set_text(v: String) -> void:
	if v == text: return
	text = v
	if _label: _label.text = v

func set_state(v: State) -> void:
	if v == state: return
	state = v
	_refresh()

func set_icon(v: Texture2D) -> void:
	icon = v
	if _icon: _icon.texture = v

## The pill itself, as drawn (the dot hangs outside it).
func pill_rect() -> Rect2: return Rect2(_pill.position, _pill.size)

func _refresh() -> void:
	if _label == null: return
	var calm := state == State.NORMAL
	_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(
		UiTokens.COLOR_WARNING_TINT if state == State.FULL else UiTokens.COLOR_SURFACE, _RADIUS,
		UiTokens.COLOR_BORDER if calm else UiTokens.COLOR_AMBER, UiTokens.STROKE_DEFAULT)
		.with_margins(_PAD_L, _PAD_Y, _PAD_R, _PAD_Y))
	_label.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT if calm else UiTokens.COLOR_WARNING)
	_dot.visible = state == State.FULL
	_layout()

func _layout() -> void:
	if _pill == null: return
	var s := _pill.get_combined_minimum_size()
	_pill.position = Vector2.ZERO
	_pill.size = s
	custom_minimum_size = s
	size = s
	_dot.position = Vector2(s.x - _DOT_IN, -_DOT_UP)

## One tap (mouse button; raw touches arrive as emulated mouse events): the host decides what it opens.
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()
