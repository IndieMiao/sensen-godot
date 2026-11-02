extends GdUnitTestSuite
## q(272) (SGODOT-378, cross-city plan H step 2): the keepers' local requests away from home — the greeting card's one
## key under Trade (Deliver > Request > the gap, none without one), the keeper's name tag mark, the request card
## (`Wen · Tackle Keeper · local request`, the keeper's line, coins only, Deliver to with the city away, Drop request ›,
## `Bo's other requests · 2 ›`), Today's rows (`Deliver to Wen · Shanghai`, not one of today's 6) and the pin's reason
## (`Wen · New request`). 不知火舞 378 091a3ae9 / 77524b0e.

const P0Locals := preload("res://modules/p0/p0_locals.gd")
const P0LocalRequest := preload("res://scenes/p0/panels/p0_local_request.gd")
const PinReason := preload("res://modules/p0/p0_pin_reason.gd")

const TACKLE := "gn-1796236~tackle0"
const CABIN := "gn-1802238~cabin0"

func _loc(id: String, over := {}) -> Dictionary:
	var r := {"id": id, "template": "req_sys_fish_common", "title": "Pond Catch", "kind": "fish", "items": ["fish_crucian"],
		"rarity": null, "style": null, "family": null, "icon": "fish_crucian", "qty": 3, "have": 1, "ready": false, "status": "open",
		"coins": 24, "base": 14, "bonus": 10, "accepted_at": null, "expires_in": 3_600_000, "visit": null, "where": null,
		"place": TACKLE, "giver": "Wen", "giver_role": "Tackle Keeper", "cluster": "gn-1796236", "city": "Shanghai", "here": true}
	r.merge(over, true)
	return r

func _view(locals: Array, sys_used := 1) -> Dictionary:
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
	v.locals = locals
	v.boards = {"stall": {"slots": []}, "market": {"slots": []}, "elsewhere": []}
	v.quotas = {"sys_requests": {"used": sys_used, "cap": 6, "resets_in": 9 * 3_600_000 + 12 * 60_000},
		"request_bonus": {"used": 0, "cap": 100, "resets_in": 9 * 3_600_000 + 12 * 60_000}}
	v.firsts = ["harvest:crop_radish", "catch:fish_crucian", "cook:dish_grilled_crucian"]
	if v.get("stall", null) is Dictionary: v.stall.board = {"requests": []}   # past the first session (Pond Catch handed in)
	v.req_done = []
	return v

func test_the_keepers_key_picks_deliver_then_request_then_the_gap_and_none_without_one() -> void:
	var open := _loc("req_loc_a")
	var short := _loc("req_loc_b", {"status": "accepted"})
	var ready := _loc("req_loc_c", {"status": "accepted", "ready": true, "have": 3})
	assert_dict(P0Locals.key(_view([]), TACKLE)).is_empty()
	assert_dict(P0Locals.key(_view([short]), TACKLE)).contains_key_value("reason", "Need 2 more Pond Crucian")
	assert_str(str(P0Locals.key(_view([short]), TACKLE).text)).is_equal("Deliver")
	assert_dict(P0Locals.key(_view([short, open]), TACKLE)).contains_key_value("text", "Request")
	assert_dict(P0Locals.key(_view([short, open, ready]), TACKLE)).contains_key_value("kind", "deliver")
	assert_str(P0Locals.badge(_view([short, open]), TACKLE)).is_equal("request")
	assert_str(P0Locals.badge(_view([open, ready]), TACKLE)).is_equal("deliverable")
	assert_str(P0Locals.badge(_view([short]), TACKLE)).is_equal("")
	# another city's (opened from home) is not this keeper's here
	assert_dict(P0Locals.key(_view([_loc("req_loc_d", {"here": false})]), TACKLE)).is_empty()

func test_a_long_gap_drops_the_items_name() -> void:
	var r := _loc("req_loc_e", {"status": "accepted", "kind": "material", "items": ["copper_ore"], "qty": 12, "have": 0})
	var gap := P0Locals.gap_text(_view([r]), r)
	var key := P0Locals.key(_view([r]), TACKLE)
	assert_str(str(key.reason)).is_equal(gap if gap.length() <= P0Locals.KEY_CHARS else "Need 12 more")

