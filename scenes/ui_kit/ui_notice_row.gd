class_name UiNoticeRow
extends Button
## A compact notice that leads somewhere (SGODOT-225; "Bag capacity recovery" on BAG-5 482:144): a 44 high raised
## row with a border, one Compact 11 Bold line in secondary and a `›`, e.g. `Bag full · +5 slots at Homestead
## Lv3`. Navigation only (LOCK-08): the host opens a panel or moves the camera. Emits Button `pressed`.

# BAG-5 "Bag capacity recovery" (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _H := 44.0
const _RADIUS := 12.0
const _PAD_X := 9.0      # label x 9 inside the 1 px border … chevron x 314 of 336
const _CHEVRON_W := 10.0

var _label: Label

func _init(text_: String = "") -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = _H
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(st, box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = _PAD_X
	row.offset_right = -(_PAD_X + UiTokens.STROKE_DEFAULT)
	add_child(row)
	_label = UiKit.label(text_, UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_label)
	var chevron := UiKit.label("›", UiTokens.STYLE_C13_XB, UiTokens.COLOR_SECONDARY)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.custom_minimum_size.x = _CHEVRON_W
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chevron)

func set_notice(v: String) -> void: _label.text = v
func notice() -> String: return _label.text
