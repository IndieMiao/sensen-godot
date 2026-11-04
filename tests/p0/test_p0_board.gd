extends GdUnitTestSuite
## Board requests in the counter drawer (SGODOT-224; BOARD-READY / SHORT / DONE 1498:96193 / 96574 / 96382, BOARD-1 /
## BOARD-3 / BOARD-DROPPED 482:284 / 288 / 322; 不知火舞 on 224): the rows' model (P0Board), the rows on the board page,
## a delivery turning its row Done, and the request sheet with its drop flow.

const STORE := "user://test_p0_board.json"
const MEI := {"keeper": "Mei", "place": "Mission Market Square"}

func _view() -> Dictionary:
	return {
		"energy": {"value": 150, "max": 200}, "coins": 200, "bag": {"capacity": 25, "slots": [
			{"id": "fish_crucian", "qty": 1}, {"id": "crop_radish", "qty": 6}, {"id": "crop_carrot", "qty": 4}]},
		"names": {"fish_crucian": "Pond Crucian", "crop_radish": "Radish", "crop_carrot": "Carrot", "crop_potato": "Potato"},
		"quotas": {"sys_requests": {"used": 4, "cap": 6}, "request_bonus": {"used": 0, "cap": 100}},
		"shops": {"market": {"buy": [], "sell": []}, "homestead": {"buy": [], "sell": []}},
		"keepers": {"market": {"greet": "board", "board_open": 2, "board_templates": []}},
		"boards": {
			"market": {"slots": [
				{"id": "m1", "title": "Dusk Haul", "kind": "fish", "items": [], "rarity": 2, "icon": "fish_crucian", "qty": 4,
					"have": 4, "ready": true, "coins": 36, "status": "open"},
				{"id": "m2", "title": "Market Basket", "kind": "crop", "items": ["crop_radish", "crop_carrot", "crop_potato"],
					"rarity": null, "icon": "crop_radish", "qty": 6, "have": 0, "ready": false, "coins": 140, "status": "open"}]},
			"stall": {"slots": [
				{"id": "req_pond_catch", "title": "Pond Catch", "kind": "fish", "items": ["fish_crucian"], "rarity": null,
					"icon": "fish_crucian", "qty": 2, "have": 1, "ready": false, "coins": 14, "status": "accepted"},
				{"empty": true, "held": true}]}},   # a new account's slot 2, held 72 h: no countdown (q(99))
	}

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

# ---------------------------------------------------------------- model

func test_rows_say_what_they_take_and_what_the_button_does() -> void:
	var rows := P0Board.cards(_view(), "market")
	var dusk: Dictionary = rows[0]
	assert_array([dusk.title, dusk.status, dusk.facts, dusk.reward, dusk.command, dusk.reason]).is_equal(
		["Dusk Haul", "Ready to deliver", ["4 Fine fish · any kind"], "36 coins", "Deliver", ""])
	assert_dict(dusk.cmd).is_equal({"type": "deliver", "request": "m1"})
	assert_array(dusk.needs.map(func(n): return [n.name, n.have, n.need])).is_equal([["Fine fish", 4, 4]])
	var basket: Dictionary = rows[1]
	assert_array([basket.status, basket.facts, basket.command]).is_equal(["Open", ["3 crops · 6 each"], "Track"])
	assert_dict(basket.cmd).is_equal({"type": "accept", "request": "m2"})
	assert_array(basket.needs.map(func(n): return [n.name, n.have, n.need])).is_equal([["Radish", 6, 6], ["Carrot", 4, 6], ["Potato", 0, 6]])
	var pond: Dictionary = P0Board.cards(_view(), "stall")[0]
	assert_array([pond.status, pond.facts, pond.command, pond.reason]).is_equal(
		["Tracked", ["2 Pond Crucian"], "Deliver", "Need 1 more Pond Crucian"])   # the gap on the button (LOCK-10)
	assert_dict(pond.cmd).is_empty()

