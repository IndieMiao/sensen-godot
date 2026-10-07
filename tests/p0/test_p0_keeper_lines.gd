extends GdUnitTestSuite
## Keeper greeting copy from view.keepers facts (SGODOT-224; 李白 SGODOT-228 b7d8b665 D; server keepersView).

func _view() -> Dictionary:
	return {
		"drinks": {"energy": 30},
		"names": {"fish_perch": "River Perch"},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
		"gear": {"rods": [{"id": "rod_reed", "reach": 3, "price": 80}]},
		"shops": {"tackle": {"buy": [{"id": "rod_reed", "price": 80}, {"id": "bait_worm", "price": 2}]},
			"market": {"buy": [{"id": "tool_row_hoe", "price": 240}]}},
		"keepers": {
			"tea": {"greet": "cups_left", "cups_left": 2, "full": false, "online": 12},
			"post": {"greet": "request", "cups_left": 2, "request_by": "res_pip", "board_open": 2, "refill_in": null},
			"tackle": {"greet": "worms", "worms_left": 30, "next_fish": {"pond": {"id": "fish_perch", "level": 2}, "river": null}},
			"market": {"greet": "row_hoe", "board_open": 2, "board_templates": ["req_sys_crop_mixed", "req_sys_fish_fine"], "refill_in": null},
		},
	}

func test_tea_house() -> void:
	var v := _view()
	var l := P0Logic.keeper_lines(v, "tea", {place = "Lotus Tea House"})
	assert_str(l.line).is_equal("Pours the tea · Lotus Tea House")
	assert_str(l.greet).is_equal("Sit a minute. Hot tea, 30 Energy back.")
	assert_str(l.trade).is_equal("Trade · order tea")
	assert_str(l.question).is_equal("Any news in town?")
	assert_str(l.answer).is_equal("Quiet day. 12 people around Shanghai right now.")
	assert_str(l.leave).is_equal("Just passing by")
	v.keepers.tea.greet = "full"
	assert_str(P0Logic.keeper_lines(v, "tea").greet).is_equal("You look rested. Tea's here when you need it.")
	v.keepers.tea.greet = "cups_out"
	v.keepers.tea.online = null
	var out := P0Logic.keeper_lines(v, "tea")
	assert_str(out.greet).is_equal("That's three cups today. Come back tomorrow.")
	assert_str(out.answer).is_equal("Quiet day.")

func test_travel_post() -> void:
	var v := _view()
	var l := P0Logic.keeper_lines(v, "post", {place = "Huangpu Travel Post"})
	assert_str(l.line).is_equal("Runs the post · Huangpu Travel Post")
	assert_str(l.greet).is_equal("Coffee's fresh. Pip's been asking for a hand.")
	assert_str(l.trade).is_equal("Trade · get a coffee")
	assert_str(l.answer).is_equal("Pip has a request for you.")
	v.keepers.post = {"greet": "cups_left", "cups_left": 1, "request_by": null, "board_open": 0, "refill_in": 14280000}
	l = P0Logic.keeper_lines(v, "post")
	assert_str(l.greet).is_equal("Coffee's fresh. 1 cup left today.")
	assert_str(l.answer).is_equal("All quiet. The Market Board refills in 3h 58m.")
	v.keepers.post.board_open = 2
	assert_str(P0Logic.keeper_lines(v, "post").answer).is_equal("The Market Board has 2 requests today.")

func test_tackle_shop() -> void:
	var v := _view()
	var near := {nearest = {name = "Reed Pond", site = "pond"}}
	var l := P0Logic.keeper_lines(v, "tackle", near)
	assert_str(l.greet).is_equal("Worms are 2 coins. 30 left today.")
	assert_str(l.trade).is_equal("Trade · see the rods")
	assert_str(l.answer).is_equal("Reed Pond is closest. River Perch need Fishing Lv2.")
	v.keepers.tackle.greet = "reed_rod"
	v.keepers.tackle.next_fish.pond = null
	l = P0Logic.keeper_lines(v, "tackle", near)
	assert_str(l.greet).is_equal("Reed Rod's in. 80 coins, lands up to Rare.")
	assert_str(l.answer).is_equal("Reed Pond is closest. You can land everything there.")

func test_market_square() -> void:
	var v := _view()
	var l := P0Logic.keeper_lines(v, "market", {place = "Xuhui Market Square"})
	assert_str(l.line).is_equal("Keeps the stall · Xuhui Market Square")
	assert_str(l.greet).is_equal("Morning! Row Hoes just came in — sows three plots at once, Farming Lv4. Anything I can get you?")
	assert_str(l.trade).is_equal("Trade · open the stall")
	assert_str(l.answer).is_equal("Fresh off the board: Market Basket and Dusk Haul.")
	v.keepers.market = {"greet": "board", "board_open": 0, "board_templates": [], "refill_in": 14280000}
	l = P0Logic.keeper_lines(v, "market")
	assert_str(l.greet).is_equal("The Market Board has 0 requests today.")
	assert_str(l.answer).is_equal("Board's empty. Next request in 3h 58m.")
