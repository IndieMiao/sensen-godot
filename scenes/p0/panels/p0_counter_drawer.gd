class_name P0CounterDrawer
extends UiDrawer
## P0 counter drawer (SGODOT-224; LOCK-15 / 16; FARM-6 482:46, NPC-2 482:116, NPC-2-2 482:118). Top to bottom:
##   head       the unattended Homestead Stall: `Homestead Stall` + Close, then Buy | Stall Board (FARM-6);
##              an outpost: UiKeeperBar (role tint, `Finn's Tackle · Xuhui Tackle Shop`, `Tackle Keeper · Finn`,
##              the keeper's line), then Buy | Market Board at the market (NPC-2). The P0 tackle shop has one page,
##              so no tab row (李白 / 安其拉 q(46), NPC-2-2).
##   shelf      UiShopRow per offer (F-07 counter_buy: stepper + Buy, or the grey reason), four rows tall, scrolls.
##   bag half   divider · `Bag 19/25` + capacity track · the scope chip (`All` at home, `Sell here` at an outpost)
##              with the buy-back line · the selected stack's card (UiInfoSheet, counter_sell: Sell / Sell All,
##              Locked + Unlock) · the five-column grid (at an outpost only what this counter buys, LOCK-15).
##              A counter that buys nothing (the P0 market) has no bag half.
##   board      the Stall Board / Market Board page: `board` is left empty for the P0 UI to fill.
##   drinks     the tea house and the post desk (NPC-6 482:133, NPC-7-P0 1507:97237, TEA-DONE / NEARFULL / BLOCKED):
##              keeper bar with the shared-cups note, `Drinks left today · 3 of 3`, the next cup's line and one
##              command (`Hot Tea · +30 Energy`, or the grey reason). A shorter drawer (top at y 534), no bag.
## Everything shown comes from the server view (view.shops[role], view.quotas, view.keepers) through P0ItemInfo /
## P0Logic; names and places come from the outpost's ctx. Buttons only report (`action_requested`); the P0 UI sends
## the command with the shop.

signal action_requested(action: StringName, item_id: String, payload: Dictionary)
signal info_requested(item_id: String)
signal section_changed(section: String)

const HEIGHT := 696.0           # drawer top at y 104 of 800 (FARM-6, NPC-2-2)
const HEIGHT_DRINKS := 266.0    # NPC-6 / NPC-7-P0: keeper bar at y 540
## A counter that buys nothing back (the P0 market, sell []): keeper bar, tabs and the four-row shelf only.
const HEIGHT_NO_BAG := 420.0
const DRINK_ROLES := ["tea", "post"]
## KeeperBar notes on the drink counters (NPC-6, NPC-7-P0): one daily cup count across both.
const DRINK_NOTES := {"tea": "Counts across all tea houses · %d cups a day", "post": "Shares the %d cups a day with tea"}
## The drink's short name in the sold-out reason (TEA-BLOCKED `Tea 3/3 today · back tomorrow`).
const DRINK_SHORT := {"tea": "Tea", "post": "Coffee"}
const SHELF_ROWS := 4           # FARM-6: four product rows, then the divider at y 428
const _ROW_H := 58.0
const _TOP_KEEPER := 6.0        # keeper bar at y 110
const _TOP_STALL := 0.0         # stall title row (44, Close) at y 104, its chips right under it
const _GAP := 8.0
const _SMALL := 4.0
const _TRACK := Vector2(110, 3) # Compact/Shop Bag capacity track
const _SCOPE_H := 36.0
const _DRINK_INSET := 12.0      # NPC-6: fact / line / command at x 24
const _DRINK_GAP := 6.0         # keeper bar (with its note) to `Drinks left today`
## Shop titles over the keeper's place (KeeperBar Titled: `Finn's Tackle`, `Mei's Stall`, `Ama's Tea`, `Sigrid's Desk`).
const SHOP_NOUN := {"tackle": "Tackle", "market": "Stall", "tea": "Tea", "post": "Desk"}
## Keeper role and P0 name when the opener passes no ctx (assets/p0/p0_outposts.json keeper, SGODOT-227).
const KEEPERS := {"tackle": ["Tackle Keeper", "Finn"], "market": ["Market Keeper", "Mei"], "tea": ["Tea Host", "Ama"],
	"post": ["Post Clerk", "Sigrid"]}