func test_page_facts_count_the_day_and_the_next_request() -> void:
	assert_array(P0Board.facts(_view(), "market")).is_equal([["Requests today", "4/6"]])
	var v := _view()
	v.quotas.request_bonus.used = 20
	# q(99): the held slot is not the next request — before the tutorial is handed in there is no "Next request" line …
	assert_array(P0Board.facts(v, "stall")).is_equal([["Requests today", "4/6"], ["Bonus today", "20/100"]])
	# … after it, its slot refills in 4 h and that is the line (whole hours, q(97)); the held slot still doesn't count.
	v.boards.stall.slots[0] = {"empty": true, "refill_in": 4 * 3600000}
	assert_array(P0Board.facts(v, "stall")).is_equal([["Requests today", "4/6"], ["Next request", "4h"], ["Bonus today", "20/100"]])
	assert_str(P0Logic.span(14280000)).is_equal("3h 58m")
	assert_str(P0Logic.span(780000)).is_equal("13m")   # q(97): not `13:00`

func test_a_delivered_slot_shows_its_row_done() -> void:
	var v := _view()
	var was: Dictionary = P0Board.cards(v, "market")[0]
	v.boards.market.slots[0] = {"empty": true, "refill_in": 14400000}
	var rows := P0Board.cards(v, "market", {0: was})
	assert_array([rows[0].title, rows[0].status, rows[0].done, rows[0].reward, rows[0].info]).is_equal(["Dusk Haul", "Done", true, "36 coins", false])

func test_the_request_sheet_knows_where_and_what_comes_next() -> void:
	var d := P0Board.detail(_view(), "stall", "req_pond_catch")
	assert_array([d.title, d.state, d.effect, d.delivery, d.tracked, d.go]).is_equal(["Pond Catch", "Tracked",
		"Bring the required fish to the Homestead Stall.", "14 coins", true, "pond:" + P0Guide.BEGINNER_POND])
	assert_dict(d.next).is_empty()   # slot 2 is held (q(99)): no "next" countdown for it
	var refilling := _view()
	refilling.boards.stall.slots[1] = {"empty": true, "refill_in": 8 * 3600000}   # e.g. after a drop
	assert_dict(P0Board.detail(refilling, "stall", "req_pond_catch").next).is_equal({"slot": "Second board slot", "within": "8h"})
	var basket := P0Board.detail(_view(), "market", "m2")
	assert_bool(basket.tracked).is_false()   # open: no Drop request
	assert_str(basket.effect).is_equal("Bring the required crops to any San Francisco market.")   # 李白 q(68)
	assert_str(basket.item).is_empty()   # a mixed basket has no single item: no Details ›
	assert_str(P0Board.detail(_view(), "market", "m1").item).is_empty()   # nor has "4 Fine fish · any kind"
	assert_str(d.item).is_equal("fish_crucian")
	var timber := _view()
	timber.names["wood"] = "Timber"
	timber.boards.stall.slots[0] = {"id": "t1", "title": "Timber Run", "kind": "material", "items": ["wood"], "qty": 10,
		"have": 0, "ready": false, "coins": 30, "status": "accepted"}
	assert_str(P0Board.detail(timber, "stall", "t1").effect).is_equal("Bring the required timber to the Homestead Stall.")
	assert_dict(P0Board.detail(_view(), "market", "gone")).is_empty()

# ---------------------------------------------------------------- P0Ui

func _ui(v := {}) -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	ui.layer = 128
	ui.set_view(v if not v.is_empty() else _view())
	return ui

func _rows(ui: P0Ui) -> Array:
	return ui._counter.board.get_children().filter(func(c): return c is UiBoardCard and c.visible)

func _navs(ui: P0Ui) -> Array:
	return ui._modal.find_children("*", "UiNavButton", true, false).map(func(b): return (b as UiNavButton).label)

func test_the_board_page_lists_rows_and_track_accepts() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.open_counter("market", {"section": "board", "ctx": MEI})
	var rows := _rows(ui)
	assert_array(rows.map(func(r): return (r as UiBoardCard).request_id)).is_equal(["m1", "m2"])
	var facts := ui._counter.board.get_children().filter(func(c): return c is HBoxContainer and not c is UiBoardCard)
	assert_int(facts.size()).is_equal(1)   # Requests today
	var sent := []
	ui.command.connect(func(c): sent.append(c))
	(rows[1] as UiBoardCard).command_button().activated.emit()
	assert_array(sent).is_equal([{"type": "accept", "request": "m2"}])

