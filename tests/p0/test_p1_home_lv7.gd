extends GdUnitTestSuite
## Homestead Lv7 says what it brings (P1 exit C18; 李白 q(172)): the orchard and the sprinklers reach their most there —
## §8.6.2's `Orchard 8/8` and `Sprinklers 10/10` on HOME-1's What changes and on the level-up banner. And the Cooking
## skill page names Lv7–10's conveniences and title instead of their ids (李元芳 on 286).

func _view() -> Dictionary:
	var next := {"level": 7, "coins": {"need": 1490, "have": 2000}, "skills": {"need": 13, "have": 20}, "materials": [],
		"energy": 260, "meals": 260, "unlocks": ["orchard_8", "sprinklers_10"], "can_upgrade": true, "block": null}
	return {"energy": {"value": 142, "max": 250}, "bag": {"capacity": 25}, "skills": {"farming": {"level": 7}},
		"homestead": {"level": 6, "next": next, "unlocks": {"board_slots": 3}}}

func test_lv7_is_where_the_orchard_and_the_sprinklers_reach_their_most() -> void:
	var h: Dictionary = P0Logic.content().homestead
	var lv7: Dictionary = (h.levels as Array).filter(func(l): return int(l.level) == 7)[0]
	assert_array(lv7.unlocks).is_equal(["orchard_8", "sprinklers_10"])
	# the numbers the lines say: 1 + level trees and 3 + level sprinklers, at most 8 and 10 — reached at Lv7, not before
	assert_int(int(h.perennial_slots.base) + 7 * int(h.perennial_slots.per_level)).is_equal(int(h.perennial_slots.max))
	assert_int(int(h.perennial_slots.max)).is_equal(8)
	assert_int(int(h.sprinkler_max.base) + 7 * int(h.sprinkler_max.per_level)).is_equal(int(h.sprinkler_max.max))
	assert_int(int(h.sprinkler_max.max)).is_equal(10)

func test_home_1_and_the_banner_say_them() -> void:
	var p := P0Logic.home_panel(_view())
	assert_array(p.changes.map(func(c): return str(c.text))).is_equal(["Max Energy 260 · Meals 260 a day", "Orchard 8/8", "Sprinklers 10/10"])
	var m := P0Logic.home_moment(_view(), {"level": 7, "unlocks": ["orchard_8", "sprinklers_10"]})
	assert_str(str(m.detail)).is_equal("Orchard 8/8\nSprinklers 10/10")

func test_the_cooking_page_names_every_level() -> void:
	var view := {}
	var by_level := {}
	for lv in [7, 8, 9, 10]: by_level[lv] = P0Logic.level_unlocks(view, "cooking", lv)
	assert_dict(by_level).is_equal({7: ["Steady Hand II", "Fast Mastery"], 8: ["Cook All", "Bigger Provisions"],
		9: ["Chef's Touch"], 10: ["Lucky Double", "Chef title"]})
	for k in P0Logic.content().cooking.conveniences:   # never an id: every key in the content has its name
		assert_bool(P0Logic.CONVENIENCE_NAMES.has(k)).override_failure_message(k).is_true()
