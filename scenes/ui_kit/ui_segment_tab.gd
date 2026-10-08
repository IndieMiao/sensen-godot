class_name UiSegmentTab
extends PanelContainer
## SegmentedTabs 1225:83884 (SGODOT-212 / 225; LOCK-13): the 2–3 way mode switch (WP7-C F-05) — `Bag | Gear`
## (LOCK-13), `Cookbook 4/48 | Experiment` (LOCK-20), `To do | Parcels | Updates` (LOCK-14). A border-coloured track
## 34 high (padding 3, gap 2, radius 17); the selected segment is white with a primary outline and an ExtraBold 12
## primary label, the others Bold 12 secondary on the track — never the command green (LOCK-13). Segments draw 28
## high and take touches 44 high (安其拉's design check on 225). Options are {label, count?}; `changed(index)` fires
## when the player picks another option.

signal changed(index: int)

# SegmentedTabs main (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _TRACK_H := 34.0
const _TRACK_PAD := 3.0
const _TRACK_GAP := 2
const _TRACK_RADIUS := 17.0

var selected := 0: set = set_selected

var _group := ButtonGroup.new()
var _tabs: Array[Button] = []
var _row: HBoxContainer

func _init(options: Array = [], selected_ := 0) -> void:
	custom_minimum_size.y = _TRACK_H
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_BORDER, _TRACK_RADIUS)
		.with_margins(_TRACK_PAD, _TRACK_PAD, _TRACK_PAD, _TRACK_PAD))
	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", _TRACK_GAP)
	add_child(_row)
	for o in options: _add_option(o if o is Dictionary else {label = str(o)})
	selected = selected_

func tabs() -> Array[Button]: return _tabs

func set_selected(v: int) -> void:
	selected = clampi(v, 0, maxi(0, _tabs.size() - 1))
	# set_pressed_no_signal does not release the other buttons of the group, so set every tab.
	for i in _tabs.size(): _tabs[i].set_pressed_no_signal(i == selected)
	_recolor()

func _add_option(o: Dictionary) -> void:
	var tab := _Segment.new()
	tab.focus_mode = Control.FOCUS_NONE
	tab.theme_type_variation = UiTokens.BUTTON_SEGMENT_TAB
	tab.toggle_mode = true
	tab.button_group = _group
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.custom_minimum_size.x = UiTokens.SIZE_TOUCH
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := UiKit.label(str(o.get("label", "")), UiTokens.STYLE_C12_B)
	title.name = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	if str(o.get("count", "")) != "":
		var count := UiKit.label(str(o.count), UiTokens.STYLE_C10_B)
		count.name = "Count"
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(count)
	tab.add_child(row)
	var index := _tabs.size()
	tab.toggled.connect(func(on: bool):
		if not on: return
		selected = index
		changed.emit(index))
	_tabs.append(tab)
	_row.add_child(tab)

func _recolor() -> void:
	for i in _tabs.size():
		var on := i == selected
		var ink := UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_SECONDARY
		for l in _tabs[i].get_child(0).get_children():
			(l as Label).add_theme_color_override(&"font_color", ink)
			if l.name == "Title": l.theme_type_variation = UiTokens.STYLE_C12_XB if on else UiTokens.STYLE_C12_B

## A segment: draws inside the 28 track lane, takes touches 44 high around it.
class _Segment extends Button:
	func _has_point(point: Vector2) -> bool:
		var grow := Vector2(maxf(0.0, UiTokens.SIZE_TOUCH - size.x), maxf(0.0, UiTokens.SIZE_TOUCH - size.y)) * 0.5
		return Rect2(-grow, size + grow * 2.0).has_point(point)