## Page tabs: the stall's board and the market's board (FARM-6 / NPC-2); one page shows no tab row.
const SECTIONS := {"homestead": [["buy", "Buy"], ["board", "Stall Board"]], "market": [["buy", "Buy"], ["board", "Market Board"]]}

var view := {}
var role := "homestead"
## The outpost's ctx: {keeper, place, nearest} (SGODOT-227 keeper_ctx()).
var ctx := {}
var section := "buy"
## `place` for the item-info rules ("home" at the stall, "outpost").
var place := "home"

var keeper_bar: UiKeeperBar
var shelf: VBoxContainer
var sheet: UiInfoSheet
var grid: UiInventoryGrid
## The board page's column (Stall Board / Market Board); the P0 UI fills it.
var board: VBoxContainer

var _top_pad := _TOP_STALL
var _shelf_box: TouchScrollContainer
var _bag_half: VBoxContainer
var _count: Label
var _track: _Track
var _quota: Label
var _drinks: VBoxContainer
var _rows := {}   # item id -> UiShopRow
var _qty := {}    # item id -> stepper count
var _key := 0

func _init(view_: Dictionary = {}, role_ := "homestead", ctx_ := {}, section_ := "buy") -> void:
	role = role_
	ctx = ctx_
	_top_pad = _TOP_STALL if role == "homestead" else _TOP_KEEPER
	super(HEIGHT_DRINKS if role in DRINK_ROLES else (HEIGHT if has_bag_half(view_, role) else HEIGHT_NO_BAG))
	view = view_
	place = "home" if role == "homestead" else "outpost"
	section = section_ if _sections().any(func(s): return s[0] == section_) or section_ == "specialty" else "buy"
	_build_head()
	if role in DRINK_ROLES:
		_drinks = VBoxContainer.new()
		_drinks.add_theme_constant_override(&"separation", 0)
		var inset := MarginContainer.new()   # NPC-6: the fact, line and command sit at x 24 (12 inside the body)
		for side in [&"margin_left", &"margin_right"]: inset.add_theme_constant_override(side, int(_DRINK_INSET))
		_gap(body, _DRINK_GAP)
		inset.add_child(_drinks)
		body.add_child(inset)
		refresh(view_, true)
		return
	_shelf_box = TouchScrollContainer.new()
	_shelf_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_shelf_box.custom_minimum_size.y = SHELF_ROWS * _ROW_H
	body.add_child(_shelf_box)
	shelf = VBoxContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.add_theme_constant_override(&"separation", 0)
	_shelf_box.add_child(shelf)
	board = VBoxContainer.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_theme_constant_override(&"separation", int(_GAP))
	body.add_child(board)
	_build_bag_half()
	refresh(view_, true)

func _restyle() -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 0.0)
	box.corner_radius = Vector4(UiTokens.RADIUS_SHEET, UiTokens.RADIUS_SHEET, 0.0, 0.0)
	add_theme_stylebox_override(&"panel", box.with_margins(pad, _top_pad, pad, safe_bottom))

func _sections() -> Array: return SECTIONS.get(role, [])

