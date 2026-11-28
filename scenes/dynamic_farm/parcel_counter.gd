extends UiDrawer
## Jasmine's counter on the dynamic farm map (C-59): the main farm's counter drawer (P0CounterDrawer, an outpost's
## Sell here half) rebuilt from the same kit pieces for the parcel's own save. The main counter is not touched: it
## reads the P0 view, this one the parcel farm (C-58). Top to bottom: UiKeeperBar (market tint) · `Coins` ·
## divider · `Bag` · the selected stack's card (UiInfoSheet: `12 each`, Sell / Sell All · N coins, as P0's
## counter_sell) · the five-column grid with only what Jasmine buys (LOCK-15: an outpost shows what it buys).
## Prices are the rules' (assets/farm/data/dynamic_farm.json, C-58); the server ignores any price in a request.
## C-149: a shelf over the divider, as the P0 counter's Buy page (FARM-6 / NPC-2): one UiShopRow per `buy_prices` item
## (`Bag ×3`, `9 coins`, stepper + Buy, or the grey `Need 4 more coins`; copy as PM finalised it on C-149#10).
## Buttons only report (`sell_requested`, `buy_requested`); the town sends the command.
## C-186 (C-185 §3.3 D–E, MS-15 / MS-02): a sale floats `+N` over its key and up to three coins fly to the Coins row, which
## bumps and rolls as the first lands; a purchase rolls the coins down (they flash, nothing pops); a tap on a grey
## `Need N more coins` shakes the key and flashes the Coins number `action/danger` (no toast: the key already says it).
## C-211 (MS-15's rest): a stack sold out folds its card away (height to 0 in 200, exit) while its grid icon fades (120);
## a purchase rolls the shelf row's `Bag ×N` up to the new count. Reduced: the card closes and the count changes at once.
## C-232 (0.4.7): once the player has been to the Aquatic Park pier (the save's `fishing.gifted_at`), the shelf also has the
## tackle (`economy.buy_prices` rods and baits, limits in `fishing.goods`): a rod is a one-off row (no stepper) until owned,
## then its row goes; baits step up to what the coins and the day's limit cover. Below the item's farm level the key is the
## grey `Farm Lv4 needed`, a used-up day `Sold out today`; the effect line is P0's (`Bite window 2.6 s`, `Faster bites`,
## `More Rare fish`). More than SHELF_ROWS rows scroll in a shelf 2½ rows high; the drawer grows by what the shelf shows.

signal sell_requested(item_id: String, count: int)
signal buy_requested(item_id: String, count: int)

const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fishing = preload("res://modules/dynamic_farm/parcel_fishing.gd")
## 560 for the bag half as before (C-59), plus one shelf row (58) and its gap.
const HEIGHT := 626.0
const ROW_H := 58.0
## C-232: up to this many shelf rows stand open; more scroll in a shelf ROWS_SHOWN rows high (the half row says it scrolls).
const SHELF_ROWS := 2
const ROWS_SHOWN := 2.5
const _MAX_STEP := 99
const _GAP := 8.0
const _SMALL := 4.0
const _COLUMNS := 5

var farm := {}
var prices := {}
## Item id → coins each on Jasmine's shelf (C-149 `economy.buy_prices`).
var buy_prices := {}
var shelf: VBoxContainer
## C-232: the shelf's scroll (rows past SHELF_ROWS); its height follows the rows shown.
var shelf_scroll: TouchScrollContainer
## C-232: the server's clock (the day's bait limit); the town sets its server_now.
var now_ms: Callable = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)
var keeper_bar: UiKeeperBar
var sheet: UiInfoSheet
var grid: UiInventoryGrid
var coins: UiFactRow
var _empty: Label
var _rows := {}   # item id -> UiShopRow
var _qty := {}    # item id -> stepper count
## Where the last Sell / Sell All key was (global), for the coins that fly from it (C-186 MS-15).
var sell_point := Vector2.INF
## A sale's coins are on their way: refresh() leaves the number for the roll.
var _rolling := false
## The sold-out card folding away (its clip, which holds the sheet until it is done), else null.
var _fold: Control

