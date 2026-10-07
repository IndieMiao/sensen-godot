class_name UiProfileMoreMenu
extends PanelContainer
## ··· menu on someone else's profile (SGODOT-225; ProfileMoreMenu 1233:107735, LOCK-22). Rows by relation, the
## destructive ones in the danger colour; confirmations and done states are WP5 (P2, not built in P0):
##   default        Unfollow · Block · Report
##   close_friend   Unfollow · Remove Close Friend · Block · Report   (LOCK-22 2026-10-07: un-close, keep mutual; ProfileMoreMenu order)
##   blocked        Report                                            (the relation pill reads Blocked, button Unblock)
## Emits `picked(id)`.

signal picked(id: StringName)

const _W := 200.0
const _RADIUS := 14.0
const _PAD_Y := 6.0
const _ROW_H := 44.0
const _ROW_PAD := 16.0

static func rows_for(relation: StringName) -> Array:
	var block := {id = &"block", label = "Block", danger = true}
	var report := {id = &"report", label = "Report", danger = true}
	var unfollow := {id = &"unfollow", label = "Unfollow", danger = false}
	match relation:
		&"blocked": return [report]
		&"close_friend": return [unfollow, {id = &"remove_close_friend", label = "Remove Close Friend", danger = false}, block, report]
		_: return [unfollow, block, report]

func _init(relation: StringName = &"default") -> void:
	custom_minimum_size.x = _W
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
		.with_margins(0, _PAD_Y, 0, _PAD_Y))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	add_child(col)
	for r in rows_for(relation):
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = _ROW_H
		var label := UiKit.label(str(r.label), UiTokens.STYLE_BODY_B14, UiTokens.COLOR_DANGER if r.danger else UiTokens.COLOR_TEXT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = _ROW_PAD
		b.add_child(label)
		var id: StringName = r.id
		b.pressed.connect(func(): picked.emit(id))
		col.add_child(b)

func labels() -> Array:
	return get_child(0).get_children().map(func(b): return (b.get_child(0) as Label).text)
