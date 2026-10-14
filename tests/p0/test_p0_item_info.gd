extends GdUnitTestSuite
## F-07 item detail rules (SGODOT-224; SGODOT-207 168a4cc3 rev 1–2; 李白 25f3cb4c; K-3 = A).

const SNAPSHOT := "res://tests/p0/snapshots/item_info.json"

func _view() -> Dictionary:
	return {
		"coins": 40,
		"energy": {"value": 150, "max": 200},
		"meals": {"used": 0, "cap": 300, "resets_in": 3600000},
		"names": {"seed_radish": "Radish Seeds", "crop_radish": "Radish", "fish_crucian": "Pond Crucian",
			"dish_grilled_crucian": "Grilled Crucian", "bait_worm": "Worm Bait", "rod_reed": "Reed Rod", "rod_starter": "Starter Rod",
			"timber": "Timber"},
		"items": {
			"seed_radish": {"name": "Radish Seeds", "kind": "seed", "sell": null},
			"crop_radish": {"name": "Radish", "kind": "crop", "sell": 5, "rarity": 1},
			"fish_crucian": {"name": "Pond Crucian", "kind": "fish", "sell": 6, "rarity": 1},
			"dish_grilled_crucian": {"name": "Grilled Crucian", "kind": "dish", "sell": null, "rarity": 1, "quality": 1, "meal": 45, "full": 45},
			"bait_worm": {"name": "Worm Bait", "kind": "bait", "sell": null},
			"timber": {"name": "Timber", "kind": "material", "sell": 2},
		},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2, "grow_h": 4, "level": 1}],
		"bag": {"capacity": 25, "slots": [{"id": "seed_radish", "qty": 20}, {"id": "crop_radish", "qty": 12},
			{"id": "fish_crucian", "qty": 3}, {"id": "dish_grilled_crucian", "qty": 1}, {"id": "bait_worm", "qty": 5}, {"id": "timber", "qty": 12}]},
		"stall": {"buy": [{"id": "seed_radish", "name": "Radish Seeds", "price": 4, "gate": 1, "skill": "farming", "unlocked": true, "left": null}],
			"board": {"requests": [{"id": "req_1", "item": "fish_crucian", "qty": 2, "have": 3, "status": "accepted"}]}},
		"tackle": {"buy": [{"id": "rod_reed", "name": "Reed Rod", "price": 80, "gate": 3, "skill": "fishing", "unlocked": false, "xp_to_go": 215, "owned": false, "left": null},
			{"id": "bait_worm", "name": "Worm Bait", "price": 2, "gate": 2, "skill": "fishing", "unlocked": true, "left": 7, "daily": 30}]},
		"gear": {"rods": [{"id": "rod_starter", "name": "Starter Rod", "reach": 2, "level": 1, "hook_bonus_ms": 0, "owned": true, "equipped": true},
			{"id": "rod_reed", "name": "Reed Rod", "reach": 3, "level": 3, "hook_bonus_ms": 400, "owned": false, "equipped": false}]},
		"fishing": {"dex": [{"id": "fish_crucian", "caught": 3}, {"id": "fish_carp", "caught": 0}]},
		# The counters as the P0 server sends them (SGODOT-228, assets/p0/p0_content.json shops / quotas).
		"shops": {"homestead": {"sell": [{"kind": "crop", "rate": 1, "quota": null}, {"kind": "fish", "rate": 1, "quota": null},
				{"kind": "dish", "rate": 1, "quota": "dish"}, {"kind": "material", "rate": 1, "quota": "material"}]},
			"tackle": {"sell": [{"kind": "fish", "rate": 0.8, "quota": "fish_tackle"}]}},
		"quotas": {"fish_tackle": {"used": 0, "cap": 80, "resets_in": 33120000, "scope": "any Tackle Shop"},
			"dish": {"used": 0, "cap": 120, "resets_in": 33120000, "scope": "Homestead Stall"},
			"material": {"used": 0, "cap": 30, "resets_in": 33120000, "scope": "Homestead Stall"}},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
	}

