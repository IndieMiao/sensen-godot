extends GdUnitTestSuite
## SKILL-1 (SGODOT-233; 482:167, §4.8.4 / §4.8.7): a row a track — Level, the next new things, the XP NeedTile —
## milestones unfolding in place (reached ✓, the next one `N XP to go`, the rest locked), First times n/8 · n/7 · n/14.

const STORE := "user://test_p0_skills.json"
const TIPS := "user://test_p0_skills_tips.json"

func _view() -> Dictionary:
	return {"energy": {"value": 150, "max": 200}, "coins": 40,
		"skills": {"farming": {"level": 2, "xp": 60}, "fishing": {"level": 1, "xp": 20}, "cooking": {"level": 3, "xp": 120}},
		"names": {"fert_compost": "Compost", "tool_row_hoe": "Row Hoe", "bait_worm": "Worm Bait", "fish_perch": "River Perch",
			"fish_bass": "Largemouth Bass", "fish_trout": "Rainbow Trout", "fish_koi": "Golden Koi", "fish_catfish": "Catfish",
			"fish_sturgeon": "Silver Sturgeon", "fish_eel": "River Eel", "fish_mackerel": "Mackerel", "fish_seabass": "Sea Bass",
			"rod_carbon": "Carbon Rod", "bait_lure": "Spinner Lure", "trap_fish": "Fish Trap"},
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
	# P1 (李白 on #214, §5.2.3 / §4.5): the regional crops are one item at Lv5, `Regional seeds`; perennials go by their
	# sapling (`Apple Sapling`, `Grapevine Cutting`).
	assert_array(farming.milestones.map(func(m): return [m.line, m.mark, m.fact])).is_equal([
		["Lv2 · Carrot, Herb", "done", ""], ["Lv3 · Potato, Chamomile, Compost", "next", "90 XP to go"],
		["Lv4 · Tomato, Chili, Row Hoe", "locked", ""], ["Lv5 · Cabbage, Corn, Regional seeds", "locked", ""],
		["Lv6 · Cucumber, Sprinkler", "locked", ""], ["Lv7 · Apple Sapling, Compost Bin", "locked", ""], ["Lv8 · Strawberry, Greenhouse", "locked", ""],
		["Lv9 · Melon, Citrus Sapling, Grapevine Cutting, Harvest All", "locked", ""], ["Lv10 · Seed Saver", "locked", ""]])
	var fishing: Dictionary = d.tracks[1]
	assert_str(fishing.next).is_equal("Next: River Perch, Largemouth Bass, Rainbow Trout, Mackerel and Worm Bait")
	# This season's waters only — Coast from P1 (Clover Pond, SGODOT-283), so Mackerel and Sea Bass are in; the regional
	# fish as one item at Lv3, after the gear (李白 on #214, §14 `Next Lv3 · Reed Rod, Regional fish`); the Carbon Rod
	# and the Spinner Lure where they open (§6.4).
	assert_array(fishing.milestones.map(func(m): return m.line)).is_equal([
		"Lv2 · River Perch, Largemouth Bass, Rainbow Trout, Mackerel, Worm Bait", "Lv3 · Reed Rod, Regional fish, 3-day Forecast",
		"Lv4 · Golden Koi, Catfish", "Lv5 · Sea Bass, Spinner Lure, Fish Trap", "Lv6 · Carbon Rod", "Lv7 · Silver Sturgeon, Gift Clues",
		"Lv8 · 2nd Fish Trap, Biting now", "Lv9 · River Eel (night)", "Lv10 · 3rd Fish Trap"])   # q(178): the traps Lv8 and Lv10 add, the conveniences
	assert_str(d.tracks[2].next).is_equal("Next: third ingredient slot")
	var v := _view()
	v.skills.farming = {"level": 4, "xp": 412}
	assert_str(P0SkillsDrawer.skills_data(v).tracks[0].next).is_equal("Next: Cabbage, Corn and Regional seeds")
	v.skills.farming = {"level": 9, "xp": 2100}   # Lv10 brings Seed Saver (content farming.conveniences, §4.6.1)
	assert_str(P0SkillsDrawer.skills_data(v).tracks[0].next).is_equal("Next: Seed Saver")

func test_first_times_count_this_seasons_things() -> void:
	var d := P0SkillsDrawer.skills_data(_view())
	var rows: Array = d.firsts.map(func(f): return [f.name, f.have, f.need])
	assert_array(rows.map(func(r): return r[0])).is_equal(["Crops", "Fish", "Dishes"])
	# Crops first-harvested n/20: the whole table, regional and perennial ones too (李白 on #214, §4.8 / SKILL-1)
	assert_array(rows[0]).is_equal(["Crops", 2, P0Logic.content().get("crops", []).size()])
	assert_int(rows[0][2]).is_equal(20)
	# Fish first-caught n/20: the whole table (李白 on #214, §4.8 / SKILL-1), Coast's Mackerel counts once caught
	assert_array(rows[1]).is_equal(["Fish", 2, P0Logic.content().get("fish", []).size()])
	assert_int(rows[1][2]).is_equal(20)
	assert_array(rows[2]).is_equal(["Dishes", 1, 2])

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

func _ui_with_view(v: Dictionary) -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(v)
	ui.set_surface("farm")
	return ui

## int11 (不知火舞 on 225): Close on what the profile opened closes that layer only, back to the profile, as the system
## Back does; opened from the world, Close goes to the world.
func test_close_on_what_the_profile_opened_comes_back_to_the_profile() -> void:
	var ui: P0Ui = await _ui_with_view(_view())
	ui.open_profile()
	await await_idle_frame()
	ui._profile.skill_pressed.emit("farming")
	await await_idle_frame()
	(ui.find_children("*", "P0SkillsDrawer", true, false)[0] as P0SkillsDrawer).close_pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("profile")
	ui._profile.collection_pressed.emit("fish")
	await await_idle_frame()
	(ui.find_children("*", "P0FishDex", true, false)[0] as P0FishDex).close_pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("profile")
	ui.close_modal()   # the profile's own ‹: the world
	await await_idle_frame()
	ui.open_skills()   # from the world …
	await await_idle_frame()
	(ui.find_children("*", "P0SkillsDrawer", true, false)[0] as P0SkillsDrawer).close_pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("")   # … Close goes to the world
	assert_bool(ui.has_modal()).is_false()

## int11: the profile's farm card has a › and opens HOME-1 over the profile; its Close comes back to the profile. Away
## from the homestead the upgrade is greyed with HOME-1's own away wording.
func test_the_farm_card_opens_home_1_over_the_profile() -> void:
	var v := _view()
	v["homestead"] = {"level": 1, "next": {"level": 2, "coins": {"need": 100, "have": 200}, "skills": {"need": 3, "have": 6},
		"materials": [], "energy": 220, "meals": 220, "unlocks": [], "can_upgrade": true}}
	var ui: P0Ui = await _ui_with_view(v)
	ui.open_profile()
	await await_idle_frame()
	var page := ui._profile
	var card := page.find_children("*", "UiFarmCard", true, false)[0] as UiFarmCard
	assert_bool(card.chevron).is_true()
	card.pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("homestead")
	assert_object(ui._modal.get_child(0)).is_same(page)   # over the profile
	var button := ui._modal.find_children("*", "UiCommandButton", true, false)[0] as UiCommandButton
	assert_str(button.reason).is_equal("")   # at home: as HOME-1 says from the farm
	(ui._modal.find_children("*", "UiDismissButton", true, false)[0] as UiDismissButton).pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("profile")
	ui.space = "outpost"   # away from home
	ui._profile.farm_pressed.emit()
	await await_idle_frame()
	button = ui._modal.find_children("*", "UiCommandButton", true, false)[0] as UiCommandButton
	assert_str(button.reason).is_equal(str(P0Logic.home_panel(ui.view, false).reason))   # HOME-1's own away wording (苏烈 #146)
	assert_str(button.reason).is_not_empty()
	ui.close_modal()
	await await_idle_frame()

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
