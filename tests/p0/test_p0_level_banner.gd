extends GdUnitTestSuite
## Level-up MomentBanners (SGODOT-233; §4.8.3 / §4.8.6): the account's first teaches and offers Use bait (≤ 3 s), later
## levels say what opened and what is next (1.5 s), Cooking Lv4 changes the day; HOME-2 is the same banner; all of
## them queue with the other moments (q(49) ④).

const HomePanel = preload("res://scenes/p0/home/p0_home_panel.gd")
const STORE := "user://test_p0_level_banner.json"
const TIPS := "user://test_p0_level_banner_tips.json"

func _view() -> Dictionary:
	return {
		"energy": {"value": 150, "max": 200}, "coins": 40,
		"skills": {"farming": {"level": 3, "xp": 150}, "fishing": {"level": 2, "xp": 70}, "cooking": {"level": 4, "xp": 220}},
		"names": {"bait_worm": "Worm Bait", "wild_herb": "Wild Herb", "dish_herb_grilled_fish": "Herb Grilled Fish",
			"dish_fish_soup": "Fresh Fish Soup", "fert_compost": "Compost", "tool_row_hoe": "Row Hoe", "seed_carrot": "Carrot Seeds",
			"seed_herb": "Herb Seeds", "seed_potato": "Potato Seeds", "seed_chamomile": "Chamomile Seeds", "seed_tomato": "Tomato Seeds",
			"seed_chili": "Chili Seeds"},
		"stall": {"buy": [{"id": "seed_potato", "skill": "farming", "gate": 3}, {"id": "fert_compost", "skill": "farming", "gate": 3},
			{"id": "bait_worm", "skill": "fishing", "gate": 2}]},
		"bag": {"capacity": 25, "slots": [{"id": "bait_worm", "qty": 3}]},
	}

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func test_the_accounts_first_level_up_teaches() -> void:
	var b := P0Logic.level_banner(_view(), {"skill": "fishing", "level": 2, "energy": 50,
		"gifts": [["bait_worm", 3], ["wild_herb", 3], ["recipe:dish_herb_grilled_fish", 1]]}, true)
	# SKILL-3 (482:65)
	assert_that([b.title, b.subtitle, b.detail, b.tip, b.action, b.seconds]).is_equal(["Fishing Lv 2",
		"Fine fish now stay on the hook", "New recipe: Herb Grilled Fish", P0Logic.LEVEL_TIP, "Use bait", 3.0])
	assert_array(b.rewards.map(func(r): return r.text)).is_equal(["+50 Energy", "+3 Worm Bait", "+3 Wild Herb"])

## FARM-LV2 (1368:91797) with q(69): New for you · the crops, the gift as a pill, the next level on Tip.
func test_farming_lv2_reads_like_the_accepted_frame() -> void:
	var v := _view()
	v.skills.farming = {"level": 2, "xp": 50}
	var b := P0Logic.level_banner(v, {"skill": "farming", "level": 2, "energy": 30, "gifts": [["seed_carrot", 5]]})
	assert_that([b.title, b.subtitle, b.detail, b.tip, b.seconds]).is_equal(["Farming Lv 2",
		"New for you · Carrot, Herb", "", "Next Lv3 · Potato, Chamomile, Compost · 100 XP", 1.5])
	assert_array(b.rewards.map(func(r): return r.text)).is_equal(["+30 Energy", "+5 Carrot Seeds"])

func test_a_later_level_says_what_opened_and_what_is_next() -> void:
	var b := P0Logic.level_banner(_view(), {"skill": "farming", "level": 3, "energy": 30, "gifts": []})
	assert_that([b.title, b.subtitle, b.detail, b.tip, b.action, b.seconds]).is_equal(["Farming Lv 3",
		"New for you · Potato, Chamomile, Compost", "", "Next Lv4 · Tomato, Chili, Row Hoe · 150 XP", "", 1.5])

func test_cooking_levels_name_their_slot_recipe_and_conveniences() -> void:
	var four := P0Logic.level_banner(_view(), {"skill": "cooking", "level": 4, "energy": 0, "gifts": []})
	assert_that([four.title, four.subtitle, four.seconds]).is_equal(["Cooking Lv 4 · 3rd slot", "Three-ingredient dishes now possible", 1.5])
	assert_str(four.tip).is_equal("Today changes: 3-ingredient dishes")   # a level that changes the day (q(69))
	assert_bool(four.rewards.is_empty()).is_true()   # Cooking levels give no Energy (§3.4.8)
	var v := _view()
	v.skills.cooking = {"level": 2, "xp": 30}
	var two := P0Logic.level_banner(v, {"skill": "cooking", "level": 2, "energy": 0, "gifts": [["recipe:dish_fish_soup", 1]]})
	assert_that([two.title, two.subtitle, two.detail, two.tip]).is_equal(["Cooking Lv 2", "New for you · Cook Again",
		"New recipe: Fresh Fish Soup", "Next Lv3 · Double Clue, Hearty Mishap · 70 XP"])

func test_banners_queue_with_the_other_moments_and_use_bait_acts_in_place() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_mode("fish")
	ui.set_surface("pond")
	ui.queue_card(func(): ui.show_catch("fish_crucian", 1, 15))
	ui.queue_card(func(): ui.show_level_up({"skill": "fishing", "level": 2, "energy": 50, "gifts": [["bait_worm", 3]]}, true))
	await await_idle_frame()
	assert_int(ui.find_children("*", "UiMomentBanner", true, false).size()).is_equal(0)   # the catch card first
	ui.close_modal()
	await await_idle_frame()
	await await_idle_frame()
	var banners := ui.find_children("*", "UiMomentBanner", true, false)
	assert_int(banners.size()).is_equal(1)
	var b: UiMomentBanner = banners[0]
	assert_float(b.position.y).is_equal(float(UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H) + 10.0 + ui.safe_top())
	b.action_pressed.emit()   # Use bait: the banner closes, the bait goes on the hook, nothing travels
	assert_str(ui.modal_kind).is_equal("")
	assert_str(ui.selected_bait).is_equal("bait_worm")

func test_home_2_is_the_same_banner() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	var card: Control = HomePanel.moment(ui, P0Logic.home_moment({"energy": {"max": 220}}, {"kind": "homestead", "level": 3, "unlocks": ["warming_cabinet"]}))
	assert_bool(card is UiMomentBanner).is_true()
	assert_str(ui.modal_kind).is_equal("card")

## 李元芳 int7: in the farmhouse the Cooking Lv2 banner reached the bottom of the screen with its content in the top
## fifth — its wrapped tip was first measured at zero width. The banner is as tall as its content, under the HUD.
func test_a_banner_is_as_tall_as_its_content() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_surface("room")
	ui.show_level_up({"skill": "cooking", "level": 2, "energy": 0, "gifts": []}, true)
	for i in 3: await await_idle_frame()
	var b: UiMomentBanner = ui.find_children("*", "UiMomentBanner", true, false)[0]
	assert_float(b.size.y).is_equal_approx(b.get_combined_minimum_size().y, 0.5)
	assert_float(b.size.y).is_less(ui.root.size.y * 0.4)
