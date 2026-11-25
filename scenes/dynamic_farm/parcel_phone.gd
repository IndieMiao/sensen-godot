extends UiPhone
## The dynamic farm's in-game phone (C-107; design C-85 ⑦ Inbox and ⑧ Phone, owner-approved; C-84 C-M1–C-M5): the
## kit's UiPhone with its three tabs, Tasks / Inbox / Collection (C-82#19: the concept's Updates tab became Collection).
##   Tasks       the first-visit guide's steps (ParcelTasks) under GET STARTED and TOWN: done rows ticked, struck
##               through and grey, the current one ringed in the action colour. Tapping the current row closes the
##               phone and shows that step's tip again (`task_pressed`); nothing else is new and no row gives a reward.
##   Inbox       Parcels · N / Updates (P0Inbox's rows and words over a P0-style view: `{inbox, bag}`); the parcel
##               save has no inbox, so the dynamic farm passes none and the page reads `No parcels` / `No updates yet`.
##   Collection  2-column category cards (icon, name, bar, `9/20`); a card opens its 4-column grid, got ones in colour
##               and the rest as silhouettes, ‹ back. Categories the package has no data for are not shown; with none
##               the page reads `Nothing collected yet` (the dynamic farm has no fish, dishes, cities or postcards).
## Empty pages say the shortest fact only (C-M5). Data in through refresh(); signals out.

signal task_pressed(key: String)
signal claim_requested(cmd: Dictionary)

const TASKS_TAB := 0
const INBOX_TAB := 1
const COLLECTION_TAB := 2
const TITLES := ["Tasks", "Inbox", "Collection"]
const NO_TASKS := "No tasks"
const NO_PARCELS := "No parcels"
const NO_UPDATES := "No updates yet"
const NOTHING_COLLECTED := "Nothing collected yet"
## Collection cards: 2 columns, 6 apart; the detail grid 4 columns.
const CARD_COLUMNS := 2
const GRID_COLUMNS := 4
const CARD_ICON := 40.0
const GRID_ICON := 34.0
const BAR_H := 5.0
## A got item's cell is drawn in colour, the rest as a 35 % black silhouette (C-85 ⑧-D).
const SILHOUETTE := Color(Color.BLACK, 0.35)
const ROW_ICON := 32.0
const DOT := 6.0

## ParcelTasks.rows: [{key, group, title, state: "done" | "current" | "todo"}].
var tasks: Array = []
## A P0-style inbox view: {inbox: {parcels, updates}, bag?: {capacity, slots | free}}; {} = nothing.
var inbox := {}
## [{id, name, icon, got, total, items: [{icon, got}]}].
var collection: Array = []
## "parcels" or "updates".
var inbox_segment := "parcels"
## The category whose grid shows (index into `collection`), -1 for the cards.
var category := -1

func _init() -> void:
	super([{"title": TITLES[0], "icon": UiArt.color("tab_tasks")}, {"title": TITLES[1], "icon": UiArt.color("tab_inbox")},
		{"title": TITLES[2], "icon": UiArt.color("tab_collection")}])
	name = "Phone"
	tab_selected.connect(func(i: int): if i != selected: show_tab(i, signi(i - selected)))
	back_pressed.connect(func():
		category = -1
		show_tab(COLLECTION_TAB, -1))

## New data; the page showing is rebuilt in place.
func refresh(tasks_: Array, inbox_ := {}, collection_: Array = []) -> void:
	tasks = tasks_
	inbox = inbox_
	collection = collection_.filter(func(c: Dictionary): return int(c.get("total", 0)) > 0)
	if category >= collection.size(): category = -1
	set_badge(INBOX_TAB, P0Inbox.badge(inbox) if not inbox.is_empty() else 0)
	if page != null: show_tab(selected, 0)

