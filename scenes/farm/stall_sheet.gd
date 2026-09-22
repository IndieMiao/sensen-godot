class_name StallSheet
extends PanelContainer
## 路边摊：卖产出、买种子。数字只是把服务端会给的数提前写在按钮上，成交以回包为准。
## 所有文案经本地化；数量和价格仍以服务端确认结果为准。

signal sell_requested(items: Array)        ## [{kind:"produce", id, qty}]
signal buy_requested(crop: String, qty: int)
signal fish_sell_requested(stack_id: String, quantity: int)
signal retry_requested()
signal closed()

const BUY_QTY := 3

var _title: Label
var _budget: Label
var _wallet: Label
var _selling_rows: VBoxContainer
var _buying_rows: VBoxContainer
var _footer: VBoxContainer
var _quantity_row: HBoxContainer
var _tabs: Dictionary = {}
var _page := "sell"
var _page_chosen := false
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _sell_all: Button
var _sell_items: Array = []
var _buy_qty := BUY_QTY
var _quantity: Label
var _quantity_minus: Button
var _quantity_plus: Button
var _busy := false
var _uncertain := false
var _retry: Button
var _last_state: Dictionary = {}
var _last_unlocked: Array = []
var _last_budget := 100
var _recipes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/recipes.json")).get("recipes", {})

func _init() -> void:
	name = "StallSheet"
	theme_type_variation = &"BottomSheet"
	add_theme_stylebox_override("panel", GameUi.panel_style(10))
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 8.0
	offset_right = -8.0
	offset_bottom = -8.0
	offset_top = -420.0
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	head.custom_minimum_size.y = 44
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	head.add_child(GameUi.picture(GameUi.icon("store"), 24))
	_title = GameUi.label(L10n.text("Roadside stall"), 17)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title)
	var purse := HBoxContainer.new()
	purse.add_theme_constant_override("separation", 4)
	var coin := GameUi.picture(GameUi.icon("coins"), 18)
	coin.modulate = GameUi.GOLD
	purse.add_child(coin)
	_wallet = GameUi.label("0", 14, GameUi.INK)
	_wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	purse.add_child(_wallet)
	head.add_child(purse)
	var close := GameUi.button("x", "", L10n.text("Close stall"))
	close.name = "CloseStall"
	close.theme_type_variation = &"IconButton"
	close.custom_minimum_size = Vector2(44, 44)
	close.pressed.connect(func():
		if _busy: return
		visible = false
		emit_signal("closed"))
	head.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	for spec in [["sell", "Sell"], ["seeds", "Seeds"]]:
		var tab := GameUi.button("", L10n.text(str(spec[1])), L10n.text(str(spec[1])))
		tab.name = "StallPage_" + str(spec[0])
		tab.custom_minimum_size.y = 44
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_page.bind(str(spec[0])))
		tabs.add_child(tab)
		_tabs[spec[0]] = tab
	_budget = GameUi.label("", 11, GameUi.MUTED)
	v.add_child(_budget)
	_retry = GameUi.button("rotate-ccw", L10n.text("Check last trade"), L10n.text("Reload the last trade result"))
	_retry.visible = false
	_retry.pressed.connect(func():
		if not _retry.disabled: retry_requested.emit())
	v.add_child(_retry)
	_scroll = TouchScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows)
	_selling_rows = VBoxContainer.new()
	_selling_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selling_rows.add_theme_constant_override("separation", 5)
	_rows.add_child(_selling_rows)
	_buying_rows = VBoxContainer.new()
	_buying_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buying_rows.add_theme_constant_override("separation", 5)
	_rows.add_child(_buying_rows)
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 6)
	v.add_child(_footer)

func _ready() -> void:
	GameUi.register_modal(self)

