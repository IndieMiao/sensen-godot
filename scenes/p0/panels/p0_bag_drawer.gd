class_name P0BagDrawer
extends UiDrawer
## P0 Bag | Gear drawer (SGODOT-225; BAG-1-P0 / BAG-2-2 / BAG-2 · Gear; LOCK-12 / 13). Built from the kit:
##   quick_row   the drawer's first row is the quick bar (LOCK-12); the P0 UI puts its UiQuickBar here
##               (P0Ui.bind_quick_bar, SGODOT-221) and keeps it in step with the bottom bar.
##   header      UiBagHeader: Bag N/cap | Gear, Sort · Recent / Type (Bag side), capacity bar.
##   Bag side    seven category chips (one capacity), a hint, the item-info card of the tapped cell
##               (UiInfoSheet, F-07 bag context; no Sell in the bag, no close button: tap another cell to
##               switch, a blank cell to fold it) and the five-column grid.
##   Gear side   `✓ Equipped`, six GearSlot cells, the tapped slot's candidates (Equipped / Equip / greyed
##               gate and source) and `Gear does not use Bag slots.`
## Everything shown comes from the server view through P0Logic / P0ItemInfo; buttons only report back
## (`action_requested`), the P0 UI sends the command.

signal action_requested(action: StringName, item_id: String, payload: Dictionary)
signal side_changed(side: String)

const HEIGHT := 546.0   # drawer top at y 254 of 800 (BAG-2-2)
const CATEGORIES := ["All", "Seeds", "Fish", "Produce", "Dishes", "Materials", "Tackle"]
const _KIND_OF_CATEGORY := {"Seeds": ["seed"], "Fish": ["fish"], "Produce": ["crop"], "Dishes": ["dish"],
	"Materials": ["material"], "Tackle": ["bait", "rod"]}
const GEAR_SLOTS := ["farming", "fishing", "mining", "combat", "ring", "charm"]
const _ROW_GAP := 8.0      # Bag layout spacers: 8 under the quick bar, under the header, above the grid
const _SMALL_GAP := 4.0
const _SLOT_LIST_GAP := 12.0
## Sort behind `Sort · …` (Bag side; 不知火舞 on SGODOT-225): Type is the default — by category in Tab order,
## then rarity high → low, count high → low, most recent first (§10); a tap switches to Recent (most recent
## first, the server's order) and back. Kept on this device; the quick bar and Gear are not sorted.
const SORTS := ["Type", "Recent"]
const _PREFS := "user://p0_ui.cfg"

var view := {}
var side := "bag"
var category := "All"
var sort := "Type"
## Remember the Sort choice in user:// (off in tests).
var persist := true
var gear_slot := "fishing"
## `place` for the item-info rules ("home", "pond", "outpost").
var place := "home"
## Pins of the current action's quick bar, for the info card's Pin / Unpin (kept by the P0 UI).
var pinned := func(_id: String) -> bool: return false

var quick_row: MarginContainer
var header: UiBagHeader
var sheet: UiInfoSheet
var grid: UiInventoryGrid

var _bag_box: VBoxContainer
var _gear_box: VBoxContainer
var _chips: HBoxContainer
var _hint: Label

func _init(view_: Dictionary = {}, side_ := "bag", focus := "") -> void:
	super(HEIGHT)
	view = view_
	side = side_
	quick_row = MarginContainer.new()
	quick_row.custom_minimum_size.y = UiTokens.SIZE_QUICK_BAR_H
	body.add_child(quick_row)
	_gap(body, _ROW_GAP)
	header = UiBagHeader.new(0, 25, UiBagHeader.Pane.BAG if side == "bag" else UiBagHeader.Pane.GEAR)
	header.side_changed.connect(func(s: int): set_side("bag" if s == 0 else "gear"))
	header.sort_pressed.connect(func(): set_sort(SORTS[(SORTS.find(sort) + 1) % SORTS.size()]))
	sort = saved_sort()
	body.add_child(header)
	_bag_box = VBoxContainer.new()
	_bag_box.add_theme_constant_override(&"separation", 0)
	_bag_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_bag_box)
	_gear_box = VBoxContainer.new()
	_gear_box.add_theme_constant_override(&"separation", 0)
	body.add_child(_gear_box)
	_build_bag()
	refresh(view_)
	if focus != "" and P0Logic.bag_count(view, focus) > 0: grid.select(focus)