## Shows tab `index`'s page; `step` slides it in from that side (M-09), 0 in place.
func show_tab(index: int, step := 0) -> void:
	if index != COLLECTION_TAB: category = -1
	select(index, step != 0)
	match index:
		TASKS_TAB:
			set_head(TITLES[index])
			show_page(_tasks_page(), step)
		INBOX_TAB:
			set_head(TITLES[index])
			show_page(_inbox_page(), step)
		_:
			if category >= 0:
				var c: Dictionary = collection[category]
				set_head(str(c.name), true, "%d/%d" % [int(c.got), int(c.total)])
				show_page(_grid_page(c), step)
			else:
				set_head(TITLES[COLLECTION_TAB])
				show_page(_cards_page(), step)

# ------------------------------------------------------------------ Tasks

func _tasks_page() -> Control:
	if tasks.is_empty(): return _empty(NO_TASKS)
	var scroll := _scroll()
	var list := scroll.get_child(0) as VBoxContainer
	list.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S3))
	var group := ""
	for t: Dictionary in tasks:
		if str(t.group) != group:
			group = str(t.group)
			var head := UiKit.label(group, UiTokens.STYLE_TYPE_MICRO, UiTokens.COLOR_PHONE_TEXT_MUTED)
			head.name = "Group_" + group.replace(" ", "_")
			var pad := MarginContainer.new()
			pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pad.add_theme_constant_override(&"margin_left", int(UiTokens.SPACE_S2))
			pad.add_theme_constant_override(&"margin_top", 0 if list.get_child_count() == 0 else int(UiTokens.SPACE_S2))
			pad.add_child(head)
			list.add_child(pad)
		var state: UiTaskRow.State = UiTaskRow.State.DONE if t.state == "done" else UiTaskRow.State.CURRENT \
			if t.state == "current" else UiTaskRow.State.TODO
		var row := UiTaskRow.new(str(t.title), state, UiTaskRow.Look.PHONE)
		row.name = "Task_" + str(t.key)
		row.tappable = state == UiTaskRow.State.CURRENT
		var key := str(t.key)
		row.pressed.connect(func(): if not closing: task_pressed.emit(key))
		list.add_child(row)
	return scroll

# ------------------------------------------------------------------ Inbox

func _inbox_page() -> Control:
	var col := VBoxContainer.new()
	col.name = "InboxPage"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S4))
	var parcels := P0Inbox.parcel_rows(inbox) if not inbox.is_empty() else []
	var updates := P0Inbox.update_rows(inbox, Time.get_unix_time_from_system() * 1000.0) if not inbox.is_empty() else []
	var unread := updates.any(func(u: Dictionary): return u.unread)
	col.add_child(_segment(["Parcels · %d" % parcels.size() if not parcels.is_empty() else "Parcels", "Updates"],
		0 if inbox_segment == "parcels" else 1, unread, func(i: int):
			inbox_segment = "parcels" if i == 0 else "updates"
			show_tab(INBOX_TAB, 0)))
	var rows: Array = parcels if inbox_segment == "parcels" else updates
	if rows.is_empty():
		var empty := _empty(NO_PARCELS if inbox_segment == "parcels" else NO_UPDATES)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(empty)
		return col
	if inbox_segment == "parcels" and inbox.get("bag") is Dictionary:
		var room := UiKit.label(P0Inbox.capacity_line(inbox), UiTokens.STYLE_TYPE_MICRO,
			UiTokens.COLOR_BADGE_NOTIFY if P0Inbox._free(inbox) <= 0 else UiTokens.COLOR_PHONE_TEXT_MUTED)
		room.name = "Capacity"
		col.add_child(room)
	var scroll := _scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := scroll.get_child(0) as VBoxContainer
	list.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S2))
	for r: Dictionary in rows: list.add_child(_inbox_row(r))
	col.add_child(scroll)
	if inbox_segment == "parcels":
		var all := P0Inbox.claim_all(inbox)
		if not all.is_empty():
			var button := UiCommandButton.new(str(all.label) if not str(all.label).is_empty() else str(all.reason),
				UiCommandButton.Kind.PRIMARY, true)
			button.name = "ClaimAll"
			button.disabled = (all.keys as Array).is_empty()
			button.activated.connect(func(): claim_requested.emit({"type": "claim_parcels", "keys": all.keys}))
			col.add_child(button)
	return col