func _labels(s: Dictionary) -> Array: return s.buttons.map(func(b): return "%s:%s" % [b.kind, b.label])

func test_fill_drops_segments_with_empty_tokens() -> void:
	assert_str(P0ItemInfo.fill("{count} · {source}", {count = "12", source = ""})).is_equal("12")
	assert_str(P0ItemInfo.fill("{a}", {a = ""})).is_empty()
	assert_str(P0ItemInfo.fill("Sells for {sell} · Fish-dex {dex}", {sell = "6", dex = "1/2"})).is_equal("Sells for 6 · Fish-dex 1/2")

func test_predicates_are_and_of_optionally_negated_flags() -> void:
	var f := {a = true, b = false}
	assert_bool(P0ItemInfo.holds("", f)).is_true()
	assert_bool(P0ItemInfo.holds("a & !b", f)).is_true()
	assert_bool(P0ItemInfo.holds("a & b", f)).is_false()
	assert_bool(P0ItemInfo.holds("!a", f)).is_false()

func test_rule_table_only_uses_known_flags_and_tokens() -> void:
	var v := _view()
	var f := P0ItemInfo.flags(v, "crop_radish", &"bag")
	var t := P0ItemInfo.tokens(v, "crop_radish", &"bag")
	var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for key in P0ItemInfo.rules():
		if key.begins_with("_"): continue
		var r: Dictionary = P0ItemInfo.rules()[key]
		var texts: Array = r.get("facts", []).duplicate()   # never append to the cached table
		var exprs := []
		for b in r.get("buttons", []):
			texts.append(b.label); exprs.append(str(b.get("when", "")))
			for u in b.get("unless", []): texts.append(u.label); exprs.append(str(u.when))
		for text in texts:
			for m in re.search_all(str(text)): assert_bool(t.has(m.get_string(1))).override_failure_message("%s: unknown token %s" % [key, m.get_string(1)]).is_true()
		for e in exprs:
			for term in str(e).split("&"):
				var n := term.strip_edges().trim_prefix("!").strip_edges()
				if n != "": assert_bool(f.has(n)).override_failure_message("%s: unknown flag %s" % [key, n]).is_true()

func test_actions_the_server_cannot_do_yet_do_not_show() -> void:
	var s := P0ItemInfo.spec(_view(), "seed_radish", &"bag", {place = "pond"})
	assert_array(_labels(s)).is_equal(["secondary:Pin"])   # no Store, not even the grey At home only
	assert_bool(s.lock.shown).is_false()
	assert_array(_labels(P0ItemInfo.spec(_view(), "fish_crucian", &"bag"))).is_empty()   # no Gift › before gifting exists

func _full() -> Dictionary:
	var v := _view()
	v["storage"] = {}
	v["residents"] = []
	for slot in v.bag.slots: slot["locked"] = false
	return v

func test_seed_in_the_bag_pins_and_stores_only_at_home() -> void:
	var s := P0ItemInfo.spec(_full(), "seed_radish", &"bag", {place = "home"})
	assert_array(s.facts).is_equal(["2 Energy per plot · Ready in 4h"])   # F-07 wording: whole hours, int Energy
	assert_array(_labels(s)).is_equal(["secondary:Pin", "secondary:Store"])   # no primary button
	assert_bool(s.lock.shown).is_true()
	s = P0ItemInfo.spec(_full(), "seed_radish", &"bag", {place = "pond", pinned = true})
	assert_array(_labels(s)).is_equal(["secondary:Unpin", "unavailable:At home only"])
	assert_str(s.badge).is_equal("pinned")

func test_never_sellable_kinds_show_no_sell_and_no_grey_text() -> void:
	for id in ["seed_radish", "bait_worm"]:
		assert_bool(P0ItemInfo.spec(_view(), id, &"counter_sell").card).is_false()
	assert_bool(P0ItemInfo.spec(_view(), "crop_radish", &"gift").buttons.is_empty()).is_true()   # K-3 A: no Gift on crops

