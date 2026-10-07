class_name UiBadge
extends PanelContainer
## StateBadge 483:324 (SGODOT-212): a 32 px primaryTint pill with a short state word, e.g. "Ready",
## "Familiar". Display only; hugs its text. World and map status icons are STATE-ICONS (LOCK-11), not this.

var text := "": set = set_text

var _label: Label

func _init(text_: String = "") -> void:
	theme_type_variation = UiTokens.PANEL_BADGE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size.y = UiTokens.SIZE_STATE_BADGE_H
	_label = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_PRIMARY)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	text = text_

func set_text(v: String) -> void:
	text = v
	if _label != null: _label.text = v
