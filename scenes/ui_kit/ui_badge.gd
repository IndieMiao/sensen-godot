class_name UiBadge
extends PanelContainer
## StateBadge 483:324 (SGODOT-212): a 32 px primaryTint pill with a short state word, e.g. "Ready",
## "Familiar". Display only; hugs its text. World and map status icons are STATE-ICONS (LOCK-11), not this.

const _PAD_X := 8.0   # the Badge style's side padding (gen_theme)

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

## Another tone than the main's primaryTint / primary (a resident's affinity stage, UiResidentBar.stage_tone): the
## pill keeps the Badge style's shape and padding, only its fill and ink change.
func set_tone(fill: Color, ink: Color) -> void:
	# The Badge style as the theme builds it (a full-round pill, 8 side padding: tools/ui/gen_theme.gd), in this fill;
	# built here, not copied from the theme, so it works before the badge is in the tree.
	add_theme_stylebox_override(&"panel", UiStyleBox.make(fill, UiTokens.SIZE_STATE_BADGE_H * 0.5)
		.with_margins(_PAD_X, 0.0, _PAD_X, 0.0))
	_label.add_theme_color_override(&"font_color", ink)
