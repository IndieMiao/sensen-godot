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
	# the whole dex: a full MomentBanner (283 DEX-COMPLETE) — the badge, its words, three pills, ≤ 3 s
	var full := P0FishDex.milestone_card(_view(20), "fishdex_20", "fish_snakehead", 50, 300, "Fish-dex complete")
	assert_that([full.banner, full.kind, full.title, full.subtitle, full.seconds]).is_equal([true, "complete", "Fish-dex complete", "20/20", 3.0])
	assert_array(full.rewards.map(func(r): return [r.text, r.tone])).is_equal([["+50 Energy", UiFloatText.Tone.ENERGY_GAIN],
		["+300 coins", UiFloatText.Tone.COINS], ["Badge", UiFloatText.Tone.ITEM]])
	assert_object(full.icon).is_same(P0FishDex.badge_icon())
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
	assert_object(_card()).is_null()   # not a RewardMoment: the full banner (283 DEX-COMPLETE)
	var b := rt.ui.root.find_children("*", "UiMomentBanner", true, false).front() as UiMomentBanner
	assert_that([b.kind, b.title, b.subtitle, b.action]).is_equal([UiMomentBanner.Kind.COMPLETE, "Fish-dex complete", "20/20", ""])
	assert_object(b.icon).is_same(P0FishDex.badge_icon())
	assert_int(b.rewards.size()).is_equal(3)
	assert_bool(_floats().any(func(t): return t.contains("+50 Energy") or t.contains("coins"))).is_false()   # on the banner only
	rt.ui.close_modal()
	await get_tree().process_frame

## Another reward's Energy (a first Fine fish) still floats: only the milestone's own is on its card.
func test_other_energy_still_floats() -> void:
	rt.session.state_changed.emit(_view(9), [{"kind": "energy", "delta": 20, "reason": "reward"}, {"kind": "reward", "id": "first_fish_2", "energy": 20}])
	for i in 3: await get_tree().process_frame
	assert_bool(_floats().any(func(t): return t.contains("+20 Energy"))).is_true()
	assert_object(_card()).is_null()

# ---------------------------------------------------------------- after the catch's own card (q(49); 苏烈 on #353)
class LandingWorld extends Node:   # a world that shows a landed fish itself (the pond's p0_event with its panel open)
	func p0_event(_ev: Dictionary, _v: Dictionary) -> bool: return true

const CATCH := {"kind": "catch", "fish": "fish_snakehead", "rarity": 1, "result": "landed", "refund": 0}

func _shown() -> Array:
	return rt.ui.root.find_children("*", "UiRewardMoment", true, false).filter(func(m): return not m.is_queued_for_deletion()) \
		.map(func(m): return str((m as UiRewardMoment).event))

## A rod's 10th kind: the card is held while the fish flies, and the pond's settle queues it after the Caught! card.
func test_a_rods_milestone_comes_after_its_caught_card() -> void:
	var v := _view(10)
	rt.session.view = v
	rt.ui.set_view(v)
	rt.world = auto_free(LandingWorld.new())
	rt._on_state(v, [CATCH, {"kind": "xp", "skill": "fishing", "amount": 2, "percent": 100}] + _events(10, 30, 100))
	for i in 3: await get_tree().process_frame
	assert_array(_shown()).is_empty()   # not while the fish is in the air
	assert_int(rt.catch_cards.size()).is_equal(1)
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_pond.gd\"\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc over_head() -> Vector2: return Vector2(180, 300)\n"
	stub.reload()
	var pond: Node3D = auto_free(Node3D.new())
	pond.set_script(stub)
	pond.rt = rt
	pond.cam = Camera3D.new()
	pond.add_child(pond.cam)
	pond.panel = auto_free(P0FishingPanel.new())
	pond.panel.visible = false
	add_child(pond)
	pond._settle(CATCH, 0.0, 10)   # the fish in the hand: floats, then the Caught! card CARD_AFTER_FLOATS_S on
	await get_tree().create_timer(pond.CARD_AFTER_FLOATS_S + 0.2).timeout
	assert_array(_shown()).is_equal(["Caught!"])
	assert_int(rt.ui._card_queue.size()).is_equal(1)   # the milestone waits its turn
	rt.ui.close_modal()
	for i in 3: await get_tree().process_frame
	assert_array(_shown()).is_equal(["Fish-dex 10/20"])
	rt.ui.close_modal()
	await get_tree().process_frame

## A trap's 10th kind: after its In your trap! card, which comes once the fish is in the creel.
func test_a_traps_milestone_comes_after_its_in_your_trap_card() -> void:
	var v := _view(10)
	rt.session.view = v
	rt.ui.set_view(v)
	rt._on_state(v, [{"kind": "item", "id": "fish_snakehead", "delta": 1}, {"kind": "xp", "skill": "fishing", "amount": 2, "percent": 100}] \
		+ _events(10, 30, 100) + [{"kind": "trap", "action": "collected", "place": "pond_san_francisco_03", "fish": 1, "left": 0}])
	for i in 3: await get_tree().process_frame
	assert_array(_shown()).is_empty()   # not before the trap's card
	await get_tree().create_timer(UiItemFly.FLIGHT_S + P0Runtime.TRAP_CARD_AFTER_S + 0.15).timeout
	assert_array(_shown()).is_equal(["In your trap!"])
	assert_int(rt.ui._card_queue.size()).is_equal(1)
	rt.ui.close_modal()
	for i in 3: await get_tree().process_frame
	assert_array(_shown()).is_equal(["Fish-dex 10/20"])
	rt.ui.close_modal()
	await get_tree().process_frame
