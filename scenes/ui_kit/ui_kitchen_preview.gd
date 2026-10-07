class_name UiKitchenPreview
extends Panel
## Compact/Kitchen/Preview 655:58436 (SGODOT-226, LOCK-20): the preview capsule under the pot's slot bar. Facts
## only (plan §7.2.7): the dish name ("Unknown dish" for an unknown combination), its rarity and its cooking time.
## 292×26 surface pill with a hairline border; display only.

const _W := 292.0
const _H := 26.0
const _BORDER := 0.6
const _TITLE := Rect2(9.4, 4.4, 154, 17)
const _STATE := Rect2(169.4, 5.4, 58, 15)
const _TIME := Rect2(233.4, 4.4, 48, 17)

var title := "": set = set_title
## Rarity word (Common / Fine / Rare / Legendary); "" hides it.
var state := "": set = set_state
var time := "": set = set_time

var _title: Label
var _state: Label
var _time: Label

func _init() -> void:
	custom_minimum_size = Vector2(_W, _H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, _H * 0.5, UiTokens.COLOR_BORDER, _BORDER))
	_title = _text(_TITLE, UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT)
	_state = _text(_STATE, UiTokens.STYLE_C11_B, UiTokens.COLOR_INFO)
	_time = _text(_TIME, UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT)

func _text(r: Rect2, style: StringName, color: Color) -> Label:
	var l := UiKit.label("", style, color)
	l.position = r.position
	l.size = r.size
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(l)
	return l

func set_title(v: String) -> void: title = v; if _title: _title.text = v
func set_state(v: String) -> void: state = v; if _state: _state.text = v
func set_time(v: String) -> void: time = v; if _time: _time.text = v

func show_facts(title_: String, state_: String, time_: String) -> void:
	title = title_
	state = state_
	time = time_
