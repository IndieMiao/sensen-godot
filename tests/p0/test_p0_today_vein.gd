extends GdUnitTestSuite
## v4q(9) ① (SGODOT-355 C2-d; 不知火舞, the user a + b 11-02): Today's `<vein> · Reach Floor 10` row — after the guide and
## Pip's First Dig, at Homestead Lv5 and Lv6, iron first then quartz, one at a time, gone at Floor 10 of any vein of that
## main, none when the Homestead row points at the same mine; after the other things to do now, before the Homestead
## material row, and q(143)'s tracked request never takes its place.

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
	assert_str(str(row.line)).is_equal("Ironvale Vein · Reach Floor 10")
	assert_str(str(row.go)).is_equal("mine:wd-254-115")
	assert_str(str(row.icon)).is_equal("vein")
	assert_str(str(row.dot)).is_equal("vein:wd-254-115")
	assert_str(str(P0Logic.vein_row(_view(6)).go)).is_equal("mine:wd-254-115")
	assert_dict(P0Logic.vein_row(_view(4))).is_empty()   # the next three (5, 6, 7) need no iron
	assert_dict(P0Logic.vein_row(_view(7))).is_empty()   # Lv7 on: the Homestead row says it (user a)

func test_none_during_the_guide_or_before_pips_first_dig() -> void:
	assert_dict(P0Logic.vein_row(_view(5, {}, {"guide": {"step": "t_gather"}}))).is_empty()
	assert_dict(P0Logic.vein_row(_view(5, {}, {"first_dig": {"done": false}}))).is_empty()
	assert_dict(P0Logic.vein_row(_view(5, {}, {"first_dig": null}))).is_empty()

func test_quartz_once_the_iron_vein_is_down_to_ten_and_none_when_both_are() -> void:
	var iron_done := {"wd-254-115": {"deepest": 10, "guards": []}}
	assert_str(str(P0Logic.vein_row(_view(5, iron_done)).line)).is_equal("Shrew Vein · Reach Floor 10")
	var both := {"wd-254-115": {"deepest": 12}, "wd-253-117": {"deepest": 10}}
	assert_dict(P0Logic.vein_row(_view(6, both))).is_empty()
	assert_str(str(P0Logic.vein_row(_view(5, {"wd-254-115": {"deepest": 9}})).line)).is_equal("Ironvale Vein · Reach Floor 10")

func test_any_iron_vein_down_to_ten_ends_the_iron_row() -> void:
	# a vein the map has read (an old home's), not among the free three now
	P0WildSites.accept("t", {"sites": [{"id": "wd-200-100", "type": "vein", "lat": 10.0, "lng": 10.0, "mine": {"main": "iron_ore"}}]})
	assert_str(str(P0Logic.vein_row(_view(5, {"wd-200-100": {"deepest": 11}})).line)).is_equal("Shrew Vein · Reach Floor 10")
	# a quarry down to ten ends nothing
	assert_str(str(P0Logic.vein_row(_view(5, {"wd-255-116": {"deepest": 30}})).line)).is_equal("Ironvale Vein · Reach Floor 10")

func test_none_when_the_homestead_row_points_at_the_same_mine() -> void:
	var home := {"row": {"line": "Homestead Lv8 · Iron Ore 4 to go", "go": "mine:wd-254-115"}, "now": true}
	assert_dict(P0Logic.vein_row(_view(5), home)).is_empty()
	var other := {"row": {"line": "Homestead Lv6 · Timber 3 to go", "go": "gather:gn-5391959~wood0"}, "now": true}
	assert_str(str(P0Logic.vein_row(_view(5), other).go)).is_equal("mine:wd-254-115")

func test_in_today_it_follows_the_things_to_do_now_and_keeps_its_place() -> void:
	var v := _view(5, {}, {"plots": [{"state": "ready", "crop": "crop_radish"}, {"state": "sown", "crop": "crop_radish"}]})
	var rows := P0Logic.today_rows(v)
	var lines: Array = rows.map(func(r): return str(r.line))
	assert_bool(lines.has("Ironvale Vein · Reach Floor 10")).is_true()
	assert_int(lines.find("Ironvale Vein · Reach Floor 10")).is_greater(lines.find(lines.filter(func(l): return l.begins_with("Harvest"))[0]))
	assert_array(P0Logic.today_dots(rows)).contains(["vein:wd-254-115"])