func _build_head() -> void:
	if role == "homestead":
		var h := HBoxContainer.new()
		var title := UiKit.label("Homestead Stall", UiTokens.STYLE_C14_XB)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(title)
		var close := UiCloseButton.new()
		close.pressed.connect(func(): close_requested.emit())
		h.add_child(close)
		body.add_child(h)
	else:
		keeper_bar = UiKeeperBar.new(UiKeeperBar.role_of(role))
		var who: Array = KEEPERS.get(role, ["", ""])
		var name := str(ctx.get("keeper", who[1]))
		keeper_bar.portrait = keeper_portrait(name)
		keeper_bar.title = "%s's %s" % [name, str(SHOP_NOUN.get(role, ""))]
		keeper_bar.place = str(ctx.get("place", ""))
		keeper_bar.keeper = "%s · %s" % [str(ctx.get("role", who[0])), name]
		keeper_bar.close_pressed.connect(func(): close_requested.emit())
		body.add_child(keeper_bar)
	var tabs := _sections()
	if tabs.size() > 1:
		if keeper_bar: _gap(body, _SMALL)
		var labels := PackedStringArray(tabs.map(func(s): return str(s[1])))
		var at := maxi(0, tabs.map(func(s): return s[0]).find(section))
		body.add_child(UiFilterChip.row(labels, at, func(i: int): set_section(str(tabs[i][0]))))
		# FARM-6 has 36 px chips (rows at y 188); the kit's chips keep a 44 px touch row, so rows start at 192.
	else:
		_gap(body, _GAP)   # rows at y 199 under the keeper bar (NPC-2-2)

func _build_bag_half() -> void:
	_bag_half = VBoxContainer.new()
	_bag_half.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_half.add_theme_constant_override(&"separation", 0)
	body.add_child(_bag_half)
	_gap(_bag_half, _GAP)
	var line := ColorRect.new()
	line.color = UiTokens.COLOR_BORDER
	line.custom_minimum_size.y = 1.0
	_bag_half.add_child(line)
	_gap(_bag_half, _SMALL + 1.0)
	var cap := HBoxContainer.new()
	cap.custom_minimum_size.y = 24.0
	cap.add_theme_constant_override(&"separation", int(_GAP))
	var label := UiKit.label("Bag", UiTokens.STYLE_C14_XB)
	label.custom_minimum_size.x = 38.0
	cap.add_child(label)
	_count = UiKit.label("", UiTokens.STYLE_C12_XB)
	_count.custom_minimum_size.x = 50.0
	cap.add_child(_count)
	_track = _Track.new()
	_track.custom_minimum_size = _TRACK
	_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(_track)
	_bag_half.add_child(cap)
	_gap(_bag_half, 2.0)
	var scope := HBoxContainer.new()
	scope.custom_minimum_size.y = _SCOPE_H
	scope.add_theme_constant_override(&"separation", 12)
	var chip := UiFilterChip.new("All" if role == "homestead" else "Sell here", true)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE   # one scope per counter: a label, not a filter
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scope.add_child(chip)
	_quota = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	_quota.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quota.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quota.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope.add_child(_quota)
	_bag_half.add_child(scope)
	_gap(_bag_half, _SMALL)
	sheet = UiInfoSheet.new()
	sheet.rules = func(id: String, c: StringName, o: Dictionary) -> Dictionary: return P0ItemInfo.spec(view, id, c, o)
	sheet.action_requested.connect(func(a: StringName, id: String, p: Dictionary): action_requested.emit(a, id, p))
	sheet.info_requested.connect(func(id: String): info_requested.emit(id))
	_bag_half.add_child(sheet)
	_gap(_bag_half, _SMALL)
	grid = UiInventoryGrid.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.sell_mode = role != "homestead"
	grid.can_sell = func(it: Dictionary) -> bool: return P0ItemInfo.flags(view, str(it.id), &"counter_sell", _opts()).sold_here
	grid.on_select = func(it: Dictionary): select(str(it.id))
	grid.selection_cleared.connect(func(): sheet.close())
	_bag_half.add_child(grid)

func _opts(qty := 1) -> Dictionary: return {counter = role, place = place, qty = qty}

