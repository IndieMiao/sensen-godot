class_name UiPotCard
extends PanelContainer
## The pot card under the 3D pot (SGODOT-256 ⑤ A', LOCK-20; Figma Review row 53 1913:32854, "Pot strip"): the slots
## (UiPotSlot, 20 apart) and under them one result line, PotResultLine 1913:32882 — the dish name (`Unknown dish` for
## an unknown mix, `Tried before` for a mix that failed, `?` with only seasonings in) in C13 ExtraBold, its rarity dot
## (no rarity word) and `· 15 s` in C12 Bold secondary. No status line: whether the pot can start is the Cook / Queue
## button's (greyed with the reason). Surface, radius 16, the float shadow, 10 inside, 8 between the slots and the line:
## 92 high with the line, 64 without it (an empty pot). As wide as its widest row; the owner centres it on the pot axis.

const PAD := 10.0
const RADIUS := 16.0
const SLOT_GAP := 20
const LINE_GAP := 8
const LINE_H := 20.0
const _LINE_SEP := 6
const _DOT := 8.0
const _DOT_RING := 1.5
const RARITY_COLORS := UiItemCell.RARITY_COLORS

var _slots: HBoxContainer
var _line: HBoxContainer
var _title: Label
var _dot: Panel
var _sep: Label
var _time: Label
## A small secondary tag at the card's top right (`×2` while Big Pot Double is on, 不知火舞 02ad95bc ④); "" hides it.
var tag := "": set = set_tag
var _tag: Label
var _tag_layer: Control

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, RADIUS).with_margins(PAD, PAD, PAD, PAD)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	add_theme_stylebox_override(&"panel", box)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", LINE_GAP)
	add_child(col)
	_slots = HBoxContainer.new()
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override(&"separation", SLOT_GAP)
	col.add_child(_slots)
	_line = HBoxContainer.new()
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.alignment = BoxContainer.ALIGNMENT_CENTER
	_line.custom_minimum_size.y = LINE_H
	_line.add_theme_constant_override(&"separation", _LINE_SEP)
	col.add_child(_line)
	_title = UiKit.label("", UiTokens.STYLE_C13_XB, UiTokens.COLOR_TEXT)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.add_child(_title)
	_dot = Panel.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.custom_minimum_size = Vector2(_DOT, _DOT)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line.add_child(_dot)
	_sep = UiKit.label("·", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	_sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.add_child(_sep)
	_time = UiKit.label("", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.add_child(_time)
	show_result("")
	# The panel fits its children to its content box; the tag lives on a plain layer there, placed by hand.
	_tag_layer = Control.new()
	_tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_layer.visible = false   # only while a tag shows (the layout snapshots stay as they were)
	add_child(_tag_layer)
	_tag = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_tag.name = "Tag"
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.visible = false
	_tag_layer.add_child(_tag)
	_tag_layer.resized.connect(_place_tag)

func set_tag(v: String) -> void:
	tag = v
	if _tag == null: return
	_tag.text = v
	_tag.visible = v != ""
	_tag_layer.visible = v != ""
	_place_tag()

## The tag sits in the card's top-right corner, over the 10 padding; it takes no layout room.
func _place_tag() -> void:
	if _tag == null or _tag_layer == null: return
	var m := _tag.get_minimum_size()
	_tag.size = m
	_tag.position = Vector2(_tag_layer.size.x + PAD - m.x - 6.0, -PAD + 3.0)

## The tag's rect in the card's coordinates (tests).
func tag_rect() -> Rect2: return Rect2(_tag_layer.position + _tag.position, _tag.size) if _tag and _tag.visible else Rect2()

## Replaces the slots (UiPotSlot, built and wired by the owner).
func set_slots(slots: Array) -> void:
	for c in _slots.get_children():
		_slots.remove_child(c)
		c.queue_free()
	for s in slots: _slots.add_child(s)
	reset_size()

func slots() -> Array: return _slots.get_children()

## The result line: `title` "" hides it (the card shrinks to its slots); `rarity` 0 drops the dot, `time` "" the time.
func show_result(title: String, rarity := 0, time := "") -> void:
	_title.text = title
	_line.visible = title != ""
	_dot.visible = rarity > 0
	if rarity > 0:
		# RarityDot 1178:82149: a white ring; Legendary's light gold keeps a gold-ink ring so it shows on cream.
		_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(RARITY_COLORS[clampi(rarity - 1, 0, 3)], _DOT * 0.5,
			UiTokens.COLOR_GOLD_INK if rarity >= 4 else UiTokens.COLOR_SURFACE_RAISED, _DOT_RING))
	_time.text = time
	_time.visible = time != ""
	_sep.visible = _time.visible
	reset_size()

func result_title() -> String: return _title.text if _line.visible else ""
func result_time() -> String: return _time.text if _line.visible and _time.visible else ""
func result_rarity_shown() -> bool: return _line.visible and _dot.visible