func _inbox_row(r: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.name = "Row_" + str(r.key)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PHONE_ROW, UiTokens.RADIUS_LG - 2)
		.with_margins(UiTokens.SPACE_S4, UiTokens.SPACE_S3 - 1, UiTokens.SPACE_S4, UiTokens.SPACE_S3 - 1))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S1))
	box.add_child(col)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S4))
	col.add_child(line)
	var icon := UiKit.icon(r.get("icon"), ROW_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var title := UiKit.label(str(r.title), UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_PHONE_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(title)
	if r.has("can_claim"):
		var claim := UiCommandButton.new("Claim", UiCommandButton.Kind.PRIMARY, true)
		claim.name = "Claim"
		claim.disabled = not bool(r.can_claim)
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var key := str(r.key)
		claim.activated.connect(func(): claim_requested.emit({"type": "claim_parcel", "key": key}))
		line.add_child(claim)
	# The source and time on their own line under the name and button, never cut (C-85 V-241 2).
	var sub := " · ".join([str(r.get("sub", "")), str(r.get("left", r.get("time", "")))].filter(func(s: String): return not s.is_empty()))
	if not sub.is_empty():
		var below := UiKit.label(sub, UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_PHONE_TEXT_MUTED)
		below.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(below)
	return box

## The page's two-part switch: `phone/row` pill, the chosen part raised on `phone/card`; an unread dot on part 1.
func _segment(labels: Array, chosen: int, dot: bool, pick: Callable) -> Control:
	var bar := PanelContainer.new()
	bar.name = "Segment"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PHONE_ROW, UiTokens.RADIUS_PILL)
		.with_margins(UiTokens.SPACE_S1 + 1, UiTokens.SPACE_S1 + 1, UiTokens.SPACE_S1 + 1, UiTokens.SPACE_S1 + 1))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	bar.add_child(row)
	for i in labels.size():
		var part := Button.new()
		part.name = "Part%d" % i
		part.text = str(labels[i])
		part.focus_mode = Control.FOCUS_NONE
		part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on := i == chosen
		var box := UiStyleBox.make(UiTokens.COLOR_PHONE_CARD if on else Color.TRANSPARENT, UiTokens.RADIUS_PILL)
		for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]: part.add_theme_stylebox_override(st, box)
		for slot in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
			part.add_theme_color_override(slot, UiTokens.COLOR_PHONE_TEXT if on else UiTokens.COLOR_PHONE_TEXT_MUTED)
		part.add_theme_font_override(&"font", UiKit.theme().get_font(&"font", UiTokens.STYLE_TYPE_MICRO))
		part.add_theme_font_size_override(&"font_size", UiKit.theme().get_font_size(&"font_size", UiTokens.STYLE_TYPE_MICRO) + 1)
		part.custom_minimum_size.y = UiTokens.SIZE_TODO_ROW_H
		part.pressed.connect(func(): if i != chosen and not closing: pick.call(i))
		row.add_child(part)
		if dot and i == 1:
			# Unread Updates: a red dot at the part's top right (C-85 ⑦-A).
			var mark := Panel.new()
			mark.name = "Unread"
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_BADGE_UNREAD, UiTokens.RADIUS_PILL))
			mark.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			mark.offset_left = -UiTokens.SPACE_S6 - DOT
			mark.offset_right = -UiTokens.SPACE_S6
			mark.offset_top = UiTokens.SPACE_S2
			mark.offset_bottom = UiTokens.SPACE_S2 + DOT
			part.add_child(mark)
	return bar

# ------------------------------------------------------------------ Collection

