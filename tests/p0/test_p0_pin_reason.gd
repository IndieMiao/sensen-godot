extends GdUnitTestSuite
## Why a map pin wears its mark (q(103), SGODOT-268; style 不知火舞 on 268, ◆ chat and singular 李白 on 268): the
## reason line under a pin card's subtitle, from the server's map_markers or the client's own first-session marks —
## which, like the server since q(103), mark a pond only for a taken request.

const PinReason := preload("res://modules/p0/p0_pin_reason.gd")
const P0Map := preload("res://scenes/p0/p0_map.gd")
const REED := "pond_san_francisco_03"   # Fern Pond, the beginner pond (SGODOT-270; the name kept for the history)

const NAMES := {"fish_crucian": "Pond Crucian", "rod_reed": "Reed Rod", "bait_worm": "Worm Bait"}

## The first session's view: Pond Catch on the Stall Board, as both the boards and the older stall panel have it.
func _tutorial(status: String, have: int) -> Dictionary:
	var r := {"id": P0Guide.TUTORIAL, "title": "Pond Catch", "kind": "fish", "items": ["fish_crucian"], "rarity": null,
		"qty": 2, "have": have, "ready": have >= 2, "status": status}
	return {"names": NAMES,
		"boards": {"stall": {"slots": [r]}, "market": {"slots": []}},
		"stall": {"board": {"requests": [{"id": P0Guide.TUTORIAL, "title": "Pond Catch", "item": "fish_crucian", "qty": 2,
			"have": have, "status": status}]}}}

# ---------------------------------------------------------------- the client's own marks (q(103) ④)
func test_an_untaken_pond_catch_marks_no_pond() -> void:
	var v := _tutorial("open", 0)
	assert_array(PinReason.markers(v)).is_empty()
	assert_array(P0Map.pin_marks(v)).is_empty()            # was the beginner pond's ! before q(103)
	assert_str(P0Map.home_mark(v)).is_empty()
	assert_dict(PinReason.reason(v, REED)).is_empty()

func test_a_taken_pond_catch_marks_the_beginner_pond_until_the_fish_are_in_the_bag() -> void:
	var v := _tutorial("accepted", 0)
	assert_array(P0Map.pin_marks(v)).is_equal([{"id": REED, "state": "request"}])
	var why := PinReason.reason(v, REED)
	assert_str(str(why.state)).is_equal("request")
	assert_str(str(why.text)).is_equal("Pond Catch · Pond Crucian 0/2")
	assert_str(str(why.request)).is_equal(P0Guide.TUTORIAL)
	assert_str(str(PinReason.reason(_tutorial("accepted", 1), REED).text)).is_equal("Pond Catch · Pond Crucian 1/2")
	# Two in the bag: the ! leaves the pond and the homestead wears the ✓.
	var full := _tutorial("accepted", 2)
	assert_array(P0Map.pin_marks(full)).is_empty()
	assert_str(P0Map.home_mark(full)).is_equal("deliverable")
	assert_dict(PinReason.reason(full, REED)).is_empty()
	assert_str(str(PinReason.reason(full, "home").text)).is_equal("Pond Catch · Ready to deliver")
	# Handed in: nothing left.
	var done := {"names": NAMES, "boards": {"stall": {"slots": [{"empty": true}]}}, "stall": {"board": {"requests": []}}}
	assert_array(PinReason.markers(done)).is_empty()

## q(104): a taken request whose fish is above the player's Fishing level marks no pond (Pond Crucian is Lv1, so the
## real Pond Catch always does; a heavier fish stands in here).
func test_a_fish_the_player_cannot_land_yet_marks_no_pond() -> void:
	var v := _tutorial("accepted", 0)
	v.stall.board.requests[0].item = "fish_koi"
	v.boards.stall.slots[0].items = ["fish_koi"]
	v["skills"] = {"fishing": {"level": 2}}
	assert_array(PinReason.markers(v)).is_empty()
	v.skills.fishing.level = 4
	assert_array(P0Map.pin_marks(v)).is_equal([{"id": REED, "state": "request"}])

func test_the_older_stall_panel_alone_still_reads_the_tutorial() -> void:
	var v := _tutorial("accepted", 0)
	v.erase("boards")   # a server without view.boards
	assert_str(str(PinReason.reason(v, REED).text)).is_equal("Pond Catch · Pond Crucian 0/2")