func test_crop_sells_at_the_homestead_with_the_real_coins() -> void:
	var s := P0ItemInfo.spec(_view(), "crop_radish", &"counter_sell", {counter = "homestead"})
	assert_array(_labels(s)).is_equal(["secondary:Sell", "primary:Sell All · 60 coins"])
	assert_str(s.quota.text).is_equal("Crops & fish · no daily limit")
	s = P0ItemInfo.spec(_view(), "crop_radish", &"counter_sell", {counter = "tackle"})
	assert_array(_labels(s)).is_equal(["unavailable:Sell at home"])

func test_tackle_pays_eighty_percent_rounded_down_and_says_the_coins() -> void:
	var s := P0ItemInfo.spec(_view(), "fish_crucian", &"counter_sell", {counter = "tackle"})
	assert_array(_labels(s)).is_equal(["secondary:Sell", "primary:Sell All · 12 coins"])   # floor(6 × 0.8) = 4, × 3
	assert_bool(s.facts.has("4 each")).is_true()

func test_quota_short_of_the_stack_and_used_up() -> void:
	# Server shapes (SGODOT-228): shops[role].sell = [{kind, rate, quota}], view.quotas[id] = {used, cap, resets_in, scope}.
	var v := _view()
	v["shops"] = {"tackle": {"sell": [{"kind": "fish", "rate": 0.8, "quota": "fish_tackle"}]}}
	v["quotas"] = {"fish_tackle": {"used": 70, "cap": 80, "resets_in": 33120000, "scope": "any Tackle Shop"}}
	var s := P0ItemInfo.spec(v, "fish_crucian", &"counter_sell", {counter = "tackle"})
	# the allowance is coins (server ⌊left / unit⌋): 10 left at ⌊6 × 0.8⌋ = 4 each takes 2 of 3
	assert_array(_labels(s)).is_equal(["secondary:Sell", "primary:Sell 2 · 8 coins"])
	assert_str(s.quota.text).is_equal("Fish buy-back today 70/80")
	assert_str(s.quota.note).is_equal("any Tackle Shop · resets in 9h 12m")
	v.quotas.fish_tackle.used = 77   # 3 coins left can't pay for one at 4: the server says limit_reached
	s = P0ItemInfo.spec(v, "fish_crucian", &"counter_sell", {counter = "tackle"})
	assert_array(_labels(s)).is_equal(["unavailable:Limit reached · 9h 12m"])
	v.shops["market"] = {"sell": []}   # P0 markets take nothing
	assert_array(_labels(P0ItemInfo.spec(v, "crop_radish", &"counter_sell", {counter = "market"}))).is_equal(["unavailable:Sell at home"])

func test_a_market_quota_short_of_the_stack_sells_what_fits() -> void:
	var v := _view()
	v["shops"] = {"market": {"sell": [{"kind": "crop", "rate": 0.8, "quota": "crop_market"}]}}
	v["quotas"] = {"crop_market": {"used": 40, "cap": 60, "resets_in": 33120000, "scope": "all San Francisco markets"}}
	var s := P0ItemInfo.spec(v, "crop_radish", &"counter_sell", {counter = "market"})
	assert_array(_labels(s)).is_equal(["secondary:Sell", "primary:Sell 5 · 20 coins"])   # 20 coins left at ⌊5 × 0.8⌋ = 4: 5 of 12
	assert_str(s.quota.note).is_equal("all San Francisco markets · resets in 9h 12m")

