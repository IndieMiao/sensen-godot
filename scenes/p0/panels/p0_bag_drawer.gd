class_name P0BagDrawer
extends UiDrawer
## P0 Bag | Gear drawer (SGODOT-225; BAG-1-P0 / BAG-2-2 / BAG-2 · Gear; LOCK-12 / 13). Built from the kit:
##   quick_row   the drawer's first row is the quick bar (LOCK-12); the P0 UI puts its UiQuickBar here
##               (P0Ui.bind_quick_bar, SGODOT-221) and keeps it in step with the bottom bar.
##   header      UiBagHeader: Bag N/cap | Gear, Sort · Type / Recent (Bag side, per Tab), capacity bar.
##   Bag side    seven category chips (one capacity), a hint, the item-info card of the tapped cell
##               (UiInfoSheet, F-07 bag context; no Sell in the bag, no close button: tap another cell to
##               switch, a blank cell to fold it) and the five-column grid.
##   Gear side   `✓ Equipped`, six GearSlot cells, the tapped slot's candidates (Equipped / Equip / greyed
##               gate and source) and `Gear does not use Bag slots.`
## Everything shown comes from the server view through P0Logic / P0ItemInfo; buttons only report back
## (`action_requested`), the P0 UI sends the command.

signal action_requested(action: StringName, item_id: String, payload: Dictionary)
## A greyed card button was tapped (UiInfoSheet.unavailable_requested): the P0 UI may say why, e.g. Gift (225).
signal unavailable_requested(action: StringName, item_id: String, reason: String)
signal side_changed(side: String)
signal gear_slot_changed(key: String)

const HEIGHT := 546.0   # drawer top at y 254 of 800 (BAG-2-2)
const CATEGORIES := ["All", "Seeds", "Fish", "Produce", "Dishes", "Materials", "Tackle"]
const GEAR_SLOTS := ["farming", "fishing", "mining", "combat", "ring", "charm"]
## Tabs that also list Farm Storage stacks, after the bag's, while at home (§10.4.8, BAG-2-2; SGODOT-228 / 231).
const STORAGE_TABS := ["Seeds", "Materials", "Tackle"]
const _ROW_GAP := 8.0      # Bag layout spacers: 8 under the quick bar, under the header, above the grid
const _SMALL_GAP := 4.0
const _SLOT_LIST_GAP := 12.0
## Sort behind `Sort · …` (Bag side; 不知火舞 on SGODOT-225): Type is the default — by category in Tab order,
## then rarity high → low, count high → low, most recent first (§10); a tap switches to Recent (most recent
## first, the server's order) and back. Kept on this device for each Tab apart (BagHeader main, 安其拉 on 225);
## the quick bar and Gear are not sorted.
const SORTS := ["Type", "Recent"]
const _PREFS := "user://p0_ui.cfg"

var view := {}
var side := "bag"
var category := "All"
var sort := "Type"
var _sorts := {}   # Tab → Sort chosen this time (and in user://)
## Remember the Sort choice in user:// (off in tests).
var persist := true
var gear_slot := "fishing"
## `place` for the item-info rules ("home", "pond", "outpost").
var place := "home"
## The resident within reach for the bag card's Gift ({id, name, gifted_today}; {} when none, SGODOT-225).
var near := {}
## Pins of the current action's quick bar, for the info card's Pin / Unpin (kept by the P0 UI).
var pinned := func(_id: String) -> bool: return false
## True when Pin can't take this item: its bar has five pinned already (the card greys Pin, q(61)).
var bar_full := func(_id: String) -> bool: return false
## Gift drawer (RESIDENT-GIFT): {kind: "resident", id, name, likes}. The header becomes `Gift to <name>` and the
## count only (Bag side, no Gear: WP1b), the Dishes chip is preselected, and the card uses the &"gift" rules.
var gift_to := {}

var quick_row: MarginContainer
var header: UiBagHeader
var sheet: UiInfoSheet
var grid: UiInventoryGrid

