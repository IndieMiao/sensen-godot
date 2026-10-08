extends GdUnitTestSuite
## P0 M2 client rules: Cast states, creel line, eating button, known-page match, heat preview.

func _view() -> Dictionary:
	return {
		"energy": {"value": 150, "max": 200, "next_in": 120000, "regen_ms": 240000},
		"bag": {"capacity": 25, "free": 21, "slots": [{"id": "fish_crucian", "qty": 3}, {"id": "fish_carp", "qty": 1}, {"id": "crop_herb", "qty": 2}, {"id": "bait_worm", "qty": 3}]},
		"fishing": {"cast_energy": 5, "cast": null, "protection_left": 9},
		"meals": {"used": 60, "cap": 200, "resets_in": 3600000, "eaten": {}},
		"names": {"fish_crucian": "Pond Crucian", "fish_carp": "Common Carp", "crop_herb": "Herb", "dish_grilled_crucian": "Grilled Crucian"},
		"items": {
			"fish_crucian": {"name": "Pond Crucian", "kind": "fish", "family": "W", "rarity": 1, "cook": true},
			"fish_carp": {"name": "Common Carp", "kind": "fish", "family": "W", "rarity": 1, "cook": true},
			"crop_herb": {"name": "Herb", "kind": "crop", "family": "S", "rarity": 1, "cook": true},
			"dish_grilled_crucian": {"name": "Grilled Crucian", "kind": "dish", "quality": 0, "rarity": 1, "meal": 20, "full": 20},
			"dish_grilled_crucian@good": {"name": "Grilled Crucian", "kind": "dish", "quality": 1, "rarity": 1, "meal": 10, "full": 25},
		},
		"cooking": {"cookbook": [
			{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "rarity": 1, "in": ["fish_crucian"], "known": true},
			{"id": "dish_grilled_fish", "name": "Grilled Fish", "rarity": 1, "in": ["W1"], "known": true},
			{"id": "dish_herb_grilled_fish", "name": null, "rarity": 2, "in": ["?", "?"], "known": false},
		]},
	}

func test_cast_states_follow_creel_energy_and_line() -> void:
	var v := _view()
	var a := P0Logic.fish_action(v, "bait_worm")
	assert_str(str(a.verb)).is_equal("Cast")
	assert_str(str(a.sub)).is_equal("5 Energy")
	assert_that(a.cmd).is_equal({"type": "cast", "bait": "bait_worm", "site": "pond"})
	assert_str(str(P0Logic.fish_action(v, "", "river").cmd.site)).is_equal("river")
	v.energy.value = 4
	assert_that(P0Logic.fish_action(v, "").cmd).is_equal({"type": "energy_card"})
	v.bag.free = 0
	assert_str(str(P0Logic.fish_action(v, "").sub)).is_equal("Creel full")
	v.fishing.cast = {"rarity": 1, "bite_in": 1000}
	assert_bool(bool(P0Logic.fish_action(v, "").enabled)).is_false()

func test_creel_and_protection_lines() -> void:
	var v := _view()
	assert_str(P0Logic.creel_line(v)).is_equal("Creel 4 · 21 free")
	assert_str(P0Logic.protection_line(v)).is_equal("Catch protection 9 left today")
	v.fishing.protection_left = null
	assert_str(P0Logic.protection_line(v)).is_equal("")

func test_eat_button_says_the_real_gain() -> void:
	var v := _view()
	assert_str(str(P0Logic.eat_button(v, "dish_grilled_crucian").text)).is_equal("Eat · +20 Energy")
	assert_str(str(P0Logic.eat_button(v, "dish_grilled_crucian@good").text)).is_equal("Same dish again · +10 (half)")
	v.energy.value = 195
	assert_str(str(P0Logic.eat_button(v, "dish_grilled_crucian").confirm)).is_equal("Only +5 of 20 · Eat anyway?")
	v.energy.value = 200
	var full := P0Logic.eat_button(v, "dish_grilled_crucian")
	assert_bool(bool(full.enabled)).is_false()
	assert_str(str(full.text)).is_equal("Energy full · eat later")
	v.energy.value = 100
	v.meals.used = 200
	assert_str(str(P0Logic.eat_button(v, "dish_grilled_crucian").text)).starts_with("Full belly")

func test_known_pages_match_specific_before_tags_and_never_reveal_unknown() -> void:
	var v := _view()
	assert_str(str(P0Logic.match_known(v, ["fish_crucian"]).get("id", ""))).is_equal("dish_grilled_crucian")
	assert_str(str(P0Logic.match_known(v, ["fish_carp"]).get("id", ""))).is_equal("dish_grilled_fish")
	assert_bool(P0Logic.match_known(v, ["fish_crucian", "crop_herb"]).is_empty()).is_true()