## The Market Square (SGODOT-284, 不知火舞 on 240): this city's climate's regional crops and fish at 0.8, 60 coins a
## day for the city; it lists only what it takes (LOCK-15), says Buy-back today over all San Francisco markets (NPC-3) and Limit reached when spent.
func _market_view(used: int) -> Dictionary:
	var v := _view()
	v.items["crop_pumpkin"] = {"name": "Pumpkin", "kind": "crop", "sell": 22, "rarity": 1}
	v.items["fish_salmon"] = {"name": "Salmon", "kind": "fish", "sell": 32, "rarity": 2}
	v.bag.slots.append({"id": "crop_pumpkin", "qty": 4})
	v.bag.slots.append({"id": "fish_salmon", "qty": 1})
	v["shops"] = {"market": {"sell": [{"kind": "crop", "rate": 0.8, "quota": "regional_market", "regional": true, "items": ["crop_pumpkin"]},
		{"kind": "fish", "rate": 0.8, "quota": "regional_market", "regional": true, "items": ["fish_salmon", "fish_arctic_char"]}]}}
	v["quotas"] = {"regional_market": {"used": used, "cap": 60, "resets_in": 33120000, "scope": "all San Francisco markets"}}
	return v

func test_the_market_buys_only_its_regional_crops_and_fish() -> void:
	var v := _market_view(20)
	var s := P0ItemInfo.spec(v, "crop_pumpkin", &"counter_sell", {counter = "market"})
	assert_array(s.facts).is_equal(["17 each"])   # ⌊22 × 0.8⌋; no count line, the corner says ×4 (不知火舞 on 246)
	assert_array(_labels(s)).is_equal(["secondary:Sell", "primary:Sell 2 · 34 coins"])   # 40 coins left: 2 of 4
	assert_str(s.quota.text).is_equal("Buy-back today 20/60")
	assert_str(s.quota.note).is_equal("all San Francisco markets · resets in 9h 12m")
	assert_bool(P0ItemInfo.flags(v, "fish_salmon", &"counter_sell", {counter = "market"}).sold_here).is_true()
	for id in ["crop_radish", "fish_crucian", "timber"]:   # not regional here: not listed in the Sell here grid
		assert_bool(P0ItemInfo.flags(v, id, &"counter_sell", {counter = "market"}).sold_here).is_false()
	assert_str(P0CounterDrawer.quota_text(v, "market")).is_equal("Buy-back today 20/60\nall San Francisco markets · resets in 9h 12m")
	v = _market_view(50)   # 10 coins left can't pay for a 17-coin Pumpkin
	assert_array(_labels(P0ItemInfo.spec(v, "crop_pumpkin", &"counter_sell", {counter = "market"}))).is_equal(["unavailable:Limit reached · 9h 12m"])
	assert_array(_labels(P0ItemInfo.spec(v, "fish_salmon", &"counter_sell", {counter = "market"}))).is_equal(["unavailable:Limit reached · 9h 12m"])

func test_locked_stack_shows_locked_and_unlock_only() -> void:
	var v := _view()
	v.bag.slots[1]["locked"] = true
	var s := P0ItemInfo.spec(v, "crop_radish", &"counter_sell")
	assert_array(_labels(s)).is_equal(["unavailable:Locked", "secondary:Unlock"])
	assert_bool(s.lock.locked).is_true()
	assert_str(s.badge).is_equal("locked")   # Locked wins over Pinned

func test_fish_gift_is_grey_without_mutual_friends() -> void:
	var s := P0ItemInfo.spec(_full(), "fish_crucian", &"bag")
	assert_array(_labels(s)).is_equal(["unavailable:Gift · Mutual friends only"])
	assert_array(s.facts).is_equal(["Sells for 6 · Fish-dex 1/2"])   # no known source: no bare "3" line (×3 is in the title)
	assert_str(s.rarity_text).is_equal("Common")   # rarity sits on the state line, not in facts
	var v := _full()
	v["social"] = {"mutual": 2}
	assert_array(_labels(P0ItemInfo.spec(v, "fish_crucian", &"bag"))).is_equal(["nav:Gift ›"])