# ---------------------------------------------------------------- the server's marks (q(48) data, q(103) lines)
func _server(markers: Array) -> Dictionary:
	var v := _tutorial("accepted", 0)
	v.boards.market = {"slots": [
		{"id": "mk_1", "title": "Market Basket", "kind": "crop", "items": ["crop_radish", "crop_carrot"], "qty": 3, "have": 0,
			"ready": false, "status": "open"},
		{"id": "mk_2", "title": "Fine Catch", "kind": "fish", "items": [], "rarity": 2, "qty": 4, "have": 1, "ready": false,
			"status": "accepted"},
		{"empty": true}]}
	v["residents"] = {"res_pip": {"request": {"id": "req_res_pip_1", "kind": "fish", "rarity": 1, "qty": 3, "have": 3,
		"ready": true}, "request_state": "accepted"}}
	v["map_markers"] = markers
	return v

func test_each_mark_says_why_in_the_q103_wording() -> void:
	var v := _server([
		{"place": REED, "kind": "request", "why": {"request": P0Guide.TUTORIAL, "tracked": true}},
		{"place": "sh_market_1", "kind": "request", "why": {"request": "mk_1"}},
		{"place": "sh_post_1", "kind": "request", "why": {"request": "req_res_pip_2", "resident": "res_pip"}},
		{"place": "home", "kind": "deliver", "why": {"request": P0Guide.TUTORIAL, "tracked": true}},
		{"place": "sh_tackle_1", "kind": "new", "why": {"item": "rod_reed"}},
	])
	assert_str(str(PinReason.reason(v, REED).text)).is_equal("Pond Catch · Pond Crucian 0/2")
	assert_str(str(PinReason.reason(v, "sh_market_1").text)).is_equal("Market Board · 1 request")   # one untaken
	assert_str(str(PinReason.reason(v, "sh_post_1").text)).is_equal("Pip · New request")
	assert_str(str(PinReason.reason(v, "home").text)).is_equal("Pond Catch · Ready to deliver")
	assert_str(str(PinReason.reason(v, "sh_tackle_1").text)).is_equal("New for you · Reed Rod")
	assert_str(str(PinReason.reason(v, "sh_tackle_1").state)).is_equal("new")
	assert_dict(PinReason.reason(v, "sh_tea_1")).is_empty()   # no mark, no line

func test_market_requests_count_and_a_residents_chat_reads_new_chat() -> void:
	var v := _server([{"place": "sh_market_1", "kind": "request", "why": {"request": "mk_1"}},
		{"place": "sh_post_1", "kind": "new", "why": {"resident": "res_pip"}}])
	v.boards.market.slots[1].status = "open"
	assert_str(str(PinReason.reason(v, "sh_market_1").text)).is_equal("Market Board · 2 requests")
	assert_str(str(PinReason.reason(v, "sh_post_1").text)).is_equal("Pip · New chat")   # 李白 on 268

## The server keeps one mark per place, the strongest, and says how many more it held (`more`); a client given several
## for one place counts the rest too.
func test_more_marks_at_a_place_add_plus_n_more() -> void:
	var v := _server([{"place": "sh_market_1", "kind": "deliver", "why": {"request": "mk_2"}, "more": 1}])
	assert_str(str(PinReason.reason(v, "sh_market_1").text)).is_equal("Fine Catch · Ready to deliver · +1 more")
	assert_int(int(PinReason.reason(v, "sh_market_1").more)).is_equal(1)
	var two := _server([{"place": "sh_post_1", "kind": "request", "why": {"request": "req_res_pip_2", "resident": "res_pip"}},
		{"place": "sh_post_1", "kind": "new", "why": {"resident": "res_pip"}, "more": 0}])
	assert_str(str(PinReason.reason(two, "sh_post_1").text)).is_equal("Pip · New request · +1 more")
	var none := _server([{"place": REED, "kind": "request", "why": {"request": P0Guide.TUTORIAL, "tracked": true}, "more": 0}])
	assert_str(str(PinReason.reason(none, REED).text)).is_equal("Pond Catch · Pond Crucian 0/2")

## While the new-player guide is on, the server's pins carry why.guide (SGODOT-341, 不知火舞 694e8da8): the pond says the
## mark's own line from view.guide.marks, the Homestead the step's Today row, never `Market Board · 0 requests`.
func _guided(step: String, row: Dictionary, marks: Array, progress := {"have": 0, "need": 1}) -> Dictionary:
	var v := _server([])
	v.map_markers = marks.filter(func(m): return m.has("place")).map(func(m): return {"place": m.place,
		"kind": "request", "why": {"guide": step, "tracked": true}})
	v["guide"] = {"step": step, "recover": null, "progress": progress, "row": row, "marks": marks}
	return v

