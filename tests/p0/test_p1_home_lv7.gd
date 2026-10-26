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
	assert_array(lv7.unlocks).is_equal(["orchard_8", "sprinklers_10", "plots_48"])   # q(172): and 8 more plots, 40–47
	# the numbers the lines say: 1 + level trees and 3 + level sprinklers, at most 8 and 10 — reached at Lv7, not before
	assert_int(int(h.perennial_slots.base) + 7 * int(h.perennial_slots.per_level)).is_equal(int(h.perennial_slots.max))
	assert_int(int(h.perennial_slots.max)).is_equal(8)
	assert_int(int(h.sprinkler_max.base) + 7 * int(h.sprinkler_max.per_level)).is_equal(int(h.sprinkler_max.max))
	assert_int(int(h.sprinkler_max.max)).is_equal(10)

func test_home_1_and_the_banner_say_them() -> void:
	var p := P0Logic.home_panel(_view())
	assert_array(p.changes.map(func(c): return str(c.text))).is_equal(["Max Energy 260 · Meals 260 a day", "Orchard 8/8", "Sprinklers 10/10"])
	assert_array(p.changes.slice(1).map(func(c): return str(c.note))).is_equal(["+1 slot", "+1 sprinkler"])   # q(172)
	var m := P0Logic.home_moment(_view(), {"level": 7, "unlocks": ["orchard_8", "sprinklers_10"]})
	assert_str(str(m.detail)).is_equal("Orchard 8/8\nSprinklers 10/10")
	# and the 8 plots on the field's edge (q(172) ①), as Lv3's `Plots 40 · 10 more to till`
	var v := _view()
	v.homestead.next.unlocks = ["orchard_8", "sprinklers_10", "plots_48"]
	assert_str("%s · %s" % [P0Logic.home_panel(v).changes[-1].text, P0Logic.home_panel(v).changes[-1].note]).is_equal("Plots 48 · 8 more to till")
	assert_str(str(P0Logic.home_moment(v, {"level": 7, "unlocks": ["orchard_8", "sprinklers_10", "plots_48"]}).detail)).ends_with("Plots 48")

func test_the_cooking_page_names_every_level() -> void:
	var view := {}
	var by_level := {}
	for lv in [7, 8, 9, 10]: by_level[lv] = P0Logic.level_unlocks(view, "cooking", lv)
	# Lv8 is Batch Cook (q(200) ①; Bigger Provisions still waits for P2's Provisions, q(199)): `Lv8 · Batch Cook`,
	# Lv8's banner `New for you · Batch Cook`, Lv7's `Next Lv8 · Batch Cook · N XP`
	assert_dict(by_level).is_equal({7: ["Steady Hand II", "Fast Mastery"], 8: ["Batch Cook"],
		9: ["Chef's Touch"], 10: ["Lucky Double", "Chef title"]})
	var v := {"skills": {"cooking": {"level": 7, "xp": 1000}}}
	assert_str(str(P0Logic.level_banner(v, {"skill": "cooking", "level": 7}).tip)).is_equal("Next Lv8 · Batch Cook · 350\u00a0XP")
	var eight := P0Logic.level_banner({"skills": {"cooking": {"level": 8, "xp": 1400}}}, {"skill": "cooking", "level": 8})
	assert_that([eight.subtitle, eight.tip]).is_equal(["New for you · Batch Cook", "Next Lv9 · Chef's Touch · 300\u00a0XP"])
	var cook: Dictionary = P0SkillsDrawer.skills_data({"skills": {"cooking": {"level": 7, "xp": 1000}}}).tracks[2]
	assert_str(str(cook.next)).is_equal("Next: Batch Cook")
	assert_array(cook.milestones.map(func(m): return str(m.line))).contains(["Lv8 · Batch Cook"])
	for k in P0Logic.content().cooking.conveniences:   # never an id: every key in the content has its name (a title's in TITLE_NAMES)
		assert_bool(P0Logic.CONVENIENCE_NAMES.has(k) or P0Logic.TITLE_NAMES.has(k)).override_failure_message(k).is_true()
