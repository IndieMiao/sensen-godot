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
	assert_str(str(P0Logic.resident_request("res_nadia", "req_res_nadia_six_radishes").get("title", ""))).is_equal("Four Radishes")   # v4q(4) ⑥ 丁20; the id kept
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

## q(224) ① / q(225) ①: a request card whose reward gives a recipe card (A Fresh Radish, The Big Basket) ends its
## reward line on `New recipe` (no dish name) while the page is not known; a request without a recipe does not.
func test_a_recipe_request_card_says_new_recipe() -> void:
	var reward := "+%d Friendship · 20 coins" % int(P0Logic.content().affinity.request)
	var card := func(v: Dictionary) -> String: return str(P0Ui._request_card_data(v, "res_nadia", P0Logic.resident_bar(v, "res_nadia")).reward)
	var req := {"id": "req_res_nadia_radish", "kind": "crop", "item": "crop_radish", "qty": 1, "coins": 20, "have": 0, "ready": false}
	var v := _nadia({"request": req, "request_state": "open"})
	assert_str(card.call(v)).is_equal(reward + " · New recipe")
	v["cooking"] = {"cookbook": [{"id": "dish_fish_soup", "known": false}]}
	assert_str(card.call(v)).is_equal(reward + " · New recipe")
	v.cooking.cookbook[0].known = true                                   # already known: the server gives no card
	assert_str(card.call(v)).is_equal(reward)
	req = {"id": "req_res_nadia_six_radishes", "kind": "harvest", "item": "crop_radish", "qty": 6, "coins": 20, "have": 0, "ready": false}
	assert_str(card.call(_nadia({"request": req, "request_state": "open"}))).is_equal(reward)
	req = {"id": "req_res_nadia_3", "kind": "crop", "item": "crop_radish", "qty": 6, "coins": 20, "have": 0, "ready": false}
	v = _nadia({"request": req, "request_state": "open"})
	assert_str(card.call(v)).is_equal(reward + " · New recipe")       # the P1 line's recipe requests too (q(225) ①)
	v["cooking"] = {"cookbook": [{"id": "dish_roast_veggies", "known": true}]}
	assert_str(card.call(v)).is_equal(reward)
	req = {"id": "req_res_nadia_1", "kind": "crop", "item": "crop_potato", "qty": 6, "coins": 20, "have": 0, "ready": false}
	assert_str(card.call(_nadia({"request": req, "request_state": "open"}))).is_equal(reward)   # no recipe in its reward

## ResidentRequestCard: the card's title is the request's name and Deliver to names the outpost from the home set.
func test_the_request_card_names_the_request_and_where_to_deliver() -> void:
	var req := {"id": "req_res_nadia_radish", "kind": "crop", "item": "crop_radish", "qty": 1, "coins": 20, "have": 0, "ready": false}
	var v := _nadia({"request": req, "request_state": "open", "place": "sh_market_1"})
	var card := P0Ui._request_card_data(v, "res_nadia", P0Logic.resident_bar(v, "res_nadia"))
	assert_str(str(card.title)).is_equal("A Fresh Radish")
	assert_str(str(card.deliver_to)).is_equal("Nadia · %s" % str(P0Outposts.find("sh_market_1").name))
	v.residents.res_nadia.place = "nowhere_1"
	assert_str(str(P0Ui._request_card_data(v, "res_nadia", P0Logic.resident_bar(v, "res_nadia")).deliver_to)).is_equal("Nadia")

func test_story_rewards_name_the_reward_types_without_revealing_the_title() -> void:
	for resident in P0Logic.content().residents:
		for req in P0Logic.content().residents[resident].requests:
			var v := {"residents": {resident: {"request": req}}}
			var card := P0Ui._request_card_data(v, resident, {})
			var title := str(req.get("reward", {}).get("title", ""))
			assert_bool(str(card.reward).ends_with("New title")).is_equal(title != "")
			if title != "": assert_str(str(card.reward)).not_contains(title)
			if title != "" and str(req.get("reward", {}).get("recipe", "")) != "":
				assert_str(str(card.reward)).ends_with("New recipe · New title")

func test_request_card_shows_actual_coins_and_a_separate_reset_line_only_when_short() -> void:
	var req := {"id": "req_res_nadia_4", "coins": 90, "bonus": 80}
	var v := _nadia({"request": req})
	v["quotas"] = {"request_bonus": {"used": 100, "cap": 100, "resets_in": (9 * 60 + 12) * 60000}}
	var card := P0Ui._request_card_data(v, "res_nadia", {})
	assert_str(str(card.reward)).is_equal("+5 Friendship · 10 coins · New recipe · New title")
	assert_str(str(card.bonus_note)).is_equal("Bonus resets in 9h 12m")
	v.quotas.request_bonus.used = 75
	assert_str(str(P0Ui._request_card_data(v, "res_nadia", {}).reward)).contains("35 coins")
	v.quotas.request_bonus.used = 20
	card = P0Ui._request_card_data(v, "res_nadia", {})
	assert_str(str(card.reward)).contains("90 coins")
	assert_str(str(card.bonus_note)).is_empty()
	v.quotas.request_bonus.used = 100
	req.bonus = 90
	assert_str(str(P0Ui._request_card_data(v, "res_nadia", {}).reward)).contains("0 coins")
	req.bonus = -10
	card = P0Ui._request_card_data(v, "res_nadia", {})
	assert_str(str(card.reward)).contains("100 coins")
	assert_str(str(card.bonus_note)).is_empty()
	req.erase("bonus")   # old server: no guessed floor or reset note
	card = P0Ui._request_card_data(v, "res_nadia", {})
	assert_str(str(card.reward)).contains("90 coins")
	assert_str(str(card.bonus_note)).is_empty()