func test_dish_eats_and_greys_eat_when_energy_is_full() -> void:
	var s := P0ItemInfo.spec(_full(), "dish_grilled_crucian", &"bag")
	assert_array(_labels(s)).is_equal(["primary:Eat · +45 Energy", "unavailable:Gift to a resident"])
	assert_str(s.rarity_text).is_equal("Common")
	assert_int(s.quality).is_equal(1)
	assert_array(s.facts).is_equal(["+45 Energy"])
	var v := _full()
	v.energy.value = 200
	assert_array(_labels(P0ItemInfo.spec(v, "dish_grilled_crucian", &"bag"))).is_equal(["unavailable:Energy full", "unavailable:Gift to a resident"])

## Deliver answers one accepted board request (opts.target {request}); it takes the primary slot and Eat steps down.
## Nothing opens a bag card for a request yet (the Stall Board card and the resident bar deliver themselves), so
## without a target there is no Deliver.
func test_deliver_takes_the_primary_slot_for_its_accepted_request() -> void:
	var v := _full()
	v.stall.board.requests.append({"id": "req_2", "item": "dish_grilled_crucian", "qty": 1, "have": 1, "status": "accepted"})
	assert_array(_labels(P0ItemInfo.spec(v, "dish_grilled_crucian", &"bag", {target = {request = "req_2"}}))) \
		.is_equal(["secondary:Eat · +45 Energy", "primary:Deliver", "unavailable:Gift to a resident"])
	assert_array(_labels(P0ItemInfo.spec(v, "dish_grilled_crucian", &"bag"))) \
		.is_equal(["primary:Eat · +45 Energy", "unavailable:Gift to a resident"])
	assert_array(_labels(P0ItemInfo.spec(v, "fish_crucian", &"gift", {target = {request = "req_1"}}))).is_equal(["primary:Deliver"])
	v.stall.board.requests[1].status = "open"   # not accepted yet: the board's Accept comes first
	assert_array(_labels(P0ItemInfo.spec(v, "dish_grilled_crucian", &"bag", {target = {request = "req_2"}}))) \
		.is_equal(["primary:Eat · +45 Energy", "unavailable:Gift to a resident"])

## A dish's Gift on the bag card (不知火舞 / 李白 on 225): `Gift to <Name>` for the resident within reach, else grey
## `Gift to a resident`; grey `Gift already given today` once that resident has had today's gift. Mystery Dish too.
func test_dish_gift_names_the_resident_within_reach() -> void:
	var near := {id = "res_pip", name = "Pip", gifted_today = false}
	assert_array(_labels(P0ItemInfo.spec(_full(), "dish_grilled_crucian", &"bag", {near = near}))) \
		.is_equal(["primary:Eat · +45 Energy", "secondary:Gift to Pip"])
	near.gifted_today = true
	assert_array(_labels(P0ItemInfo.spec(_full(), "dish_grilled_crucian", &"bag", {near = near}))) \
		.is_equal(["primary:Eat · +45 Energy", "unavailable:Gift already given today"])
	var v := _full()
	v.bag.slots.append({"id": "dish_mystery", "qty": 1})
	v.items["dish_mystery"] = {"name": "Mystery Dish", "kind": "dish", "sell": null, "meal": 10, "full": 10}
	var gifts := _labels(P0ItemInfo.spec(v, "dish_mystery", &"bag", {near = {id = "res_pip", name = "Pip"}}))
	assert_bool(gifts.has("secondary:Gift to Pip")).is_true()   # residents take it, not a fan (q(33))
	var drawer := _labels(P0ItemInfo.spec(v, "dish_mystery", &"gift", {target = {kind = "resident", id = "res_pip"}}))
	assert_bool(drawer.has("primary:Gift")).is_true()