## npc: {name, role, title, look}; prices: item id → coins each (sold here); buy_prices_: item id → coins each (bought).
func _init(farm_: Dictionary, prices_: Dictionary, npc: Dictionary, portrait: Texture2D, buy_prices_ := {}) -> void:
	super(HEIGHT)
	prices = prices_
	buy_prices = buy_prices_
	keeper_bar = UiKeeperBar.new(UiKeeperBar.Role.MARKET)
	keeper_bar.portrait = portrait
	keeper_bar.title = str(npc.get("title", ""))
	keeper_bar.keeper = "%s · %s" % [str(npc.get("role", "")), str(npc.get("name", ""))]
	keeper_bar.close_pressed.connect(func(): close_requested.emit())
	body.add_child(keeper_bar)
	_gap(_GAP)
	coins = UiFactRow.new("Coins", "0")
	coins.icon = UiArt.COIN
	body.add_child(coins)
	shelf_scroll = TouchScrollContainer.new()
	shelf_scroll.name = "Shelf"
	shelf_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	body.add_child(shelf_scroll)
	shelf = VBoxContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.add_theme_constant_override(&"separation", 0)
	shelf_scroll.add_child(shelf)
	for id in buy_prices:
		var row := UiShopRow.new()
		row.name = "Buy_%s" % id
		row.bought.connect(func(item: String, qty: int): buy_requested.emit(item, qty))
		row.quantity_changed.connect(func(item: String, qty: int):
			_qty[item] = qty
			_show_row(item))
		shelf.add_child(row)
		_rows[id] = row
	_gap(_GAP)
	var line := ColorRect.new()
	line.color = UiTokens.COLOR_BORDER
	line.custom_minimum_size.y = 1.0
	body.add_child(line)
	_gap(_SMALL + 1.0)
	body.add_child(UiKit.label("Bag", UiTokens.STYLE_C14_XB))
	_gap(_SMALL)
	sheet = UiInfoSheet.new()
	sheet.rules = func(id: String, _c: StringName, _o: Dictionary) -> Dictionary: return spec(id)
	sheet.action_requested.connect(func(a: StringName, id: String, p: Dictionary):
		sell_point = _key_point(a)
		sell_requested.emit(id, int(p.get("count", 1))))
	sheet.visible = false
	body.add_child(sheet)
	_gap(_SMALL)
	_empty = UiKit.label("Nothing to sell", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	body.add_child(_empty)
	grid = UiInventoryGrid.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.sell_mode = true
	grid.can_sell = func(_it: Dictionary) -> bool: return true
	grid.on_select = func(it: Dictionary): select(str(it.id))
	grid.selection_cleared.connect(func(): if _fold == null: sheet.close())
	body.add_child(grid)
	refresh(farm_)

func action_area() -> Control: return sheet if sheet != null and sheet.is_visible_in_tree() else null

## What Jasmine buys from the bag, in the rules' price order.
func sellable() -> Array:
	return prices.keys().filter(func(id): return int(farm.get("bag", {}).get(id, 0)) > 0)

## New farm from the store: coins, the grid and the open card follow it; the selection stays while it can be sold.
func refresh(farm_: Dictionary) -> void:
	farm = farm_
	# The row's value is always the farm's; a count still running (coins in flight, a roll) keeps its number drawn.
	var drawn := coins_label().text
	coins.value = str(int(farm.get("coins", 0)))
	if _rolling or UiMotion.rolling(coins_label()): coins_label().text = drawn
	var items := sellable().map(func(id): return {id = id, icon = ParcelItems.icon_of(id),
		qty = int(farm.bag[id]), rarity = 0, kind = "", tab = &""})
	# The stacks leaving the grid (sold out): their icons fade where they were (MS-15).
	var leaving := []
	for id in grid.shown_items().map(func(it): return str(it.id)):
		if int(farm.get("bag", {}).get(id, 0)) <= 0 and grid.cell_for(id) != null: leaving.append(grid.cell_for(id))
	if not UiMotion.reduced and is_inside_tree():
		for cell: UiItemCell in leaving: _fade_icon(cell)
	# The open card's stack sold out: it folds away (the grid dropping its selection then leaves the card to the fold).
	if sheet.is_open() and _fold == null and int(farm.get("bag", {}).get(sheet.item_id(), 0)) <= 0: fold_sheet()
	grid.capacity = maxi(_COLUMNS, ceili(items.size() / float(_COLUMNS)) * _COLUMNS)
	grid.items = items
	_empty.visible = items.is_empty()
	for id in _rows: _show_row(id)
	_fit_shelf()
	if sheet.is_open() and _fold == null:
		if int(farm.get("bag", {}).get(sheet.item_id(), 0)) > 0: sheet.refresh()
		else:
			sheet.close()
			grid.clear_selection()
	elif _fold != null: grid.clear_selection()

## MS-15: the sold-out stack's card folds away — clipped to a box that shrinks from its height to 0 (200, exit) as it
## fades, the rows under it rising with it; then it closes. Reduced, or off screen: it closes at once.
func fold_sheet() -> void:
	if UiMotion.reduced or not sheet.is_visible_in_tree():
		sheet.close()
		return
	var h := sheet.size.y
	var w := sheet.size.x
	_fold = Control.new()
	_fold.name = "SheetFold"
	_fold.clip_contents = true
	_fold.mouse_filter = Control.MOUSE_FILTER_STOP   # its keys take no taps while it goes
	_fold.custom_minimum_size.y = h
	body.add_child(_fold)
	body.move_child(_fold, sheet.get_index())
	sheet.reparent(_fold, false)
	sheet.position = Vector2.ZERO
	sheet.size = Vector2(w, h)
	var shield := Control.new()
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_fold.add_child(shield)
	var tw := UiMotion.tween(_fold, UiTokens.MOTION_EASING_EXIT)
	tw.tween_property(_fold, "custom_minimum_size:y", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS))
	tw.parallel().tween_property(sheet, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS))
	tw.tween_callback(_end_fold)
	_fold.set_meta(&"_ui_fold", tw)

