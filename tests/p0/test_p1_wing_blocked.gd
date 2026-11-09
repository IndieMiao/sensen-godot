extends GdUnitTestSuite
## Homestead Lv8's Kitchen Wing and what stands on its cells (q(303), SGODOT-450; 不知火舞 450 v1.2, 后裔's interface):
## the cells come from content decor.yard.wing, as the server reads them; from Lv8 they are the house's (`Space taken`).
## Before the upgrade into it, pieces or facilities on them are its last gap (homestead.next.blocked): HOME-1's key grey
## with `Space taken`, a tap `Space taken · clear it first`, Today's `Homestead Lv8 · Space taken` to do now with no red
## dot and a Show into Decorate. A save already past Lv8 with them held (homestead.wing_blocked): `Kitchen Wing · Space
## taken` (the Master Farmhouse's name from Lv15), the same Show, no dot.

const WING := [Vector2i(5, 17), Vector2i(5, 18), Vector2i(6, 18), Vector2i(7, 16), Vector2i(7, 17), Vector2i(7, 18), Vector2i(8, 18)]

static func _held() -> Dictionary:
	return {"cells": [[7, 16], [6, 18]], "pieces": [{"uid": 3, "item": "deco_planter", "x": 7, "y": 16, "rot": 0}],
		"facilities": [{"id": 1, "kind": "compost_bin", "x": 6, "y": 18}]}

## Lv7 with everything for Lv8 had: only the wing's cells can stop it.
static func _lv7() -> Dictionary:
	return {
		"coins": 900, "energy": {"value": 150, "max": 200},
		"skills": {"farming": {"level": 6, "xp": 0}, "fishing": {"level": 5, "xp": 0}, "cooking": {"level": 5, "xp": 0}},
		"bag": {"capacity": 25, "slots": []}, "firsts": ["harvest:crop_radish"],
		"homestead": {"level": 7, "next": {"level": 8, "coins": {"need": 600, "have": 900}, "skills": [], "materials": [],
			"energy": 260, "meals": 4, "unlocks": ["kitchen_extension"], "can_upgrade": true}},
		"decor": {"placed": [{"uid": 3, "id": "deco_planter", "x": 7, "y": 16, "rot": 0}], "cap": 48, "used": 1, "stored": {}},
		"mine": {"at": null, "records": {}},
	}

static func _home_row(v: Dictionary) -> Dictionary:
	for r in P0Logic.today_rows(v):
		if str(r.line).begins_with("Homestead") or str(r.line).begins_with("Upgrade to Homestead"): return r
	return {}

func test_the_wing_cells_are_the_contents_and_the_houses_from_lv8() -> void:
	assert_array(P0Decor.wing_cells()).contains_exactly_in_any_order(WING)
	assert_int(int(P0Decor.wing().homestead)).is_equal(8)
	var v := {"homestead": {"level": 7}, "decor": {"placed": [], "cap": 48, "stored": {}}}
	for c in WING: assert_str(P0Decor.reason(v, "deco_planter", c)).override_failure_message(str(c)).is_equal("")
	v.homestead.level = 8
	for c in WING: assert_str(P0Decor.reason(v, "deco_planter", c)).override_failure_message(str(c)).is_equal("Space taken")
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(4, 17))).is_equal("")   # beside the wing: free as before
	assert_str(P0Decor.reason(v, "deco_bench", Vector2i(4, 17))).is_equal("Space taken")   # a 2×1 reaching (5, 17)
	v.homestead.level = 15   # the Master Farmhouse keeps them
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(8, 18))).is_equal("Space taken")
	assert_bool(P0Decor.wing_cells().any(func(c): return P0Decor.nearest_spot(v, "deco_planter", 0, Vector2i(6, 17)) == c)).is_false()

