extends GdUnitTestSuite
## q(255) Today's Homestead row (SGODOT-341; 不知火舞 frames on 302 e7e3eb4f, order 341 bbdef20e): after the guide and
## below Homestead Lv3, one row points at the next level's first gap — a material, then coins; nothing when only skills
## are short; `Upgrade to Homestead Lv2` once everything is met, the only one that lights the red dot.

const KAI := "req_res_kai_1"

func _view() -> Dictionary:
	return {
		"coins": 120, "energy": {"value": 150, "max": 200},
		"skills": {"farming": {"level": 2, "xp": 60, "next": 100}, "fishing": {"level": 1, "xp": 10, "next": 40}, "cooking": {"level": 1, "xp": 0}},
		"names": {"fish_crucian": "Pond Crucian", "crop_radish": "Radish", "wood": "Timber", "stone": "Stone", "fiber": "Reeds"},
		"bag": {"capacity": 25, "slots": []},
		"firsts": ["harvest:crop_radish"],
		"homestead": {"level": 1, "next": {"level": 2, "coins": {"need": 80, "have": 120}, "skills": [{"skill": "fishing", "need": 3, "have": 3}],
			"materials": [{"id": "fiber", "name": "Reeds", "need": 3, "have": 0}, {"id": "wood", "name": "Timber", "need": 6, "have": 0},
				{"id": "stone", "name": "Stone", "need": 4, "have": 0}], "can_upgrade": false}},
		"gather": {"spots": [
			{"id": "spot_grove", "name": "Timber Grove", "open": true, "ready": true, "ready_in": 0, "yield": [["wood", 6]]},
			{"id": "spot_rock_pile", "name": "Rock Pile", "open": true, "ready": true, "ready_in": 0, "yield": [["stone", 4]]},
			{"id": "spot_reed_bank", "name": "Reed Bank", "open": true, "ready": true, "ready_in": 0, "yield": [["fiber", 3], ["bait_worm", 2]]}]},
		"mine": {"runs": {"used": 0, "limit": 2, "resets_in": 3600000}},
	}

static func _spot(v: Dictionary, id: String) -> Dictionary:
	for sp in v.gather.spots:
		if str(sp.id) == id: return sp
	return {}

static func _cool(v: Dictionary, id: String, ms := 7200000) -> void:
	_spot(v, id).ready = false
	_spot(v, id).ready_in = ms

static func _lines(v: Dictionary) -> Array: return P0Logic.today_rows(v).map(func(r): return str(r.line))

static func _home(v: Dictionary) -> Dictionary:
	for r in P0Logic.today_rows(v):
		if str(r.line).contains("Homestead"): return r
	return {}

func test_the_first_material_in_order_leads_and_points_at_its_ready_spot() -> void:
	var v := _view()
	var row := _home(v)
	assert_str(str(row.line)).is_equal("Homestead Lv2 · Timber 6 to go")   # Timber before Reeds and Stone, whatever the server's order
	assert_str(str(row.icon)).is_equal("level_up")
	assert_str(str(row.go)).is_equal("spot_grove")
	assert_str(str(row.dot)).is_empty()   # a material never lights the dot (q(255) ⑤)
	assert_str(_lines(v)[0]).is_equal("Homestead Lv2 · Timber 6 to go")   # gatherable now: with the rows to do now
	v.homestead.next.materials[1].have = 6
	assert_str(str(_home(v).line)).is_equal("Homestead Lv2 · Stone 4 to go")

func test_a_material_cooling_down_goes_to_still_to_go() -> void:
	var v := _view()
	_cool(v, "spot_grove")
	v.plots = [{"state": "growing", "crop": "crop_radish", "ready_in": 3600000}]
	var lines := _lines(v)
	assert_str(str(lines[0])).is_equal("Radish ready in 1h")   # the countdown comes first now
	assert_str(str(lines[1])).is_equal("Homestead Lv2 · Timber 6 to go")
	assert_str(str(_home(v).go)).is_equal("spot_grove")   # the only place Timber comes from, cooling down

func test_stone_goes_to_the_mine_while_the_rock_pile_cools_and_a_run_is_left() -> void:
	var v := _view()
	v.homestead.next.materials = [{"id": "stone", "name": "Stone", "need": 4, "have": 0}]
	_cool(v, "spot_rock_pile")
	assert_str(str(_home(v).go)).is_equal("mine")
	assert_str(str(_lines(v)[0])).is_equal("Homestead Lv2 · Stone 4 to go")   # the mine is open: doable now
	v.mine.runs.used = 2
	assert_str(str(_home(v).go)).is_equal("spot_rock_pile")   # neither: the Rock Pile, cooling down
	assert_bool(P0Logic.homestead_row(v).now).is_false()

func test_coins_short_points_at_the_stall_and_lights_nothing() -> void:
	var v := _view()
	v.homestead.next.materials = []
	v.homestead.next.coins = {"need": 160, "have": 120}   # HOME-1's coin tile: the 40-coin floor is in `need`
	var row := _home(v)
	assert_str(str(row.line)).is_equal("Homestead Lv2 · 40 coins to go")
	assert_str(str(row.go)).is_equal("stall")
	assert_array(P0Logic.today_dots(P0Logic.today_rows(v))).is_empty()

func test_only_skills_short_says_nothing() -> void:
	var v := _view()
	v.homestead.next.materials = []
	v.homestead.next.skills = [{"skill": "fishing", "need": 3, "have": 2}]
	assert_dict(_home(v)).is_empty()
	assert_array(_lines(v)).contains(["Fishing Lv2 · 30 XP to go"])   # Today's own skill row says it

