extends GdUnitTestSuite
## Pip's Homestead request (A 包反馈 1, spec ③ v3 / eval-B, over q(255)'s Homestead row): after the guide, the next level's
## first gap as v4q(1) words it (skill, travel, material, coins), or `Upgrade to Homestead Lv{n}` with the hand-ins here
## (it is one, its dot `homestead:<n>`). The gap row lights once, the first time it is there (`pip:home`, seen for good).
## A tap off its Show opens HOME-1. Order: hand-ins here > Upgrade > hand-ins away > Limit reached > the gap row > Pip's
## First Dig > the vein one > the others still short (newest taken first). No crops, stove or skill rows in Today.

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
		"mine": {"at": null, "records": {}},
	}

static func _lines(v: Dictionary) -> Array: return P0Logic.today_rows(v).map(func(r): return str(r.line))

static func _home(v: Dictionary) -> Dictionary:
	for r in P0Logic.today_rows(v):
		if str(r.line).contains("Homestead"): return r
	return {}

func test_the_first_material_in_order_leads_with_no_show_yet() -> void:
	var v := _view()
	var row := _home(v)
	assert_str(str(row.line)).is_equal("Homestead Lv2 · Timber 6 to go")   # Timber before Reeds and Stone, whatever the server's order
	assert_str(str(row.icon)).is_equal("level_up")
	assert_str(str(row.go)).is_empty()    # no farm spot to show (v4q(4) ①); a city's point is C's
	assert_str(str(row.dot)).is_equal(P0Logic.PIP_HOME_DOT)   # Pip's request: lights once, the first time (spec ③ v3)
	assert_bool(bool(row.get("home_request", false))).is_true()   # a tap opens HOME-1
	assert_bool(P0Logic.homestead_row(v).now).is_false()
	v.homestead.next.materials[1].have = 6
	assert_str(str(_home(v).line)).is_equal("Homestead Lv2 · Stone 4 to go")

func test_no_countdown_comes_with_it() -> void:
	var v := _view()
	v.plots = [{"state": "growing", "crop": "crop_radish", "ready_in": 3600000}]
	assert_array(_lines(v)).is_equal(["Homestead Lv2 · Timber 6 to go"])   # the crop's countdown is the field's

func test_coins_short_points_at_the_stall_and_lights_nothing() -> void:
	var v := _view()
	v.homestead.next.materials = []
	v.homestead.next.coins = {"need": 160, "have": 120}   # HOME-1's coin tile: the 40-coin floor is in `need`
	var row := _home(v)
	assert_str(str(row.line)).is_equal("Homestead Lv2 · 40 coins to go")
	assert_str(str(row.go)).is_equal("stall")
	assert_array(P0Logic.today_dots(P0Logic.today_rows(v))).is_equal([P0Logic.PIP_HOME_DOT])   # the same key at every gap

func test_only_skills_short_shows_homestead_and_deduplicates_the_skill() -> void:
	var v := _view()
	v.homestead.next.materials = []
	v.homestead.next.skills = [{"skill": "fishing", "need": 3, "have": 2}]
	assert_str(_home(v).line).is_equal("Homestead Lv2 · Fishing Lv3 needed")
	assert_bool(_lines(v).has("Fishing Lv2 · 30 XP to go")).is_false()

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
	assert_bool(bool(rows[1].get("home_request", false))).is_true()
	assert_int(rows.size()).is_equal(2)   # no Harvest row (A 包反馈 1)
	assert_array(P0Logic.today_dots(rows)).contains(["homestead:2"])

func test_the_gap_row_leads_the_short_ones() -> void:
	var v := _tracked(_view())
	v.plots = [{"state": "ready", "crop": "crop_radish"}]
	assert_array(_lines(v)).is_equal(["Homestead Lv2 · Timber 6 to go", "Dusk Supper · Grilled dishes 0/1"])

func test_none_during_the_guide_but_later_levels_keep_the_row() -> void:
	var v := _view()
	v["guide"] = {"step": "first_sow"}
	assert_dict(P0Logic.homestead_row(v)).is_empty()
	v.erase("guide")
	v.homestead.level = 3
	v.homestead.next.level = 4
	assert_str(str(P0Logic.homestead_row(v).row.line)).is_equal("Homestead Lv4 · Timber 6 to go")
	v.homestead.level = 2
	v.homestead.next.level = 3
	assert_str(str(P0Logic.homestead_row(v).row.line)).is_equal("Homestead Lv3 · Timber 6 to go")

## The mine mouth left the farm in 355 b1, the gathering spots with v4q(4) ①: no longer homestead targets.
func test_the_sign_is_shown_on_the_farm() -> void:
	assert_bool(P0Ui.home_target("mine")).is_false()
	assert_bool(P0Ui.home_target("spot_grove")).is_false()
	assert_str(P0Ui.show_label("sign", "home", true)).is_equal("Show")
	assert_str(P0Ui.show_label("sign", "pond", true)).is_equal("Show on map")
	assert_str(P0Ui.map_target("sign")).is_equal("home")

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

## Old Kai's short request (the others still short, after Pip's).
func _tracked(v: Dictionary) -> Dictionary:
	v.residents = (v.get("residents", {}) as Dictionary).merged({"res_old_kai": {"request": {"id": "req_res_kai_2", "kind": "fish",
		"rarity": 3, "have": 0, "qty": 1, "ready": false, "accepted_at": 9000}, "request_state": "accepted"}}, true)
	return v

func test_upgrade_comes_with_the_hand_ins_here_before_the_short_ones() -> void:
	var v := _tracked(_view())
	v.homestead.next.materials = []
	v.homestead.next.can_upgrade = true
	v.boards = {"stall": {"slots": [
		{"id": "a", "title": "Crate A", "kind": "crop", "items": ["crop_radish"], "have": 2, "qty": 2, "ready": true, "status": "accepted", "accepted_at": 1},
		{"id": "b", "title": "Crate B", "kind": "crop", "items": ["crop_radish"], "have": 2, "qty": 2, "ready": true, "status": "accepted", "accepted_at": 2}]}}
	assert_array(_lines(v)).is_equal(["Crate A · Deliver at the Stall", "Crate B · Deliver at the Stall", "Upgrade to Homestead Lv2",
		"Dusk Supper · Grilled dishes 0/1"])