func test_a_delivery_from_the_drawer_turns_its_row_done_and_floats_the_coins() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.open_counter("market", {"section": "board", "ctx": MEI})
	await await_idle_frame()
	var v := _view()
	v.boards.market.slots[0] = {"empty": true, "refill_in": 14400000}
	ui.set_view(v)
	ui.counter_events([{"kind": "request", "id": "m1", "status": "done", "coins": 36}])
	var rows := _rows(ui)
	var done := rows.filter(func(r): return (r as UiBoardCard).request_id == "m1")
	assert_int(done.size()).is_equal(1)
	assert_str((done[0] as UiBoardCard)._status.text).is_equal("Done")
	assert_bool((done[0] as UiBoardCard).command_button().visible).is_false()
	var floats := ui.root.get_children().filter(func(c): return c is UiFloatText)
	assert_array(floats.map(func(f): return f.text)).contains(["+36 coins"])
	ui.close_modal()
	ui.open_counter("market", {"section": "board", "ctx": MEI})
	assert_array(_rows(ui).map(func(r): return (r as UiBoardCard).request_id)).is_equal(["m2"])   # gone once closed

## 刘邦 on #73: the Homestead Stall has no keeper bar; a delivery from its Stall Board turns the row Done all the same.
func test_a_delivery_at_the_unattended_stall_turns_its_row_done() -> void:
	var v := _view()
	v.boards.stall.slots[0].have = 2
	v.boards.stall.slots[0].ready = true
	var ui := _ui(v)
	await await_idle_frame()
	ui.open_counter("homestead", {"section": "board"})
	assert_object(ui._counter.keeper_bar).is_null()
	await await_idle_frame()
	var after := _view()
	after.boards.stall.slots[0] = {"empty": true, "refill_in": 14400000}
	ui.set_view(after)
	ui.counter_events([{"kind": "request", "id": "req_pond_catch", "status": "done", "coins": 14}])
	var rows := _rows(ui)
	assert_array(rows.map(func(r): return [(r as UiBoardCard).request_id, (r as UiBoardCard)._status.text])).is_equal([["req_pond_catch", "Done"]])
	assert_array(ui.root.get_children().filter(func(c): return c is UiFloatText).map(func(f): return f.text)).contains(["+14 coins"])

## 蒙恬 rc0: the runtime sets the view every frame; the board's buttons must survive an unchanged view, or a tap
## pressed on one is released on its replacement and lost. A countdown fact still ticks in place.
func test_an_unchanged_view_keeps_the_rows_and_ticks_the_facts() -> void:
	var v := _view()
	v.boards.stall.slots[1] = {"empty": true, "refill_in": 8 * 3600000}   # slot 2 refilling (after a drop): a countdown to tick
	var ui := _ui(v)
	await await_idle_frame()
	ui.open_counter("homestead", {"section": "board"})
	var before: UiCommandButton = (_rows(ui)[0] as UiBoardCard).command_button()
	ui.set_view(v)
	ui.set_view(v)
	assert_object((_rows(ui)[0] as UiBoardCard).command_button()).is_same(before)
	v.boards.stall.slots[1].refill_in = 3600000 * 5 + 60000 * 3
	ui.set_view(v)
	assert_object((_rows(ui)[0] as UiBoardCard).command_button()).is_same(before)
	var facts := ui._counter.board.get_children().filter(func(c): return c is HBoxContainer and not c is UiBoardCard)
	assert_str(((facts[1] as HBoxContainer).get_child(1) as Label).text).is_equal("5h 3m")
	v.boards.stall.slots[0].status = "open"   # a row changed: rebuilt
	ui.set_view(v)
	assert_object((_rows(ui)[0] as UiBoardCard).command_button()).is_not_same(before)