func test_upgrade_follows_the_hand_ins_and_lights_the_dot() -> void:
	var v := _view()
	v.homestead.next.materials = []
	v.homestead.next.can_upgrade = true
	v["residents"] = {"res_old_kai": {"request": {"id": KAI, "kind": "fish", "rarity": 1, "have": 1, "qty": 1, "ready": true}, "request_state": "accepted"}}
	v.plots = [{"state": "ready", "crop": "crop_radish"}]
	var rows := P0Logic.today_rows(v)
	assert_str(str(rows[0].dot)).is_equal("deliver:" + KAI)   # hand-ins first (bbdef20e)
	assert_str(str(rows[1].line)).is_equal("Upgrade to Homestead Lv2")
	assert_str(str(rows[1].go)).is_equal("sign")
	assert_str(str(rows[2].line)).is_equal("Harvest 1 Radish")
	assert_array(P0Logic.today_dots(rows)).contains(["homestead:2"])

func test_a_gatherable_material_follows_the_other_things_to_do_now() -> void:
	var v := _view()
	v.plots = [{"state": "ready", "crop": "crop_radish"}]
	assert_array(_lines(v).slice(0, 2)).is_equal(["Harvest 1 Radish", "Homestead Lv2 · Timber 6 to go"])

func test_none_during_the_guide_or_from_lv3() -> void:
	var v := _view()
	v["guide"] = {"step": "first_sow"}
	assert_dict(P0Logic.homestead_row(v)).is_empty()
	v.erase("guide")
	v.homestead.level = 3
	v.homestead.next.level = 4
	assert_dict(P0Logic.homestead_row(v)).is_empty()
	v.homestead.level = 2
	v.homestead.next.level = 3
	assert_str(str(P0Logic.homestead_row(v).row.line)).is_equal("Homestead Lv3 · Timber 6 to go")

func test_the_sign_spots_and_the_mine_are_shown_on_the_farm() -> void:
	for go in ["sign", "spot_grove", "spot_rock_pile", "mine"]:
		assert_str(P0Ui.show_label(go, "home", true)).is_equal("Show")
		assert_str(P0Ui.show_label(go, "pond", true)).is_equal("Show on map")
		assert_str(P0Ui.map_target(go)).is_equal("home")

## An account the new guide never ran, its first-session Pond Catch ready to hand in (P0Guide's lead row): Upgrade
## follows that hand-in too (刘邦 on #542 [P2]; bbdef20e: hand-ins never give way).
func test_upgrade_follows_the_first_sessions_hand_in_too() -> void:
	var v := _view()
	v.homestead.next.materials = []
	v.homestead.next.can_upgrade = true
	v.firsts = []
	v.bag.slots = [{"id": "fish_crucian", "qty": 2}]
	v["stall"] = {"board": {"requests": [{"id": P0Guide.TUTORIAL, "title": "Pond Catch", "item": "fish_crucian", "qty": 2,
		"have": 2, "coins": 14, "where": "any pond", "status": "accepted"}]}}
	var rows := P0Logic.today_rows(v)
	var at_deliver := -1
	var at_upgrade := -1
	for i in rows.size():
		if str(rows[i].dot).begins_with("deliver:"): at_deliver = i
		if str(rows[i].line) == "Upgrade to Homestead Lv2": at_upgrade = i
	assert_int(at_deliver).is_greater_equal(0)
	assert_int(at_upgrade).is_greater(at_deliver)

## q(143)'s tracked short request takes the 3rd row, but never Upgrade, as it never takes a hand-in (不知火舞 on 341, A′;
## 刘邦 on #542 [P1]); a material row gives way as other rows do.
func _tracked(v: Dictionary) -> Dictionary:
	v.residents = (v.get("residents", {}) as Dictionary).merged({"res_old_kai": {"request": {"id": "req_res_kai_2", "kind": "fish",
		"rarity": 3, "have": 0, "qty": 1, "ready": false, "accepted_at": 9000}, "request_state": "accepted"}}, true)
	return v

func test_the_tracked_request_never_takes_upgrades_row() -> void:
	var v := _tracked(_view())
	v.homestead.next.materials = []
	v.homestead.next.can_upgrade = true
	v.boards = {"stall": {"slots": [
		{"id": "a", "title": "Crate A", "kind": "crop", "items": ["crop_radish"], "have": 2, "qty": 2, "ready": true, "status": "accepted", "accepted_at": 1},
		{"id": "b", "title": "Crate B", "kind": "crop", "items": ["crop_radish"], "have": 2, "qty": 2, "ready": true, "status": "accepted", "accepted_at": 2}]}}
	var lines := _lines(v)
	assert_str(str(lines[0])).is_equal("Crate A · Deliver at the Stall")
	assert_str(str(lines[1])).is_equal("Crate B · Deliver at the Stall")
	assert_str(str(lines[2])).is_equal("Upgrade to Homestead Lv2")

func test_a_material_row_gives_way_to_the_tracked_request() -> void:
	var v := _tracked(_view())
	v.plots = [{"state": "ready", "crop": "crop_radish"}, {"state": "sown", "crop": "crop_radish"}]
	var lines := _lines(v)
	assert_array(lines.slice(0, 2)).is_equal(["Harvest 1 Radish", "Water 1 sown plot"])
	assert_str(str(lines[2])).ends_with("0/1")   # Old Kai's tracked request, as q(143) had it; the material row comes back later
	assert_bool(lines.has("Homestead Lv2 · Timber 6 to go")).is_false()
