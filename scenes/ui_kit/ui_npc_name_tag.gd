class_name UiNpcNameTag
extends PanelContainer
## NPC name tag (SGODOT-250; NpcNameTag 1674:101195, LOCK-16 v2): an interactable NPC carries only its name over the
## head (Sigrid / Ama / Pip / Mei / Finn) — no Talking, no Tap to talk. Surface pill, 1 px color/border edge, soft
## shadow, padding 10 / 4, Caption ExtraBold 12. Highlight (nearest within reach, or in a conversation): 2 px
## color/primary edge and 1.1× around its centre. NPCs you cannot talk to carry no tag. Display only.

const _HIGHLIGHT_SCALE := 1.1

var text := "": set = set_text
var highlight := false: set = set_highlight

var _label: Label
var _head := Vector2.INF   # where place_over put it; it re-sits there when its size settles (theme, name)

func _init(name_ := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", UiTokens.STYLE_CAPTION_XB12, UiTokens.COLOR_TEXT)
	add_child(_label)
	# Measured before the theme reaches it the pill comes out too big and never shrinks back by itself.
	minimum_size_changed.connect(_resit)
	text = name_
	_refresh()

func set_text(v: String) -> void:
	text = v
	if _label: _label.text = v

func set_highlight(v: bool) -> void: highlight = v; _refresh()

## Centre the tag horizontally over `head` (a screen point above the NPC), sitting on it.
func place_over(head: Vector2) -> void:
	_head = head
	_resit()

func _resit() -> void:
	reset_size()
	var s := get_combined_minimum_size()
	pivot_offset = s * 0.5
	if _head != Vector2.INF: position = Vector2(_head.x - s.x * 0.5, _head.y - s.y)

func _refresh() -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 12.0,
		UiTokens.COLOR_PRIMARY if highlight else UiTokens.COLOR_BORDER, UiTokens.STROKE_SELECTED if highlight else UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 3)
	# Padding 10 / 4 outside the text, inside the edge (49 × 26; the 2 px Highlight edge makes it 51 × 28). Godot's line
	# box for Caption 12 is 18 against Figma's 16, so the vertical padding gives back 1 px a side.
	var edge := float(UiTokens.STROKE_SELECTED if highlight else UiTokens.STROKE_DEFAULT)
	box.with_margins(10.0 + edge, 3.0 + edge, 10.0 + edge, 3.0 + edge)
	add_theme_stylebox_override(&"panel", box)
	scale = Vector2.ONE * (_HIGHLIGHT_SCALE if highlight else 1.0)