func test_a_guide_pin_says_the_guide_step_not_the_market_board() -> void:
	var fish := _guided("t_fish", {"line": "Catch 2 fish · Fern Pond", "icon": "fish_crucian", "go": REED},
		[{"place": REED, "kind": "request", "why": "Catch 2 fish · 0/2"}], {"have": 0, "need": 2})
	assert_str(str(PinReason.reason(fish, REED).text)).is_equal("Catch 2 fish · 0/2")
	assert_str(str(PinReason.reason(fish, REED).state)).is_equal("request")
	fish.guide.marks[0].why = "Catch 2 fish · 1/2"   # the server fills the count
	assert_str(str(PinReason.reason(fish, REED).text)).is_equal("Catch 2 fish · 1/2")
	var meal := _guided("t_meal", {"line": "Cook it: Grilled Crucian", "icon": "dish_grilled_crucian", "go": "home"},
		[{"place": "home", "object": "farmhouse", "kind": "request"}])
	assert_str(str(PinReason.reason(meal, "home").text)).is_equal("Cook it: Grilled Crucian")
	# A count over one rides on the row as Today shows it.
	var two := _guided("t_x", {"line": "Bring 2 Radishes", "icon": "crop_radish", "go": "home"},
		[{"place": "home", "kind": "request"}], {"have": 1, "need": 2})
	assert_str(str(PinReason.reason(two, "home").text)).is_equal("Bring 2 Radishes · 1/2")
	# Neither a line at the place nor a row: nothing said, not the Market Board's count.
	var bare := _guided("t_y", {}, [{"place": "home", "kind": "request"}])
	bare.guide.row = null
	assert_str(str(PinReason.reason(bare, "home").text)).is_empty()

## One lookup for every request the marks name, with where it is handed in (周瑜's pond toasts read the same).
func test_requests_say_how_far_along_they_are_and_where_they_go() -> void:
	var v := _server([])
	var t := PinReason.request_of(v, P0Guide.TUTORIAL)
	assert_str(PinReason.progress_text(t)).is_equal("Pond Catch · Pond Crucian 0/2")
	assert_str(str(t.deliver)).is_equal("Deliver at the Stall")
	assert_bool(bool(t.tracked)).is_true()
	var market := PinReason.request_of(v, "mk_2")
	assert_str(PinReason.progress_text(market)).is_equal("Fine Catch · Fine fish 1/4")
	assert_str(str(market.deliver)).is_equal("Deliver at Mission Market Square")
	var pip := PinReason.request_of(v, "req_res_pip_1")
	assert_str(PinReason.progress_text(pip)).is_equal("Pip's First Fish · Common fish 3/3")
	assert_str(str(pip.deliver)).is_equal("Deliver to Pip")
	assert_bool(bool(pip.ready)).is_true()
	assert_dict(PinReason.request_of(v, "gone")).is_empty()

# ---------------------------------------------------------------- the row on the card (不知火舞 on 268)
func test_the_reason_row_is_an_18_px_mark_and_one_ellipsised_c13_line() -> void:
	var row: HBoxContainer = auto_free(P0PlaceSheet.reason_row({"state": "request", "text": "Pond Catch · Pond Crucian 0/2"}))
	assert_float(row.custom_minimum_size.y).is_equal(24.0)
	assert_int(row.get_theme_constant(&"separation")).is_equal(6)
	var mark: Control = row.get_node("Mark")
	assert_that(mark.custom_minimum_size).is_equal(Vector2(18, 18))
	var badge := mark.get_child(0) as UiStatusBadge
	assert_int(badge.state).is_equal(UiStatusBadge.State.REQUEST)   # the pin's own mark
	assert_float(badge.scale.x * UiTokens.SIZE_STATUS_BADGE_WORLD).is_equal_approx(18.0, 0.001)
	var text: Label = row.get_node("Text")
	assert_str(text.text).is_equal("Pond Catch · Pond Crucian 0/2")
	assert_int(text.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_bool(text.clip_text).is_true()
	for key in ["deliverable", "new"]:
		var r: HBoxContainer = auto_free(P0PlaceSheet.reason_row({"state": key, "text": "x"}))
		assert_int((r.get_node("Mark").get_child(0) as UiStatusBadge).state).is_equal(UiStatusBadge.state_of(key))
