extends GdUnitTestSuite
## q(218) (SGODOT-344): Nadia's teaching requests on the client — the content lookups find them outside her line, a
## harvest request's gap reads `Harvest 4 more Radishes`, and A Fresh Radish's thanks line names the home's beginner pond.

func _nadia(over: Dictionary) -> Dictionary:
	var r := {"affinity": 17, "stage": "Acquainted", "stage_from": 15, "next_stage": "Familiar", "next_at": 45,
		"chatted_today": true, "gift_today": true, "meal": "none", "request": null, "request_state": "none",
		"need_stage": null, "next_in": null}
	r.merge(over, true)
	return {"residents": {"res_nadia": r}, "names": {"crop_radish": "Radish"}, "bag": {"slots": []}}

func test_the_teaching_requests_are_found_by_id_but_stay_out_of_her_line() -> void:
	assert_str(str(P0Logic.resident_request("res_nadia", "req_res_nadia_radish").get("title", ""))).is_equal("A Fresh Radish")
	assert_str(str(P0Logic.resident_request("res_nadia", "req_res_nadia_six_radishes").get("title", ""))).is_equal("Six Radishes")
	assert_str(str(P0Logic.resident_request("res_nadia", "req_res_nadia_1").get("title", ""))).is_equal("Potatoes, Please")
	assert_dict(P0Logic.resident_request("res_nadia", "req_res_nobody")).is_empty()
	assert_str(P0Logic.request_owner("req_res_nadia_six_radishes")).is_equal("res_nadia")
	assert_bool(P0Logic.is_intro_request("res_nadia", "req_res_nadia_radish")).is_true()
	assert_bool(P0Logic.is_intro_request("res_nadia", "req_res_nadia_1")).is_false()
	var line: Array = P0Logic.content().residents.res_nadia.requests.map(func(q): return str(q.id))
	assert_array(line).is_equal(["req_res_nadia_1", "req_res_nadia_2", "req_res_nadia_3", "req_res_nadia_4"])

func test_a_harvest_request_writes_its_gap_on_the_button() -> void:
	var req := {"id": "req_res_nadia_six_radishes", "kind": "harvest", "item": "crop_radish", "qty": 6, "coins": 20, "have": 2, "ready": false}
	var bar := P0Logic.resident_bar(_nadia({"request": req, "request_state": "accepted"}), "res_nadia")
	assert_str(str(bar.request_label)).is_equal("Deliver")
	assert_str(str(bar.request_reason)).is_equal("Harvest 4 more Radishes")
	req.have = 5
	assert_str(str(P0Logic.resident_bar(_nadia({"request": req, "request_state": "accepted"}), "res_nadia").request_reason)).is_equal("Harvest 1 more Radish")
	req.have = 6
	req.ready = true
	assert_that(P0Logic.resident_bar(_nadia({"request": req, "request_state": "accepted"}), "res_nadia").request_cmd) \
		.is_equal({"type": "deliver", "request": "req_res_nadia_six_radishes"})

func test_the_open_teaching_request_shows_its_own_line() -> void:
	var req := {"id": "req_res_nadia_radish", "kind": "crop", "item": "crop_radish", "qty": 1, "coins": 20, "have": 0, "ready": false}
	assert_str(P0Ui.resident_ask(_nadia({"request": req, "request_state": "open"}), "res_nadia")) \
		.is_equal("No fresh radishes anywhere this morning. Could you spare one?")

func test_the_thanks_line_names_the_homes_beginner_pond() -> void:
	var v := _nadia({})
	assert_str(P0Logic.request_thanks(v, "req_res_nadia_radish")) \
		.is_equal("Here's my soup recipe. A fish from Fern Pond and a radish, that's all it takes.")
	v["home"] = {"set": {"pond": "pond_san_francisco_06"}}
	assert_str(P0Logic.request_thanks(v, "req_res_nadia_radish")).contains("A fish from %s and a radish" % \
		str(P0Logic.content().fishing.places.pond_san_francisco_06.name))
	assert_str(P0Logic.request_thanks(v, "req_res_nadia_six_radishes")).is_equal("")
	assert_str(P0Logic.request_thanks(v, "req_res_nadia_1")).is_equal("")

## q(224) ①: A Fresh Radish's card ends its reward line on `New recipe` (no dish name); a request without a recipe does not.
func test_a_recipe_request_card_says_new_recipe() -> void:
	var req := {"id": "req_res_nadia_radish", "kind": "crop", "item": "crop_radish", "qty": 1, "coins": 20, "have": 0, "ready": false}
	var v := _nadia({"request": req, "request_state": "open"})
	var reward := "+%d Friendship · 20 coins" % int(P0Logic.content().affinity.request)
	assert_str(str(P0Ui._request_card_data(v, "res_nadia", P0Logic.resident_bar(v, "res_nadia")).reward)).is_equal(reward + " · New recipe")
	req = {"id": "req_res_nadia_six_radishes", "kind": "harvest", "item": "crop_radish", "qty": 6, "coins": 20, "have": 0, "ready": false}
	v = _nadia({"request": req, "request_state": "open"})
	assert_str(str(P0Ui._request_card_data(v, "res_nadia", P0Logic.resident_bar(v, "res_nadia")).reward)).is_equal(reward)
