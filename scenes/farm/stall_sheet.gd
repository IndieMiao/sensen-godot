class_name StallSheet
extends PanelContainer
## 路边摊：卖产出、买种子。数字只是把服务端会给的数提前写在按钮上，成交以回包为准。
## 界面文案一律英文。

signal sell_requested(items: Array)        ## [{kind:"produce", id, qty}]
signal buy_requested(crop: String, qty: int)
signal closed()

const BUY_QTY := 3

var _title: Label
var _budget: Label
var _rows: VBoxContainer

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
	_title = Label.new()
	_title.text = "Roadside stall"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	head.add_child(_title)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"GhostButton"
	close.custom_minimum_size.y = 40.0
	close.pressed.connect(func():
		visible = false
		emit_signal("closed"))
	head.add_child(close)
	_budget = Label.new()
	_budget.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	v.add_child(_budget)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	v.add_child(_rows)

## 用最新状态重画。stall_budget 每日 100（economy.json）。
## 行节点复用：refresh 可能在某个按钮自己的 pressed 回调里被调（卖完立刻刷新），
## 那时 free 掉按钮会崩，queue_free 又会留一堆孤儿——所以行一次建好，之后只改文字和可用性。
func refresh(state: Dictionary, unlocked: Array, budget_per_day := 100) -> void:
	_ensure_rows()
	var settled := int((state.get("stall", {}) as Dictionary).get("settled", 0))
	_budget.text = "Today's sales %d / %d coins" % [settled, budget_per_day]
	var inv: Dictionary = state.get("inventory", {})
	var produce: Dictionary = inv.get("produce", {})
	var any_produce := false
	for id in CropInfo.ORDER:
		var n := int(produce.get(id, 0))
		var row: Dictionary = _produce_rows[id]
		_qty[id] = n
		(row.box as Control).visible = n > 0
		if n <= 0:
			continue
		any_produce = true
		var price := CropInfo.unit_price(id)
		var room := maxi(0, budget_per_day - settled)
		var can := mini(n, room / maxi(price, 1))
		(row.label as Label).text = "%s ×%d · %d each" % [CropInfo.name_of(id), n, price]
		(row.button as Button).text = "Sell all · +%d" % (can * price)
		(row.button as Button).disabled = can <= 0
	_empty.visible = not any_produce
	var wallet := int(state.get("wallet", 0))
	for id in CropInfo.ORDER:
		var row: Dictionary = _seed_rows[id]
		(row.box as Control).visible = unlocked.has(id)
		if not unlocked.has(id):
			continue
		var have := NextStep.seeds_of(inv, id)
		var cost := CropInfo.seed_price(id) * BUY_QTY
		(row.label as Label).text = "%s seeds ×%d · %d each" % [CropInfo.name_of(id), have, CropInfo.seed_price(id)]
		(row.button as Button).text = "Buy %d · %d coins" % [BUY_QTY, cost]
		(row.button as Button).disabled = wallet < cost
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 8.0
	offset_right = -8.0
	offset_bottom = -8.0

var _produce_rows: Dictionary = {}
var _seed_rows: Dictionary = {}
var _qty: Dictionary = {}
var _empty: Label
var _built := false

func _ensure_rows() -> void:
	if _built:
		return
	_built = true
	for id in CropInfo.ORDER:
		_produce_rows[id] = _row(func(): emit_signal("sell_requested", [{"kind": "produce", "id": id, "qty": int(_qty.get(id, 0))}]))
	_empty = Label.new()
	_empty.text = "Nothing to sell yet — harvest something first"
	_empty.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_empty.add_theme_color_override("font_color", DesignTokens.INK_SUB)
	_rows.add_child(_empty)
	var seeds_title := Label.new()
	seeds_title.text = "Seeds"
	seeds_title.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	seeds_title.add_theme_color_override("font_color", DesignTokens.INK_SUB)
	_rows.add_child(seeds_title)
	for id in CropInfo.ORDER:
		_seed_rows[id] = _row(func(): emit_signal("buy_requested", id, BUY_QTY))

func _row(on_press: Callable) -> Dictionary:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	h.add_child(l)
	var b := Button.new()
	b.theme_type_variation = &"AccentButton"
	b.custom_minimum_size = Vector2(130.0, 40.0)
	b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	b.pressed.connect(on_press)
	h.add_child(b)
	h.visible = false
	_rows.add_child(h)
	return {"box": h, "label": l, "button": b}

func open() -> void:
	visible = true

## 当前可见的行按钮（测试用）。
func row_buttons() -> Array:
	var out := []
	for r in _rows.get_children():
		if not (r as Control).visible:
			continue
		for c in r.get_children():
			if c is Button:
				out.append(c)
	return out