func test_buy_rows_say_why_they_cannot_be_bought() -> void:
	var s := P0ItemInfo.spec(_view(), "rod_reed", &"counter_buy", {counter = "tackle"})
	assert_array(_labels(s)).is_equal(["unavailable:Fishing Lv3 needed"])
	var v := _view()
	v.tackle.buy[0].unlocked = true
	s = P0ItemInfo.spec(v, "rod_reed", &"counter_buy", {counter = "tackle"})
	assert_array(_labels(s)).is_equal(["unavailable:Need 40 more coins"])
	s = P0ItemInfo.spec(_view(), "bait_worm", &"counter_buy", {counter = "tackle", qty = 3})
	assert_array(_labels(s)).is_equal(["secondary:Buy"])
	assert_dict(s.price).is_equal({each = 2, total = 6, text = "6 coins", line = "3 × 2 coins"})
	assert_bool(s.facts.has("Stock 7/30 · Bag ×5")).is_true()

func test_row_hoe_and_bag_upgrade_buy_rows() -> void:
	var v := _view()
	v.coins = 500
	v.gear["hoes"] = [{"id": "tool_row_hoe", "name": "Row Hoe", "owned": false, "equipped": false, "sow": 3, "price": 240, "gate": 4}]
	v.shops["market"] = {"buy": [{"id": "tool_row_hoe", "name": "Row Hoe", "price": 240, "need": 280, "to": "gear", "skill": "farming",
		"gate": 4, "unlocked": false, "xp_to_go": 300, "homestead_ok": true, "owned": false, "left": null, "materials": []}], "sell": []}
	v.shops.homestead["buy"] = [{"id": "bag_upgrade_1", "name": "Bag Upgrade I", "price": 150, "need": 190, "to": "bag_cap", "skill": null,
		"gate": 0, "unlocked": true, "homestead": 3, "homestead_ok": true, "owned": false, "left": null,
		"materials": [{"id": "fiber", "name": "Reeds", "need": 10, "have": 4}, {"id": "wood", "name": "Timber", "need": 6, "have": 6}]}]
	var hoe := P0ItemInfo.spec(v, "tool_row_hoe", &"counter_buy", {counter = "market"})
	assert_array(hoe.facts).is_equal(["Sows 3 plots at once"])
	assert_array(_labels(hoe)).is_equal(["unavailable:Farming Lv4 needed"])
	assert_str(str(hoe.price.text)).is_equal("240 coins")
	var up := P0ItemInfo.spec(v, "bag_upgrade_1", &"counter_buy", {counter = "homestead"})
	# line 3: the first material still short, the others short counted (不知火舞 on 284, q(174)); Timber is in, so none more
	assert_array(up.facts).is_equal(["+5 bag slots", "Reeds 4/10"])
	assert_array(_labels(up)).is_equal(["unavailable:Need 6 Reeds"])
	v.shops.homestead.buy[0].materials[1].have = 2
	assert_array(P0ItemInfo.spec(v, "bag_upgrade_1", &"counter_buy", {counter = "homestead"}).facts).is_equal(["+5 bag slots", "Reeds 4/10 · +1 more"])
	v.shops.homestead.buy[0].materials[0].have = 10
	v.shops.homestead.buy[0].materials[1].have = 6
	var ready := P0ItemInfo.spec(v, "bag_upgrade_1", &"counter_buy", {counter = "homestead"})
	assert_array(ready.facts).is_equal(["+5 bag slots", "Materials ready"])
	assert_array(_labels(ready)).is_equal(["secondary:Buy"])

func test_rods_in_gear_equip_or_show_equipped() -> void:
	var starter := P0ItemInfo.spec(_view(), "rod_starter", &"gear")
	assert_array(_labels(starter)).is_equal(["unavailable:✓ Equipped"])
	assert_str(str(starter.facts[0])).is_equal("Lands up to Fine fish · Bite window 2.2 s")   # absolute window (76834e35)
	var s := P0ItemInfo.spec(_view(), "rod_reed", &"gear")
	assert_array(_labels(s)).is_empty()
	assert_array(s.facts).is_equal(["Lands up to Rare fish · Bite window 2.6 s", "Fishing Lv3 · Tackle Shop"])
	var v := _view()
	for r in v.gear.rods: if str(r.id) == "rod_reed": r.owned = true
	assert_array(_labels(P0ItemInfo.spec(v, "rod_reed", &"gear"))).is_equal(["primary:Equip"])   # solid (BAG-2)