func test_the_request_sheet_drops_a_tracked_request() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.open_counter("homestead", {"section": "board"})
	(_rows(ui)[0] as UiBoardCard).info_pressed.emit()   # the title ›
	assert_str(ui.modal_kind).is_equal("board_request")
	var head: UiObjectHeader = ui._modal.find_children("*", "UiObjectHeader", true, false)[0]
	assert_array([head.title, head.state]).is_equal(["Pond Catch", "Tracked"])
	assert_array(_navs(ui)).is_equal(["Show on map", "Drop request", "Details"])
	var drop_nav: UiNavButton = ui._modal.find_children("*", "UiNavButton", true, false)[1]
	drop_nav.pressed.emit()
	assert_str(ui.modal_kind).is_equal("board_drop")
	var sent := []
	ui.command.connect(func(c): sent.append(c))
	var drop: UiCommandButton = ui._modal.find_children("*", "UiCommandButton", true, false)[0]
	assert_str(drop.label).is_equal("Drop request")
	drop.activated.emit()
	assert_array(sent).is_equal([{"type": "drop", "request": "req_pond_catch"}])
	ui.board_dropped("req_pond_catch")
	assert_str(ui.modal_kind).is_equal("board_dropped")
	head = ui._modal.find_children("*", "UiObjectHeader", true, false)[0]
	assert_array([head.state, head.effect]).is_equal(["Dropped", "Your fish remain in your bag."])
	(ui._modal.find_children("*", "UiDismissButton", true, false)[0] as UiDismissButton).pressed.emit()
	assert_str(ui.modal_kind).is_equal("counter")   # Close goes back to the list

func test_an_open_request_cannot_be_dropped_and_back_returns_to_the_list() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.open_board_request("market", "m2")
	assert_bool(_navs(ui).has("Drop request")).is_false()
	ui.back_modal()
	assert_str(ui.modal_kind).is_equal("counter")
	assert_str(ui._counter.section).is_equal("board")

## 不知火舞 on 224: Details › lays the item's InfoSheet over the sheet (×0 when none in the bag, no buttons); a tap
## outside or Back returns to the request.
func test_details_lay_the_items_card_over_the_request() -> void:
	var v := _view()
	v.bag.slots = []
	var ui := _ui(v)
	await await_idle_frame()
	ui.open_board_request("homestead", "req_pond_catch")
	var nav: UiNavButton = ui._modal.find_children("*", "UiNavButton", true, false).filter(func(b): return (b as UiNavButton).label == "Details")[0]
	nav.pressed.emit()
	var sheet: UiInfoSheet = ui._modal.find_children("*", "UiInfoSheet", true, false)[0]
	assert_str(sheet._title.text).is_equal("Pond Crucian")
	assert_bool(sheet._qty_pill.visible).is_true()
	assert_str(sheet._qty.text).is_equal("×0")
	assert_object(sheet.scrim()).is_not_null()   # the request below is dimmed: the card is its own layer
	assert_object(sheet.scrim().color).is_equal(UiTokens.COLOR_SCRIM_MODAL)
	assert_str(ui.modal_kind).is_equal("board_request")
	assert_bool(ui.close_top_layer()).is_true()   # Android Back closes the card, not the request (刘邦 on #73)
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("board_request")
	assert_array(ui._modal.find_children("*", "UiInfoSheet", true, false)).is_empty()
	assert_bool(ui.close_top_layer()).is_true()
	assert_str(ui.modal_kind).is_equal("counter")

## The runtime's side of BOARD-DONE: a delivery from the counter drawer floats its coins once, from the row's button,
## not again at the player (亚瑟 on #77: the coins float's skip must survive the float queue).
func test_a_counter_delivery_floats_its_coins_once() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.ui.quick_store = STORE
	rt.session.view = _view()
	rt.ui.set_view(_view())
	rt.ui.open_counter("market", {"section": "board", "ctx": MEI})
	await await_idle_frame()
	var v := _view()
	v.boards.market.slots[0] = {"empty": true, "refill_in": 14400000}
	v.coins = 236
	rt.session.view = v
	rt._on_state(v, [{"kind": "request", "id": "m1", "status": "done", "coins": 36}, {"kind": "coins", "delta": 36}])
	await get_tree().process_frame
	await get_tree().process_frame
	var coins := rt.ui.root.get_children().filter(func(c): return c is UiFloatText and str(c.text).contains("+36 coins"))
	assert_int(coins.size()).is_equal(1)

