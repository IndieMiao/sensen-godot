class_name UiWordmark
extends HBoxContainer
## Wordmark (placeholder) 1187:82582 (WP6; SGODOT-233): the sprout and "Gensen" in primary ExtraBold, 148 × 44. A
## stand-in until the brand logo arrives: replace this one component and every screen follows.

const SPROUT := preload("res://assets/ui/kit_icons/sprout.svg")
const _SPROUT := 30.0
const _GAP := 6
const _NAME_SIZE := 32   # Name ExtraBold 32 in the main; a constant until the next token export adds the style
const NAME := "Gensen"

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", _GAP)
	var sprout := UiKit.icon(SPROUT, _SPROUT)
	sprout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(sprout)
	var name_label := UiKit.label(NAME, UiTokens.STYLE_TITLE_XB20, UiTokens.COLOR_PRIMARY_INK)
	name_label.add_theme_font_size_override(&"font_size", _NAME_SIZE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)
