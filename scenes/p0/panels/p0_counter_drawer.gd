class_name P0CounterDrawer
extends UiDrawer
## P0 counter drawer (SGODOT-224; LOCK-15 / 16; FARM-6 482:46, NPC-2 482:116, NPC-2-2 482:118). Top to bottom:
##   head       the unattended Homestead Stall: `Homestead Stall` + Close, then Buy | Stall Board (FARM-6);
##              an outpost: UiKeeperBar (role tint, `Finn's Tackle · Mission Tackle Shop`, `Tackle Keeper · Finn`,
##              the keeper's line), then Buy | Market Board at the market (NPC-2). The P0 tackle shop has one page,
##              so no tab row (李白 / 安其拉 q(46), NPC-2-2).
##   shelf      UiShopRow per offer (F-07 counter_buy: stepper + Buy, or the grey reason), four rows tall, scrolls.
##   bag half   divider · `Bag 19/25` + capacity track · the scope chip (`All` at home, `Sell here` at an outpost)
##              with the buy-back line · the selected stack's card (UiInfoSheet, counter_sell: Sell / Sell All,
##              Locked + Unlock) · the five-column grid (at an outpost only what this counter buys, LOCK-15).
##              A counter that buys nothing (the P0 market) has no bag half.
##   board      the Stall Board / Market Board page: `board` is left empty for the P0 UI to fill.
##   specialty  the market's City Specialty shelf (MARKET-SPECIALTY 1394:92801, 李白 q(48)): its own short sheet,
##              `City Specialty` and the postcard row, no keeper bar, no tabs, no bag; the P0 UI floats Close above it.
##   drinks     the tea house and the post desk (NPC-6 482:133, NPC-7-P0 1507:97237, TEA-DONE / NEARFULL / BLOCKED):
##              keeper bar with the shared-cups note, `Cups used · 0/3`, the next cup's line and one
##              command (`Hot Tea · +30 Energy`, or the grey reason). The cups are counted once, used / limit (q(98) ③). A shorter drawer (top at y 534), no bag.
## Everything shown comes from the server view (view.shops[role], view.quotas, view.keepers) through P0ItemInfo /
## P0Logic; names and places come from the outpost's ctx. Buttons only report (`action_requested`); the P0 UI sends
## the command with the shop.

signal action_requested(action: StringName, item_id: String, payload: Dictionary)
signal info_requested(item_id: String)
signal section_changed(section: String)
## fit_height() has settled the short market drawer's height.
signal fitted

const HEIGHT := 696.0           # drawer top at y 104 of 800 (FARM-6, NPC-2-2)
const HEIGHT_DRINKS := 276.0    # NPC-6 / NPC-7-P0: keeper bar at y 540 (16 under the top, clear of the handle; 不知火舞 on 265)
## A counter that buys nothing back (the P0 market, sell []): keeper bar, tabs and its rows only, until fit_height()
## shortens it to its content (q(48): the P0 market has no bag half; 不知火舞 on #56).
const HEIGHT_NO_BAG := 420.0
## MARKET-SPECIALTY: sheet top at y 663 with one row (16 + title 27 + 8 + rows + 28).
const SPECIALTY_PAD := 16.0
static func specialty_height(rows: int) -> float: return 79.0 + 58.0 * maxi(1, rows)
const DRINK_ROLES := ["tea", "post"]
## KeeperBar notes on the drink counters (NPC-6, NPC-7-P0): one daily cup count across both.
const DRINK_NOTES := {"tea": "Counts across all tea houses · %d cups a day", "post": "Shares the %d cups a day with tea"}
## The drink's short name in the sold-out reason (TEA-BLOCKED `Tea 3/3 today · Resets in 9h 12m`, q(98) ③).
const DRINK_SHORT := {"tea": "Tea", "post": "Coffee"}
const SHELF_ROWS := 4           # FARM-6: four product rows, then the divider at y 428
const _ROW_H := 58.0
const _TOP_KEEPER := 16.0       # keeper bar at y 120: under the drawer handle (8–12) with 4 to spare (不知火舞 on 265, A)
const _TOP_STALL := 0.0         # stall title row (44, Close) at y 104, its chips right under it
const _GAP := 8.0
const _SMALL := 4.0
const _TRACK := Vector2(110, 3) # Compact/Shop Bag capacity track
const _SCOPE_H := 36.0
const _DRINK_INSET := 12.0      # NPC-6: fact / line / command at x 24
const _DRINK_GAP := 6.0         # keeper bar (with its note) to `Cups used`
## Shop titles over the keeper's place (KeeperBar Titled: `Finn's Tackle`, `Mei's Stall`, `Ama's Tea`, `Sigrid's Desk`).
const SHOP_NOUN := {"tackle": "Tackle", "market": "Stall", "tea": "Tea", "post": "Desk"}
## Keeper role and P0 name when the opener passes no ctx (assets/p0/p0_outposts.json keeper, SGODOT-227).
const KEEPERS := {"tackle": ["Tackle Keeper", "Finn"], "market": ["Market Keeper", "Mei"], "tea": ["Tea Host", "Ama"],
	"post": ["Post Clerk", "Sigrid"]}