func _cards_page() -> Control:
	if collection.is_empty(): return _empty(NOTHING_COLLECTED)
	var scroll := _scroll()
	var list := scroll.get_child(0) as VBoxContainer
	var grid := GridContainer.new()
	grid.name = "Cards"
	grid.columns = CARD_COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override(&"h_separation", int(UiTokens.SPACE_S3))
	grid.add_theme_constant_override(&"v_separation", int(UiTokens.SPACE_S3))
	list.add_child(grid)
	for i in collection.size(): grid.add_child(_card(collection[i], i))
	return scroll

func _card(c: Dictionary, index: int) -> Control:
	var card := Button.new()
	card.name = "Card_" + str(c.get("id", index))
	card.focus_mode = Control.FOCUS_NONE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UiStyleBox.make(UiTokens.COLOR_PHONE_ROW, UiTokens.RADIUS_LG - 2)
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]: card.add_theme_stylebox_override(st, box)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: pad.add_theme_constant_override("margin_" + side, int(UiTokens.SPACE_S4))
	card.add_child(pad)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S2))
	pad.add_child(col)
	var icon := UiKit.icon(c.get("icon"), CARD_ICON)
	col.add_child(icon)
	col.add_child(UiKit.label(str(c.name), UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_PHONE_TEXT))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size.y = BAR_H
	bar.max_value = maxi(1, int(c.total))
	bar.value = int(c.got)
	bar.add_theme_stylebox_override(&"background", UiStyleBox.make(UiTokens.COLOR_PHONE_CARD, UiTokens.RADIUS_PILL))
	bar.add_theme_stylebox_override(&"fill", UiStyleBox.make(UiTokens.COLOR_PROGRESS_FILL, UiTokens.RADIUS_PILL))
	col.add_child(bar)
	col.add_child(UiKit.label("%d/%d" % [int(c.got), int(c.total)], UiTokens.STYLE_TYPE_MICRO, UiTokens.COLOR_PHONE_TEXT_MUTED))
	card.ready.connect(func(): card.custom_minimum_size.y = pad.get_combined_minimum_size().y)
	# C-85 ⑧ motion 4: the bar fills from 0 to its value over 400 once the page shows.
	if not UiMotion.reduced:
		var to := bar.value
		bar.value = 0
		card.ready.connect(func():
			var tw := UiMotion.tween(bar, UiTokens.MOTION_EASING_STANDARD)
			tw.tween_property(bar, "value", to, UiMotion.secs(UiTokens.MOTION_DURATION_SLOW_MS)))
	card.pressed.connect(func():
		if closing: return
		category = index
		show_tab(COLLECTION_TAB, 1))
	return card

func _grid_page(c: Dictionary) -> Control:
	var scroll := _scroll()
	var list := scroll.get_child(0) as VBoxContainer
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = GRID_COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override(&"h_separation", int(UiTokens.SPACE_S3))
	grid.add_theme_constant_override(&"v_separation", int(UiTokens.SPACE_S3))
	list.add_child(grid)
	var cell_side := (UiTokens.SIZE_PHONE_W - UiTokens.SIZE_PHONE_BEZEL * 2 - _BODY_SIDE * 2 - UiTokens.SPACE_S3 * (GRID_COLUMNS - 1)) / float(GRID_COLUMNS)
	for item: Dictionary in c.get("items", []):
		var cell := PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.custom_minimum_size = Vector2.ONE * cell_side
		cell.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PHONE_ROW, UiTokens.RADIUS_MD))
		var icon := UiKit.icon(item.get("icon"), GRID_ICON)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not bool(item.get("got", false)): icon.modulate = SILHOUETTE
		cell.add_child(icon)
		grid.add_child(cell)
	return scroll

# ------------------------------------------------------------------ Shared

func _scroll() -> TouchScrollContainer:
	var scroll := TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(list)
	return scroll

## The shortest fact, centred (C-M5): no picture, no explanation.
func _empty(text: String) -> Control:
	var label := UiKit.label(text, UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_PHONE_TEXT_MUTED)
	label.name = "Empty"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