func test_snapshot_of_every_kind_and_context() -> void:
	var v := _view()
	var out := {}
	for id in ["seed_radish", "crop_radish", "fish_crucian", "dish_grilled_crucian", "bait_worm", "rod_reed", "rod_starter", "timber"]:
		for ctx in P0ItemInfo.CONTEXTS:
			var s := P0ItemInfo.spec(v, id, ctx, {counter = "tackle" if id.begins_with("rod") or id.begins_with("bait") else "homestead"})
			if not s.card: continue
			out["%s/%s" % [id, ctx]] = {facts = s.facts, buttons = _labels(s), price = s.price, quota = s.quota, lock = s.lock, badge = str(s.badge)}
	var text := JSON.stringify(out, "  ", true) + "\n"
	if OS.get_environment("UPDATE_ITEM_INFO") == "1" or not FileAccess.file_exists(SNAPSHOT):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SNAPSHOT.get_base_dir()))
		var f := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	assert_str(text).is_equal(FileAccess.get_file_as_string(SNAPSHOT))

func test_hours_read_like_f07() -> void:
	assert_str(P0ItemInfo.hours(4.0)).is_equal("4h")
	assert_str(P0ItemInfo.hours(1.5)).is_equal("1h 30m")
	assert_str(P0ItemInfo.hours(0.75)).is_equal("45m")

func test_storage_stacks_take_ten_or_all_at_home() -> void:
	var v := _full()
	v.storage = {"items": [{"id": "timber", "name": "Timber", "qty": 12}, {"id": "seed_radish", "name": "Radish Seeds", "qty": 4}]}
	var s := P0ItemInfo.spec(v, "timber", &"storage", {place = "home"})
	assert_array(s.facts).is_equal(["12 · Farm Storage"])
	assert_array(_labels(s)).is_equal(["secondary:Take 10", "primary:Take all"])
	assert_that(s.buttons.map(func(b): return [b.id, b.payload])).is_equal([[&"take_out", {"qty": 10}], [&"take_out", {"qty": "all"}]])
	assert_array(_labels(P0ItemInfo.spec(v, "seed_radish", &"storage", {place = "home"}))).is_equal(["primary:Take all"])   # 4 stored: no Take 10
	assert_array(_labels(P0ItemInfo.spec(v, "timber", &"storage", {place = "pond"}))).is_equal(["unavailable:At home only"])

func test_buy_rows_use_the_server_wallet_need_and_homestead_gate() -> void:
	var v := _view()
	v["shops"] = {"homestead": {"buy": [
		{"id": "seed_radish", "price": 4, "need": 44, "skill": "farming", "gate": 1, "unlocked": true, "homestead": null, "homestead_ok": true, "left": null},
		{"id": "bait_worm", "price": 2, "need": 42, "skill": "fishing", "gate": 1, "unlocked": true, "homestead": 2, "homestead_ok": false, "left": 30}]}}
	assert_array(_labels(P0ItemInfo.spec(v, "seed_radish", &"counter_buy"))).is_equal(["unavailable:Need 4 more coins"])   # 40 coins, needs 44
	assert_array(_labels(P0ItemInfo.spec(v, "bait_worm", &"counter_buy"))).is_equal(["unavailable:Homestead Lv2 needed"])

func test_torches_read_as_materials() -> void:
	var v := _view()
	v.items["torch"] = {"name": "Torch", "kind": "torch", "sell": null}
	assert_str(P0ItemInfo.kind_of(v, "torch")).is_equal("material")

