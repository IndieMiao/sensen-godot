class_name UiNavButton
extends Button
## Navigation (SGODOT-212): NavigationRow 483:217 (full-width row, label left, chevron right, 49 high) and
## Compact/Navigation 633:41276 ("Gift ›" in a 44 hit area). Navigation only opens a panel or moves the
## camera; it never jumps the player anywhere (LOCK-08). Emits Button `pressed`.

const CHEVRON := "›"

var compact := false: set = set_compact
var label := "": set = set_label
## Compact only: false drops the ` ›` (BagHeader's `Sort · Type`, a toggle rather than a way somewhere).
var chevron := true: set = set_chevron

var _chevron: Label

func _init(text_: String = "", compact_ := false) -> void:
	focus_mode = Control.FOCUS_NONE
	_chevron = UiKit.label(CHEVRON, UiTokens.STYLE_TITLE_B20, UiTokens.COLOR_INFO)
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chevron.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_chevron.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_chevron)
	label = text_
	compact = compact_

func set_compact(v: bool) -> void:
	compact = v
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_EXPAND_FILL
	_apply()
func set_label(v: String) -> void: label = v; _apply()
func set_chevron(v: bool) -> void: chevron = v; _apply()

func _apply() -> void:
	if _chevron == null: return
	_chevron.visible = not compact
	if compact:
		theme_type_variation = UiTokens.BUTTON_NAV_COMPACT
		alignment = HORIZONTAL_ALIGNMENT_CENTER
		text = "%s %s" % [label, CHEVRON] if chevron else label
		custom_minimum_size = Vector2.ZERO
		UiKit.ensure_hit_area(self)
	else:
		theme_type_variation = UiTokens.BUTTON_NAV_ROW
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		text = label
		custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_NAVIGATION_ROW)