var _key := 0   # hash of what the drawer shows; refresh() skips a view that changes none of it
var _bag_box: VBoxContainer
var _gear_box: VBoxContainer
var _chips: HBoxContainer
var _hint: Label
## BAG-5 "Bag capacity recovery" under the grid (Bag side, full bag, not while gifting).
var full_row: UiNoticeRow
var _full_gap: Control

func _init(view_: Dictionary = {}, side_ := "bag", focus := "", gift_to_ := {}) -> void:
	super(HEIGHT)
	view = view_
	gift_to = gift_to_
	side = "bag" if not gift_to.is_empty() else side_
	if not gift_to.is_empty():
		var title := UiKit.label("Gift to %s" % str(gift_to.get("name", "")), UiTokens.STYLE_C14_XB)
		body.add_child(title)
		if str(gift_to.get("likes", "")) != "":
			body.add_child(UiKit.label(str(gift_to.likes), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
		_gap(body, _ROW_GAP)
	# The quick bar goes here (P0Ui.bind_quick_bar, SGODOT-221); the row and its gap stay folded until it does.
	quick_row = MarginContainer.new()
	quick_row.visible = false
	quick_row.set_meta(UiDrawer.KEEP_INPUT, true)   # its slots drag to Pin / Remove; no swipe-close from them
	body.add_child(quick_row)
	var quick_gap := _gap(body, _ROW_GAP)
	quick_gap.visible = false
	quick_row.child_entered_tree.connect(func(_n):
		quick_row.visible = true
		quick_gap.visible = true)
	header = UiBagHeader.new(0, 25, UiBagHeader.Pane.BAG if side == "bag" else UiBagHeader.Pane.GEAR)
	header.side_changed.connect(func(s: int): set_side("bag" if s == 0 else "gear"))
	header.sort_pressed.connect(func(): set_sort(SORTS[(SORTS.find(sort) + 1) % SORTS.size()]))
	sort = saved_sort(category) if persist else SORTS[0]
	header.show_tabs = gift_to.is_empty()
	body.add_child(header)
	_bag_box = VBoxContainer.new()
	_bag_box.add_theme_constant_override(&"separation", 0)
	_bag_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_bag_box)
	_gear_box = VBoxContainer.new()
	_gear_box.add_theme_constant_override(&"separation", 0)
	body.add_child(_gear_box)
	_build_bag()
	if not gift_to.is_empty():
		var dishes := CATEGORIES.find("Dishes")
		(_chips.get_child(dishes) as Button).button_pressed = true
		set_category("Dishes")
	refresh(view_)
	if focus != "" and P0Logic.bag_count(view, focus) > 0: grid.select(focus)

## New server view: counts, cells and the open card follow it; the selection, filter and scroll stay. The P0 UI
## calls this every frame, so a view that changes nothing the drawer shows is skipped.
func refresh(view_: Dictionary, force := false) -> void:
	var key := [view_.get("bag", {}), view_.get("gear", {}), view_.get("storage", {}), int(view_.get("energy", {}).get("value", 0)),
		view_.get("meals", {}).get("used", 0), view_.get("homestead", {}).get("unlocks", {}), side].hash()
	view = view_
	if key == _key and not force: return
	_key = key
	var bag: Dictionary = view.get("bag", {})
	header.used = (bag.get("slots", []) as Array).size()
	header.capacity = int(bag.get("capacity", 25))
	header.sort_label = sort
	_bag_box.visible = side == "bag"
	_gear_box.visible = side == "gear"
	grid.capacity = int(bag.get("capacity", 25))
	grid.items = items()
	_hint.visible = not sheet.is_open()
	_hint.text = hint_for(category, not storage_items(view, category, place).is_empty())
	var full := bag_full_text(view) if gift_to.is_empty() else ""
	full_row.set_notice(full)
	full_row.visible = full != ""
	_full_gap.visible = full_row.visible
	if sheet.is_open(): sheet.refresh()
	if side == "gear": _build_gear()

func set_side(v: String) -> void:
	if v == side: return
	side = v
	header.side = UiBagHeader.Pane.BAG if v == "bag" else UiBagHeader.Pane.GEAR
	grid.clear_selection()
	refresh(view, true)
	side_changed.emit(v)

func set_category(v: String) -> void:
	category = v
	sort = str(_sorts.get(v, saved_sort(v) if persist else SORTS[0]))
	header.sort_label = sort
	grid.filter = func(it: Dictionary) -> bool: return in_category(it, category)
	grid.items = items()
	_hint.text = hint_for(category, not storage_items(view, category, place).is_empty())

func set_sort(v: String) -> void:
	sort = v
	_sorts[category] = v
	header.sort_label = v
	grid.items = items()
	if persist:
		var cfg := ConfigFile.new()
		cfg.load(_PREFS)
		cfg.set_value("bag_sort", category, v)
		cfg.save(_PREFS)

## The Sort kept for a Tab on this device; Type when none.
static func saved_sort(cat := "All") -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_PREFS) != OK: return SORTS[0]
	var v := str(cfg.get_value("bag_sort", cat, SORTS[0]))
	return v if v in SORTS else SORTS[0]

