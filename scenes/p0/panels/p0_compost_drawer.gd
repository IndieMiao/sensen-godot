class_name P0CompostDrawer
extends UiDrawer
## The Compost Bin's drawer (COMPOST-BIN 2231:122380, COMPOST-BIN-LIMIT 2231:122659; q(118) ③, q(121); 不知火舞 on 241):
## LOCK-15's counter + bag with the bag half only. Top to bottom:
##   head    `Compost Bin` + Close — no keeper bar: nobody tends it and nothing is sold
##   bag     `Bag 19/25` and its capacity track
##   scope   the `Crops` chip (a label, the one scope) and the day's line on the right: `Compost today 2/5` over
##           `resets in 9h 12m`; red `Limit reached` over `resets in 9h 12m` once the day's 5 are in
##   card    the selected crop (UiInfoSheet): `Compost 1` / `Compost All · 3` (all of it the day still takes), or the grey
##           `Limit reached · 9h 12m` at the cap (q(121))
##   grid    the five-column grid of the bag's crops — any crop, regional and fruit too
## Everything comes from the server view (bag, compost); buttons only report (`compost_requested`), the P0 UI sends.

signal compost_requested(item_id: String, qty: int)
signal info_requested(item_id: String)
## A grey button was tapped: the P0 UI toasts its words (LOCK-10).
signal unavailable_requested(reason: String)

const HEIGHT := 356.0           # COMPOST-BIN: the drawer's top at y 444 of 800
const _GAP := 8.0
const _SMALL := 4.0
const _TRACK := Vector2(110, 3)
const _SCOPE_H := 36.0

var view := {}
var sheet: UiInfoSheet
var grid: UiInventoryGrid
var _count: Label
var _cap_track: P0CounterDrawer._Track
var _quota: Label
var _key := 0

func _init(view_: Dictionary = {}) -> void:
	super(HEIGHT)
	view = view_
	var h := HBoxContainer.new()
	var title := UiKit.label("Compost Bin", UiTokens.STYLE_C14_XB)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(title)
	var close := UiCloseButton.new()
	close.pressed.connect(func(): close_requested.emit())
	h.add_child(close)
	body.add_child(h)
	_gap(body, _GAP)
	var line := ColorRect.new()
	line.color = UiTokens.COLOR_BORDER
	line.custom_minimum_size.y = 1.0
	body.add_child(line)
	_gap(body, _SMALL + 1.0)
	var cap := HBoxContainer.new()
	cap.custom_minimum_size.y = 24.0
	cap.add_theme_constant_override(&"separation", int(_GAP))
	var label := UiKit.label("Bag", UiTokens.STYLE_C14_XB)
	label.custom_minimum_size.x = 38.0
	cap.add_child(label)
	_count = UiKit.label("", UiTokens.STYLE_C12_XB)
	_count.custom_minimum_size.x = 50.0
	cap.add_child(_count)
	_cap_track = P0CounterDrawer._Track.new()
	_cap_track.custom_minimum_size = _TRACK
	_cap_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(_cap_track)
	body.add_child(cap)
	_gap(body, 2.0)
	var scope := HBoxContainer.new()
	scope.custom_minimum_size.y = _SCOPE_H
	scope.add_theme_constant_override(&"separation", 12)
	var chip := UiFilterChip.new("Crops", true)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE   # one scope: a label, not a filter
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scope.add_child(chip)
	_quota = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	_quota.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quota.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quota.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scope.add_child(_quota)
	body.add_child(scope)
	_gap(body, _SMALL)
	sheet = UiInfoSheet.new()
	sheet.rules = func(id: String, _c: StringName, _o: Dictionary) -> Dictionary: return spec(view, id)
	sheet.action_requested.connect(func(a: StringName, id: String, p: Dictionary):
		if a == &"compost": compost_requested.emit(id, int(p.get("qty", 1))))
	sheet.info_requested.connect(func(id: String): info_requested.emit(id))
	sheet.unavailable_requested.connect(func(_a: StringName, _id: String, r: String): unavailable_requested.emit(r))
	body.add_child(sheet)
	_gap(body, _SMALL)
	grid = UiInventoryGrid.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.filter = func(it: Dictionary) -> bool: return str(it.get("kind", "")) == "crop"
	grid.on_select = func(it: Dictionary): select(str(it.id))
	grid.selection_cleared.connect(func(): sheet.close())
	body.add_child(grid)
	refresh(view_, true)