func test_heat_preview_matches_the_server_window() -> void:
	var h := {"at": 2500, "spin": 1600, "gold": 0.5, "width": 0.35}
	assert_bool(P0Logic.heat_hit(h, 2500 + 0.675 * 1600)).is_true()
	assert_bool(P0Logic.heat_hit(h, 2500 + 0.5 * 1600 - 140)).is_true()
	assert_bool(P0Logic.heat_hit(h, 2500 + 0.5 * 1600 - 200)).is_false()

func test_quick_bar_holds_bait_at_the_pond() -> void:
	var v := _view()
	assert_that(P0Logic.quick_bar(v, [], "fish")).is_equal(["bait_worm"])
	assert_that(P0Logic.quick_bar(v, [], "farm")).is_equal([])

func test_ingredient_tags_read_as_words() -> void:
	var v := _view()
	assert_str(P0Logic.ingredient_label(v, "W1")).is_equal("Any Common fish")
	assert_str(P0Logic.ingredient_label(v, "S1")).is_equal("Any seasoning")
	assert_str(P0Logic.ingredient_label(v, "fish_crucian")).is_equal("Pond Crucian")

func test_reward_and_blessing_lines() -> void:
	assert_str(P0Logic.reward_line("first_fish_2", 20)).is_equal("First Fine fish! +20 Energy")
	assert_str(P0Logic.reward_line("first_dish_3", 30)).is_equal("First Rare dish! +30 Energy")
	assert_str(P0Logic.reward_line("cookbook_8", 50)).is_equal("Home Cook · 8 recipes · +50 Energy")
	var v := _view()
	assert_str(P0Logic.blessing_line(v)).is_equal("")
	v["blessing"] = {"left": 5 * 86400000 - 1000}
	v.meals.cap = 300
	assert_str(P0Logic.blessing_line(v)).is_equal("Newcomer Blessing · 5 days left · faster Energy, Meals 300")

func test_creel_full_key_carries_the_fish4_reason_and_pills() -> void:
	var v := _view()
	v.bag.free = 0
	var a := P0Logic.fish_action(v, "")
	assert_bool(bool(a.enabled)).is_false()
	assert_str(str(a.verb)).is_equal("Cast")
	assert_str(str(a.sub)).is_equal("Creel full")   # plan §10.2.2; the long reason is the creel badge's and the toast's
	assert_bool(bool(a.get("creel_full", false))).is_true()
	assert_bool(P0Logic.fish_action(_view(), "").has("creel_full")).is_false()

func test_bait_at_zero_casts_without_bait() -> void:
	# Bait is optional (不知火舞 on PR #12): a pinned bait at 0 leaves Cast as it is and goes without bait.
	var v := _view()
	v.bag.slots = v.bag.slots.filter(func(s): return s.id != "bait_worm")   # pinned at 0 on the bar, none in the bag
	var a := P0Logic.fish_action(v, "bait_worm")
	assert_bool(bool(a.enabled)).is_true()
	assert_str(str(a.sub)).is_equal("5 Energy")
	assert_that(a.cmd).is_equal({"type": "cast", "bait": null, "site": "pond"})

func test_got_away_lines_for_level_and_rod_gates() -> void:
	# Thresholds come from the bundled content (Fishing: 0, 70, 220, 480 …); Common catches give 5 XP.
	var v := _view()
	v["skills"] = {"fishing": {"level": 1, "xp": 40, "floor": 0, "next": 70}}
	assert_str(P0Logic.level_gate_line(v, 2)).is_equal("Fishing Lv2 · 30 XP to go")
	assert_str(P0Logic.level_gate_line(v, 4)).is_equal("Fishing Lv4 needed · about 88 casts")
	v.fishing["dex"] = [
		{"id": "fish_perch", "rarity": 2, "level": 2, "where": ["river", "pond"]},
		{"id": "fish_bass", "rarity": 2, "level": 2, "where": ["pond", "river"]},
		{"id": "fish_mackerel", "rarity": 2, "level": 2, "where": ["coast"]},
		{"id": "fish_koi", "rarity": 3, "level": 4, "where": ["pond"]},
	]
	v.names["fish_perch"] = "River Perch"
	v.names["fish_bass"] = "Largemouth Bass"
	assert_that(P0Logic.fish_at_level(v, 2)).is_equal(["River Perch", "Largemouth Bass"])   # coast-only fish excluded
	v["gear"] = {"rods": [{"id": "rod_starter", "name": "Starter Rod", "reach": 2, "level": 1, "price": 0, "owned": true},
		{"id": "rod_reed", "name": "Reed Rod", "reach": 3, "level": 3, "price": 80, "owned": false}]}
	assert_str(str(P0Logic.rod_for(v, 3).name)).is_equal("Reed Rod")
	assert_bool(P0Logic.rod_for(v, 4).is_empty()).is_true()

func test_rarity_colours_follow_the_design_kit() -> void:
	assert_str(P0Logic.rarity_color(2).to_html(false)).is_equal("6fa8dc")   # Fine blue
	assert_str(P0Logic.rarity_color(3).to_html(false)).is_equal("a98bd6")   # Rare violet
	assert_str(P0Logic.rarity_text_color(1).to_html(false)).is_equal("7fa37b")
