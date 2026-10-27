class_name UiNpcNameTag
extends PanelContainer
## NPC name tag (SGODOT-250; NpcNameTag 1674:101195, LOCK-16 v2): an interactable NPC carries only its name over the
## head (Sigrid / Ama / Pip / Mei / Finn) — no Talking, no Tap to talk. Surface pill, 1 px color/border edge, soft
## shadow, padding 10 / 4, Caption ExtraBold 12. Highlight (nearest within reach, or in a conversation): 2 px
## color/primary edge and 1.1× around its centre. NPCs you cannot talk to carry no tag. It takes no input itself: the
## host checks hit_rect() and a tap on it is a tap on its NPC (P0Ui._tap_at, like the facility icon buttons).

const _HIGHLIGHT_SCALE := 1.1

var text := "": set = set_text
var highlight := false: set = set_highlight

var status := -1: set = set_status
var _badge: UiStatusBadge
var _label: Label
var _head := Vector2.INF   # where place_over put it; it re-sits there when its size settles (theme, name)

func _init(name_ := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", UiTokens.STYLE_CAPTION_XB12, UiTokens.COLOR_TEXT)
	add_child(_label)
	# A CanvasItem host inherits the name tag's transform without PanelContainer laying out another label.
	var mark_host := Node2D.new()
	add_child(mark_host)
	_badge = UiStatusBadge.new()
	_badge.size_kind = UiStatusBadge.Size.NPC
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	mark_host.add_child(_badge)
	# Measured before the theme reaches it the pill comes out too big and never shrinks back by itself.
	minimum_size_changed.connect(_resit)
	text = name_
	_refresh()

# Hosts set these every frame (P0Ui.npc_tag): an unchanged value does nothing.
func set_text(v: String) -> void:
	if v == text: return
	text = v
	if _label: _label.text = v

func set_highlight(v: bool) -> void:
	if v == highlight: return
	highlight = v; _refresh()

## 340 row 105: reuse the existing 36 px NPC StatusBadge above the unchanged name pill.
func set_status(v: int) -> void:
	if v == status: return
	status = v
	if _badge == null: return
	_badge.visible = status >= 0
	if status >= 0: _badge.state = status as UiStatusBadge.State
	_resit()

## Centre the tag horizontally over `head` (a screen point above the NPC), sitting on it.
func place_over(head: Vector2) -> void:
	_head = head
	_resit()

## The tag's touch area (global): the pill grown to the 44 px touch size around its centre (26 px tall as drawn). Players
## tap a name to talk to that NPC (李元芳 int10c: Pip's name, just below Sigrid behind the counter, opened Sigrid).
func hit_rect() -> Rect2:
	var r := get_global_rect()
	if _badge != null and _badge.visible: r = r.merge(_badge.get_global_rect())
	var gx := maxf(0.0, (UiTokens.SIZE_TOUCH - r.size.x) * 0.5)
	var gy := maxf(0.0, (UiTokens.SIZE_TOUCH - r.size.y) * 0.5)
	return r.grow_individual(gx, gy, gx, gy)

func _resit() -> void:
	reset_size()
	var s := get_combined_minimum_size()
	pivot_offset = s * 0.5
	if _badge != null:
		_badge.reset_size()
		_badge.position = Vector2((s.x - _badge.size.x) * 0.5, -_badge.size.y - UiTokens.SPACE_WITHIN)
	if _head != Vector2.INF: position = Vector2(_head.x - s.x * 0.5, _head.y - s.y)

func _refresh() -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 12.0,
		UiTokens.COLOR_PRIMARY if highlight else UiTokens.COLOR_BORDER, UiTokens.STROKE_SELECTED if highlight else UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	# Padding 10 / 4 outside the text, inside the edge (49 × 26; the 2 px Highlight edge makes it 51 × 28). Godot's line
	# box for Caption 12 is 18 against Figma's 16, so the vertical padding gives back 1 px a side.
	var edge := float(UiTokens.STROKE_SELECTED if highlight else UiTokens.STROKE_DEFAULT)
	box.with_margins(10.0 + edge, 3.0 + edge, 10.0 + edge, 3.0 + edge)
	add_theme_stylebox_override(&"panel", box)
	scale = Vector2.ONE * (_HIGHLIGHT_SCALE if highlight else 1.0)