func _restyle() -> void:   # the title row sits right under the top edge, as the Homestead Stall's (FARM-6)
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 0.0)
	box.corner_radius = Vector4(UiTokens.RADIUS_SHEET, UiTokens.RADIUS_SHEET, 0.0, 0.0)
	add_theme_stylebox_override(&"panel", box.with_margins(pad, 0.0, pad, safe_bottom))

func action_area() -> Control: return sheet if sheet != null and sheet.is_visible_in_tree() else null

static func _gap(parent: Control, h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(g)

## New server view: counts, the day's line, the grid and the open card follow it; the selection stays.
func refresh(view_: Dictionary, force := false) -> void:
	var key := [view_.get("bag", {}), view_.get("compost", null)].hash()
	view = view_
	if key == _key and not force: return
	_key = key
	var bag: Dictionary = view.get("bag", {})
	var used := (bag.get("slots", []) as Array).size()
	var capacity := int(bag.get("capacity", 25))
	_count.text = "%d/%d" % [used, capacity]
	_cap_track.fill = clampf(float(used) / maxf(1.0, float(capacity)), 0.0, 1.0)
	_cap_track.queue_redraw()
	grid.capacity = capacity
	grid.items = P0BagDrawer.bag_items(view)
	if grid.selected_id != "" and P0Logic.bag_count(view, grid.selected_id) <= 0:
		grid.clear_selection()   # the whole stack went in
	if sheet.is_open(): sheet.refresh()
	var q := quota(view)
	_quota.text = str(q.text)
	_quota.add_theme_color_override(&"font_color", UiTokens.COLOR_DANGER if bool(q.full) else UiTokens.COLOR_SECONDARY)

func select(id: String) -> void:
	sheet.open(id, &"bag", {})

## The day's line: `Compost today 2/5` / `resets in 9h 12m`, or red `Limit reached` / `resets in 9h 12m` (q(121)).
static func quota(view: Dictionary) -> Dictionary:
	var q = view.get("compost", null)
	if not q is Dictionary: return {text = "", full = false}
	var resets := "resets in " + P0Logic.span(float(q.get("resets_in", 0)))
	if int(q.get("left", 0)) <= 0: return {text = "Limit reached\n" + resets, full = true}
	return {text = "Compost today %d/%d\n%s" % [int(q.get("used", 0)), int(q.get("cap", 5)), resets], full = false}

## The selected crop's card: its name, `Crop`, its count; `Compost 1` and `Compost All · N` (N: what the bag holds of
## it, at most what the day still takes), or the grey `Limit reached · 9h 12m` at the cap (q(121)).
static func spec(view: Dictionary, id: String) -> Dictionary:
	var q = view.get("compost", null)
	var left := int(q.get("left", 0)) if q is Dictionary else 0
	var have := P0Logic.bag_count(view, id)
	var buttons: Array = []
	if left <= 0:
		buttons.append({id = &"limit", label = "Limit reached · " + P0Logic.span(float(q.get("resets_in", 0)) if q is Dictionary else 0.0),
			kind = &"unavailable", payload = {}})
	else:
		var n := mini(have, left)
		buttons.append({id = &"compost", label = "Compost 1", kind = &"secondary", payload = {qty = 1}})
		buttons.append({id = &"compost", label = "Compost All · %d" % n, kind = &"primary", payload = {qty = n}})
	return {card = have > 0, id = id, kind = "crop", icon = P0Logic.icon(id), title = P0Logic.item_name(view, id), quantity = have,
		info = true, rarity = 0, rarity_text = "", quality = 0, region = "", badge = &"", facts = ["Crop"], buttons = buttons,
		lock = {shown = false, locked = false}, price = {}, quota = {}}
