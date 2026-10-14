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
	var b := P0Logic.level_banner(_view(), {"skill": "fishing", "level": 2, "energy": 0,
		"gifts": [["bait_worm", 3], ["wild_herb", 3], ["recipe:dish_herb_grilled_fish", 1]]}, true)
	# SKILL-3 (482:65)
	assert_that([b.title, b.subtitle, b.detail, b.tip, b.action, b.seconds]).is_equal(["Fishing Lv2",
		"Fine fish now stay on the hook", "New recipe: Herb Grilled Fish", P0Logic.LEVEL_TIP, "Use bait", 3.0])
	# q(101): skill level-ups give no Energy, the gift's items alone (no `+50 Energy`)
	assert_array(b.rewards.map(func(r): return r.text)).is_equal(["+3 Worm Bait", "+3 Wild Herb"])

## FARM-LV2 (1368:91797) with q(69): New for you · the crops, the gift as a pill, the next level on Tip.
func test_farming_lv2_reads_like_the_accepted_frame() -> void:
	var v := _view()
	v.skills.farming = {"level": 2, "xp": 50}
	var b := P0Logic.level_banner(v, {"skill": "farming", "level": 2, "energy": 0, "gifts": [["seed_carrot", 5]]})
	assert_that([b.title, b.subtitle, b.detail, b.tip, b.seconds]).is_equal(["Farming Lv2",
		"New for you · Carrot, Herb", "", "Next Lv3 · Potato, Chamomile, Compost · 100 XP", 1.5])
	assert_array(b.rewards.map(func(r): return r.text)).is_equal(["+5 Carrot Seeds"])   # q(101): no `+30 Energy`

func test_a_later_level_says_what_opened_and_what_is_next() -> void:
	var b := P0Logic.level_banner(_view(), {"skill": "farming", "level": 3, "energy": 0, "gifts": []})
	assert_that([b.title, b.subtitle, b.detail, b.tip, b.action, b.seconds]).is_equal(["Farming Lv3",
		"New for you · Potato, Chamomile, Compost", "", "Next Lv4 · Tomato, Chili, Row Hoe · 150 XP", "", 1.5])
	assert_bool(b.rewards.is_empty()).is_true()   # a level without a gift has no reward row (q(101))

## q(101) across versions: this client with a server from before it, which still pays the level-up Energy, says what was
## paid (the bar moved, never unsaid); with one after it (0, or no field at all) there is no Energy pill — never `+0`.
func test_the_energy_pill_shows_only_what_a_server_really_paid() -> void:
	var gifts := [["bait_worm", 3], ["wild_herb", 3]]
	var old := P0Logic.level_banner(_view(), {"skill": "fishing", "level": 2, "energy": 50, "gifts": gifts}, true)
	assert_array(old.rewards.map(func(r): return r.text)).is_equal(["+50 Energy", "+3 Worm Bait", "+3 Wild Herb"])
	for ev in [{"skill": "fishing", "level": 2, "energy": 0, "gifts": gifts}, {"skill": "fishing", "level": 2, "gifts": gifts}]:
		var b := P0Logic.level_banner(_view(), ev, true)
		assert_array(b.rewards.map(func(r): return r.text)).is_equal(["+3 Worm Bait", "+3 Wild Herb"])
		assert_bool(b.rewards.any(func(r): return str(r.text).contains("Energy"))).is_false()
	var later := P0Logic.level_banner(_view(), {"skill": "farming", "level": 3, "energy": 0, "gifts": []})
	assert_bool(later.rewards.any(func(r): return str(r.text).contains("Energy"))).is_false()

## On screen: a level without a gift shows the banner without its reward row (UiMomentBanner hides an empty one).
func test_a_banner_without_rewards_shows_no_reward_row() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.show_level_up({"skill": "farming", "level": 3, "energy": 0, "gifts": []})
	await await_idle_frame()
	var banners := ui.find_children("*", "UiMomentBanner", true, false)
	assert_int(banners.size()).is_equal(1)
	var b: UiMomentBanner = banners[0]
	assert_str(b.title).is_equal("Farming Lv3")
	assert_bool(b._rewards_box.visible).is_false()