func test_pickaxes_in_gear_say_stone_per_rock_and_where_from() -> void:
	# LOCK-29; view.gear.picks as the server sends it (SGODOT-231 PR #17).
	var v := _view()
	v.gear["picks"] = [{"id": "pick_starter", "name": "Starter Pickaxe", "owned": true, "equipped": true, "stone": 1, "level": 1},
		{"id": "pick_copper", "name": "Copper Pickaxe", "owned": false, "equipped": false, "stone": 2, "level": 2, "price": 0, "source": "workbench"}]   # machine codes (周瑜 #17)
	assert_str(P0ItemInfo.kind_of(v, "pick_copper")).is_equal("pick")
	var s := P0ItemInfo.spec(v, "pick_starter", &"gear")
	assert_array(s.facts).is_equal(["1 Stone per rock"])
	assert_array(_labels(s)).is_equal(["unavailable:✓ Equipped"])
	s = P0ItemInfo.spec(v, "pick_copper", &"gear")
	assert_array(s.facts).is_equal(["2 Stone per rock", "Workbench"])
	assert_array(_labels(s)).is_empty()

func test_bag_tabs_follow_the_plan() -> void:
	var v := _view()
	v.items["torch"] = {"name": "Torch", "kind": "torch", "sell": null}
	var tabs := {}
	for id in ["seed_radish", "fert_compost", "crop_radish", "fish_crucian", "dish_grilled_crucian", "bait_worm", "rod_reed", "timber", "torch"]:
		tabs[id] = P0ItemInfo.tab_of(v, id)
	assert_dict(tabs).is_equal({"seed_radish": &"seeds", "fert_compost": &"seeds", "crop_radish": &"produce", "fish_crucian": &"fish",
		"dish_grilled_crucian": &"dishes", "bait_worm": &"tackle", "rod_reed": &"tackle", "timber": &"materials", "torch": &"materials"})
	assert_str(P0ItemInfo.tab_of(v, "postcard_san_francisco")).is_empty()   # keepsakes: All only

## A dish stack with its quality (`dish_x@good`, §7.2.5; 李元芳 on 286 5d27bd93): the card names the dish and shows its
## art, never the raw id or the sprout; the quality is the state line's stars (`Common ★`).
func test_a_good_dish_reads_as_the_dish_with_a_star() -> void:
	var v := _view()
	v.items["dish_grilled_crucian@good"] = {"kind": "dish", "sell": null, "rarity": 1, "quality": 1, "meal": 45, "full": 50}
	v.bag.slots.append({"id": "dish_grilled_crucian@good", "qty": 2})
	var s := P0ItemInfo.spec(v, "dish_grilled_crucian@good", &"bag")
	assert_str(str(s.title)).is_equal("Grilled Crucian")
	assert_object(s.icon).is_same(P0Logic.icon("dish_grilled_crucian"))
	assert_int(int(s.quality)).is_equal(1)
	assert_str(P0Logic.dish_label(v, "dish_grilled_crucian@good")).is_equal("Grilled Crucian ★")
	assert_str(P0Logic.item_name(v, "dish_grilled_crucian@perfect")).is_equal("Grilled Crucian")   # no names / items entry
	assert_str(P0Logic.item_name(v, "fish_unknown")).is_equal("fish_unknown")   # other ids as before
	assert_str(P0Logic.base_id("dish_grilled_crucian@good")).is_equal("dish_grilled_crucian")
	# the card's state line: the stars together, as dish_label (不知火舞 on #263)
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(336, 400)
	add_child(auto_free(host))
	var sheet := UiInfoSheet.new()
	host.add_child(sheet)
	sheet.rules = func(id: String, ctx: StringName, opts: Dictionary) -> Dictionary:
		return {id = id, title = "Herb Grilled Fish", rarity_text = "Fine", quality = 2, facts = [], buttons = []}
	sheet.open("dish_herb_grilled_fish@perfect", &"bag")
	assert_str(sheet._state.text).is_equal("Fine ★★")