func set_gear_slot(v: String) -> void:
	if v == gear_slot: return
	gear_slot = v
	if side == "gear": _build_gear()
	gear_slot_changed.emit(v)

# ---------------------------------------------------------------- data

## Bag stacks as grid items: {id, icon, qty, rarity, kind}, in the chosen sort order, then Farm Storage stacks
## on the storage tabs.
func items() -> Array:
	return bag_items(view, sort) + storage_items(view, category, place)

## Farm Storage stacks for a tab: {id = "storage:<item>", item, icon, qty, kind, stored = true}. Only at home,
## only on Seeds / Materials / Tackle, and only when the server sends storage and the item-info rules have the
## storage card (capability gating: no dead cells).
static func storage_items(view: Dictionary, cat: String, at := "home") -> Array:
	if at != "home" or cat not in STORAGE_TABS or not view.has("storage") or &"storage" not in P0ItemInfo.CONTEXTS: return []
	var out := []
	for st in view.get("storage", {}).get("items", []):
		var id := str(st.get("id", ""))
		var it := {id = "storage:" + id, item = id, icon = P0Logic.icon(id), qty = int(st.get("qty", 0)), rarity = 0,
			kind = P0ItemInfo.kind_of(view, id), tab = P0ItemInfo.tab_of(view, id), stored = true}
		if in_category(it, cat): out.append(it)
	return out

## BAG-5: with every slot taken, where more room comes from — `Bag full · +5 slots at Homestead Lv3` while Bag
## Upgrade I is locked, `Bag full · +5 slots · Bag Upgrade I` once it is for sale; "" when the bag has room or no
## upgrade is left (the row only shows where it can lead somewhere).
static func bag_full_text(view: Dictionary) -> String:
	var bag: Dictionary = view.get("bag", {})
	var cap := int(bag.get("capacity", 25))
	if (bag.get("slots", []) as Array).size() < cap: return ""
	var state := str(view.get("homestead", {}).get("unlocks", {}).get("bag_upgrade_1", ""))
	var ups: Array = P0Logic.content().get("bag_upgrades", [])
	if ups.is_empty() or state in ["", "owned"]: return ""
	var up: Dictionary = ups[0]
	var more := int(up.get("capacity", cap)) - cap
	if more <= 0: return ""
	if state == "locked": return "Bag full · +%d slots at Homestead Lv%d" % [more, int(up.get("homestead", 0))]
	return "Bag full · +%d slots · %s" % [more, str(up.get("name", ""))]

## The line above the grid: `Materials · Bag first, then Farm Storage` when storage stacks follow.
static func hint_for(cat: String, has_storage: bool) -> String:
	return "%s · Bag first, then Farm Storage" % cat if has_storage else "Select an item to see its details."