## SGODOT-284 P1 templates: a style list and a crop family name what an any-of-a-kind request takes.
func test_p1_rows_name_styles_and_families() -> void:
	var v := _view()
	v.boards.market.slots = [
		{"id": "m3", "title": "Packed Lunches", "kind": "dish", "items": [], "rarity": null, "style": ["Grilled", "Dessert"],
			"family": null, "icon": "dish_grilled_fish", "qty": 3, "have": 1, "ready": false, "coins": 30, "status": "accepted"},
		{"id": "m4", "title": "Orchard Basket", "kind": "crop", "items": [], "rarity": null, "style": null, "family": "O",
			"icon": "crop_chamomile", "qty": 4, "have": 0, "ready": false, "coins": 50, "status": "open"},
		{"id": "m5", "title": "Fine Produce", "kind": "crop", "items": [], "rarity": 2, "style": null, "family": null,
			"icon": "crop_tomato", "qty": 4, "have": 0, "ready": false, "coins": 40, "status": "open"}]
	var rows := P0Board.cards(v, "market")
	assert_array(rows[0].facts).is_equal(["3 Grilled or Dessert dishes · any kind"])
	assert_str(str(rows[0].reason)).is_equal("Need 2 more Grilled or Dessert dishes")
	assert_array(rows[1].facts).is_equal(["4 Orchard crops · any kind"])
	assert_array(rows[2].facts).is_equal(["4 Fine crops · any kind"])

## A material is a mass noun (奕星 11-04, 不知火舞 on the Stall Board): `7 Clay` on the row and its button's gap, never
## `7 Claies` — the row reads it as the item card and the Chinese table do (黏土).
func test_material_rows_keep_the_materials_name_in_the_plural() -> void:
	var v := _view()
	v.names.merge({"clay": "Clay", "wood": "Timber", "flax": "Flax", "coal": "Coal"})
	v.boards.stall.slots = [
		{"id": "s1", "title": "Clay for Pots", "kind": "material", "items": ["clay"], "rarity": null, "icon": "clay", "qty": 7,
			"have": 0, "ready": false, "coins": 30, "status": "accepted"},
		{"id": "s2", "title": "Timber Order", "kind": "material", "items": ["wood"], "rarity": null, "icon": "wood", "qty": 5,
			"have": 2, "ready": false, "coins": 30, "status": "accepted"}]
	var rows := P0Board.cards(v, "stall")
	assert_array([rows[0].facts, rows[0].reason]).is_equal([["7 Clay"], "Need 7 more Clay"])
	assert_array([rows[1].facts, rows[1].reason]).is_equal([["5 Timber"], "Need 3 more Timber"])

## SGODOT-284 Stamp Run: a check-in, not items — the row says where, the gap until the player has been there.
func test_p1_stamp_run_reads_visit_and_the_gap_is_the_check_in() -> void:
	var v := _view()
	v.boards.market.slots = [{"id": "v1", "title": "Stamp Run", "kind": "visit", "items": [], "rarity": null, "style": null,
		"family": null, "visit": {"place": "sh_tea_1", "done": false}, "icon": null, "qty": 1, "have": 0, "ready": false,
		"coins": 40, "status": "accepted"}]
	var row: Dictionary = P0Board.cards(v, "market")[0]
	assert_array(row.facts).is_equal(["Visit Oak Tea House"])
	assert_str(str(row.reason)).is_equal("Visit Oak Tea House first")
	assert_array(row.needs.map(func(n): return [n.name, n.have, n.need])).is_equal([["Oak Tea House", 0, 1]])
	var d := P0Board.detail(v, "market", "v1")
	assert_str(str(d.effect)).is_equal("Visit Oak Tea House, then come back to any San Francisco market.")
	assert_str(str(d.go)).is_equal("outpost:sh_tea_1")   # by the outpost's id, not its role (SGODOT-311)
	v.boards.market.slots[0].visit.done = true
	v.boards.market.slots[0].ready = true
	row = P0Board.cards(v, "market")[0]
	assert_array([row.status, row.command, row.reason]).is_equal(["Ready to deliver", "Deliver", ""])