## New server view: the shelf, counts, the grid and the open card follow it; the selection, steppers and scroll
## stay. Called every frame by the P0 UI, so a view that changes nothing shown here is skipped.
func refresh(view_: Dictionary, force := false) -> void:
	var key := [view_.get("shops", {}).get(role, {}), view_.get("quotas", {}), view_.get("bag", {}), view_.get("gear", {}),
		int(view_.get("coins", 0)), view_.get("keepers", {}).get(role, {}), section, _qty].hash()
	view = view_
	if key == _key and not force: return
	_key = key
	if keeper_bar: keeper_bar.line = str(P0Logic.keeper_lines(view, role, ctx).get("greet", ""))
	if _drinks != null:
		_fill_drinks()
		return
	var shows_shelf := section != "board"
	_shelf_box.visible = shows_shelf
	board.visible = not shows_shelf
	_fill_shelf()
	var buys := has_bag_half(view, role)
	_bag_half.visible = buys and shows_shelf
	if not _bag_half.visible: return
	var bag: Dictionary = view.get("bag", {})
	var used := (bag.get("slots", []) as Array).size()
	var capacity := int(bag.get("capacity", 25))
	_count.text = "%d/%d" % [used, capacity]
	_track.fill = clampf(float(used) / maxf(1.0, float(capacity)), 0.0, 1.0)
	_track.queue_redraw()
	grid.capacity = capacity
	grid.items = P0BagDrawer.bag_items(view)
	if sheet.is_open(): sheet.refresh()
	_quota.text = quota_text(view, role, grid.selected_id if sheet.is_open() else "")

## The offers on the current page: the Buy shelf, or the market's City Specialty shelf (content market.specialty).
func offers() -> Array:
	var all: Array = view.get("shops", {}).get(role, {}).get("buy", [])
	if role != "market": return all
	var listed: Array = P0Logic.content().get("market", {}).get("specialty" if section == "specialty" else "buy", [])
	return all.filter(func(o): return listed.has(str(o.get("id", ""))))

func _fill_shelf() -> void:
	var list := offers()
	var ids := list.map(func(o): return str(o.id))
	if ids != _rows.keys():
		for c in shelf.get_children():
			c.hide()
			c.queue_free()
		_rows.clear()
		for id in ids:
			var row := UiShopRow.new()
			row.bought.connect(func(item: String, qty: int): action_requested.emit(&"buy", item, {qty = qty}))
			row.info_requested.connect(func(item: String): info_requested.emit(item))
			row.quantity_changed.connect(func(item: String, qty: int):
				_qty[item] = qty
				_show_row(item))
			shelf.add_child(row)
			_rows[id] = row
	for id in ids: _show_row(str(id))

func _show_row(id: String) -> void:
	var o := {}
	for x in offers():
		if str(x.get("id", "")) == id: o = x
	if o.is_empty() or not _rows.has(id): return
	var qty := int(_qty.get(id, 1))
	var spec := P0ItemInfo.spec(view, id, &"counter_buy", _opts(qty))
	var once := bool(o.get("once", false)) or str(o.get("to", "")) in ["gear", "bag_cap"]
	(_rows[id] as UiShopRow).show_spec(spec, once, int(o.left) if o.get("left", null) != null else 99)

func set_section(v: String) -> void:
	if v == section: return
	section = v
	refresh(view, true)
	section_changed.emit(v)