## Page tabs: the stall's board and the market's board (FARM-6 / NPC-2); one page shows no tab row. The stall's Decor
## page (P1, SGODOT-284; FARM-6-DECOR, Figma 2187:33369, q(111)): the yard pieces, into Farm Storage.
const SECTIONS := {"homestead": [["buy", "Buy"], ["decor", "Decor"], ["board", "Stall Board"]], "market": [["buy", "Buy"], ["board", "Market Board"]]}

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
var _cap_track: _Track
var _quota: Label
var _scope: HBoxContainer        # the scope chip and buy-back line (none on the Decor page: nothing is sold there)
var _decor_line: Label           # the Decor page's fact line under the stall's title (`Decor 12/24 · Goes to Farm Storage`)
var _drinks: VBoxContainer
var _rows := {}   # item id -> UiShopRow
var _qty := {}    # item id -> stepper count
var _fit_frames := 0   # frames left before fit_height() measures (both pages laid out)
var _key := 0


## q(16): the toast sits above the selected stack's Sell card (the counter's decision area) while it shows.
func action_area() -> Control: return sheet if sheet != null and sheet.is_visible_in_tree() else null

func _init(view_: Dictionary = {}, role_ := "homestead", ctx_ := {}, section_ := "buy") -> void:
	role = role_
	ctx = ctx_
	_top_pad = _TOP_STALL if role == "homestead" else _TOP_KEEPER
	var specialty := role == "market" and section_ == "specialty"
	if specialty: _top_pad = SPECIALTY_PAD
	view = view_
	section = "specialty" if specialty else (section_ if _sections().any(func(s): return s[0] == section_) else "buy")
	super(HEIGHT_DRINKS if role in DRINK_ROLES else (specialty_height(offers().size()) if specialty
		else (HEIGHT if has_bag_half(view_, role) else HEIGHT_NO_BAG)))
	if specialty: pad = SPECIALTY_PAD
	place = "home" if role == "homestead" else "outpost"
	if specialty:
		body.add_child(UiKit.label("City Specialty", UiTokens.STYLE_TITLE_XB20))
		_gap(body, _GAP - 2.0)   # Figma's title box is 27, Nunito XB 20 is 29 here: the row stays at y 714
	else:
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
	_shelf_box.custom_minimum_size.y = (offers().size() if section == "specialty" or is_short() else SHELF_ROWS) * _ROW_H
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
		var titles := VBoxContainer.new()
		titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		titles.alignment = BoxContainer.ALIGNMENT_CENTER
		titles.add_theme_constant_override(&"separation", 0)
		var title := UiKit.label("Homestead Stall", UiTokens.STYLE_C14_XB)
		titles.add_child(title)
		_decor_line = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
		_decor_line.visible = false
		titles.add_child(_decor_line)
		h.add_child(titles)
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
	_cap_track = _Track.new()
	_cap_track.custom_minimum_size = _TRACK
	_cap_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(_cap_track)
	_bag_half.add_child(cap)
	_gap(_bag_half, 2.0)
	var scope := HBoxContainer.new()
	_scope = scope
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
	grid.on_select = func(it: Dictionary): if section != "decor": select(str(it.id))   # Decor: the bag only shows
	grid.selection_cleared.connect(func(): sheet.close())
	_bag_half.add_child(grid)

