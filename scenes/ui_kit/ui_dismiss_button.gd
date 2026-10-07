class_name UiDismissButton
extends Button
## Dismiss 483:220 (SGODOT-212): the quiet full-width text button that closes a sheet or card, e.g. "Not now".
## Not for the Energy card, whose only button is the primary `Free to do now` (LOCK-09). Emits `pressed`.

func _init(text_: String = "Not now") -> void:
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = UiTokens.BUTTON_DISMISS
	text = text_
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_DISMISS)