## New server view: counts, cells and the open card follow it; the selection, filter and scroll stay.
func refresh(view_: Dictionary) -> void:
	view = view_
	var bag: Dictionary = view.get("bag", {})
	header.used = (bag.get("slots", []) as Array).size()
	header.capacity = int(bag.get("capacity", 25))
	header.sort_label = sort
	_bag_box.visible = side == "bag"
	_gear_box.visible = side == "gear"
	grid.capacity = int(bag.get("capacity", 25))
	grid.items = items()
	_hint.visible = not sheet.is_open()
	if sheet.is_open(): sheet.refresh()
	if side == "gear": _build_gear()

func set_side(v: String) -> void:
	if v == side: return
	side = v
	header.side = UiBagHeader.Pane.BAG if v == "bag" else UiBagHeader.Pane.GEAR
	grid.clear_selection()
	refresh(view)
	side_changed.emit(v)

func set_category(v: String) -> void:
	category = v
	grid.filter = func(it: Dictionary) -> bool: return in_category(it, category)

func set_sort(v: String) -> void:
	sort = v
	header.sort_label = v
	grid.items = items()
	if persist:
		var cfg := ConfigFile.new()
		cfg.load(_PREFS)
		cfg.set_value("bag", "sort", v)
		cfg.save(_PREFS)

static func saved_sort() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_PREFS) != OK: return SORTS[0]
	var v := str(cfg.get_value("bag", "sort", SORTS[0]))
	return v if v in SORTS else SORTS[0]

func set_gear_slot(v: String) -> void:
	gear_slot = v
	_build_gear()

# ---------------------------------------------------------------- data

## Bag stacks as grid items: {id, icon, qty, rarity, kind}, in the chosen sort order.
func items() -> Array:
	return bag_items(view, sort)

static func bag_items(view: Dictionary, sort_by := "Type") -> Array:
	var out := []
	for s in view.get("bag", {}).get("slots", []):
		var id := str(s.get("id", ""))
		var it := P0Logic.item(view, id)
		out.append({id = id, icon = P0Logic.icon(str(it.get("base", id))), qty = int(s.get("qty", 0)),
			rarity = int(it.get("rarity", 0)) if id.begins_with("fish_") or id.begins_with("dish_") else 0,
			kind = P0ItemInfo.kind_of(view, id)})
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

static func in_category(it: Dictionary, cat: String) -> bool:
	if cat == "All": return true
	return str(it.get("kind", "")) in _KIND_OF_CATEGORY.get(cat, [])

## The six Gear slots: {key, role, item, icon, name, empty}.
static func gear_slots(view: Dictionary) -> Array:
	var slots: Dictionary = view.get("gear", {}).get("slots", {})
	return GEAR_SLOTS.map(func(k: String) -> Dictionary:
		var id := _slot_item(slots, k)
		return {key = k, role = k.capitalize(), item = id, icon = P0Logic.icon(id) if id != "" else null,
			name = P0Logic.item_name(view, id) if id != "" else "Empty", empty = id == ""})

## Candidates for one slot as UiGearRow data. Rods come from the view (owned, equipped, gates); the other P0
## slots only hold their starter tool.
static func gear_rows(view: Dictionary, key: String) -> Array:
	var out := []
	if key == "fishing":
		for r in view.get("gear", {}).get("rods", []):
			var id := str(r.id)
			var spec := P0ItemInfo.spec(view, id, &"gear")
			var facts: Array = spec.get("facts", [])
			var state: StringName = &"equipped" if r.get("equipped", false) else (&"owned" if r.get("owned", false) else StringName(facts[1] if facts.size() > 1 else "Locked"))
			var action := {}
			for b in spec.get("buttons", []):
				if StringName(b.get("id", &"")) != &"equipped": action = b
			out.append({id = id, icon = P0Logic.icon(id), title = str(spec.get("title", id)), state = state,
				effect = str(facts[0]) if facts.size() > 0 else "", action = action})
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
	_bag_box.add_child(sheet)
	_gap(_bag_box, _ROW_GAP)
	grid = UiInventoryGrid.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.on_select = func(it: Dictionary):
		sheet.open(str(it.id), &"bag", {place = place, pinned = bool(pinned.call(str(it.id)))})
		_hint.visible = false
	grid.selection_cleared.connect(func():
		sheet.close()
		_hint.visible = true)
	_bag_box.add_child(grid)

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

static func _gap(parent: Control, h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(g)
