extends GdUnitTestSuite
## 传说鱼收线 (q(282), SGODOT-389; 用户「传奇鱼 AB»): A′ — fishing.json's Legendary tier eased to 0.22 / 0.47 / 20 / 0.13
## (only P0 reads the file now: the old farm server and Journey are retired, 周瑜 / 奕星), each value still harder than
## Rare's; B — a Spinner Lure slows a Rare or Legendary fish ×0.8. The rod's band and loss and the sure bite apply after
## both; Common, Fine and Rare unchanged.

const CARBON := {"band_bonus": 0.05, "loss_mult": 0.9}

func test_legendary_is_p0s_own_and_still_harder_than_rare() -> void:
	var legend := P0FishingPanel.reel_tier(4, {}, false)
	var rare := P0FishingPanel.reel_tier(3, {}, false)
	assert_array([float(legend.bar_size), float(legend.fish_speed), float(legend.turn_steps), float(legend.gain), float(legend.loss)]).is_equal([0.22, 0.47, 20.0, 0.12, 0.13])
	assert_float(float(legend.bar_size)).is_less(float(rare.bar_size))
	assert_float(float(legend.fish_speed)).is_greater(float(rare.fish_speed))
	assert_int(int(legend.turn_steps)).is_less(int(rare.turn_steps))
	assert_float(float(legend.loss)).is_greater(float(rare.loss))
	assert_float(float(FishingModel.data().tiers["4"].fish_speed)).is_equal(0.47)   # the table holds what P0 plays: one set of numbers
	var was := {1: [0.34, 0.2, 40.0, 0.08], 2: [0.29, 0.32, 30.0, 0.1], 3: [0.24, 0.44, 22.0, 0.12]}   # Common, Fine, Rare
	for r in was:
		var t := P0FishingPanel.reel_tier(r, {}, false)
		assert_array([float(t.bar_size), float(t.fish_speed), float(t.turn_steps), float(t.loss)]).override_failure_message(str(r)).is_equal(was[r])

func test_the_lure_slows_a_rare_or_legendary_fish_and_the_rod_still_applies() -> void:
	var lure := CARBON.merged({"cast": {"bait": "bait_lure"}})
	assert_float(float(P0FishingPanel.reel_tier(4, lure, false).fish_speed)).is_equal_approx(0.376, 0.0001)
	assert_float(float(P0FishingPanel.reel_tier(3, lure, false).fish_speed)).is_equal_approx(0.352, 0.0001)
	assert_float(float(P0FishingPanel.reel_tier(2, lure, false).fish_speed)).is_equal(0.32)   # Fine: as it was
	assert_float(float(P0FishingPanel.reel_tier(4, CARBON.merged({"cast": {"bait": "bait_worm"}}), false).fish_speed)).is_equal(0.47)
	var t := P0FishingPanel.reel_tier(4, lure, true)
	assert_float(float(t.bar_size)).is_equal_approx(0.27, 0.0001)   # Carbon +5 points over 0.22
	assert_float(float(t.loss)).is_equal_approx(0.117, 0.0001)      # Carbon −10 % of 0.13
	assert_bool(bool(t.sure)).is_true()