func test_cooking_levels_name_their_slot_recipe_and_conveniences() -> void:
	var four := P0Logic.level_banner(_view(), {"skill": "cooking", "level": 4, "energy": 0, "gifts": []})
	assert_that([four.title, four.subtitle, four.seconds]).is_equal(["Cooking Lv4 · 3rd slot", "Three-ingredient dishes now possible", 1.5])
	assert_str(four.tip).is_equal("Today changes: 3-ingredient dishes")   # a level that changes the day (q(69))
	assert_bool(four.rewards.is_empty()).is_true()   # Cooking levels give no Energy (§3.4.8)
	var v := _view()
	v.skills.cooking = {"level": 2, "xp": 30}
	var two := P0Logic.level_banner(v, {"skill": "cooking", "level": 2, "energy": 0, "gifts": [["recipe:dish_fish_soup", 1]]})
	assert_that([two.title, two.subtitle, two.detail, two.tip]).is_equal(["Cooking Lv2", "New for you · Cook Again",
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
	ui.queue_card(func(): ui.show_level_up({"skill": "fishing", "level": 2, "energy": 0, "gifts": [["bait_worm", 3]]}, true))
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

## 李元芳 int7: the first level-up came while the fishing panel was up; its input shield (layer 30) took the tap on
## Use bait. A banner with a button waits until the world is back from "busy"; what queues behind it still comes.
func test_use_bait_waits_out_the_fishing_panel_and_then_works() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_mode("fish")
	ui.set_surface("busy")   # the fishing presentation
	ui.queue_card(func(): ui.show_level_up({"skill": "fishing", "level": 2, "energy": 0, "gifts": [["bait_worm", 3]]}, true))
	ui.queue_card(func(): ui.show_catch("fish_crucian", 1, 15))   # behind it in the queue
	await await_idle_frame()
	await await_idle_frame()
	assert_int(ui.find_children("*", "UiMomentBanner", true, false).size()).is_equal(0)   # held
	assert_str(ui.modal_kind).is_equal("card")   # the catch card did not wait behind it
	ui.close_modal()
	ui.set_surface("pond")   # the panel closed
	await await_idle_frame()
	var banners := ui.find_children("*", "UiMomentBanner", true, false)
	assert_int(banners.size()).is_equal(1)
	(banners[0] as UiMomentBanner).action_pressed.emit()
	assert_str(ui.selected_bait).is_equal("bait_worm")

func test_use_bait_away_from_the_water_puts_it_on_the_hook_for_the_next_cast() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_mode("farm")
	ui._banner_action("use_bait")
	assert_str(ui.selected_bait).is_equal("bait_worm")

## 李元芳 int7: `+5 XP` rose across the banner's `+3 Wild Herb`. While a moment is up, floats rise under its card.
func test_floats_rise_under_a_moment_card() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.show_level_up({"skill": "fishing", "level": 3, "energy": 0, "gifts": []})
	ui.float_text("+5 XP", Vector2(180, 200), UiFloatText.Tone.XP)
	var f: Node = ui.root.get_children().filter(func(c): return c is UiFloatText).back()
	assert_int(f.get_index()).is_less(ui._modal.get_index())

## The nine levels that change the day (q(176)): their Tip says so instead of the next level. The others still name the
## next one, the traps too (`Next Lv8 · 2nd Fish Trap, Biting now`, not a bare `Next Lv8 · 550 XP`; 286 e89ae800, q(178)).
func test_the_nine_day_changing_levels_say_so_and_the_trap_levels_are_named_ahead() -> void:
	var v := _view()
	var said := {}
	for key in ["farming:6", "farming:7", "farming:8", "fishing:4", "fishing:5", "fishing:6", "fishing:8", "fishing:9", "cooking:4"]:
		var parts: PackedStringArray = key.split(":")
		said[key] = P0Logic.level_banner(v, {"skill": parts[0], "level": int(parts[1]), "energy": 0, "gifts": []}).tip
	assert_dict(said).is_equal({"farming:6": "Today changes: no more watering", "farming:7": "Today changes: fruit every two days",
		"farming:8": "Today changes: grow any climate's crops", "fishing:4": "Today changes: River is your water now",
		"fishing:5": "Today changes: traps fish for you", "fishing:6": "Today changes: Coast is your water now",
		"fishing:8": "Today changes: two traps to check", "fishing:9": "Today changes: eels bite at night",
		"cooking:4": "Today changes: 3-ingredient dishes"})
	for t in said.values(): assert_int((t as String).length()).is_less_equal(39)   # q(176): fits the Tip line
	var th: Array = P0Logic.content().get("skills", {}).get("fishing", [])
	v.skills.fishing = {"level": 7, "xp": int(th[6])}
	assert_str(P0Logic.level_banner(v, {"skill": "fishing", "level": 7, "energy": 0, "gifts": []}).tip) \
		.is_equal("Next Lv8 · 2nd Fish Trap, Biting now · %d XP" % (int(th[7]) - int(th[6])))
	assert_str(P0Logic.level_banner(v, {"skill": "fishing", "level": 3, "energy": 0, "gifts": []}).tip).starts_with("Next Lv4 · ")

## q(178) ⑥: Fishing's banner subtitle is `New for you · ` and the level's milestone row, as Farming and Cooking — Lv9
## without the row's `(night)` (its Tip says it); Lv2, the first session's, keeps `Fine fish now stay on the hook`.
func test_fishing_banners_say_new_for_you_as_their_milestone_row() -> void:
	var v := _view()
	for f in P0Logic.content().get("fish", []): v.names[str(f.id)] = str(f.name)   # as the server's view names them
	var sub := func(lv: int) -> String: return str(P0Logic.level_banner(v, {"skill": "fishing", "level": lv, "energy": 0, "gifts": []}).subtitle)
	assert_str(sub.call(2)).is_equal("Fine fish now stay on the hook")
	assert_str(sub.call(3)).is_equal("New for you · Reed Rod, Regional fish, 3-day Forecast")
	assert_str(sub.call(7)).is_equal("New for you · Silver Sturgeon, Gift Clues")
	assert_str(sub.call(8)).is_equal("New for you · 2nd Fish Trap, Biting now")
	assert_str(sub.call(9)).is_equal("New for you · River Eel, Quick Recast")
	assert_str(sub.call(10)).is_equal("New for you · 3rd Fish Trap, Bigger Creel, Master Angler title")   # its title last (#398)
	assert_str(P0Logic.level_banner(v, {"skill": "farming", "level": 6, "energy": 0, "gifts": []}).subtitle).starts_with("New for you · ")