func test_the_card_says_who_the_keepers_line_coins_only_and_deliver_to_with_the_city_away() -> void:
	var r := _loc("req_loc_f")
	var d := P0LocalRequest.card_data(_view([r]), r)
	assert_str(str(d.who)).is_equal("Wen · Tackle Keeper · local request")
	assert_str(str(d.reward)).is_equal("24 coins")
	assert_str(str(d.action)).is_equal("Accept")
	assert_str(str(d.line)).is_not_empty()
	assert_bool((P0Logic.content().requests.local.lines.tackle as Array).has(str(d.line).replace("Shanghai", "{city}"))).is_true()
	var away := _loc("req_loc_g", {"here": false, "status": "accepted"})
	assert_str(P0Locals.deliver_to(away)).ends_with(" · Shanghai")
	# away, still short: the gap as in the city (不知火舞 on 378: no new line away)
	assert_str(str(P0LocalRequest.card_data(_view([away]), away).reason)).is_equal("Need 2 more Pond Crucian")
	# the day's bonus nearly spent: the reward says what is paid (q(262))
	var v := _view([r])
	v.quotas.request_bonus.used = 95
	assert_dict(P0LocalRequest.rewards(v, r)).is_equal({"reward": "19 coins", "bonus_note": "Bonus resets in 9h 12m"})

func test_the_card_names_the_crops_drawn_one_tile_each() -> void:
	var one := _loc("req_loc_p", {"kind": "crop", "items": ["crop_radish"], "template": "req_sys_crop_basic", "title": "Fresh Greens"})
	var d := P0LocalRequest.card_data(_view([one]), one)
	assert_str(str(d.needs[0].name)).is_equal(P0Logic.item_name(_view([one]), "crop_radish"))
	var basket := _loc("req_loc_q", {"kind": "crop", "items": ["crop_radish", "crop_carrot", "crop_lettuce"], "title": "Market Basket"})
	assert_array((P0LocalRequest.card_data(_view([basket]), basket).needs as Array).map(func(n): return n.name)).is_equal(
		["crop_radish", "crop_carrot", "crop_lettuce"].map(func(i): return P0Logic.item_name(_view([basket]), i)))

func test_a_cabin_keeper_speaks_for_the_kind_asked() -> void:
	var dish := _loc("req_loc_h", {"kind": "dish", "place": CABIN, "giver": "Bo", "giver_role": "Trading Post Keeper"})
	var lines: Array = P0Logic.content().requests.local.lines.tea
	assert_bool(lines.has(P0Locals.line(dish))).is_true()

func test_today_hands_in_to_the_keeper_with_the_city_and_never_as_one_of_todays_6() -> void:
	var ready := _loc("req_loc_i", {"status": "accepted", "ready": true, "have": 3, "here": false})
	var rows: Array = P0Logic.today_rows(_view([ready], 6))
	var hand: Array = rows.filter(func(r): return str(r.line).begins_with("Pond Catch"))
	assert_int(hand.size()).is_equal(1)
	assert_str(str(hand[0].line)).is_equal("Pond Catch · Deliver to Wen · Shanghai")
	assert_str(str(hand[0].get("local_request", ""))).is_equal("req_loc_i")
	var short := _loc("req_loc_j", {"status": "accepted", "here": false})
	var line := str(P0Logic.today_rows(_view([short])).filter(func(r): return str(r.line).begins_with("Pond Catch"))[0].line)
	assert_str(line).ends_with(" · Shanghai")

func test_the_pins_reason_names_the_keeper_for_a_new_one() -> void:
	var r := _loc("req_loc_k")
	var v := _view([r])
	assert_str(PinReason.line(v, {"place": TACKLE, "kind": "request", "why": {"request": "req_loc_k"}})).is_equal("Wen · New request")
	var ready := _loc("req_loc_l", {"status": "accepted", "ready": true, "have": 3})
	assert_str(PinReason.line(_view([ready]), {"place": TACKLE, "kind": "deliver", "why": {"request": "req_loc_l", "tracked": true}}))\
		.is_equal("Pond Catch · Ready to deliver")
	var taken: Array = PinReason.taken(_view([ready]))
	assert_dict(taken[0]).contains_key_value("deliver_go", "outpost:" + TACKLE)