## new_ids (STALL-NEW-2): the offers unlocked since this counter was last opened, from the host's ctx.
func _opts(qty := 1) -> Dictionary: return {counter = role, place = place, qty = qty, new_ids = ctx.get("new", [])}

## New server view: the shelf, counts, the grid and the open card follow it; the selection, steppers and scroll
## stay. Called every frame by the P0 UI, so a view that changes nothing shown here is skipped.
func refresh(view_: Dictionary, force := false) -> void:
	var key := [view_.get("shops", {}).get(role, {}), view_.get("quotas", {}), view_.get("bag", {}), view_.get("gear", {}),
		int(view_.get("coins", 0)), view_.get("keepers", {}).get(role, {}), section, _qty, view_.get("decor", {}),
		view_.get("homestead", {}).get("level", 1)].hash()
	view = view_
	if key == _key and not force: return
	_key = key
	if keeper_bar: keeper_bar.line = str(P0Logic.keeper_lines(view, role, ctx).get("counter", ""))
	if _drinks != null:
		_fill_drinks()
		return
	var shows_shelf := section != "board"
	_shelf_box.visible = shows_shelf
	board.visible = not shows_shelf
	_fill_shelf()
	if _decor_line:
		_decor_line.visible = section == "decor"
		_decor_line.text = P0Decor.header_line(view) if section == "decor" else ""
	var buys := has_bag_half(view, role)
	_bag_half.visible = buys and shows_shelf
	if not _bag_half.visible: return
	# The Decor page sells nothing back: the bag below only shows (no scope, no Sell card; 不知火舞 on 284 263ca1d6 ②).
	_scope.visible = section != "decor"
	if section == "decor" and sheet.is_open():
		sheet.close()
		grid.clear_selection()
	var bag: Dictionary = view.get("bag", {})
	var used := (bag.get("slots", []) as Array).size()
	var capacity := int(bag.get("capacity", 25))
	_count.text = "%d/%d" % [used, capacity]
	_cap_track.fill = clampf(float(used) / maxf(1.0, float(capacity)), 0.0, 1.0)
	_cap_track.queue_redraw()
	grid.capacity = capacity
	grid.items = P0BagDrawer.bag_items(view)
	if sheet.is_open(): sheet.refresh()
	_quota.text = quota_text(view, role, grid.selected_id if sheet.is_open() else "")

## The offers on the current page: the market's City Specialty shelf (content market.specialty), or the Buy shelf —
## everything else the server lists, which on a Market includes its city's regional seed (P1 §5.2.3).
func offers() -> Array:
	var all: Array = view.get("shops", {}).get(role, {}).get("buy", [])
	# Decor (SGODOT-284) is on the stall's own Decor page (FARM-6-DECOR), cheapest first; never on the Buy shelf.
	if role == "homestead" and section == "decor":
		var pieces := all.filter(func(o): return P0Decor.is_decor(str(o.get("id", ""))))
		pieces.sort_custom(func(a, b): return int(a.get("price", 0)) < int(b.get("price", 0)))
		return pieces
	if role != "market": return all.filter(func(o): return not P0Decor.is_decor(str(o.get("id", ""))))
	var specialty: Array = P0Logic.content().get("market", {}).get("specialty", [])
	var want := section == "specialty"
	return all.filter(func(o): return specialty.has(str(o.get("id", ""))) == want)

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
	var once := bool(o.get("once", false)) or str(o.get("to", "")) in ["gear", "bag_cap"] or P0Decor.is_decor(id)   # decor: 1 a day, no stepper
	(_rows[id] as UiShopRow).show_spec(spec, once, int(o.left) if o.get("left", null) != null else 99)