## The drink page from view.drinks ({used, limit, left, price, need, energy, gain, full, items}).
func _fill_drinks() -> void:
	for c in _drinks.get_children():
		c.hide()
		c.queue_free()
	var d: Dictionary = view.get("drinks", {})
	var item := drink_item(view, role)
	var name := str(item.get("name", ""))
	var limit := int(d.get("limit", 3))
	var left := int(d.get("left", 0))
	var gain := int(d.get("gain", 0))
	var energy := gain if gain > 0 and gain < int(d.get("energy", 30)) else int(d.get("energy", 30))   # TEA-NEARFULL: +12
	if keeper_bar: keeper_bar.note = str(DRINK_NOTES.get(role, "%d")) % limit
	_drinks.add_child(UiFactRow.new("Drinks left today", "%d of %d" % [left, limit]))
	_gap(_drinks, _SMALL)
	var line := "%s · +%d Energy" % [name, energy]
	if left > 0: line += " · %d coins (%d/%d)" % [int(d.get("price", 0)), int(d.get("used", 0)) + 1, limit]
	_drinks.add_child(UiKit.label(line, UiTokens.STYLE_C12_XB))
	_gap(_drinks, _SMALL)
	var reason := ""
	if left <= 0: reason = "%s %d/%d today · back tomorrow" % [str(DRINK_SHORT.get(role, name)), limit, limit]
	elif bool(d.get("full", false)): reason = "Energy full"
	elif int(view.get("coins", 0)) < int(d.get("need", d.get("price", 0))):
		reason = "Need %d more coins" % (int(d.get("need", d.get("price", 0))) - int(view.get("coins", 0)))
	var b := UiCommandButton.new("" if reason != "" else "%s · +%d Energy" % [name, energy])
	if reason != "": b.reason = reason
	else: b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id := str(item.get("id", ""))
	b.activated.connect(func(): action_requested.emit(&"drink", id, {}))
	_drinks.add_child(b)

## The drink this counter pours (view.drinks.items: {id, name, shop}).
static func drink_item(view: Dictionary, role: String) -> Dictionary:
	for it in view.get("drinks", {}).get("items", []):
		if str(it.get("shop", "")) == role: return it
	return {}

## Select a bag stack: its counter_sell card, or nothing for a kind this counter has no card for.
func select(id: String) -> void:
	var spec := P0ItemInfo.spec(view, id, &"counter_sell", _opts())
	if bool(spec.get("card", false)): sheet.open(id, &"counter_sell", _opts())
	else: sheet.close()
	_quota.text = quota_text(view, role, id if sheet.is_open() else "")

## Whether a counter buys anything back (the P0 market buys nothing: no bag half).
static func has_bag_half(view: Dictionary, role: String) -> bool:
	return role == "homestead" or not (view.get("shops", {}).get(role, {}).get("sell", []) as Array).is_empty()

## The line beside the scope chip: the selected stack's buy-back allowance, else this counter's first allowance
## ("Fish buy-back today 30/80" over "any Tackle Shop · resets in 9h 12m"), or "Crops & fish · no daily limit" at home.
static func quota_text(view: Dictionary, role: String, selected := "") -> String:
	var q := {}
	if selected != "": q = P0ItemInfo.spec(view, selected, &"counter_sell", {counter = role}).get("quota", {})
	if q.is_empty(): q = P0ItemInfo.counter_quota(view, role)
	if q.is_empty(): return ""
	return str(q.get("text", "")) + ("\n" + str(q.note) if str(q.get("note", "")) != "" else "")

## The keeper's 44 px head (assets/p0/art/keepers/<name>_head.jpg), null for a name without art.
static func keeper_portrait(name: String, card := false) -> Texture2D:
	var path := "res://assets/p0/art/keepers/%s_%s.jpg" % [name.to_lower(), "card" if card else "head"]
	return load(path) if ResourceLoader.exists(path) else null

static func _gap(parent: Control, h: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size.y = h
	parent.add_child(c)
	return c

## Compact/Shop Bag capacity track: 110 × 3, border-colour track, primary fill.
class _Track extends Control:
	var fill := 0.0

	func _draw() -> void:
		draw_style_box(UiStyleBox.make(UiTokens.COLOR_BORDER, UiTokens.RADIUS_TRACK), Rect2(Vector2.ZERO, size))
		if fill > 0.0:
			draw_style_box(UiStyleBox.make(UiTokens.COLOR_PRIMARY, UiTokens.RADIUS_TRACK), Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * fill), size.y)))
