class_name UiInventoryGrid
extends TouchScrollContainer
## Bag grid (SGODOT-225; "Inventory · source five-column grid" in the Bag layout, LOCK-12, and the counter's
## bag half, LOCK-15). Five columns of Compact/InventoryCell spread edge to edge: the first on the content's left
## edge, the last on its right, four equal gaps (int10c 256 ④, 不知火舞: no longer on the quick bar's 52 + 4 pitch);
## rows 12 apart. Filled cells first, then dashed empty cells up to `capacity`. Scrolls vertically
## (TouchScrollContainer); cells keep their own GestureArbiter.
## Shared by the Bag | Gear drawer (2B) and the counter (2A), through two hooks:
##   on_select  Callable(item) run when a filled cell is tapped (bag: open the info sheet; counter: show the
##              sell area). Tapping another cell switches, tapping an empty cell clears (`selection_cleared`).
##   sell_mode  the counter's "Sell here" view: only items `can_sell` accepts are listed (LOCK-15); the rest
##              of the bag is not shown, so there is no Sell tab and no greyed cell to explain.
## Items are dictionaries: {id, icon (Texture2D), qty, rarity (0–4), ...}; extra keys pass through to the hooks.
## KITCHEN cells also take status, marked and kitchen_state (UiItemCell.KitchenState); unknown Cookbook pages also
## families, clues and might_have.
## `density` KITCHEN draws Compact/Kitchen/Cell (52×58) for the cooking drawer's Experiment page (LOCK-20,
## SGODOT-226); items may then carry `status` ("In pot", "Not for cooking") and `marked` (cooked tick).

signal item_selected(item: Dictionary)
signal selection_cleared
## A cell gesture other than tap (long press, lift, drag …, see UiItemCell.gesture) for the drawer that hosts
## the grid, e.g. long-press to pin, drag into the quick bar.
signal cell_gesture(item: Dictionary, outcome: Dictionary)

const COLUMNS := 5
const ROW_GAP := 12.0   # 256 ④: rows 12 apart (52 + 12 in the bag, 58 + 12 in the kitchen)
const _MIN_COLUMN_GAP := 4.0   # before the grid has a width (and on a width too narrow for five cells)

## Cell main: INVENTORY (bag, counter) or KITCHEN (Experiment). Set before the first items.
var density: UiItemCell.Density = UiItemCell.Density.INVENTORY: set = set_density
var items: Array = []: set = set_items
var capacity := 25: set = set_capacity
## Extra predicate (item -> bool), e.g. the drawer's category chip; empty = everything.
var filter := Callable(): set = set_filter
## Counter "Sell here" view (2A): list only the items `can_sell` accepts.
var sell_mode := false: set = set_sell_mode
var can_sell := Callable(): set = set_can_sell
## Called with the item when a filled cell is tapped (after the selection is drawn).
var on_select := Callable()
## The selected item's id. Setting it only marks the cell (a page a drawer opens on, a refresh keeping the choice): it
## repaints at once and emits nothing; a tap's select() / clear_selection() emit item_selected / selection_cleared.
var selected_id := "": set = set_selected_id
## The item in the air (a cell lifted toward the quick bar): its cell draws as an empty dashed cell until the drag
## ends; "" puts it back (BAR-DRAG-9, as the quick bar's own dragged slot; 不知火舞 on 225).
var lifted_id := "": set = set_lifted_id

func set_lifted_id(v: String) -> void:
	lifted_id = v
	_paint_selection()

func set_selected_id(v: String) -> void:
	selected_id = v
	if not _cells.is_empty(): _paint_selection()

var _grid: _Spread
var _cells: Array[UiItemCell] = []
var _shown: Array = []   # items behind the filled cells, in order

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = _Spread.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # the scroll's whole width, to spread over
	add_child(_grid)

## The gap between columns: (width − 5 × 52) / 4, 17 in the bag drawer's 328, 19 in the kitchen drawer's 336
## (256 ④; Inventory and Kitchen cells are both 52 wide).
func column_gap() -> int: return _Spread.gap_for(_grid.size.x)

func set_items(v: Array) -> void: items = v; refresh()
func set_density(v: UiItemCell.Density) -> void:
	if v == density: return
	density = v
	for c in _cells: c.free()
	_cells.clear()
	refresh()
func set_capacity(v: int) -> void: capacity = v; refresh()
func set_filter(v: Callable) -> void: filter = v; refresh()
func set_sell_mode(v: bool) -> void: sell_mode = v; refresh()
func set_can_sell(v: Callable) -> void: can_sell = v; refresh()

## Items the grid lists right now (after the filter and sell mode), in order.
func shown_items() -> Array: return _shown.duplicate()

## The cell drawing `id`, or null when it is not listed.
func cell_for(id: String) -> UiItemCell:
	for i in _shown.size():
		if str(_shown[i].get("id", "")) == id: return _cells[i]
	return null

