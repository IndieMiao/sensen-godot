extends GdUnitTestSuite
## q(270) (SGODOT-378, plan H step 1): one Market Board per city — the board shown names its city (`any Hayward
## market`), another city's tracked requests come from view.boards.elsewhere with ` · <City>` where they are handed in
## and on their progress line, and open their sheet from Today to be dropped anywhere.

const PinReason := preload("res://modules/p0/p0_pin_reason.gd")

func _req(id: String, over := {}) -> Dictionary:
	var r := {"id": id, "template": "req_sys_fish_fine", "title": "Dusk Haul", "kind": "fish", "items": [], "rarity": 2,
		"qty": 4, "have": 1, "ready": false, "status": "accepted", "coins": 40, "base": 20, "bonus": 20, "visit": null, "where": null}
	r.merge(over, true)
	return r

func _view(market: Dictionary, elsewhere: Array, sys_used := 1) -> Dictionary:
	return {"boards": {"stall": {"slots": []}, "market": market, "elsewhere": elsewhere},
		"quotas": {"sys_requests": {"used": sys_used, "cap": 6, "resets_in": 9 * 3_600_000 + 12 * 60_000}}, "residents": {}}

func _hayward(slots: Array) -> Dictionary:
	return {"title": "Market Board", "deliver_at": "market", "cluster": "gn-5355933", "city": "Hayward", "home": false,
		"deliver_place": "gn-5355933~market0", "deliver_name": "Acorn Market Square", "slots": slots}

func test_another_citys_tracked_request_says_where_and_which_city() -> void:
	var away := _req("dusk-hay").merged({"cluster": "gn-5355933", "city": "Hayward", "home": false,
		"deliver_place": "gn-5355933~market0", "deliver_name": "Acorn Market Square"}, true)
	var v := _view({"title": "Market Board", "home": true, "slots": []}, [away])
	var t: Array = PinReason.taken(v)
	assert_int(t.size()).is_equal(1)
	assert_str(str(t[0].deliver)).is_equal("Deliver at Acorn Market Square · Hayward")
	assert_str(str(t[0].deliver_go)).is_equal("outpost:gn-5355933~market0")
	assert_str(str(t[0].city)).is_equal("Hayward")
	assert_bool(bool(t[0].away)).is_true()
	assert_str(str(PinReason.request_of(v, "dusk-hay").deliver)).is_equal("Deliver at Acorn Market Square · Hayward")

func test_the_board_of_the_city_the_player_is_in_is_not_away() -> void:
	var v := _view(_hayward([_req("dusk-here")]), [])
	var t: Array = PinReason.taken(v)
	assert_bool(bool(t[0].away)).is_false()
	assert_str(str(t[0].deliver)).is_equal("Deliver at Acorn Market Square · Hayward")

func test_the_progress_line_ends_with_the_city_and_drops_the_need_first_when_long() -> void:
	var row := P0Logic._request_row({}, {"id": "a", "title": "Dusk Haul", "kind": "crop", "items": [], "need_name": "Fine fish",
		"have": 1, "qty": 4, "city": "Hayward"})
	assert_str(str(row.line)).is_equal("Dusk Haul · Fine fish 1/4 · Hayward")
	var long := P0Logic._request_row({}, {"id": "b", "title": "Market Basket", "kind": "crop", "items": [], "need_name": "Radish and Carrot",
		"have": 2, "qty": 6, "city": "Rio de Janeiro"})
	assert_str(str(long.line)).is_equal("Market Basket · 2/6 · Rio de Janeiro")

func test_the_sheet_names_the_boards_city_and_opens_for_a_request_elsewhere() -> void:
	var here := _view(_hayward([_req("dusk-here", {"status": "open"})]), [])
	assert_str(str(P0Board.detail(here, "market", "dusk-here").effect)).contains("any Hayward market")
	var away := _req("dusk-hay").merged({"cluster": "gn-5355933", "city": "Hayward", "home": false}, true)
	var home := _view({"title": "Market Board", "home": true, "city": "San Francisco", "slots": []}, [away])
	var d := P0Board.detail(home, "market", "dusk-hay")
	assert_bool(d.is_empty()).is_false()
	assert_str(str(d.effect)).contains("any Hayward market")
	assert_bool(bool(d.tracked)).is_true()   # its sheet offers Drop request

func test_a_stamp_run_in_another_city_comes_back_to_that_citys_market() -> void:
	var stamp := _req("stamp-hay", {"title": "Stamp Run", "kind": "visit", "rarity": null, "qty": 1, "have": 0,
		"visit": {"place": "gn-5355933~tea0", "done": false, "name": "Willow Tea House", "city": "Hayward", "cluster": "gn-5355933"}})
	var d := P0Board.detail(_view(_hayward([stamp]), []), "market", "stamp-hay")
	assert_str(str(d.effect)).is_equal("Visit Willow Tea House, then come back to any Hayward market.")
