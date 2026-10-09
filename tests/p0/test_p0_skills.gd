extends GdUnitTestSuite
## SKILL-1 (SGODOT-233; 482:167, §4.8.4 / §4.8.7): a row a track — Level, the next new things, the XP NeedTile —
## milestones unfolding in place (reached ✓, the next one `N XP to go`, the rest locked), First times n/8 · n/7 · n/14.

const STORE := "user://test_p0_skills.json"
const TIPS := "user://test_p0_skills_tips.json"

func _view() -> Dictionary:
	return {"energy": {"value": 150, "max": 200}, "coins": 40,
		"skills": {"farming": {"level": 2, "xp": 60}, "fishing": {"level": 1, "xp": 20}, "cooking": {"level": 3, "xp": 120}},
		"names": {"fert_compost": "Compost", "tool_row_hoe": "Row Hoe", "bait_worm": "Worm Bait", "fish_perch": "River Perch",
			"fish_bass": "Largemouth Bass", "fish_trout": "Rainbow Trout", "fish_koi": "Golden Koi"},
		"stall": {"buy": [{"id": "fert_compost", "skill": "farming", "gate": 3}, {"id": "bait_worm", "skill": "fishing", "gate": 2}]},
		"firsts": ["harvest:crop_radish", "harvest:crop_carrot", "catch:fish_crucian"],
		"fishing": {"dex": [{"id": "fish_crucian", "caught": 3}, {"id": "fish_mackerel", "caught": 1}]},
		"cooking": {"cookbook": [{"p0": true, "cooked": true}, {"p0": true, "cooked": false}, {"p0": false, "cooked": false}]},
		"bag": {"capacity": 25, "slots": []}}

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func test_each_track_says_its_level_what_is_next_and_its_xp() -> void:
	var d := P0SkillsDrawer.skills_data(_view())
	var farming: Dictionary = d.tracks[0]
	assert_that([farming.name, farming.level, farming.next, farming.xp, farming.need]).is_equal(
		["Farming", 2, "Next: Potato, Chamomile and Compost", 60, 150])
	assert_array(farming.milestones.map(func(m): return [m.line, m.mark, m.fact])).is_equal([
		["Lv2 · Carrot, Herb", "done", ""], ["Lv3 · Potato, Chamomile, Compost", "next", "90 XP to go"],
		["Lv4 · Tomato, Chili, Row Hoe", "locked", ""]])
	var fishing: Dictionary = d.tracks[1]
	assert_str(fishing.next).is_equal("Next: River Perch, Largemouth Bass, Rainbow Trout and Worm Bait")   # no coast fish in P0
	assert_array(fishing.milestones.map(func(m): return m.line)).is_equal([
		"Lv2 · River Perch, Largemouth Bass, Rainbow Trout, Worm Bait", "Lv3 · Reed Rod", "Lv4 · Golden Koi"])
	assert_str(d.tracks[2].next).is_equal("Next: third ingredient slot")
	var v := _view()
	v.skills.farming = {"level": 4, "xp": 412}   # nothing after Lv4 in this build's content
	assert_str(P0SkillsDrawer.skills_data(v).tracks[0].next).is_equal("Next: Lv5 · 88 XP to go")

func test_first_times_count_this_seasons_things() -> void:
	var d := P0SkillsDrawer.skills_data(_view())
	assert_array(d.firsts.map(func(f): return [f.name, f.have, f.need])).is_equal([["Crops", 2, 8], ["Fish", 1, 7], ["Dishes", 1, 2]])

## int10c 256 ⑧: what the profile opens sits over the profile, not the world: the same page moves under its scrim.
func test_what_the_profile_opens_keeps_the_profile_behind_it() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.open_profile()
	await await_idle_frame()
	var page := ui._profile
	page.skill_pressed.emit("farming")
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("skills")
	assert_object(ui._modal.get_child(0)).is_same(page)   # the same page, under the drawer's scrim
	assert_bool(page.is_visible_in_tree()).is_true()
	assert_int(ui._modal.find_children("*", "P0ProfilePage", true, false).size()).is_equal(1)
	ui.close_top_layer()   # Back: the profile itself again
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("profile")
	ui._profile.skill_pressed.emit("cooking")
	await await_idle_frame()
	ui.close_modal()   # the drawer's ✕: out to the world …
	await await_idle_frame()
	ui.open_skills()   # … so what opens from the world next has the world behind it
	await await_idle_frame()
	assert_int(ui._modal.find_children("*", "P0ProfilePage", true, false).size()).is_equal(0)

func test_milestones_unfold_in_place_and_the_drawer_comes_back_to_the_profile() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.open_profile()
	await await_idle_frame()
	ui._profile.skill_pressed.emit("farming")
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("skills")
	var d: P0SkillsDrawer = ui.find_children("*", "P0SkillsDrawer", true, false)[0]
	assert_bool(d.milestones.farming.visible).is_false()
	d.toggles.farming.pressed.emit()
	assert_bool(d.milestones.farming.visible).is_true()
	assert_str(d.toggles.farming.label).is_equal("Hide milestones")
	ui.close_top_layer()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("profile")
