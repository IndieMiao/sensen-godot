extends GdUnitTestSuite
## Selling by distance from home (q(251) / q(252), 不知火舞 pm/sell-distance/huowu-review.md, frames on 302 ca26f693):
## the Tackle Shop's and Market's quota line becomes a price line, an away sell card says the home price under its
## own, Mei names what she takes. The server puts the distance on each counter (view.shops[role].distance, 亚瑟) and
## has already multiplied it into sell[].rate; a view without it is an older server, which still counts quotas.

const SEATTLE := {"home": false, "factor": 0.8, "km": 1093.4, "trip": 4, "band": "Long Haul"}
const HOME := {"home": true, "factor": 1}

func _view(tackle_distance = HOME, market_distance = HOME) -> Dictionary:
	return {
		"coins": 230,
		"names": {"fish_rainbow_trout": "Rainbow Trout", "fish_arctic_char": "Arctic Char", "crop_pumpkin": "Pumpkin",
			"crop_radish": "Radish", "crop_grapes": "Grapes", "dish_grilled_crucian": "Grilled Crucian", "timber": "Timber"},
		"items": {
			"fish_rainbow_trout": {"name": "Rainbow Trout", "kind": "fish", "sell": 8, "rarity": 2},
			"fish_arctic_char": {"name": "Arctic Char", "kind": "fish", "sell": 7, "rarity": 1},
			"crop_pumpkin": {"name": "Pumpkin", "kind": "crop", "sell": 6, "rarity": 1},
			"crop_radish": {"name": "Radish", "kind": "crop", "sell": 1, "rarity": 1},
			"crop_grapes": {"name": "Grapes", "kind": "crop", "sell": 9, "rarity": 1},
			"dish_grilled_crucian": {"name": "Grilled Crucian", "kind": "dish", "sell": 4, "rarity": 1},
			"timber": {"name": "Timber", "kind": "material", "sell": 2},
		},
		"bag": {"capacity": 25, "slots": [{"id": "fish_rainbow_trout", "qty": 3}, {"id": "crop_radish", "qty": 4},
			{"id": "fish_arctic_char", "qty": 6}, {"id": "crop_pumpkin", "qty": 2}, {"id": "dish_grilled_crucian", "qty": 3},
			{"id": "timber", "qty": 5}]},
		"shops": {
			"homestead": {"sell": [{"kind": "crop", "rate": 1, "quota": null}, {"kind": "fish", "rate": 1, "quota": null},
				{"kind": "dish", "rate": 1, "quota": "dish"}, {"kind": "material", "rate": 1, "quota": "material"}], "distance": HOME},
			"tackle": {"sell": [{"kind": "fish", "rate": float(tackle_distance.factor), "quota": null}], "distance": tackle_distance},
			"market": {"sell": [{"kind": "crop", "rate": float(market_distance.factor), "quota": null, "regional": true, "items": ["crop_pumpkin", "crop_grapes"]},
				{"kind": "fish", "rate": float(market_distance.factor), "quota": null, "regional": true, "items": ["fish_arctic_char"]}],
				"distance": market_distance},
		},
		"quotas": {"dish": {"used": 96, "cap": 120, "resets_in": 33120000, "scope": "Homestead Stall"},
			"material": {"used": 0, "cap": 30, "resets_in": 33120000, "scope": "Homestead Stall"}},
		"keepers": {"market": {}},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
	}

## The same counters from a server before q(251): quotas, no distance.
func _old_view() -> Dictionary:
	var v := _view()
	v.shops.tackle = {"sell": [{"kind": "fish", "rate": 0.8, "quota": "fish_tackle"}]}
	v.shops.market = {"sell": [{"kind": "crop", "rate": 0.8, "quota": "regional_market", "regional": true, "items": ["crop_pumpkin"]}]}
	v.shops.homestead.erase("distance")
	v.quotas.fish_tackle = {"used": 30, "cap": 80, "resets_in": 33120000, "scope": "any Tackle Shop"}
	v.quotas.regional_market = {"used": 60, "cap": 60, "resets_in": 33120000, "scope": "all San Francisco markets"}
	return v

