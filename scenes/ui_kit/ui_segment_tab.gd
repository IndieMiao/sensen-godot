class_name UiSegmentTab
extends HBoxContainer
## SegmentTab (SGODOT-212): Tab 483:322 and Compact/Kitchen/Mode 655:58504 merged into one 2–3 way mode
## switch (WP7-C F-05): `Bag | Gear` (LOCK-13), `Cookbook 4/48 | Experiment` (LOCK-20), `To do | Parcels |
## Updates` (LOCK-14). Selected uses the SegmentTab theme look, never the command green (LOCK-13).
## Options are {label, count?}; `changed(index)` fires when the player picks another option.

signal changed(index: int)

var selected := 0: set = set_selected

var _group := ButtonGroup.new()
var _tabs: Array[Button] = []

func _init(options: Array = [], selected_ := 0) -> void:
	add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	for o in options: _add_option(o if o is Dictionary else {label = str(o)})
	selected = selected_

func tabs() -> Array[Button]: return _tabs

func set_selected(v: int) -> void:
	selected = clampi(v, 0, maxi(0, _tabs.size() - 1))
	if selected < _tabs.size(): _tabs[selected].set_pressed_no_signal(true)
	_recolor()

func _add_option(o: Dictionary) -> void:
	var tab := Button.new()
	tab.focus_mode = Control.FOCUS_NONE
	tab.theme_type_variation = UiTokens.BUTTON_SEGMENT_TAB
	tab.toggle_mode = true
	tab.button_group = _group
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_SEGMENT_TAB)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := UiKit.label(str(o.get("label", "")), UiTokens.STYLE_BODY_B14)
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
	add_child(tab)

func _recolor() -> void:
	for i in _tabs.size():
		var ink := UiTokens.COLOR_PRIMARY if i == selected else UiTokens.COLOR_SECONDARY
		for l in _tabs[i].get_child(0).get_children():
			(l as Label).add_theme_color_override(&"font_color", ink)
