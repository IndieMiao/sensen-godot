extends GdUnitTestSuite
## Pip's vein request (spec ③ v3 / eval-B, over v4q(9) ①'s row; its conditions unchanged): `<vein> · Floor n/10` — after
## the guide and Pip's First Dig, at Homestead Lv5 and Lv6, iron first then quartz, one at a time, gone at Floor 10 of any
## vein of that main, none when the Homestead request points at the same mine; after Pip's Homestead request, before the
## other short ones. Its red dot lights once a vein (`pip:vein:<id>`, seen for good).

const P0WildSites := preload("res://modules/p0/p0_wild_sites.gd")
const IRON := {"id": "wd-254-115", "type": "vein", "main": "iron_ore", "name": "Ironvale Vein", "lat": 37.25, "lng": -122.28}
const QUARTZ := {"id": "wd-253-117", "type": "vein", "main": "quartz", "name": "Shrew Vein", "lat": 37.30, "lng": -122.19}
const QUARRY := {"id": "wd-255-116", "type": "quarry", "main": null, "name": "Badger Quarry", "lat": 37.79, "lng": -121.80}

func after_test() -> void:
	P0WildSites.clear()

func _view(level := 5, records := {}, extra := {}) -> Dictionary:
	var v := {"guide": {"step": null, "end": "done"}, "first_dig": {"done": true}, "homestead": {"level": level},
		"wild": {"near3": [IRON.id, QUARTZ.id, QUARRY.id], "near3_sites": [IRON, QUARTZ, QUARRY]},
		"mine": {"records": records}, "plots": [], "skills": {}}
	v.merge(extra, true)
	return v

func test_the_iron_vein_row_at_lv5_and_lv6_only() -> void:
	var row := P0Logic.vein_row(_view(5))
	assert_str(str(row.line)).is_equal("Ironvale Vein · Floor 0/10")
	assert_str(str(row.go)).is_equal("mine:wd-254-115")
	assert_str(str(row.icon)).is_equal("vein")
	assert_str(str(row.dot)).is_equal(P0Logic.PIP_DOT + "vein:wd-254-115")
	assert_str(str(P0Logic.vein_row(_view(6)).go)).is_equal("mine:wd-254-115")
	assert_dict(P0Logic.vein_row(_view(4))).is_empty()   # the next three (5, 6, 7) need no iron
	assert_dict(P0Logic.vein_row(_view(7))).is_empty()   # Lv7 on: the Homestead row says it (user a)

func test_none_during_the_guide_or_before_pips_first_dig() -> void:
	assert_dict(P0Logic.vein_row(_view(5, {}, {"guide": {"step": "t_gather"}}))).is_empty()
	assert_dict(P0Logic.vein_row(_view(5, {}, {"first_dig": {"done": false}}))).is_empty()
	assert_dict(P0Logic.vein_row(_view(5, {}, {"first_dig": null}))).is_empty()

func test_quartz_once_the_iron_vein_is_down_to_ten_and_none_when_both_are() -> void:
	var iron_done := {"wd-254-115": {"deepest": 10, "guards": []}}
	assert_str(str(P0Logic.vein_row(_view(5, iron_done)).line)).is_equal("Shrew Vein · Floor 0/10")
	var both := {"wd-254-115": {"deepest": 12}, "wd-253-117": {"deepest": 10}}
	assert_dict(P0Logic.vein_row(_view(6, both))).is_empty()
	assert_str(str(P0Logic.vein_row(_view(5, {"wd-254-115": {"deepest": 9}})).line)).is_equal("Ironvale Vein · Floor 9/10")   # its own record

func test_any_iron_vein_down_to_ten_ends_the_iron_row() -> void:
	# a vein the map has read (an old home's), not among the free three now
	P0WildSites.accept("t", {"sites": [{"id": "wd-200-100", "type": "vein", "lat": 10.0, "lng": 10.0, "mine": {"main": "iron_ore"}}]})
	assert_str(str(P0Logic.vein_row(_view(5, {"wd-200-100": {"deepest": 11}})).line)).is_equal("Shrew Vein · Floor 0/10")
	# a quarry down to ten ends nothing
	assert_str(str(P0Logic.vein_row(_view(5, {"wd-255-116": {"deepest": 30}})).line)).is_equal("Ironvale Vein · Floor 0/10")

func test_none_when_the_homestead_row_points_at_the_same_mine() -> void:
	var home := {"row": {"line": "Homestead Lv8 · Iron Ore 4 to go", "go": "mine:wd-254-115"}, "now": true}
	assert_dict(P0Logic.vein_row(_view(5), home)).is_empty()
	var other := {"row": {"line": "Homestead Lv6 · Timber 3 to go", "go": "gather:gn-5391959~wood0"}, "now": true}
	assert_str(str(P0Logic.vein_row(_view(5), other).go)).is_equal("mine:wd-254-115")

func test_in_today_it_is_pips_request_before_the_other_short_ones() -> void:
	var v := _view(5, {}, {"plots": [{"state": "ready", "crop": "crop_radish"}, {"state": "sown", "crop": "crop_radish"}],
		"residents": {"res_old_kai": {"request": {"id": "req_res_kai_2", "kind": "fish", "rarity": 3, "have": 0, "qty": 1,
			"ready": false, "accepted_at": 9000}, "request_state": "accepted"}}})
	var rows := P0Logic.today_rows(v)
	var lines: Array = rows.map(func(r): return str(r.line))
	assert_array(lines).is_equal(["Ironvale Vein · Floor 0/10", "Dusk Supper · Grilled dishes 0/1"])   # no Harvest / Water rows
	assert_str(str(rows[0].get("vein_request", ""))).is_equal("wd-254-115")
	assert_array(P0Logic.today_dots(rows)).contains([P0Logic.PIP_DOT + "vein:wd-254-115"])

## 周瑜 on #711: down that very mine the row stays without a button; #712: a record's own type / main says which vein it
## is, any mine the player has been down (a paid one, an old home's) — nothing else needed.
func test_down_that_mine_no_button_and_a_records_own_type_counts() -> void:
	var down := P0Logic.vein_row(_view(5, {}, {"mine": {"records": {}, "at": {"mine": "wd-254-115", "floor": 4}}}))
	assert_str(str(down.line)).is_equal("Ironvale Vein · Floor 0/10")
	assert_str(str(down.go)).is_equal("")
	assert_str(str(down.dot)).is_equal(P0Logic.PIP_DOT + "vein:wd-254-115")
	var elsewhere := P0Logic.vein_row(_view(5, {}, {"mine": {"records": {}, "at": {"mine": "wd-255-116", "floor": 2}}}))
	assert_str(str(elsewhere.go)).is_equal("mine:wd-254-115")
	var paid_vein := {"wd-180-90": {"deepest": 10, "type": "vein", "main": "iron_ore"}}
	assert_str(str(P0Logic.vein_row(_view(5, paid_vein)).line)).is_equal("Shrew Vein · Floor 0/10")
	var quarry := {"wd-180-91": {"deepest": 25, "type": "quarry", "main": null}}
	assert_str(str(P0Logic.vein_row(_view(5, quarry)).line)).is_equal("Ironvale Vein · Floor 0/10")