## The fold is over (or cut short by another pick): the card is back in its place, closed.
func _end_fold() -> void:
	if _fold == null: return
	var fold := _fold
	_fold = null
	UiMotion._kill(fold, &"_ui_fold")
	var at := fold.get_index()
	sheet.reparent(body, false)
	body.move_child(sheet, at)
	sheet.modulate.a = 1.0
	sheet.close()
	fold.queue_free()

## A stack leaving the grid: its icon fades out (120) over where its cell drew it.
func _fade_icon(cell: UiItemCell) -> void:
	if cell.icon == null or cell._icon == null or not cell._icon.is_visible_in_tree(): return
	var ghost := TextureRect.new()
	ghost.name = "SoldGhost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.texture = cell.icon
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var at := cell._icon.get_global_rect()
	ghost.top_level = true   # the drawer is a container: a plain child would be stretched over it
	add_child(ghost)
	ghost.global_position = at.position
	ghost.size = at.size
	var tw := UiMotion.tween(ghost, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_property(ghost, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	tw.tween_callback(ghost.queue_free)

## C-211 (MS-15): a purchase rolls the shelf row's `Bag ×N` from `before` up to the bag's count now (400; it bumps).
func roll_bag(id: String, before: int) -> void:
	var row: UiShopRow = _rows.get(id)
	if row == null: return
	UiMotion.roll(row._effect, float(before), float(int(farm.get("bag", {}).get(id, 0))), "Bag ×%d")

## The Coins row's number (rolls, flashes) and its icon (the coins' landing).
func coins_label() -> Label: return coins._value
func coins_icon() -> Control: return coins._icon

## The sheet key `action` (&"sell" / &"sell_all") on screen, else the sheet's middle, else INF.
func _key_point(action: StringName) -> Vector2:
	var want := "Sell" if action == &"sell" else "Sell All"
	for b in sheet.find_children("*", "UiCommandButton", true, false):
		var key := b as UiCommandButton
		if key.is_visible_in_tree() and (key.label == want or (action == &"sell_all" and key.label.begins_with(want))):
			return key.get_global_rect().get_center()
	return sheet.get_global_rect().get_center() if sheet.is_visible_in_tree() else Vector2.INF

## MS-15: `+N` rises over the key, coins fly to the Coins row; as the first lands its icon bumps and the number rolls
## from `before` to `after` (400). Reduced: only the number (set at once).
func celebrate_sale(before: int, after: int) -> void:
	var gain := after - before
	var at := sell_point if sell_point != Vector2.INF else coins.get_global_rect().get_center()
	var host := get_parent() as Control
	if gain > 0 and host != null and is_inside_tree():
		var f := UiGainFloat.new("+%d" % gain, UiGainFloat.Tone.COINS, UiArt.COIN)
		f.name = "SaleFloat"
		f.theme = UiKit.theme()
		host.add_child(f)
		f.play(at - host.global_position - Vector2(0, UiTokens.SPACE_S5))
	_rolling = true
	coins.value = str(after)
	coins_label().text = str(before)   # the row's value is the new sum; its number counts up to it as the coins land
	fly_coins(gain, at, coins_icon(), func():
		_rolling = false
		UiMotion.roll(coins_label(), float(before), float(int(farm.get("coins", after))), "%d", coins_icon()))

## A purchase: the coins roll down to what is left (MS-03: they flash, nothing pops).
func roll_coins(before: int) -> void:
	_rolling = false
	UiMotion.roll(coins_label(), float(before), float(int(farm.get("coins", 0))))

func select(id: String) -> void:
	_end_fold()
	sheet.open(id, &"counter_sell")

## The selected stack's card, as P0's counter_sell: `12 each`, Sell (one) and Sell All · N coins.
func spec(id: String) -> Dictionary:
	var count := int(farm.get("bag", {}).get(id, 0))
	var each := int(prices.get(id, 0))
	var out := {id = id, title = ParcelItems.name_of(id), icon = ParcelItems.icon_of(id), quantity = count,
		info = false, facts = ["%d each" % each], buttons = []}
	if count > 0 and each > 0:
		out.buttons = [{id = &"sell", label = "Sell", kind = &"secondary", sends = true, payload = {count = 1}},
			{id = &"sell_all", label = "Sell All · %d coins" % (count * each), kind = &"primary", sends = true, payload = {count = count}}]
	return out

## The shelf's row for an item, null when Jasmine does not sell it.
func row_of(id: String) -> UiShopRow:
	return _rows.get(id, null)

## How many of `id` the coins cover (the stepper's top), at least 1 so the row still draws its stepper; C-232: no more than
## the day's bait limit leaves.
func affordable(id: String) -> int:
	var each := int(buy_prices.get(id, 0))
	var top := clampi(int(farm.get("coins", 0)) / each, 1, _MAX_STEP) if each > 0 else 1
	var left := Fishing.can_buy(ParcelFarm.rules(), farm, id, int(now_ms.call()))
	return clampi(left, 1, top) if left >= 0 else top

## C-232: whether the shelf shows `id` now: always, unless it is tackle (fishing.goods) and the player has not been to the
## pier yet, or a rod already owned.
func on_shelf(id: String) -> bool:
	var g: Dictionary = ParcelFarm.rules().get("fishing", {}).get("goods", {}).get(id, {})
	if g.is_empty(): return true
	if farm.get("fishing", {}).get("gifted_at") == null: return false
	return not g.has("max_owned") or int(farm.get("bag", {}).get(id, 0)) < int(g.max_owned)

## The shelf's rows on show, in the rules' order.
func shelf_ids() -> Array:
	return _rows.keys().filter(func(id): return (_rows[id] as Control).visible)

## The shelf as tall as its rows, ROWS_SHOWN at most (scrolling past them); the drawer grows by what it shows over one row.
func _fit_shelf() -> void:
	var n := shelf_ids().size()
	var shown := minf(float(n), ROWS_SHOWN) if n > SHELF_ROWS else float(n)
	shelf_scroll.custom_minimum_size.y = shown * ROW_H
	set_height(HEIGHT + maxf(0.0, shown - 1.0) * ROW_H)

## A shelf row, as P0's counter_buy (F-07) in the copy PM finalised on C-149#10 (C-45 / Q-61): the name, `Bag ×N` under
## it, the price for the chosen count (`9 coins`, `18 coins`), then stepper + Buy, or the grey `Need N more coins`.
## No grow-time line and no `2 × 9 coins` working.
## C-232 tackle: the effect on the third line; below its farm level `Farm Lv4 needed`, the day's baits bought `Sold out
## today`, both before the coins (the server checks them first).
func buy_spec(id: String, qty := 1) -> Dictionary:
	var each := int(buy_prices.get(id, 0))
	qty = maxi(1, qty)
	var short := each * qty - int(farm.get("coins", 0))
	var button := {id = &"buy", label = "Buy", kind = &"secondary", payload = {}} if short <= 0 \
		else {id = &"buy", label = "Need %d more coins" % short, kind = &"unavailable", payload = {}}
	var rules := ParcelFarm.rules()
	var g: Dictionary = rules.get("fishing", {}).get("goods", {}).get(id, {})
	if g.has("min_level") and ParcelFarm.farm_level(farm) < int(g.min_level):
		button = {id = &"buy", label = "Farm Lv%d needed" % int(g.min_level), kind = &"unavailable", payload = {}}
	elif g.has("daily") and Fishing.can_buy(rules, farm, id, int(now_ms.call())) == 0:
		button = {id = &"buy", label = "Sold out today", kind = &"unavailable", payload = {}}
	var facts := ["Bag ×%d" % int(farm.get("bag", {}).get(id, 0))]
	var effect := tackle_effect(id)
	if effect != "": facts.append(effect)
	return {id = id, title = ParcelItems.name_of(id), icon = ParcelItems.icon_of(id), info = false, facts = facts,
		price = {each = each, total = each * qty, text = "%d coins" % (each * qty), line = ""},
		buttons = [button]}

## C-232: a rod's or bait's effect in P0's words (P0ItemInfo: `Bite window 2.6 s`, `Faster bites`, `More Rare fish`); "".
static func tackle_effect(id: String) -> String:
	var f: Dictionary = ParcelFarm.rules().get("fishing", {})
	if f.is_empty(): return ""
	for rod: Dictionary in f.rods:
		if rod.id == id: return "Bite window %.1f s" % (float(int(f.hook_window_ms) + int(rod.hook_bonus_ms)) / 1000.0)
	if f.baits.has(id): return "More Rare fish" if int(f.baits[id].shift[f.baits[id].shift.size() - 1]) > 0 else "Faster bites"
	return ""

func _show_row(id: String) -> void:
	var row := _rows[id] as UiShopRow
	row.visible = on_shelf(id)
	if not row.visible: return
	var top := affordable(id)
	var qty := clampi(int(_qty.get(id, 1)), 1, top)
	_qty[id] = qty
	# The row's new stepper takes its old count, capped at `top` (the wallet shrank under it): the same as qty here.
	# C-232: a rod is one-off (no stepper), as P0's counter_buy.
	var g: Dictionary = ParcelFarm.rules().get("fishing", {}).get("goods", {}).get(id, {})
	row.show_spec(buy_spec(id, qty), int(g.get("max_owned", 0)) == 1, top)
	if row.buy != null and row.buy.is_unavailable():
		row.buy.unavailable_pressed.connect(func(_r: String): refuse(row.buy))

## MS-02: the grey key shakes and the Coins number flashes `action/danger` (120); the key's own text says why.
func refuse(key: Control) -> void:
	UiMotion.shake(key)
	UiMotion.flash(coins_label(), UiTokens.COLOR_ACTION_DANGER)

func _gap(h: float) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size.y = h
	body.add_child(c)