func _labels(s: Dictionary) -> Array: return s.buttons.map(func(b): return "%s:%s" % [b.kind, b.label])

func test_the_price_line_says_home_price_at_home_and_how_far_away() -> void:
	assert_str(P0CounterDrawer.quota_text(_view(), "tackle")).is_equal("Home price")
	assert_str(P0CounterDrawer.quota_text(_view(), "market")).is_equal("Home price")
	assert_str(P0CounterDrawer.quota_text(_view(SEATTLE), "tackle")).is_equal("80% of home price\n1,093 km · Trip 4 · Long Haul")
	var london := {"home": false, "factor": 0.6, "km": 8616.0, "trip": 6, "band": "Intercontinental"}
	assert_str(P0CounterDrawer.quota_text(_view(HOME, london), "market")).is_equal("60% of home price\n8,616 km · Trip 6 · Intercontinental")
	# selecting a fish there changes nothing: no quota counts it
	assert_str(P0CounterDrawer.quota_text(_view(SEATTLE), "tackle", "fish_rainbow_trout")).is_equal("80% of home price\n1,093 km · Trip 4 · Long Haul")

func test_the_homestead_stall_says_home_price_and_keeps_its_dish_and_material_quotas() -> void:
	assert_str(P0CounterDrawer.quota_text(_view(), "homestead")).is_equal("Home price")
	assert_str(P0CounterDrawer.quota_text(_view(), "homestead", "crop_pumpkin")).is_equal("Home price")
	assert_str(P0CounterDrawer.quota_text(_view(), "homestead", "dish_grilled_crucian")).is_equal("Dish buy-back today 96/120\nHomestead Stall · resets in 9h 12m")
	assert_str(P0CounterDrawer.quota_text(_view(), "homestead", "timber")).is_equal("Material buy-back today 0/30\nHomestead Stall · resets in 9h 12m")

func test_an_older_server_keeps_its_quota_lines() -> void:
	assert_str(P0CounterDrawer.quota_text(_old_view(), "tackle")).is_equal("Fish buy-back today 30/80\nany Tackle Shop · resets in 9h 12m")
	assert_str(P0CounterDrawer.quota_text(_old_view(), "homestead")).is_equal("Crops & fish · no daily limit")
	var full := P0ItemInfo.spec(_old_view(), "crop_pumpkin", &"counter_sell", {counter = "market"})
	assert_array(_labels(full)).is_equal(["unavailable:Limit reached · 9h 12m"])
	assert_str(str(full.get("fact_note", ""))).is_empty()   # no distance: no home price under the unit price
	assert_str(P0Logic.market_sell_line(_old_view())).is_empty()   # Mei keeps her greeting

func test_an_away_sell_card_says_the_home_price_under_its_own() -> void:
	var s := P0ItemInfo.spec(_view(SEATTLE), "fish_rainbow_trout", &"counter_sell", {counter = "tackle"})
	assert_str(str(s.facts[-1])).is_equal("6 each")   # 8 × 0.8
	assert_str(str(s.fact_note)).is_equal("8 at home")
	assert_array(_labels(s)).is_equal(["secondary:Sell", "primary:Sell All · 18 coins"])   # no quota, no Limit reached
	var home := P0ItemInfo.spec(_view(), "fish_rainbow_trout", &"counter_sell", {counter = "tackle"})
	assert_str(str(home.facts[-1])).is_equal("8 each")
	assert_str(str(home.fact_note)).is_empty()
	assert_str(str(P0ItemInfo.spec(_view(), "crop_pumpkin", &"counter_sell", {counter = "homestead"}).fact_note)).is_empty()

func test_the_lowest_band_never_prices_a_coin_item_at_zero() -> void:
	var tokyo := {"home": false, "factor": 0.6, "km": 8280.0, "trip": 6, "band": "Intercontinental"}
	var v := _view(HOME, tokyo)
	v.shops.market.sell[0].items.append("crop_radish")
	var s := P0ItemInfo.spec(v, "crop_radish", &"counter_sell", {counter = "market"})
	assert_str(str(s.facts[-1])).is_equal("1 each")   # ⌊1 × 0.6⌋ = 0 → 1, as the server rounds (q(251) ②)
	assert_array(_labels(s)).is_equal(["secondary:Sell", "primary:Sell All · 4 coins"])

