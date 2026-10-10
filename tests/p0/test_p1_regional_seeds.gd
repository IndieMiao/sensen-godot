extends GdUnitTestSuite
## P1 regional seeds at the Market (§5.2.3, SGODOT-240): the server lists the city's regional seed among the Market's
## goods; the drawer's Buy page shows it (everything but the City Specialty), with its daily stock and, for a crop away
## from its climate zone, the ×1.5 time it takes on this farm.

func _view(offer := {}) -> Dictionary:
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
	var buy: Array = v.shops.market.buy
	var pumpkin := {"id": "seed_pumpkin", "name": "Pumpkin Seeds", "price": 17, "need": 17, "to": "bag", "skill": "farming",
		"gate": 5, "unlocked": true, "xp_to_go": 0, "homestead": null, "homestead_ok": true, "once": false, "owned": false,
		"left": 6, "daily": 10, "materials": [], "in_bag": 0}
	pumpkin.merge(offer, true)
	buy.insert(1, pumpkin)   # the server's order: goods, the regional seed, the City Specialty
	v.names["seed_pumpkin"] = "Pumpkin Seeds"
	v.names["seed_pineapple"] = "Pineapple Seeds"
	(v.crops as Array).append({"id": "crop_pumpkin", "seed": "seed_pumpkin", "energy": 4, "grow_h": 20, "level": 5, "zone": "Temperate", "native": true})
	(v.crops as Array).append({"id": "crop_pineapple", "seed": "seed_pineapple", "energy": 4, "grow_h": 36, "level": 5, "zone": "Tropical", "native": false})
	return v

func _drawer(v: Dictionary, section := "buy") -> P0CounterDrawer:
	var top := CanvasLayer.new()
	add_child(auto_free(top))
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	top.add_child(host)
	var d := P0CounterDrawer.new(v, "market", {"keeper": "Mei", "place": "Mission Market Square"}, section)
	d.animate = false
	host.add_child(d)
	return d

func _ids(d: P0CounterDrawer) -> Array: return d.shelf.get_children().filter(func(c): return c.visible).map(func(r): return (r as UiShopRow).item_id)

func test_the_market_buy_page_lists_the_regional_seed_and_the_specialty_keeps_its_own_shelf() -> void:
	var buy := _drawer(_view())
	for i in 3: await get_tree().process_frame
	assert_array(_ids(buy)).is_equal(["tool_row_hoe", "seed_pumpkin"])
	var row: UiShopRow = buy._rows["seed_pumpkin"]
	assert_str(row._effect.text).is_equal("Ready in 20h")
	assert_str(row._gate.text).is_equal("Stock 6/10 · Bag ×0")   # NPC-2: `Stock 8/10`
	var special := _drawer(_view(), "specialty")
	for i in 3: await get_tree().process_frame
	assert_array(_ids(special)).is_equal(["postcard_san_francisco"])

func test_before_farming_lv5_the_row_shows_the_gate() -> void:
	var d := _drawer(_view({"unlocked": false, "xp_to_go": 40}))
	for i in 3: await get_tree().process_frame
	var row: UiShopRow = d._rows["seed_pumpkin"]
	assert_str(row._gate.text).is_equal("40 XP to go")

## A seed bought in another climate's city ripens ×1.5 at home: the row says the farm's time and `not native`.
func test_a_seed_away_from_its_zone_says_not_native() -> void:
	var v := _view()
	var use := func(id: String) -> String: return str(P0ItemInfo._seed_use(P0Logic.crop_for_seed(v, id)))
	assert_str(use.call("seed_pumpkin")).is_equal("Ready in 20h")
	assert_str(use.call("seed_pineapple")).is_equal("Ready in 36h · not native")
	assert_str(use.call("seed_radish")).is_equal("Ready in 4h")   # a stall seed has no zone