static func bag_items(view: Dictionary, sort_by := "Type") -> Array:
	var out := []
	for s in view.get("bag", {}).get("slots", []):
		var id := str(s.get("id", ""))
		var it := P0Logic.item(view, id)
		out.append({id = id, icon = P0Logic.icon(str(it.get("base", id))), qty = int(s.get("qty", 0)),
			rarity = int(it.get("rarity", 0)) if id.begins_with("fish_") or id.begins_with("dish_") else 0,
			kind = P0ItemInfo.kind_of(view, id), tab = P0ItemInfo.tab_of(view, id)})
	if sort_by == "Type":
		var order := func(it: Dictionary) -> int:
			for i in CATEGORIES.size():
				if in_category(it, CATEGORIES[i]) and CATEGORIES[i] != "All": return i
			return CATEGORIES.size()
		# [category, -rarity, -count, arrival] ascending; arrival = server order (most recent first)
		var keyed := []
		for i in out.size(): keyed.append([order.call(out[i]), -int(out[i].rarity), -int(out[i].qty), i, out[i]])
		keyed.sort_custom(func(a, b) -> bool:
			for k in 4:
				if a[k] != b[k]: return a[k] < b[k]
			return false)
		out = keyed.map(func(k): return k[4])
	return out

## Tabs follow P0ItemInfo.tab_of (§10.4.2: compost on Seeds, torches on Materials, bait / rods / picks on Tackle).
static func in_category(it: Dictionary, cat: String) -> bool:
	return cat == "All" or StringName(cat.to_lower()) == it.get("tab", &"")

## The six Gear slots: {key, role, item, icon, name, empty}.
static func gear_slots(view: Dictionary) -> Array:
	var slots: Dictionary = view.get("gear", {}).get("slots", {})
	return GEAR_SLOTS.map(func(k: String) -> Dictionary:
		var id := _slot_item(slots, k)
		return {key = k, role = k.capitalize(), item = id, icon = P0Logic.icon(id) if id != "" else null,
			name = P0Logic.item_name(view, id) if id != "" else "Empty", empty = id == ""})

## Candidates for one slot as UiGearRow data. Rods come from the view (owned, equipped, gates); the other P0
## slots only hold their starter tool.
## The view list behind a slot that has candidates: rods (fishing), picks (mining, SGODOT-231).
const _SLOT_LISTS := {"fishing": "rods", "mining": "picks"}

static func gear_rows(view: Dictionary, key: String) -> Array:
	var out := []
	var list: Array = view.get("gear", {}).get(_SLOT_LISTS.get(key, ""), []) if _SLOT_LISTS.has(key) else []
	if not list.is_empty():
		for r in list:
			var id := str(r.id)
			var spec := P0ItemInfo.spec(view, id, &"gear")
			var facts: Array = spec.get("facts", [])
			var state: StringName = &"equipped" if r.get("equipped", false) else (&"owned" if r.get("owned", false) else StringName(facts[1] if facts.size() > 1 else "Locked"))
			var action := {}
			for b in spec.get("buttons", []):
				if StringName(b.get("id", &"")) != &"equipped": action = b
			var effect := str(facts[0]) if facts.size() > 0 else ""
			if not bool(spec.get("card", true)):   # no "<kind>/gear" rule yet (picks before SGODOT-224 adds it)
				if r.has("stone"): effect = "%d Stone per rock" % int(r.stone)   # LOCK-29 wording
				if r.get("owned", false) and not r.get("equipped", false): action = {id = &"equip", label = "Equip", kind = &"secondary"}
			out.append({id = id, icon = P0Logic.icon(id), title = str(spec.get("title", r.get("name", id))), state = state,
				effect = effect, action = action})
		return out
	var id := _slot_item(view.get("gear", {}).get("slots", {}), key)
	if id != "":
		out.append({id = id, icon = P0Logic.icon(id), title = P0Logic.item_name(view, id), state = &"equipped",
			effect = "Starter tool · better ones come later"})
	return out

