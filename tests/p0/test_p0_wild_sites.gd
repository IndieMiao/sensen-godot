extends GdUnitTestSuite
## SGODOT-355 C (contract v0.1): the wild sites the map reads by viewport — kept by id, a box read once, nothing below
## zoom 6, a box across the 180° line, the server's answer taken as it is; and the local stand-in that answers from
## 后裔's wild_mock.json until the route is there (only open types, the nearest three free with a quarry and a vein).

const P0WildSites := preload("res://modules/p0/p0_wild_sites.gd")
const MOCK := "res://tests/p0/fixtures/wild_mock.json"
const SF_FARM := Vector2(37.7749, -122.4194)
const SF_BOX := [37.0, -123.5, 38.5, -121.5]

## A session stand-in: the wire the module asks on, and what it asked.
class FakeSession extends Node:
	var asked: Array = []
	var transport := func(_m: int, path: String, _b: Dictionary, cmd: Dictionary) -> void: asked.append([path, cmd])
	var view := {"travel": {"home": "gn-5391959", "farm_at": [37.7749, -122.4194]}}

var _session: FakeSession

func before_test() -> void:
	P0WildSites.clear()
	P0WildSites.mock = ""
	_session = auto_free(FakeSession.new())

func after_test() -> void:
	P0WildSites.clear()
	P0WildSites.mock = ""

func _catalog() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(MOCK)).sites

func test_ids_say_wild_by_their_prefix() -> void:
	assert_bool(P0WildSites.is_wild("wd-254-114")).is_true()
	assert_bool(P0WildSites.is_wild("gn-5391959")).is_false()
	assert_bool(P0WildSites.is_wild("gn-5391959~wood0")).is_false()

func test_below_zoom_six_nothing_is_asked() -> void:
	var got := []
	P0WildSites.fetch(_session, SF_BOX, 5.5, func(sites): got.append(sites))
	assert_array(got).is_equal([[]])
	assert_array(_session.asked).is_empty()

func test_a_box_is_asked_once_and_its_answer_kept_by_id() -> void:
	var got := []
	P0WildSites.fetch(_session, SF_BOX, 9.0, func(sites): got.append(sites.map(func(s): return s.id)))
	assert_int(_session.asked.size()).is_equal(1)
	assert_str(str(_session.asked[0][0])).starts_with("/p0/wild?bbox=37.0000,-123.5000,38.5000,-121.5000&zoom=9")
	# a second ask while the first is out waits for it, never asks again
	P0WildSites.fetch(_session, SF_BOX, 9.4, func(sites): got.append(sites.map(func(s): return s.id)))
	assert_int(_session.asked.size()).is_equal(1)
	var key: String = _session.asked[0][1].key
	P0WildSites.accept(key, {"sites": [{"id": "wd-255-114", "lat": 37.63, "lng": -122.83, "name": "Flint Quarry",
		"short": "Flint", "type": "quarry", "open": true, "free": true}, {"id": "gn-1~x", "lat": 37.7, "lng": -122.4}],
		"capped": false, "total": 1})
	assert_array(got).is_equal([["wd-255-114"], ["wd-255-114"]])   # both told; a non-wild id is not kept
	assert_bool(P0WildSites.has_site("wd-255-114")).is_true()
	assert_str(str(P0WildSites.site("wd-255-114").short)).is_equal("Flint")
	# read once: the same box at the same zoom asks nothing more
	P0WildSites.fetch(_session, SF_BOX, 9.0, func(sites): got.append(sites.size()))
	assert_int(_session.asked.size()).is_equal(1)
	assert_int(got.back()).is_equal(1)

func test_a_failed_read_tells_who_asked_and_reads_again_next_time() -> void:
	var failed := []
	P0WildSites.fetch(_session, SF_BOX, 9.0, Callable(), func(): failed.append(true))
	P0WildSites.fail(str(_session.asked[0][1].key))
	assert_array(failed).is_equal([true])
	P0WildSites.fetch(_session, SF_BOX, 9.0)
	assert_int(_session.asked.size()).is_equal(2)

func test_a_box_across_the_date_line() -> void:
	P0WildSites.accept("k", {"sites": [{"id": "wd-1-1", "lat": -17.0, "lng": 179.5}, {"id": "wd-1-2", "lat": -17.0, "lng": -179.5},
		{"id": "wd-1-3", "lat": -17.0, "lng": 170.0}]})
	var ids := P0WildSites.in_box([-18.0, 179.0, -16.0, -179.0]).map(func(s): return s.id)
	assert_array(ids).contains_exactly_in_any_order(["wd-1-1", "wd-1-2"])

func test_the_view_s_here_wins_over_a_box_read() -> void:
	P0WildSites.accept("k", {"sites": [{"id": "wd-255-114", "lat": 37.63, "lng": -122.83, "best_floor": 0}]})
	P0WildSites.remember({"wild": {"here": {"id": "wd-255-114", "lat": 37.63, "lng": -122.83, "best_floor": 7}}})
	assert_int(int(P0WildSites.site("wd-255-114").best_floor)).is_equal(7)

func test_the_stand_in_frees_the_nearest_three_with_a_quarry_and_a_vein_and_only_open_types() -> void:
	var answer := P0WildSites.mock_answer(_catalog(), [-90.0, -180.0, 90.0, 180.0], SF_FARM)
	var sites: Array = answer.sites
	assert_int(sites.size()).is_equal(P0WildSites.CAP)
	assert_bool(answer.capped).is_true()
	assert_bool(sites.all(func(s): return bool(s.open))).is_true()
	var free := sites.filter(func(s): return bool(s.free))
	assert_int(free.size()).is_equal(3)
	assert_bool(free.any(func(s): return str(s.type) == "quarry")).is_true()
	assert_bool(free.any(func(s): return str(s.type) == "vein")).is_true()
	assert_bool(sites.slice(0, 3).all(func(s): return bool(s.free))).is_true()   # the free three first
	for i in range(4, sites.size()): assert_bool(float(sites[i - 1].km) <= float(sites[i].km)).is_true()   # then nearer first
	assert_float(float(free[0].km)).is_less(100.0)

func test_the_stand_in_answers_a_fetch_from_the_file() -> void:
	P0WildSites.mock = MOCK
	var got := []
	P0WildSites.fetch(_session, SF_BOX, 9.0, func(sites): got.append(sites))
	assert_array(_session.asked).is_empty()   # never the wire
	await get_tree().process_frame
	assert_int(got.size()).is_equal(1)
	assert_bool((got[0] as Array).size() > 0).is_true()
	assert_bool((got[0] as Array).all(func(s): return float(s.lat) >= 37.0 and float(s.lat) <= 38.5)).is_true()
