class_name UiEmptyState
extends VBoxContainer
## EmptyState (SGODOT-212; WP7-B F-08 §5, no Figma main yet, engineering default): icon + one line +
## optional navigation row, centred, e.g. "No fish yet". The navigation only opens a panel or moves the
## camera (LOCK-08); copy comes from the caller (final wording by WP6 / the plan). Emits `navigate`.

signal navigate

var icon: Texture2D: set = set_icon
var text := "": set = set_text
## Navigation label, e.g. "Show on map"; "" hides the row.
var action := "": set = set_action

var _icon: TextureRect
var _label: Label
var _nav: UiNavButton

func _init(text_: String = "", icon_: Texture2D = null, action_: String = "") -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	_icon = UiKit.icon(null, UiTokens.SIZE_ITEM_ROW_ICON)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.modulate.a = UiTokens.OPACITY_ZERO_ICON
	add_child(_icon)
	_label = UiKit.label("", UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	_nav = UiNavButton.new("", true)
	_nav.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_nav.pressed.connect(func(): navigate.emit())
	add_child(_nav)
	icon = icon_
	text = text_
	action = action_

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
