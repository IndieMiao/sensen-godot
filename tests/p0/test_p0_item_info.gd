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

func test_seed_in_the_bag_pins_and_stores_only_at_home() -> void:
	var s := P0ItemInfo.spec(_view(), "seed_radish", &"bag", {place = "home"})
	assert_array(s.facts).is_equal(["2 Energy per plot · Ready in 4h 0m"])
	assert_array(_labels(s)).is_equal(["secondary:Pin", "secondary:Store"])   # no primary button
	s = P0ItemInfo.spec(_view(), "seed_radish", &"bag", {place = "pond", pinned = true})
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
	var v := _view()
	v["shops"] = {"market": {"accepts": ["crop", "fish"], "mult": 0.8,
		"quotas": {"crop": {"label": "", "used": 55, "cap": 60, "resets_in": 33120000, "scope": "all Shanghai markets"}}}}
	var s := P0ItemInfo.spec(v, "crop_radish", &"counter_sell", {counter = "market"})
	assert_array(_labels(s)).is_equal(["secondary:Sell", "primary:Sell 5 · 20 coins"])
	assert_str(s.quota.text).is_equal("Buy-back today 55/60")
	assert_str(s.quota.note).is_equal("all Shanghai markets · resets in 9h 12m")
	v.shops.market.quotas.crop.used = 60
	s = P0ItemInfo.spec(v, "crop_radish", &"counter_sell", {counter = "market"})
	assert_array(_labels(s)).is_equal(["unavailable:Limit reached · 9h 12m"])

func test_locked_stack_shows_locked_and_unlock_only() -> void:
	var v := _view()
	v.bag.slots[1]["locked"] = true
	var s := P0ItemInfo.spec(v, "crop_radish", &"counter_sell")
	assert_array(_labels(s)).is_equal(["unavailable:Locked", "secondary:Unlock"])
	assert_bool(s.lock.locked).is_true()
	assert_str(s.badge).is_equal("locked")   # Locked wins over Pinned

func test_fish_gift_is_grey_without_mutual_friends() -> void:
	var s := P0ItemInfo.spec(_view(), "fish_crucian", &"bag")
	assert_array(_labels(s)).is_equal(["unavailable:Gift · Mutual friends only"])
	assert_array(s.facts).is_equal(["Common", "3", "Sells for 6 · Fish-dex 1/2"])
	var v := _view()
	v["social"] = {"mutual": 2}
	assert_array(_labels(P0ItemInfo.spec(v, "fish_crucian", &"bag"))).is_equal(["nav:Gift ›"])

func test_dish_eats_and_deliver_takes_the_primary_slot() -> void:
	var s := P0ItemInfo.spec(_view(), "dish_grilled_crucian", &"bag")
	assert_array(_labels(s)).is_equal(["primary:Eat · +45 Energy", "nav:Gift ›"])
	assert_str(s.facts[0]).is_equal("Common ★")
	var v := _view()
	v.energy.value = 200
	assert_array(_labels(P0ItemInfo.spec(v, "dish_grilled_crucian", &"bag"))).is_equal(["unavailable:Energy full", "nav:Gift ›"])

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

func test_rods_in_gear_equip_or_show_equipped() -> void:
	assert_array(_labels(P0ItemInfo.spec(_view(), "rod_starter", &"gear"))).is_equal(["unavailable:✓ Equipped"])
	var s := P0ItemInfo.spec(_view(), "rod_reed", &"gear")
	assert_array(_labels(s)).is_empty()
	assert_array(s.facts).is_equal(["Lands up to Rare fish · Bite window +0.4 s", "Fishing Lv3 · Tackle Shop"])

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
