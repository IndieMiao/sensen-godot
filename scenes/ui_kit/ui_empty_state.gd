class_name UiEmptyState
extends MarginContainer
## EmptyState (Gensen Refactor/EmptyState 1234:87237, WP6 / SGODOT-206): icon + one line + optional navigation
## row, no explanation sentence. The navigation only opens a panel or moves the camera (LOCK-08).
##   PANEL  a centred block inside a drawer, tab or list area (bag tabs, Inbox tabs, Cookbook, counter Sell here):
##          the icon sits in a 56 grey disc, one Bold 14 line, then a NavigationRow when there is somewhere to go.
##   ROW    one line inside a list (Today: `No open requests · next in 3h 12m`).
## Copy comes from the caller (the main's description lists the agreed lines). Emits `navigate`.

signal navigate

enum Kind { PANEL, ROW }

const _PANEL_PAD := Vector4(8, 24, 8, 16)   # EmptyState Kind=Panel padding left / top / right / bottom
const _ROW_PAD := Vector2(12, 10)            # Kind=Row padding
const _GAP := 10                             # both kinds

var kind: Kind
var icon: Texture2D: set = set_icon
var text := "": set = set_text
## Navigation label, e.g. "Show stall"; "" hides the row.
var action := "": set = set_action

var _icon: TextureRect
var _label: Label
var _nav: UiNavButton

func _init(text_: String = "", icon_: Texture2D = null, action_: String = "", kind_: Kind = Kind.PANEL) -> void:
	kind = kind_
	var pad := _PANEL_PAD if kind == Kind.PANEL else Vector4(_ROW_PAD.x, _ROW_PAD.y, _ROW_PAD.x, _ROW_PAD.y)
	for side in [[&"margin_left", pad.x], [&"margin_top", pad.y], [&"margin_right", pad.z], [&"margin_bottom", pad.w]]:
		add_theme_constant_override(side[0], int(side[1]))
	if kind == Kind.PANEL: _build_panel()
	else: _build_row()
	_nav.pressed.connect(func(): navigate.emit())
	icon = icon_
	text = text_
	action = action_

func _build_panel() -> void:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", _GAP)
	add_child(col)
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := float(UiTokens.SIZE_EMPTY_DISC)
	disc.custom_minimum_size = Vector2(d, d)
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_DISABLED, d * 0.5))
	_icon = UiKit.icon(null, UiTokens.SIZE_EMPTY_ICON)
	_icon.position = Vector2(d - UiTokens.SIZE_EMPTY_ICON, d - UiTokens.SIZE_EMPTY_ICON) * 0.5
	_icon.size = Vector2(UiTokens.SIZE_EMPTY_ICON, UiTokens.SIZE_EMPTY_ICON)
	_icon.modulate.a = UiTokens.OPACITY_EMPTY_ICON
	disc.add_child(_icon)
	col.add_child(disc)
	_label = UiKit.label("", UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_label)
	_nav = UiNavButton.new("")
	col.add_child(_nav)

func _build_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _GAP)
	add_child(row)
	_icon = UiKit.icon(null, UiTokens.SIZE_EMPTY_ROW_ICON)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.modulate.a = UiTokens.OPACITY_EMPTY_ICON
	row.add_child(_icon)
	_label = UiKit.label("", UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_label)
	_nav = UiNavButton.new("")
	_nav.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(_nav)

func set_icon(v: Texture2D) -> void:
	icon = v
	if _icon != null:
		_icon.texture = v
		_icon.visible = v != null

func set_text(v: String) -> void:
	text = v
	if _label != null: _label.text = v

func set_action(v: String) -> void:
	action = v
	if _nav != null:
		_nav.label = v
		_nav.visible = v != ""
