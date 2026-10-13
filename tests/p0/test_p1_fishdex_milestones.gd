extends GdUnitTestSuite
## Fish-dex milestones (§6.9.2, SGODOT-283; 不知火舞 on 283): at 10 kinds a RewardMoment Milestone `Fish-dex 10/20` over the
## kind that made it, `+30 Energy · +100 coins`; at 20 `Fish-dex complete` · `20/20` · `+50 Energy · +300 coins · Badge`.
## They come after the catch's own card (q(49)), and their Energy and coins are said there, not floated too.

var rt: P0Runtime

func before_test() -> void:
	rt = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.transport = func(_m: int, _p: String, _b: Dictionary, _c: Dictionary): pass
	rt.session.view = _view(10)

func _view(kinds: int) -> Dictionary:
	var dex := []
	for i in 20: dex.append({"id": "fish_k%d" % i, "rarity": 1, "level": 1, "caught": 1 if i < kinds else 0})
	return {"seq": 5, "energy": {"value": 120, "max": 200}, "coins": 50, "bag": {"capacity": 25, "free": 25, "slots": []},
		"skills": {"fishing": {"level": 3}, "farming": {"level": 1}, "cooking": {"level": 1}},
		"names": {"fish_snakehead": "Snakehead"}, "fishing": {"dex": dex}}

func _events(n: int, energy: int, coins: int, badge := "") -> Array:
	return [{"kind": "first", "what": "catch:fish_snakehead", "xp": 10},
		{"kind": "energy", "delta": energy, "reason": "reward"}, {"kind": "reward", "id": "fishdex_%d" % n, "energy": energy},
		{"kind": "coins", "delta": coins},
		{"kind": "milestone", "id": "fishdex_%d" % n, "title": badge, "coins": coins, "cabinet": 0, "decor": null}]

func _floats() -> Array:
	return rt.ui.root.find_children("*", "UiFloatText", true, false).map(func(f): return str((f as UiFloatText).text))

func _card() -> UiRewardMoment:
	var cards := rt.ui.root.find_children("*", "UiRewardMoment", true, false)
	return cards[0] if not cards.is_empty() else null

func test_the_card_words() -> void:
	var v := _view(10)
	assert_dict(P0FishDex.milestone_card(v, "fishdex_10", "fish_snakehead", 30, 100, "")).is_equal(
		{event = "Fish-dex 10/20", item_name = "Snakehead", icon = "fish_snakehead", strip = "+30 Energy · +100 coins"})
	assert_dict(P0FishDex.milestone_card(_view(20), "fishdex_20", "fish_snakehead", 50, 300, "Fish-dex complete")).is_equal(
		{event = "Fish-dex complete", item_name = "20/20", icon = "star", strip = "+50 Energy · +300 coins · Badge"})
	assert_str(str(P0FishDex.milestone_card(v, "fishdex_10", "fish_snakehead", 0, 100, "").strip)).is_equal("+100 coins")   # Energy capped out
	assert_dict(P0FishDex.milestone_card(v, "line_cook", "", 0, 100, "")).is_empty()

func test_ten_kinds_show_their_card_and_float_no_energy_or_coins() -> void:
	rt.session.state_changed.emit(_view(10), _events(10, 30, 100))
	for i in 3: await get_tree().process_frame
	assert_bool(_floats().any(func(t): return t.contains("+30 Energy") or t.contains("coins"))).is_false()
	var m := _card()
	assert_object(m).is_not_null()
	assert_that([m.tone, m.event, m.item_name, m.strip]).is_equal([UiRewardMoment.Tone.MILESTONE, "Fish-dex 10/20", "Snakehead",
		"+30 Energy · +100 coins"])
	rt.ui.close_modal()
	await get_tree().process_frame

func test_twenty_kinds_say_complete_with_the_badge() -> void:
	rt.session.state_changed.emit(_view(20), _events(20, 50, 300, "Fish-dex complete"))
	for i in 3: await get_tree().process_frame
	var m := _card()
	assert_that([m.event, m.item_name, m.strip]).is_equal(["Fish-dex complete", "20/20", "+50 Energy · +300 coins · Badge"])
	rt.ui.close_modal()
	await get_tree().process_frame

## Another reward's Energy (a first Fine fish) still floats: only the milestone's own is on its card.
func test_other_energy_still_floats() -> void:
	rt.session.state_changed.emit(_view(9), [{"kind": "energy", "delta": 20, "reason": "reward"}, {"kind": "reward", "id": "first_fish_2", "energy": 20}])
	for i in 3: await get_tree().process_frame
	assert_bool(_floats().any(func(t): return t.contains("+20 Energy"))).is_true()
	assert_object(_card()).is_null()