func test_held_reads_the_servers_shape_and_nothing_held_is_none() -> void:
	var v := _lv7()
	assert_dict(P0Decor.next_blocked(v)).is_empty()   # an older server, or nothing on the cells: no key
	v.homestead.next.blocked = _held()
	assert_array(P0Decor.held_cells(P0Decor.next_blocked(v))).is_equal([Vector2i(7, 16), Vector2i(6, 18)])
	assert_int(int(P0Decor.next_blocked(v).pieces[0].uid)).is_equal(3)
	v.homestead.next.blocked = {"cells": [], "pieces": [], "facilities": []}
	assert_dict(P0Decor.next_blocked(v)).is_empty()
	v.homestead.next = null   # the top level
	assert_dict(P0Decor.next_blocked(v)).is_empty()
	v.homestead.wing_blocked = _held()
	assert_dict(P0Decor.wing_blocked(v)).is_not_empty()

func test_home1_greys_upgrade_with_space_taken_as_the_last_gap() -> void:
	var v := _lv7()
	var p := P0Logic.home_panel(v)
	assert_str(str(p.reason)).is_empty()   # nothing held: Upgrade
	v.homestead.next.blocked = _held()
	p = P0Logic.home_panel(v)
	assert_str(str(p.reason)).is_equal("Space taken")
	assert_str(str(p.tap)).is_equal("Space taken · clear it first")
	assert_bool(bool(p.get("blocked", false))).is_true()
	v.homestead.next.coins.have = 500   # a gap before it says itself first
	p = P0Logic.home_panel(v)
	assert_str(str(p.reason)).is_equal("Need 100 more coins")
	assert_bool(bool(p.get("blocked", false))).is_false()
	assert_str(str(P0Logic.home_panel(v, false).reason)).is_equal("At home")   # away: as before

func test_today_says_space_taken_to_do_now_without_a_dot() -> void:
	var v := _lv7()
	assert_str(str(_home_row(v).line)).is_equal("Upgrade to Homestead Lv8")
	v.homestead.next.blocked = _held()
	var row := _home_row(v)
	assert_str(str(row.line)).is_equal("Homestead Lv8 · Space taken")
	assert_str(str(row.icon)).is_equal("deco_planter")
	assert_str(str(row.go)).is_equal(P0Logic.DECORATE_GO)
	assert_str(str(row.dot)).is_empty()
	assert_bool(bool(row.get("home_request", false))).is_true()   # a tap off its Show opens HOME-1
	assert_bool(bool(P0Logic.homestead_row(v).now)).is_true()
	assert_array(P0Logic.today_dots(P0Logic.today_rows(v))).is_empty()
	v.homestead.next.coins.have = 500   # coins first, as on HOME-1
	assert_str(str(_home_row(v).line)).is_equal("Homestead Lv8 · 100 coins to go")

func test_a_save_past_lv8_says_its_look_waits_on_the_cells() -> void:
	var v := _lv7()
	v.homestead = {"level": 9, "next": null, "wing_blocked": _held()}
	var rows := P0Logic.today_rows(v)
	var wing: Array = rows.filter(func(r): return str(r.line).ends_with("· Space taken"))
	assert_int(wing.size()).is_equal(1)
	assert_str(str(wing[0].line)).is_equal("Kitchen Wing · Space taken")
	assert_str(str(wing[0].go)).is_equal(P0Logic.DECORATE_GO)
	assert_str(str(wing[0].dot)).is_empty()
	assert_array(P0Logic.today_dots(rows)).is_empty()
	v.homestead.level = 15
	assert_str(str(P0Logic.wing_row(v).line)).is_equal("Master Farmhouse · Space taken")
	v.homestead.erase("wing_blocked")
	assert_dict(P0Logic.wing_row(v)).is_empty()

func test_decorate_is_a_farm_target() -> void:
	assert_bool(P0Ui.home_target(P0Logic.DECORATE_GO)).is_true()
	assert_str(P0Ui.show_label(P0Logic.DECORATE_GO, "home", true)).is_equal("Show")
	assert_str(P0Ui.show_label(P0Logic.DECORATE_GO, "map", true)).is_equal("Show")