## The P0 market's drawer (no bag half, q(48)): as tall as its content, not the fixed 420.
func is_short() -> bool:
	return role == "market" and section != "specialty" and _drinks == null and not has_bag_half(view, role)

## Shorten a short drawer to its taller page — the Buy rows or the Market Board's cards (the host fills the board
## even while Buy shows) — so switching tabs never changes its height (不知火舞 on #56, like City Specialty). Both
## pages are laid out together for two frames (the board's wrapping lines need their width), the other page see-through
## (刘邦 on #62), then it goes back; the host calls this on opening and when the board's cards change, not on every
## refresh. Counted in _process, so a drawer freed meanwhile simply stops (no awaited resume on a freed instance).
func fit_height() -> void:
	if not is_short() or not is_inside_tree(): return
	_shelf_box.custom_minimum_size.y = maxi(1, offers().size()) * _ROW_H
	var shelf_page := section != "board"
	_shelf_box.visible = true
	board.visible = true
	(board if shelf_page else _shelf_box).modulate.a = 0.0
	_fit_frames = 2
	set_process(true)

func _process(_dt: float) -> void:
	if _fit_frames <= 0:
		set_process(false)
		return
	_fit_frames -= 1
	if _fit_frames > 0: return
	set_process(false)
	var both := get_combined_minimum_size().y
	var shelf_h := _shelf_box.get_combined_minimum_size().y
	var board_h := board.get_combined_minimum_size().y
	var shelf_page := section != "board"
	_shelf_box.visible = shelf_page
	board.visible = not shelf_page
	_shelf_box.modulate.a = 1.0
	board.modulate.a = 1.0
	var sep := float(body.get_theme_constant(&"separation"))
	# Both pages minus the shorter one (and the gap between them) leaves the taller page's drawer; plus the sheet's
	# inset under the last card, so it never sits on the screen's edge.
	height = both - minf(shelf_h, board_h) - sep + pad
	fitted.emit()

func set_section(v: String) -> void:
	if v == section: return
	section = v
	refresh(view, true)
	if _fit_frames > 0: fit_height()   # mid-measure: start over with the new page in front
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
	# q(98) ③: the cups are counted in one place, used / limit like the Energy card's Tea tile `0/3 today`; the price
	# line no longer says which cup it is.
	_drinks.add_child(UiFactRow.new("Cups used", "%d/%d" % [int(d.get("used", limit - left)), limit]))
	_gap(_drinks, _SMALL)
	var line := "%s · +%d Energy" % [name, energy]
	if left > 0: line += " · %d coins" % int(d.get("price", 0))
	_drinks.add_child(UiKit.label(line, UiTokens.STYLE_C12_XB))
	_gap(_drinks, _SMALL)
	var reason := ""
	if left <= 0:   # the home-day reset (04:00), not "tomorrow"; the keeper still says `Come back tomorrow.` (q(98) ③)
		var resets := float(d.get("resets_in", view.get("rest", {}).get("resets_in", 0)))
		reason = "%s %d/%d today · Resets in %s" % [str(DRINK_SHORT.get(role, name)), limit, limit, P0Logic.span(resets)]
	elif bool(d.get("full", false)): reason = "Energy full"
	elif int(view.get("coins", 0)) < int(d.get("need", d.get("price", 0))):
		reason = "Need %d more coins" % (int(d.get("need", d.get("price", 0))) - int(view.get("coins", 0)))
	var b := UiCommandButton.new("" if reason != "" else "%s · +%d Energy" % [name, energy])
	if reason != "": b.reason = reason
	else: b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.sends = true   # drink (§10.7.1 Offline)
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