func fit_height(area: Vector2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var height := minf(520, maxf(300, area.y * 0.64))
	height = minf(height, maxf(1, area.y - 110))
	var width := minf(620, maxf(1, area.x - 8))
	position = Vector2((area.x - width) * 0.5, area.y - height - 4)
	size = Vector2(width, height)

func _select_page(value: String) -> void:
	if _busy: return
	_page = value
	_page_chosen = true
	_scroll.scroll_vertical = 0
	refresh(_last_state, _last_unlocked, _last_budget)

## 用最新状态重画。stall_budget 每日 100（economy.json）。
## 行节点复用：refresh 可能在某个按钮自己的 pressed 回调里被调（卖完立刻刷新），
## 那时 free 掉按钮会崩，queue_free 又会留一堆孤儿——所以行一次建好，之后只改文字和可用性。
func refresh(state: Dictionary, unlocked: Array, budget_per_day := 100) -> void:
	_last_state = state
	_last_unlocked = unlocked
	_last_budget = budget_per_day
	_ensure_rows()
	var blocked := _busy or _uncertain
	_retry.visible = _uncertain
	_retry.disabled = _busy
	var settled := int((state.get("stall", {}) as Dictionary).get("settled", 0))
	_budget.text = L10n.format_text("Today's sales %d / %d coins", [settled, budget_per_day])
	if JourneyProgress.active(state):
		budget_per_day = 2147483647
		_budget.text = L10n.text("Neighbourhood stall")
	var inv: Dictionary = state.get("inventory", {})
	var produce: Dictionary = inv.get("produce", {})
	var reserved: Dictionary = (state.get("engineering", {}) as Dictionary).get("reserved", {})
	var project := str(state.get("journey", {}).get("tracked_project", ""))
	var goal_crops := JourneyProgress.project_crop_needs(state, project)
	var goal_dishes := {}
	if JourneyProgress.project_available(state, project) and not JourneyProgress.project_complete(state, project):
		goal_dishes = JourneyProgress.data().projects[project].stages[JourneyProgress.project_stage(state, project)].dishes
	var gathering := JourneyGatherings.planned(state)
	if not gathering.is_empty():
		goal_crops = JourneyGatherings.crop_needs(state)
		goal_dishes = {JourneyGatherings.themes()[gathering].dish: 1}
	if not JourneyRequests.tracked(state).is_empty():
		goal_crops = JourneyRequests.crop_needs(state)
		goal_dishes = JourneyRequests.dish_needs(state)
	_sell_items.clear()
	var room := maxi(0, budget_per_day - settled)
	var initial_room := room
	var total := 0
	var any_produce := false
	for id in CropInfo.ORDER:
		var n := maxi(0, int(produce.get(id, 0)) - int(reserved.get(id, 0)))
		var row: Dictionary = _produce_rows[id]
		_qty[id] = n
		(row.box as Control).visible = n > 0 or int(reserved.get(id, 0)) > 0
		(row.label as Label).text = L10n.format_text("%s\n%d available%s", [CropInfo.name_of(id), n, L10n.format_text(" / %d reserved", int(reserved[id])) if int(reserved.get(id, 0)) > 0 else ""])
		(row.button as Button).disabled = blocked or n <= 0 or initial_room < CropInfo.unit_price(id, state)
		if n <= 0:
			(row.total as Label).text = "0"
			continue
		any_produce = true
		var price := CropInfo.unit_price(id, state)
		var can := mini(n, room / maxi(price, 1))
		(row.price as Label).text = L10n.format_text("%d each", price)
		(row.total as Label).text = str(can * price)
		var keep := 0
		if JourneyProgress.active(state):
			if id in ["C", "L"] and not JourneyProgress.fact(state, "shared_meal"): keep = 1
			if id == "H" and not JourneyProgress.fact(state, "planter_planted"): keep = 1
		keep = maxi(keep, int(goal_crops.get(id, 0)))
		if int(goal_crops.get(id, 0)) > 0:
			(row.label as Label).text += L10n.format_text("\n%d for your goal", mini(n, int(goal_crops[id])))
		var batch := maxi(0, n - keep)
		if batch > 0: _sell_items.append({"kind": "produce", "id": id, "qty": batch})
		var batch_value := mini(batch, can) * price
		total += batch_value
		room -= batch_value
	for id in _recipes:
		var n := int(inv.get("dishes", {}).get(id, 0))
		var row: Dictionary = _dish_rows[id]
		(row.box as Control).visible = n > 0
		if n <= 0: continue
		any_produce = true
		var price := int(JourneyProgress.data().dish_prices[id]) if JourneyProgress.active(state) else int(_recipes[id].stall_price)
		var can := mini(n, room / maxi(price, 1))
		(row.label as Label).text = L10n.format_text("%s\n%d available", [L10n.dish_name(str(id)), n])
		(row.price as Label).text = L10n.format_text("%d each", price)
		(row.total as Label).text = str(can * price)
		(row.button as Button).disabled = blocked or initial_room < price
		var keep := 1 if JourneyProgress.active(state) and id == "salad" and not JourneyProgress.fact(state, "shared_meal") else 0
		keep = maxi(keep, int(goal_dishes.get(id, 0)))
		if int(goal_dishes.get(id, 0)) > 0:
			(row.label as Label).text += L10n.format_text("\n%d for your goal", mini(n, int(goal_dishes[id])))
		var batch := maxi(0, n - keep)
		if batch > 0: _sell_items.append({"kind": "dish", "id": id, "qty": batch})
		var batch_value := mini(batch, can) * price
		total += batch_value
		room -= batch_value
	var fish_stacks: Array = state.get("bag", {}).get("slots", []) + state.get("bag", {}).get("overflow", [])
	for id in _fish_rows:
		var row: Dictionary = _fish_rows[id]
		var entries := fish_stacks.filter(func(entry): return entry.item_id == id)
		row.box.visible = not entries.is_empty()
		if entries.is_empty(): continue
		var entry: Dictionary = entries[0]
		row.stack_id = str(entry.id)
		row.label.text = ItemCatalog.name_of(id) + " · " + FishingModel.tier_name(id) + " ×" + str(int(entry.quantity))
		row.button.text = L10n.text("Sell") + " 1"
		row.button.tooltip_text = L10n.format_text("Sell %d fish · +%d coins", [1, int(FishingModel.fish(id).price)])
		row.label.text += "\n" + L10n.format_text("%d each", int(FishingModel.fish(id).price))
		row.button.disabled = blocked
	_empty.visible = not any_produce and not fish_stacks.any(func(entry): return FishingModel.fish(str(entry.item_id)).size() > 0)
	_sell_all.text = L10n.format_text("Sell all · +%d", total)
	if JourneyProgress.active(state): _sell_all.text = L10n.format_text("Sell surplus - +%d", total)
	_sell_all.disabled = blocked or total <= 0
	_sell_all.visible = any_produce
	var wallet := int(state.get("wallet", 0))
	_wallet.text = str(wallet)
	for id in CropInfo.ORDER:
		var row: Dictionary = _seed_rows[id]
		(row.box as Control).visible = unlocked.has(id)
		if not unlocked.has(id):
			continue
		var have := NextStep.seeds_of(inv, id)
		var cost := CropInfo.seed_price(id) * _buy_qty
		var bound := int(inv.get("seeds", {}).get(id, {}).get("bound", 0))
		(row.label as Label).text = L10n.format_text("%s\n%d owned%s", [CropInfo.name_of(id), have, L10n.format_text("\n%d gifted", bound).replace("\n", " · ") if bound > 0 else ""])
		(row.price as Label).text = L10n.format_text("%d each", CropInfo.seed_price(id))
		(row.button as Button).text = L10n.format_text("Buy %d · %d", [_buy_qty, cost])
		(row.button as Button).disabled = blocked or wallet < cost
	_quantity.text = L10n.count_text("%d seed", "%d seeds", _buy_qty)
	_quantity_minus.disabled = blocked or _buy_qty <= 1
	_quantity_plus.disabled = blocked or _buy_qty >= 12
	if not _page_chosen: _page = "sell" if not _empty.visible else "seeds"
	_selling_rows.visible = _page == "sell"
	_buying_rows.visible = _page == "seeds"
	_quantity_row.visible = _page == "seeds"
	_sell_all.visible = _page == "sell" and any_produce
	for id in _tabs:
		_tabs[id].theme_type_variation = &"TabSelectedButton" if id == _page else &"TabButton"
		_tabs[id].disabled = _busy
	if get_parent() is Control: fit_height((get_parent() as Control).size)

var _produce_rows: Dictionary = {}
var _seed_rows: Dictionary = {}
var _dish_rows: Dictionary = {}
var _fish_rows: Dictionary = {}
var _qty: Dictionary = {}
var _empty: Label
var _built := false

func _ensure_rows() -> void:
	if _built: return
	_built = true
	for id in CropInfo.ORDER: _produce_rows[id] = _row(id, false)
	for id in _recipes: _dish_rows[id] = _row(id, false, true)
	for id in FishingModel.data().fish:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", GameUi.card_style(false, 6))
		_selling_rows.add_child(box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		box.add_child(row)
		row.add_child(GameUi.picture(ItemCatalog.texture(str(id)), 40))
		var label := GameUi.label("", 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var button := GameUi.button("", "", L10n.text("Sell fish"), true)
		button.name = "StallFish_" + str(id)
		button.custom_minimum_size = Vector2(82, 44)
		button.add_theme_font_size_override("font_size", 11)
		button.clip_text = true
		row.add_child(button)
		_fish_rows[id] = {"box": box, "label": label, "button": button, "stack_id": ""}
		button.pressed.connect(func():
			if not button.disabled: fish_sell_requested.emit(str(_fish_rows[id].stack_id), 1))
	_empty = GameUi.label(L10n.text("No harvest in your basket yet"), 12, GameUi.MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selling_rows.add_child(_empty)
	_sell_all = GameUi.button("shopping-basket", L10n.text("Sell all"), L10n.text("Sell harvested produce"), true)
	_sell_all.name = "StallSellSurplus"
	_sell_all.pressed.connect(func():
		if not _sell_all.disabled: sell_requested.emit(_sell_items.duplicate(true)))
	_footer.add_child(_sell_all)
	_quantity_row = HBoxContainer.new()
	_quantity_row.add_theme_constant_override("separation", 8)
	_quantity_minus = GameUi.button("minus", "", L10n.text("Buy one fewer seed"))
	_quantity_minus.custom_minimum_size = Vector2(44, 44)
	_quantity_minus.pressed.connect(func(): set_buy_quantity(_buy_qty - 1))
	_quantity_row.add_child(_quantity_minus)
	_quantity = GameUi.label("", 13)
	_quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quantity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quantity_row.add_child(_quantity)
	_quantity_plus = GameUi.button("plus", "", L10n.text("Buy one more seed"))
	_quantity_plus.custom_minimum_size = Vector2(44, 44)
	_quantity_plus.pressed.connect(func(): set_buy_quantity(_buy_qty + 1))
	_quantity_row.add_child(_quantity_plus)
	_footer.add_child(_quantity_row)
	for id in CropInfo.ORDER: _seed_rows[id] = _row(id, true)

func _row(crop: String, seed: bool, dish := false) -> Dictionary:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", GameUi.card_style(false, 6))
	box.custom_minimum_size.y = 66
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	box.add_child(h)
	h.add_child(GameUi.picture(GameUi.dish_art(crop) if dish else GameUi.crop_art(crop, seed), 40))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	h.add_child(words)
	var l := GameUi.label("", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(l)
	var price := GameUi.label("", 10, GameUi.MUTED)
	words.add_child(price)
	var b: Button
	var total: Label
	if seed:
		b = GameUi.button("", "", L10n.format_text("Buy %s seeds", CropInfo.name_of(crop)), true)
		b.name = "StallSeed_" + crop
		b.custom_minimum_size = Vector2(86, 44)
		b.add_theme_font_size_override("font_size", 11)
		b.clip_text = true
		b.pressed.connect(func():
			if not b.disabled: buy_requested.emit(crop, _buy_qty))
	else:
		total = GameUi.label("", 12, GameUi.GOLD)
		total.name = "StockValue_" + crop
		total.visible = false # Full-stock value belongs to the single, explicit surplus-sale action.
		words.add_child(total)
		b = GameUi.button("", L10n.text("Sell") + " 1", L10n.format_text("Sell one %s", L10n.dish_name(crop) if dish else CropInfo.name_of(crop)), true)
		b.name = ("StallDish_" if dish else "StallProduce_") + crop
		b.custom_minimum_size = Vector2(72, 44)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func():
			if not b.disabled: sell_requested.emit([{"kind": "dish" if dish else "produce", "id": crop, "qty": 1}]))
	h.add_child(b)
	box.visible = false
	(_buying_rows if seed else _selling_rows).add_child(box)
	return {"box": box, "label": l, "button": b, "price": price, "total": total}

func set_buy_quantity(quantity: int) -> void:
	if _busy or _uncertain: return
	_buy_qty = clampi(quantity, 1, 12)
	refresh(_last_state, _last_unlocked, _last_budget)

func focus_seed(crop: String) -> void:
	if not _seed_rows.has(crop) or not _last_unlocked.has(crop): return
	_page = "seeds"
	_page_chosen = true
	set_buy_quantity(1)
	# Modal sizing and row visibility settle after opening the sheet.
	for frame in 2: await get_tree().process_frame
	if visible and _seed_rows[crop].box.is_visible_in_tree():
		_scroll.ensure_control_visible(_seed_rows[crop].box)

func set_busy(value: bool) -> void:
	_busy = value
	refresh(_last_state, _last_unlocked, _last_budget)

func is_busy() -> bool:
	return _busy

func set_uncertain(value: bool) -> void:
	_uncertain = value
	refresh(_last_state, _last_unlocked, _last_budget)

func open() -> void:
	_page_chosen = true
	visible = true

## 当前可见的行按钮（测试用）。
func row_buttons() -> Array:
	var out: Array = []
	var pending: Array[Node] = [_selling_rows if _page == "sell" else _buying_rows, _footer]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Control and not node.visible: continue
		if node is Button: out.append(node)
		for child in node.get_children(): pending.append(child)
	return out