func cells() -> Array[UiItemCell]: return _cells.duplicate()

func select(id: String) -> void:
	var item := _item(id)
	if item.is_empty():
		clear_selection()
		return
	selected_id = id   # the setter paints
	item_selected.emit(item)
	if on_select.is_valid(): on_select.call(item)

func clear_selection() -> void:
	var had := selected_id != ""
	selected_id = ""   # the setter paints
	if had: selection_cleared.emit()

## Rebuilds the cell contents; cells are reused, so the scroll position survives a refresh. A selection whose
## item is no longer listed is cleared.
func refresh() -> void:
	if _grid == null: return
	_shown = items.filter(_listed)
	var total := maxi(capacity, _shown.size())
	while _cells.size() < total:
		var c := UiItemCell.new(density)
		var i := _cells.size()
		c.tapped.connect(_on_tap.bind(i))
		c.gesture.connect(_on_gesture.bind(i))
		_grid.add_child(c)
		_cells.append(c)
	for i in _cells.size():
		var c := _cells[i]
		c.visible = i < total
		if i < _shown.size():
			var it: Dictionary = _shown[i]
			c.icon = it.get("icon", null)
			var qty := int(it.get("qty", 0))
			c.quantity = "×%d" % qty if qty > 0 else ""
			c.rarity = int(it.get("rarity", 0))
			c.status = str(it.get("status", ""))
			c.marked = bool(it.get("marked", false))
			c.kitchen_state = int(it.get("kitchen_state", UiItemCell.KitchenState.DEFAULT))
			c.families = it.get("families", [])
			c.clues = it.get("clues", [])
			c.might_have = bool(it.get("might_have", false))
			c.rack = bool(it.get("rack", false))
			c.stored = bool(it.get("stored", false))
		else:
			c.icon = null
			c.quantity = ""
			c.rarity = 0
			c.status = ""
			c.marked = false
			c.kitchen_state = UiItemCell.KitchenState.DEFAULT
			c.families = []
			c.clues = []
			c.might_have = false
			c.rack = false
			c.stored = false
	if selected_id != "" and _item(selected_id).is_empty():
		clear_selection()
	else:
		_paint_selection()

func _listed(it: Dictionary) -> bool:
	if filter.is_valid() and not bool(filter.call(it)): return false
	if sell_mode and not (can_sell.is_valid() and bool(can_sell.call(it))): return false
	return true

func _item(id: String) -> Dictionary:
	for it in _shown:
		if str(it.get("id", "")) == id: return it
	return {}

func _paint_selection() -> void:
	for i in _cells.size():
		var filled := i < _shown.size()
		var id := str(_shown[i].get("id", "")) if filled else ""
		var on := filled and id == selected_id
		var out := filled and lifted_id != "" and id == lifted_id
		_cells[i].state = UiItemCell.State.EMPTY if out or not filled else (UiItemCell.State.SELECTED if on else UiItemCell.State.DEFAULT)

func _on_tap(i: int) -> void:
	if i < _shown.size(): select(str(_shown[i].get("id", "")))
	else: clear_selection()

func _on_gesture(outcome: Dictionary, i: int) -> void:
	if i < _shown.size(): cell_gesture.emit(_shown[i], outcome)

## Five columns spread edge to edge, rows ROW_GAP apart (256 ④). A GridContainer's fixed separation can't do it:
## a gap taken from the width would make the content as wide as it was given, and a scroll container is never
## narrower than its content, so the grid could never narrow again. This one asks for five cells and the narrow gap
## only, and spreads the columns over whatever width it gets.
class _Spread extends Container:
	static func gap_for(width: float) -> int:
		return maxi(int(_MIN_COLUMN_GAP), floori((width - COLUMNS * UiTokens.SIZE_INVENTORY_CELL) / float(COLUMNS - 1)))

	func _cells_shown() -> Array:
		return get_children().filter(func(c): return c is Control and (c as Control).visible)

	func _cell() -> Vector2:
		var cell := Vector2.ZERO
		for c in _cells_shown(): cell = cell.max((c as Control).get_combined_minimum_size())
		return cell

	func _get_minimum_size() -> Vector2:
		var n := _cells_shown().size()
		if n == 0: return Vector2.ZERO
		var cell := _cell()
		var rows := ceili(n / float(COLUMNS))
		return Vector2(COLUMNS * cell.x + (COLUMNS - 1) * _MIN_COLUMN_GAP, rows * cell.y + (rows - 1) * ROW_GAP)

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN: return
		var cell := _cell()
		var pitch := Vector2(cell.x + gap_for(size.x), cell.y + ROW_GAP)
		var shown := _cells_shown()
		for i in shown.size():
			fit_child_in_rect(shown[i], Rect2(Vector2(i % COLUMNS, floori(i / float(COLUMNS))) * pitch, cell))
