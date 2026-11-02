extends GdUnitTestSuite
## q(268) (0.2.18, Joey via the user; the user's B): no wait between NPC requests — residents' gap and the boards' done
## refill are 0, a drop still waits 8 h (no redraw farming); where a wait is 0 (or past) the client says nothing about
## it: no `0h`, no `1m` (不知火舞: ≤ 0 or missing, leave the line out).

func test_the_shipped_table_has_no_request_waits() -> void:
	var c := P0Logic.content()
	assert_int(int(c.requests.done_refill_h)).is_equal(0)
	assert_int(int(c.requests.drop_refill_h)).is_equal(8)      # kept (the user's B)
	assert_int(int(c.affinity.next_request_h)).is_equal(0)
	for id in ["res_pip", "res_old_kai"]: assert_bool(bool(c.residents[id].get("one_per_day", false))).is_false()
	assert_int(int(c.requests.expire_h)).is_equal(72)           # kept
	assert_int(int(c.quotas.sys_requests.cap)).is_equal(6)       # kept
	assert_int(int(c.quotas.request_bonus.cap)).is_equal(100)    # kept

func test_dropping_still_says_its_wait() -> void:
	assert_str(P0Board.drop_wait()).is_equal("8h")

func test_a_board_slot_refilling_now_is_no_next_request() -> void:
	var view := {"quotas": {"sys_requests": {"used": 1, "cap": 6}},
		"boards": {"stall": {"slots": [{"empty": true, "refill_in": 0}, {"empty": true, "held": true}]}}}
	var labels: Array = P0Board.facts(view, "stall").map(func(f): return str(f[0]))
	assert_array(labels).is_equal(["Requests today"])
	view.boards.stall.slots[1] = {"empty": true, "refill_in": 3 * 3_600_000}   # a wait still counted down (an older save's slot)
	assert_array(P0Board.facts(view, "stall")).contains([["Next request", P0Logic.span(3 * 3_600_000.0)]])

func test_keepers_say_no_refill_time_at_zero() -> void:
	var view := {"keepers": {"post": {"greet": "cups_left", "cups_left": 2, "request_by": null, "board_open": 0, "refill_in": 0}}}
	assert_str(str(P0Logic.keeper_lines(view, "post").answer)).is_equal("All quiet.")

func test_a_resident_wait_with_nothing_left_reads_as_open() -> void:
	var r := {"affinity": 17, "stage": "Acquainted", "stage_from": 15, "next_stage": "Familiar", "next_at": 45,
		"chatted_today": true, "gift_today": true, "meal": "none", "request_state": "wait", "need_stage": null, "next_in": 0,
		"request": {"id": "req_res_nadia_1", "kind": "crop", "item": "crop_potato", "qty": 3, "coins": 20, "have": 0, "ready": false}}
	var bar := P0Logic.resident_bar({"residents": {"res_nadia": r}, "names": {}, "bag": {"slots": []}}, "res_nadia")
	assert_str(str(bar.request_reason)).is_equal("")
	assert_dict(bar.request_cmd).is_equal({"type": "accept", "request": "req_res_nadia_1"})