## 李白 on #224: with today's completion-bonus cap nearly spent, the row says what delivering pays now and when the bonus
## is back (every system request); the check-in toast names the request and where it is delivered.
func test_p1_reward_line_shows_the_bonus_cap_and_the_check_in_toast() -> void:
	var v := _view()
	var r := {"id": "v1", "title": "Stamp Run", "kind": "visit", "items": [], "visit": {"place": "sh_tea_1", "done": true},
		"qty": 1, "have": 1, "ready": true, "coins": 40, "bonus": 40, "status": "accepted"}
	v.boards.market.slots = [r]
	assert_str(P0Board.reward_line(v, r)).is_equal("40 coins")
	v.quotas.request_bonus = {"used": 80, "cap": 100, "resets_in": 33120000}
	assert_str(P0Board.reward_line(v, r)).is_equal("20 coins · Bonus resets in 9h 12m")
	v.quotas.request_bonus.used = 100
	assert_str(P0Board.reward_line(v, r)).is_equal("0 coins · Bonus resets in 9h 12m")
	var fish := {"coins": 36, "bonus": 20}   # Dusk Haul: the floor part is paid in full
	assert_str(P0Board.reward_line(v, fish)).is_equal("16 coins · Bonus resets in 9h 12m")
	assert_str(P0Logic.visit_toast(v, "v1")).is_equal("Stamp Run · Checked in\nDeliver at Mission Market Square")

## q(128) cross-city (李白 / 不知火舞, bbe6cf92): the requirement line is the place and its city with a place icon, no 1/1
## count; the gap names the outpost; Show on map goes to that pin (亚瑟's #279 loads the city); Today says where before the
## check-in, then the hand-in at home.
func test_p1_cross_city_card_and_today_say_where() -> void:
	var v := _view()
	v.boards.market.slots = [{"id": "x1", "title": "Tea Trail", "kind": "visit", "items": [], "rarity": null, "style": null,
		"family": null, "visit": {"place": "gn-1796236~tea0", "done": false, "name": "Lotus Tea House", "city": "Shanghai",
		"cluster": "gn-1796236", "lat": 31.2, "lng": 121.5}, "icon": null, "qty": 1, "have": 0, "ready": false,
		"coins": 40, "status": "accepted"}]
	var row: Dictionary = P0Board.cards(v, "market")[0]
	assert_array(row.facts).is_equal(["Lotus Tea House · Shanghai"])
	assert_object(row.get("fact_icon", null)).is_not_null()
	assert_array(row.needs).is_empty()
	assert_array([row.command, row.reason]).is_equal(["Deliver", "Visit Lotus Tea House first"])
	var d := P0Board.detail(v, "market", "x1")
	assert_str(str(d.effect)).is_equal("Visit Lotus Tea House in Shanghai, then come back to any San Francisco market.")
	assert_str(str(d.go)).is_equal("outpost:gn-1796236~tea0")
	var taken: Array = P0Logic.PinReason.taken(v)
	assert_array([P0Logic._request_row(v, taken[0]).line, P0Logic._request_row(v, taken[0]).go]).is_equal(["Tea Trail · Shanghai", "outpost:gn-1796236~tea0"])
	v.boards.market.slots[0].visit.done = true   # checked in: handed in at home, as Stamp Run
	v.boards.market.slots[0].ready = true
	row = P0Board.cards(v, "market")[0]
	assert_array([row.status, row.command, row.reason]).is_equal(["Ready to deliver", "Deliver", ""])
	assert_str(str(P0Logic.PinReason.taken(v)[0].deliver)).is_equal("Deliver at Mission Market Square")
	# one line LINE_W wide (40 characters of English, as it was): a long name is cut, the city kept
	var cut := P0Board.place_line("The Old Riverside Botanical Tea Pavilion", "Shanghai")
	assert_str(cut).is_equal("The Old Riverside Botanical Tea… · Shanghai")   # the 40-character cut's own
	assert_float(P0Logic.text_width(cut)).is_less_equal(P0Board.LINE_W)
	assert_str(P0Board.place_line("Lotus Tea House", "Shanghai")).is_equal("Lotus Tea House · Shanghai")