func test_mei_names_the_first_two_things_she_takes() -> void:
	# bag order: trout (not hers), radish (not hers), Arctic char, pumpkins
	assert_str(P0Logic.market_sell_line(_view())).is_equal("I'll take your Arctic char and pumpkins. Same price as your stall.")
	assert_str(P0Logic.market_sell_line(_view(HOME, SEATTLE))).is_equal("Arctic char and pumpkins? I'll take them, though home pays better.")
	assert_str(str(P0Logic.keeper_lines(_view(), "market").counter)).is_equal("I'll take your Arctic char and pumpkins. Same price as your stall.")

func test_mei_with_one_thing_and_with_nothing() -> void:
	var v := _view(HOME, SEATTLE)
	v.bag.slots = [{"id": "crop_pumpkin", "qty": 2}, {"id": "fish_arctic_char", "qty": 1, "gifted": true}]   # Gifted: not hers to buy
	assert_str(P0Logic.market_sell_line(v)).is_equal("Pumpkins? I'll take them, though home pays better.")
	v.shops.market.distance = HOME
	assert_str(P0Logic.market_sell_line(v)).is_equal("I'll take your pumpkins. Same price as your stall.")
	v.bag.slots = [{"id": "fish_rainbow_trout", "qty": 3}]
	assert_str(P0Logic.market_sell_line(v)).is_empty()
	assert_str(str(P0Logic.keeper_lines(v, "market").counter)).is_equal(str(P0Logic.keeper_lines(v, "market").greet))

func test_names_in_speech_keep_only_proper_adjectives_capitalised() -> void:
	var v := _view()
	assert_str(P0Logic.speech_name(v, "fish_rainbow_trout")).is_equal("rainbow trout")
	assert_str(P0Logic.speech_name(v, "fish_arctic_char")).is_equal("Arctic char")
	assert_str(P0Logic.speech_name(v, "crop_pumpkin")).is_equal("pumpkins")
	assert_str(P0Logic.speech_name(v, "crop_grapes")).is_equal("grapes")
	v.bag.slots = [{"id": "fish_rainbow_trout", "qty": 1}]
	v.shops.market.sell[1].items.append("fish_rainbow_trout")
	v.shops.market.distance = SEATTLE
	assert_str(P0Logic.market_sell_line(v)).is_equal("Rainbow trout? I'll take them, though home pays better.")

func test_the_sell_card_lays_the_home_price_under_its_unit_price() -> void:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 200)
	add_child(auto_free(host))
	var sheet := UiInfoSheet.new()
	var v := _view(SEATTLE)
	sheet.rules = func(id: String, c: StringName, o: Dictionary) -> Dictionary: return P0ItemInfo.spec(v, id, c, o)
	sheet.size = Vector2(336, 120)
	host.add_child(sheet)
	sheet.open("fish_rainbow_trout", &"counter_sell", {counter = "tackle"})
	for i in 3: await get_tree().process_frame
	assert_str(sheet._effect.text).is_equal("6 each")
	assert_str(sheet._effect_note.text).is_equal("8 at home")
	assert_bool(sheet._effect_note.visible).is_true()
	assert_float(sheet._effect_note.global_position.y).is_greater(sheet._effect.global_position.y)   # under it

func test_the_unit_price_rounds_as_the_server_does() -> void:
	var chicago := {"home": false, "factor": 0.7, "km": 2986.0, "trip": 5, "band": "Continental"}
	var v := _view(chicago)
	v.items.fish_rainbow_trout.sell = 90   # 90 × 0.7 = 62.99999… in floats: the server's floor(+1e-9) says 63
	assert_str(str(P0ItemInfo.spec(v, "fish_rainbow_trout", &"counter_sell", {counter = "tackle"}).facts[-1])).is_equal("63 each")
