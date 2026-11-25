class_name UiTaskButton
extends Button
## UI v3 HUD task button (C-H3; C-107): the 24 clay notebook (C-86 `icon_sys_tasks`) in a 44 hit area, no disc. A new
## task puts a Ø8 `badge/notify` dot on its top right. Presses play M-01; emits `pressed` (the HUD opens the task
## drop-down, C-T1).

const _ICON := 24.0
const _DOT := 8.0

var badge := false: set = set_badge

func _init(icon_: Texture2D = null) -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	custom_minimum_size = Vector2.ONE * UiTokens.SIZE_TOUCH_MIN
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	icon = icon_ if icon_ != null else UiArt.sys("tasks")
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_constant_override(&"icon_max_width", int(_ICON))
	UiMotion.press_feedback(self)

func set_badge(v: bool) -> void:
	badge = v
	queue_redraw()

func _draw() -> void:
	if not badge: return
	var c := size * 0.5 + Vector2(_ICON, -_ICON) * 0.5
	draw_circle(c, _DOT * 0.5, UiTokens.COLOR_BADGE_NOTIFY, true, -1.0, true)
