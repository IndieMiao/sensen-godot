class_name StallSheet
extends PanelContainer
## 路边摊：卖产出、买种子。数字只是把服务端会给的数提前写在按钮上，成交以回包为准。
## 界面文案一律英文。

signal sell_requested(items: Array)        ## [{kind:"produce", id, qty}]
signal buy_requested(crop: String, qty: int)
signal retry_requested()
signal closed()

const BUY_QTY := 3

var _title: Label
var _budget: Label
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
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 8.0
	offset_right = -8.0
	offset_bottom = -8.0
	offset_top = -380.0
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = GameUi.label("Roadside stall", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := GameUi.button("x", "", "Close stall")
	close.pressed.connect(func():
		if _busy: return
		visible = false
		emit_signal("closed"))
	head.add_child(close)
	_budget = GameUi.label("", 12, GameUi.MUTED)
	v.add_child(_budget)
	_retry = GameUi.button("rotate-ccw", "Check last trade", "Reload the last trade result")
	_retry.visible = false
	_retry.pressed.connect(func():
		if not _retry.disabled: retry_requested.emit())
	v.add_child(_retry)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 12)
	_scroll.add_child(_rows)

func fit_height(area: Vector2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var height := minf(maxf(320, _rows.get_combined_minimum_size().y + 100), minf(500, area.y - 150))
	position = Vector2(0, area.y - height)
	size = Vector2(area.x, height)

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
	_budget.text = "Today's sales %d / %d coins" % [settled, budget_per_day]
	if JourneyProgress.active(state):
		budget_per_day = 2147483647
		_budget.text = "Neighbourhood stall"
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
		(row.label as Label).text = "%s\n%d available%s" % [CropInfo.name_of(id), n, " / %d reserved" % int(reserved[id]) if int(reserved.get(id, 0)) > 0 else ""]
		(row.button as Button).disabled = blocked or n <= 0 or initial_room < CropInfo.unit_price(id, state)
		if n <= 0:
			(row.total as Label).text = "0"
			continue
		any_produce = true
		var price := CropInfo.unit_price(id, state)
		var can := mini(n, room / maxi(price, 1))
		(row.price as Label).text = "%d each" % price
		(row.total as Label).text = str(can * price)
		var keep := 0
		if JourneyProgress.active(state):
			if id in ["C", "L"] and not JourneyProgress.fact(state, "shared_meal"): keep = 1
			if id == "H" and not JourneyProgress.fact(state, "planter_planted"): keep = 1
		keep = maxi(keep, int(goal_crops.get(id, 0)))
		if int(goal_crops.get(id, 0)) > 0:
			(row.label as Label).text += "\n%d for your goal" % mini(n, int(goal_crops[id]))
		var batch := maxi(0, n - keep)
		if batch > 0: _sell_items.append({"kind": "produce", "id": id, "qty": batch})
		var batch_value := mini(batch, can) * price
		total += batch_value
		room -= batch_value
	for id in ["salad", "tea"]:
		var n := int(inv.get("dishes", {}).get(id, 0))
		var row: Dictionary = _dish_rows[id]
		(row.box as Control).visible = n > 0
		if n <= 0: continue
		any_produce = true
		var price := int(JourneyProgress.data().dish_prices[id]) if JourneyProgress.active(state) else int(_recipes[id].stall_price)
		var can := mini(n, room / maxi(price, 1))
		(row.label as Label).text = "%s\n%d available" % ["Vegetable salad" if id == "salad" else "Chamomile tea", n]
		(row.price as Label).text = "%d each" % price
		(row.total as Label).text = str(can * price)
		(row.button as Button).disabled = blocked or initial_room < price
		var keep := 1 if JourneyProgress.active(state) and id == "salad" and not JourneyProgress.fact(state, "shared_meal") else 0
		keep = maxi(keep, int(goal_dishes.get(id, 0)))
		if int(goal_dishes.get(id, 0)) > 0:
			(row.label as Label).text += "\n%d for your goal" % mini(n, int(goal_dishes[id]))
		var batch := maxi(0, n - keep)
		if batch > 0: _sell_items.append({"kind": "dish", "id": id, "qty": batch})
		var batch_value := mini(batch, can) * price
		total += batch_value
		room -= batch_value
	_empty.visible = not any_produce
	_sell_all.text = "Sell all · +%d" % total
	if JourneyProgress.active(state): _sell_all.text = "Sell surplus - +%d" % total
	_sell_all.disabled = blocked or total <= 0
	_sell_all.visible = any_produce
	var wallet := int(state.get("wallet", 0))
	for id in CropInfo.ORDER:
		var row: Dictionary = _seed_rows[id]
		(row.box as Control).visible = unlocked.has(id)
		if not unlocked.has(id):
			continue
		var have := NextStep.seeds_of(inv, id)
		var cost := CropInfo.seed_price(id) * _buy_qty
		var bound := int(inv.get("seeds", {}).get(id, {}).get("bound", 0))
		(row.label as Label).text = "%s\n%d owned%s" % [CropInfo.name_of(id), have, "\n%d gifted" % bound if bound > 0 else ""]
		(row.price as Label).text = "%d each" % CropInfo.seed_price(id)
		(row.button as Button).text = "Buy %d · %d" % [_buy_qty, cost]
		(row.button as Button).disabled = blocked or wallet < cost
	_quantity.text = "%d seed%s" % [_buy_qty, "" if _buy_qty == 1 else "s"]
	_quantity_minus.disabled = blocked or _buy_qty <= 1
	_quantity_plus.disabled = blocked or _buy_qty >= 12
	if get_parent() is Control: fit_height((get_parent() as Control).size)

var _produce_rows: Dictionary = {}
var _seed_rows: Dictionary = {}
var _dish_rows: Dictionary = {}
var _qty: Dictionary = {}
var _empty: Label
var _built := false

func _ensure_rows() -> void:
	if _built:
		return
	_built = true
	_rows.add_child(GameUi.label("Harvested", 12, GameUi.GREEN))
	for id in CropInfo.ORDER:
		_produce_rows[id] = _row(id, false)
	for id in ["salad", "tea"]:
		_dish_rows[id] = _row(id, false, true)
	_empty = Label.new()
	_empty.text = "No harvest in your basket yet"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_empty.add_theme_color_override("font_color", DesignTokens.INK_SUB)
	_rows.add_child(_empty)
	_sell_all = GameUi.button("shopping-basket", "Sell all", "Sell harvested produce")
	_sell_all.pressed.connect(func():
		if not _sell_all.disabled: sell_requested.emit(_sell_items.duplicate(true)))
	_rows.add_child(_sell_all)
	_rows.add_child(HSeparator.new())
	var seeds_title := Label.new()
	seeds_title.text = "Seeds"
	seeds_title.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	seeds_title.add_theme_color_override("font_color", DesignTokens.INK_SUB)
	_rows.add_child(seeds_title)
	var quantity_row := HBoxContainer.new()
	quantity_row.add_theme_constant_override("separation", 8)
	_quantity_minus = GameUi.button("minus", "", "Buy one fewer seed")
	_quantity_minus.pressed.connect(func(): set_buy_quantity(_buy_qty - 1))
	quantity_row.add_child(_quantity_minus)
	_quantity = GameUi.label("", 13)
	_quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quantity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_row.add_child(_quantity)
	_quantity_plus = GameUi.button("plus", "", "Buy one more seed")
	_quantity_plus.pressed.connect(func(): set_buy_quantity(_buy_qty + 1))
	quantity_row.add_child(_quantity_plus)
	_rows.add_child(quantity_row)
	for id in CropInfo.ORDER:
		_seed_rows[id] = _row(id, true)

func _row(crop: String, seed: bool, dish := false) -> Dictionary:
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = 48
	h.add_theme_constant_override("separation", 8)
	h.add_child(GameUi.picture(GameUi.dish_art(crop) if dish else GameUi.crop_art(crop, seed), 40))
	var l := GameUi.label("", 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	var price := GameUi.label("", 11, GameUi.MUTED)
	h.add_child(price)
	var b: Button
	var total: Label
	if seed:
		b = GameUi.button("coins", "", "Buy %s seeds" % CropInfo.name_of(crop))
		b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_theme_constant_override("icon_max_width", 14)
		b.custom_minimum_size = Vector2(100, 44)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func():
			if not b.disabled: buy_requested.emit(crop, _buy_qty))
		h.add_child(b)
	else:
		total = GameUi.label("", 14, Color("ac771c"))
		total.custom_minimum_size.x = 40
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(total)
		b = GameUi.button("coins", "1", "Sell one %s" % crop)
		b.custom_minimum_size = Vector2(48, 44)
		b.pressed.connect(func():
			if not b.disabled: sell_requested.emit([{"kind": "dish" if dish else "produce", "id": crop, "qty": 1}]))
		h.add_child(b)
	h.visible = false
	_rows.add_child(h)
	return {"box": h, "label": l, "button": b, "price": price, "total": total}

func set_buy_quantity(quantity: int) -> void:
	if _busy or _uncertain: return
	_buy_qty = clampi(quantity, 1, 12)
	refresh(_last_state, _last_unlocked, _last_budget)

func focus_seed(crop: String) -> void:
	if not _seed_rows.has(crop) or not _last_unlocked.has(crop): return
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
	visible = true

## 当前可见的行按钮（测试用）。
func row_buttons() -> Array:
	var out := []
	for r in _rows.get_children():
		if not (r as Control).visible:
			continue
		if r is Button: out.append(r)
		for c in r.get_children():
			if c is Button:
				out.append(c)
	return out