## The item in a Gear slot ("" when empty; the view sends null for an empty slot).
static func _slot_item(slots: Dictionary, key: String) -> String:
	var raw = slots.get(key, null)
	return "" if raw == null else str(raw)

# ---------------------------------------------------------------- Bag side

func _build_bag() -> void:
	_gap(_bag_box, _SMALL_GAP)
	var strip := TouchScrollContainer.new()
	strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	strip.custom_minimum_size.y = UiTokens.SIZE_FILTER_TOUCH
	_chips = UiFilterChip.row(PackedStringArray(CATEGORIES), 0, func(i: int): set_category(CATEGORIES[i]))
	strip.add_child(_chips)
	_bag_box.add_child(strip)
	_gap(_bag_box, _SMALL_GAP)
	_hint = UiKit.label("Select an item to see its details.", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_bag_box.add_child(_hint)
	sheet = UiInfoSheet.new()
	sheet.rules = func(id: String, ctx: StringName, o: Dictionary) -> Dictionary: return P0ItemInfo.spec(view, id, ctx, o)
	sheet.action_requested.connect(func(a: StringName, id: String, p: Dictionary): action_requested.emit(a, id, p))
	sheet.unavailable_requested.connect(func(a: StringName, id: String, r: String): unavailable_requested.emit(a, id, r))
	_bag_box.add_child(sheet)
	_gap(_bag_box, _ROW_GAP)
	grid = UiInventoryGrid.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.on_select = func(it: Dictionary):
		if bool(it.get("stored", false)): sheet.open(str(it.item), &"storage", {place = place})
		elif gift_to.is_empty(): sheet.open(str(it.id), &"bag", {place = place, pinned = bool(pinned.call(str(it.id))),
			bar_full = bool(bar_full.call(str(it.id))), near = near})
		else: sheet.open(str(it.id), &"gift", {place = place, target = gift_to})
		_hint.visible = false
	grid.selection_cleared.connect(func():
		sheet.close()
		_hint.visible = true)
	_bag_box.add_child(grid)
	_full_gap = _gap(_bag_box, _ROW_GAP)
	full_row = UiNoticeRow.new()
	full_row.pressed.connect(func(): action_requested.emit(&"bag_room", "", {}))
	_bag_box.add_child(full_row)

# ---------------------------------------------------------------- Gear side

func _build_gear() -> void:
	for c in _gear_box.get_children(): c.queue_free()
	_gap(_gear_box, _ROW_GAP)
	_gear_box.add_child(UiGearRow.equipped_badge())
	_gap(_gear_box, _ROW_GAP)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
	for s in gear_slots(view):
		var cell := UiItemCell.new(UiItemCell.Density.GEAR)
		cell.role = s.role
		cell.title = s.name
		cell.icon = s.icon
		cell.state = UiItemCell.State.SELECTED if s.key == gear_slot else (UiItemCell.State.EMPTY if s.empty else UiItemCell.State.DEFAULT)
		var key: String = s.key
		cell.tapped.connect(func(): set_gear_slot(key))
		row.add_child(cell)
	_gear_box.add_child(row)
	_gap(_gear_box, _SLOT_LIST_GAP)
	_gear_box.add_child(UiKit.label("%s slot" % gear_slot.capitalize(), UiTokens.STYLE_C12_XB))
	_gap(_gear_box, _SMALL_GAP)
	var rows := gear_rows(view, gear_slot)
	for d in rows:
		var r := UiGearRow.new(d)
		var id := str(d.id)
		r.action_pressed.connect(func(a: StringName): action_requested.emit(a, id, {}))
		_gear_box.add_child(r)
	if rows.is_empty():
		_gear_box.add_child(UiKit.label("Nothing for this slot yet.", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	_gap(_gear_box, _ROW_GAP)
	_gear_box.add_child(UiKit.label("Gear does not use Bag slots.", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))

static func _gap(parent: Control, h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(g)
	return g