## Far Pond (q(128) 甲): fish the home city's ponds don't have, as the bag holds them; the count and the fish to try are
## the server's.
func test_p1_far_pond_reads_not_found_at_home() -> void:
	var v := _view()
	v.names.merge({"fish_tilapia": "Tilapia", "fish_smelt": "Smelt", "fish_mullet": "Grey Mullet"})
	v.boards.market.slots = [{"id": "f1", "title": "Far Pond", "kind": "fish", "items": [], "rarity": null, "style": null,
		"family": null, "where": "not_home", "visit": null, "icon": "fish_tilapia", "qty": 3, "have": 1, "ready": false,
		"coins": 29, "status": "accepted", "tries": ["fish_tilapia", "fish_smelt", "fish_mullet"]}]
	var row: Dictionary = P0Board.cards(v, "market")[0]
	assert_array(row.facts).is_equal(["3 fish not found in San Francisco"])
	assert_object(row.get("fact_icon", null)).is_same(P0Logic.icon("fish"))
	assert_str(str(row.reward)).is_equal("29 coins")
	assert_array(row.needs.map(func(n): return [n.have, n.need])).is_equal([[1, 3]])
	assert_str(str(row.reason)).is_equal("Need 2 more fish")
	var d := P0Board.detail(v, "market", "f1")
	assert_str(str(d.effect)).is_equal("Bring 3 fish that San Francisco's ponds don't have to any San Francisco market.")
	assert_str(str(d.example)).is_equal("Try Tilapia, Smelt or Grey Mullet")
	assert_str(str(d.go)).is_equal("")   # no one place: no Show on map (不知火舞 on #285)
	var r := P0Logic._request_row(v, P0Logic.PinReason.taken(v)[0])
	assert_array([r.line, r.go]).is_equal(["Far Pond · 1/3 fish", ""])
	# two to try, one, none (the server names them at the level now)
	v.boards.market.slots[0].tries = ["fish_smelt", "fish_tilapia"]
	assert_str(P0Board.far_tries(v, v.boards.market.slots[0])).is_equal("Try Smelt or Tilapia")
	v.boards.market.slots[0].tries = ["fish_smelt"]
	assert_str(P0Board.far_tries(v, v.boards.market.slots[0])).is_equal("Try Smelt")
	v.boards.market.slots[0].tries = []
	assert_str(str(P0Board.detail(v, "market", "f1").example)).is_equal("")
	# any other request has no example line
	v.boards.market.slots[0].where = null
	assert_str(str(P0Board.detail(v, "market", "f1").example)).is_equal("")

## The board card's place line: the icon in front of the first fact only when the row has one (q(128)).
func test_p1_board_card_fact_icon() -> void:
	var card: UiBoardCard = auto_free(UiBoardCard.new())
	add_child(card)
	card.show_request({"id": "x1", "title": "Tea Trail", "status": "Tracked", "facts": ["Lotus Tea House · Shanghai"],
		"fact_icon": P0Logic.icon("pin"), "reward": "40 coins", "needs": [], "command": "Deliver", "reason": "Visit Lotus Tea House first"})
	assert_object(card.find_child("FactIcon", true, false)).is_not_null()
	card.show_request({"id": "m1", "title": "Dusk Haul", "status": "Open", "facts": ["4 Fine fish · any kind"], "reward": "36 coins",
		"needs": [], "command": "Track", "reason": ""})
	assert_object(card.find_child("FactIcon", true, false)).is_null()
