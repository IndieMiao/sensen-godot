class_name UiBagHeader
extends VBoxContainer
## Bag drawer header (SGODOT-225; BagHeader 1225:83885, LOCK-12 / 13): the Bag | Gear switch (the Bag segment
## carries the count, `Bag 19/25`), `Sort · …` on the Bag side only, and a capacity bar under the Bag segment that
## turns amber at 90 % (§10.4.1). The gift drawer hides the switch and shows the count as a plain title
## (`show_tabs = false`, WP1b: a gift is always from the Bag side).
## Emits `side_changed(side)` (0 Bag, 1 Gear) and `sort_pressed`.

signal side_changed(side: int)
signal sort_pressed

enum Pane { BAG, GEAR }

# BagHeader main (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _SWITCH_W := 220.0      # Bag | Gear switch width
const _ROW_GAP := 8.0         # switch → Sort
const _BAR := Vector2(100, 4) # capacity bar under the Bag segment …
const _BAR_X := 6.0           # … 6 in from the switch's left edge
const _FULL_AT := 0.9         # amber from 90 % (§10.4.1)

var side: Pane = Pane.BAG: set = set_side
var used := 0: set = set_used
var capacity := 25: set = set_capacity
## Sort label after `Sort · `, e.g. "Recent" / "Type"; "" hides Sort.
var sort_label := "Recent": set = set_sort_label
var show_tabs := true: set = set_show_tabs

var _tabs: UiSegmentTab
var _title: Label
var _sort: UiNavButton
var _bar: _Bar

func _init(used_ := 0, capacity_ := 25, side_: Pane = Pane.BAG) -> void:
	add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(_ROW_GAP))
	add_child(row)
	_tabs = UiSegmentTab.new(["Bag", "Gear"], side_)
	_tabs.custom_minimum_size.x = _SWITCH_W
	_tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tabs.changed.connect(func(i: int):
		side = i as Pane
		side_changed.emit(i))
	row.add_child(_tabs)
	_title = UiKit.label("", UiTokens.STYLE_C14_XB)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_sort = UiNavButton.new("", true)
	_sort.pressed.connect(func(): sort_pressed.emit())
	row.add_child(_sort)
	var bar_row := MarginContainer.new()
	bar_row.add_theme_constant_override(&"margin_left", int(_BAR_X))
	add_child(bar_row)
	_bar = _Bar.new()
	_bar.custom_minimum_size = _BAR
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar_row.add_child(_bar)
	used = used_
	capacity = capacity_
	side = side_
	sort_label = sort_label
	show_tabs = show_tabs

func set_side(v: Pane) -> void:
	side = v
	if _tabs == null: return
	if _tabs.selected != int(v): _tabs.selected = int(v)
	_refresh()

func set_used(v: int) -> void: used = v; _refresh()
func set_capacity(v: int) -> void: capacity = v; _refresh()
func set_sort_label(v: String) -> void: sort_label = v; _refresh()
func set_show_tabs(v: bool) -> void: show_tabs = v; _refresh()

func fill() -> float: return clampf(float(used) / maxf(1.0, float(capacity)), 0.0, 1.0)
func is_nearly_full() -> bool: return fill() >= _FULL_AT
func tabs() -> UiSegmentTab: return _tabs
func sort_button() -> UiNavButton: return _sort

func _refresh() -> void:
	if _bar == null: return
	var count := "Bag %d/%d" % [used, capacity]
	# The Bag segment shows the count; the label node of the first tab is "Title" (UiSegmentTab).
	var first: Label = _tabs.tabs()[0].find_child("Title", true, false)
	if first != null: first.text = count
	_tabs.visible = show_tabs
	_title.visible = not show_tabs
	_title.text = count
	var bag := side == Pane.BAG
	_sort.visible = bag and show_tabs and sort_label != ""
	_sort.label = "Sort · " + sort_label
	_bar.get_parent().visible = bag
	_bar.fill = fill()
	_bar.amber = is_nearly_full()
	_bar.queue_redraw()

class _Bar extends Control:
	var fill := 0.0
	var amber := false

	func _draw() -> void:
		draw_style_box(UiStyleBox.make(UiTokens.COLOR_BORDER, UiTokens.RADIUS_TRACK), Rect2(Vector2.ZERO, size))
		if fill > 0.0:
			draw_style_box(UiStyleBox.make(UiTokens.COLOR_AMBER if amber else UiTokens.COLOR_PRIMARY, UiTokens.RADIUS_TRACK),
				Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * fill), size.y)))