func test_the_request_card_rows_drop_and_page_through_the_keepers_requests() -> void:
	var card := UiRequestCard.new({"title": "Pond Catch", "who": "x", "deliver_to": "Wen · Xuhui Tackle Shop",
		"links": ["Drop request", "Bo's other requests · 2"]})
	add_child(auto_free(card))
	var links := card.find_children("Link*", "UiNavButton", true, false)
	assert_int(links.size()).is_equal(2)
	var got := []
	card.link_pressed.connect(func(i: int): got.append(i))
	(links[1] as UiNavButton).pressed.emit()
	assert_array(got).is_equal([1])

func test_the_grey_gap_key_opens_the_request_card_when_tapped() -> void:
	# the gap is a reason (LOCK-10): a tap emits unavailable_pressed, not activated — the card opens all the same
	var ctx := {"keeper": "Wen", "place": "Xuhui Tackle Shop", "outpost": TACKLE}
	var ui := _ui()
	await await_idle_frame()
	ui.set_view(_view([_loc("req_loc_g", {"status": "accepted"})]))
	ui.open_keeper_greeting("tackle", ctx)
	var key: UiCommandButton = ui._modal.find_children("LocalKey", "UiCommandButton", true, false)[0]
	assert_str(key.reason).is_equal("Need 2 more Pond Crucian")
	key.pressed.emit()
	assert_str(ui.modal_kind).is_equal("local_request")
	var rc: UiRequestCard = ui._modal.find_children("LocalRequestCard", "UiRequestCard", true, false)[0]
	assert_str(str(rc.data.title)).is_equal("Pond Catch")

## q(272) ⑦ (周瑜 on #610): handed in elsewhere, the server's wrong_place says where it goes — its hand-in row in the toast
func test_a_local_request_refused_wrong_place_toasts_its_hand_in_row() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.view = _view([_loc("req_loc_w", {"status": "accepted", "ready": true, "have": 3})])
	rt._on_refused("wrong_place", {}, {"type": "deliver", "request": "req_loc_w"})
	assert_str(rt.ui.toast_text()).is_equal("Pond Catch · Deliver to Wen · Shanghai")
	assert_int(rt.ui._toasts.current_severity()).is_equal(ToastLayer.Severity.ERROR)   # a refused command's (§4.8.6, 不知火舞 11-02)

func _ui() -> P0Ui:
	var u := P0Ui.new()
	add_child(auto_free(u))
	u.layer = 128
	return u

func test_the_greeting_card_puts_one_key_under_trade_and_none_without_a_request() -> void:
	var ctx := {"keeper": "Wen", "place": "Xuhui Tackle Shop", "outpost": TACKLE, "nearest": {"name": "Reed Pond", "site": "pond"}}
	var ui := _ui()
	await await_idle_frame()
	ui.set_view(_view([]))
	ui.open_keeper_greeting("tackle", ctx)
	var card: UiDialogueCard = ui._modal.find_children("*", "UiDialogueCard", true, false)[0]
	assert_int(card.content.find_children("LocalKey", "", true, false).size()).is_equal(0)
	ui.set_view(_view([_loc("req_loc_m"), _loc("req_loc_n", {"giver": "Wen"})]))
	ui.open_keeper_greeting("tackle", ctx)
	card = ui._modal.find_children("*", "UiDialogueCard", true, false)[0]
	var texts: Array = card.content.get_children().map(func(b): return (b as Button).text)
	assert_str(str(texts[0])).is_equal("Trade")
	assert_str(str(texts[1])).is_equal("Request")
	(card.content.get_child(1) as UiCommandButton).pressed.emit()   # as a tap
	assert_str(ui.modal_kind).is_equal("local_request")
	var rc: UiRequestCard = ui._modal.find_children("LocalRequestCard", "UiRequestCard", true, false)[0]
	assert_array(rc.data.links).is_equal(["Wen's other requests · 1"])
	rc.link_pressed.emit(0)   # the next one, round to the first
	rc = ui._modal.find_children("LocalRequestCard", "UiRequestCard", true, false)[0]
	assert_str(str(rc.data.title)).is_equal("Pond Catch")
	assert_array(rc.data.links).is_equal(["Wen's other requests · 1"])
	rc.dismissed.emit()   # Not now: back to the greeting, its key worked out again
	assert_str(ui.modal_kind).is_equal("greeting")
