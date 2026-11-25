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

signal sell_requested(item_id: String, count: int)
signal buy_requested(item_id: String, count: int)

const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
## 560 for the bag half as before (C-59), plus one shelf row (58) and its gap.
const HEIGHT := 626.0
const _MAX_STEP := 99
const _GAP := 8.0
const _SMALL := 4.0
const _COLUMNS := 5

var farm := {}
var prices := {}
## Item id → coins each on Jasmine's shelf (C-149 `economy.buy_prices`).
var buy_prices := {}
var shelf: VBoxContainer
var keeper_bar: UiKeeperBar
var sheet: UiInfoSheet
var grid: UiInventoryGrid
var coins: UiFactRow
var _empty: Label
var _rows := {}   # item id -> UiShopRow
var _qty := {}    # item id -> stepper count

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
	shelf = VBoxContainer.new()
	shelf.add_theme_constant_override(&"separation", 0)
	body.add_child(shelf)
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
	sheet.action_requested.connect(func(_a: StringName, id: String, p: Dictionary): sell_requested.emit(id, int(p.get("count", 1))))
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
	grid.selection_cleared.connect(func(): sheet.close())
	body.add_child(grid)
	refresh(farm_)

func action_area() -> Control: return sheet if sheet != null and sheet.is_visible_in_tree() else null

## What Jasmine buys from the bag, in the rules' price order.
func sellable() -> Array:
	return prices.keys().filter(func(id): return int(farm.get("bag", {}).get(id, 0)) > 0)

## New farm from the store: coins, the grid and the open card follow it; the selection stays while it can be sold.
func refresh(farm_: Dictionary) -> void:
	farm = farm_
	coins.value = str(int(farm.get("coins", 0)))
	var items := sellable().map(func(id): return {id = id, icon = ParcelItems.icon_of(id),
		qty = int(farm.bag[id]), rarity = 0, kind = "", tab = &""})
	grid.capacity = maxi(_COLUMNS, ceili(items.size() / float(_COLUMNS)) * _COLUMNS)
	grid.items = items
	_empty.visible = items.is_empty()
	for id in _rows: _show_row(id)
	if sheet.is_open():
		if int(farm.get("bag", {}).get(grid.selected_id, 0)) > 0: sheet.refresh()
		else:
			sheet.close()
			grid.clear_selection()

func select(id: String) -> void:
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

## How many of `id` the coins cover (the stepper's top), at least 1 so the row still draws its stepper.
func affordable(id: String) -> int:
	var each := int(buy_prices.get(id, 0))
	return clampi(int(farm.get("coins", 0)) / each, 1, _MAX_STEP) if each > 0 else 1

## A shelf row, as P0's counter_buy (F-07) in the copy PM finalised on C-149#10 (C-45 / Q-61): the name, `Bag ×N` under
## it, the price for the chosen count (`9 coins`, `18 coins`), then stepper + Buy, or the grey `Need N more coins`.
## No grow-time line and no `2 × 9 coins` working.
func buy_spec(id: String, qty := 1) -> Dictionary:
	var each := int(buy_prices.get(id, 0))
	qty = maxi(1, qty)
	var short := each * qty - int(farm.get("coins", 0))
	var button := {id = &"buy", label = "Buy", kind = &"secondary", payload = {}} if short <= 0 \
		else {id = &"buy", label = "Need %d more coins" % short, kind = &"unavailable", payload = {}}
	return {id = id, title = ParcelItems.name_of(id), icon = ParcelItems.icon_of(id), info = false,
		facts = ["Bag ×%d" % int(farm.get("bag", {}).get(id, 0))],
		price = {each = each, total = each * qty, text = "%d coins" % (each * qty), line = ""},
		buttons = [button]}

func _show_row(id: String) -> void:
	var top := affordable(id)
	var qty := clampi(int(_qty.get(id, 1)), 1, top)
	_qty[id] = qty
	# The row's new stepper takes its old count, capped at `top` (the wallet shrank under it): the same as qty here.
	(_rows[id] as UiShopRow).show_spec(buy_spec(id, qty), false, top)

func _gap(h: float) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size.y = h
	body.add_child(c)
