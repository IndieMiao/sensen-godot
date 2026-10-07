class_name UiFilterChip
extends Button
## Compact/Filter 633:41280 (SGODOT-212): toggle chip for one-of-many filters, e.g. the bag Tabs All / Seeds /
## Fish … (LOCK-12). The 26 px pill is drawn centred in a 44 px hit area (UiStyleBox.visual_height); the
## selected look is the toggle's pressed state. Put chips of one row in a ButtonGroup (UiFilterChip.row).
## Emits Button `toggled` / `pressed`.

func _init(text_: String = "", selected := false) -> void:
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = UiTokens.BUTTON_FILTER_CHIP
	toggle_mode = true
	text = text_
	button_pressed = selected
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.ensure_hit_area(self)

## A row of chips sharing one ButtonGroup; `picked(index)` fires when the selection changes.
static func row(labels: PackedStringArray, selected := 0, picked: Callable = Callable()) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	var group := ButtonGroup.new()
	for i in labels.size():
		var chip := UiFilterChip.new(labels[i], i == selected)
		chip.button_group = group
		if picked.is_valid():
			chip.toggled.connect(func(on: bool): if on: picked.call(i))
		h.add_child(chip)
	return h
