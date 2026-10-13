extends GdUnitTestSuite
## Cookbook titles (§7.6.1, SGODOT-282; 不知火舞 on 282): Home Cook (the P0 reward cookbook_8) and the milestones Line Cook
## / Head Chef / Master Chef / Muscle Memory each get a RewardMoment Milestone card after the dish card — the title,
## how far the Cookbook is, `New title · …` with what came with it — and their Energy or coins are said there, not
## floated too. The Cookbook's title strip and the Muscle Memory line are the view's counts.

const FARMHOUSE := preload("res://scenes/p0/rooms/p0_farmhouse.gd")

var rt: P0Runtime

func before_test() -> void:
	rt = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.transport = func(_m: int, _p: String, _b: Dictionary, _c: Dictionary): pass
	rt.session.view = _view()

func _milestones(reached := []) -> Array:
	return [{"id": "line_cook", "title": "Line Cook", "counts": "discovered", "need": 20, "reached": "line_cook" in reached},
		{"id": "head_chef", "title": "Head Chef", "counts": "discovered", "need": 36, "reached": "head_chef" in reached},
		{"id": "master_chef", "title": "Master Chef", "counts": "discovered", "need": 48, "reached": "master_chef" in reached},
		{"id": "muscle_memory", "title": "Muscle Memory", "counts": "mastered", "need": 10, "reached": "muscle_memory" in reached}]

func _view(discovered := 8, mastered := 2, reached := []) -> Dictionary:
	return {
		"seq": 5, "energy": {"value": 120, "max": 200}, "coins": 50,
		"bag": {"capacity": 25, "free": 24, "slots": [{"id": "fish_crucian", "qty": 1}]},
		"skills": {"cooking": {"level": 2, "xp": 40}, "farming": {"level": 1}, "fishing": {"level": 1}},
		"homestead": {"level": 1}, "rarity_names": ["Common", "Fine", "Rare", "Legendary"],
		"names": {"fish_crucian": "Pond Crucian", "dish_grilled_crucian": "Grilled Crucian"},
		"items": {"fish_crucian": {"name": "Pond Crucian", "kind": "fish", "family": "W", "rarity": 1, "cook": true}},
		"cooking": {"slots": 2, "stove": null, "conveniences": [], "derive": [[1, 2, 3]],
			"tiers": {"1": {"energy": 20, "ms": 5000}}, "pages_total": 48, "discovered": discovered, "mastered_count": mastered,
			"milestones": _milestones(reached),
			"cookbook": [{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "rarity": 1, "in": ["fish_crucian"], "known": true,
				"cooked": true, "can_cook": true, "slots": 1}]},
	}

func _farmhouse() -> P0Room:
	var r: P0Room = FARMHOUSE.new()
	r.use_runtime = false
	add_child(r)
	auto_free(r)
	r.rt = rt
	rt.attach(r)
	await get_tree().process_frame
	return r

func _dish() -> Dictionary:
	return {"kind": "dish", "pot": 3, "dish": "dish_grilled_crucian", "quality": 0, "qty": 1, "first": true, "mystery": false, "hits": 0}

# ---------------------------------------------------------------- the cards' words

func test_each_title_card_says_its_count_and_what_came_with_it() -> void:
	var v := _view()
	var home := P0KitchenLogic.title_card(v, {"kind": "reward", "id": "cookbook_8", "energy": 50})
	assert_that([home.event, home.item_name, home.strip]).is_equal(["Home Cook", "Cookbook 8/48", "New title · +50 Energy"])
	var line := P0KitchenLogic.title_card(v, {"kind": "milestone", "id": "line_cook", "title": "Line Cook", "coins": 100, "cabinet": 0,
		"decor": "recipe_stand"})
	assert_that([line.event, line.item_name, line.strip]).is_equal(["Line Cook", "Cookbook 20/48", "New title · +100 coins · Recipe Stand"])
	var head := P0KitchenLogic.title_card(v, {"kind": "milestone", "id": "head_chef", "title": "Head Chef", "coins": 0, "cabinet": 4, "decor": null})
	assert_that([head.item_name, head.strip]).is_equal(["Cookbook 36/48", "New title · Warming Cabinet +4"])
	var master := P0KitchenLogic.title_card(v, {"kind": "milestone", "id": "master_chef", "title": "Master Chef", "coins": 0, "cabinet": 0, "decor": null})
	assert_that([master.item_name, master.strip]).is_equal(["Cookbook 48/48", "New title · Gold frame"])
	var muscle := P0KitchenLogic.title_card(v, {"kind": "milestone", "id": "muscle_memory", "title": "Muscle Memory", "coins": 0, "cabinet": 0, "decor": null})
	assert_that([muscle.event, muscle.item_name, muscle.strip]).is_equal(["Muscle Memory", "Mastered 10", "New title"])
	# not the Cookbook's: other one-time rewards and the Fish-dex's milestones
	assert_dict(P0KitchenLogic.title_card(v, {"kind": "reward", "id": "first_dish_1", "energy": 10})).is_empty()
	assert_dict(P0KitchenLogic.title_card(v, {"kind": "milestone", "id": "fishdex_10", "title": "", "coins": 100})).is_empty()

func test_the_title_strip_marks_reached_the_next_with_its_count_and_the_rest_later() -> void:
	var strip := P0KitchenLogic.title_strip(_view(12, 2))
	assert_array(strip.map(func(t): return [t.title, t.state])).is_equal([["Home Cook", "reached"], ["Line Cook", "next"],
		["Head Chef", "later"], ["Master Chef", "later"]])   # Muscle Memory is not on this line (its own axis)
	assert_that([strip[1].have, strip[1].need]).is_equal([12, 20])
	assert_str(P0KitchenLogic.title_strip(_view(5, 0))[0].state).is_equal("next")
	assert_str(P0KitchenLogic.muscle_line(_view(12, 6))).is_equal("Muscle Memory 6/10")
	assert_str(P0KitchenLogic.muscle_line(_view(12, 10, ["muscle_memory"]))).is_equal("")

# ---------------------------------------------------------------- after the dish card, said once

func test_home_cook_comes_after_the_dish_card_and_its_energy_is_not_floated_too() -> void:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.phase = "serve"
	rt.session.state_changed.emit(rt.session.view, [_dish(), {"kind": "energy", "delta": 50, "reason": "reward"},
		{"kind": "reward", "id": "cookbook_8", "energy": 50}])
	for i in 3: await get_tree().process_frame
	assert_str(rt.ui.modal_kind).is_equal("kitchen_card")   # the dish first
	assert_int(rt.ui._card_queue.size()).is_equal(1)
	var floats: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).map(func(f): return (f as UiFloatText).text)
	assert_bool(floats.any(func(t): return str(t).contains("+50 Energy"))).is_false()
	rt.ui.close_modal()   # Keep
	for i in 2: await get_tree().process_frame
	var cards := rt.ui.root.find_children("*", "UiRewardMoment", true, false)
	assert_int(cards.size()).is_equal(1)
	var m := cards[0] as UiRewardMoment
	assert_that([m.tone, m.event, m.item_name, m.strip]).is_equal([UiRewardMoment.Tone.MILESTONE, "Home Cook", "Cookbook 8/48",
		"New title · +50 Energy"])
	rt.ui.close_modal()
	await get_tree().process_frame

## At the Energy cap grantOnce gives Home Cook nothing and puts no Energy of its own: the Energy just before it is another's
## (a meal eaten in the same reply) and still floats (刘邦 on #357).
func test_at_the_cap_another_energy_before_home_cook_still_floats() -> void:
	var r := await _farmhouse()
	r.get("kitchen").phase = "serve"
	rt.session.state_changed.emit(rt.session.view, [_dish(), {"kind": "energy", "delta": 30, "reason": "eat"},
		{"kind": "reward", "id": "cookbook_8", "energy": 0}])
	for i in 3: await get_tree().process_frame
	var floats: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).map(func(f): return (f as UiFloatText).text)
	assert_bool(floats.any(func(t): return str(t).contains("+30 Energy"))).is_true()
	rt.ui.close_modal()
	await get_tree().process_frame

func test_line_cooks_coins_are_on_its_card_not_floated() -> void:
	var r := await _farmhouse()
	r.get("kitchen").phase = "serve"
	rt.session.state_changed.emit(_view(20), [_dish(), {"kind": "coins", "delta": 100},
		{"kind": "milestone", "id": "line_cook", "title": "Line Cook", "coins": 100, "cabinet": 0, "decor": "recipe_stand"}])
	for i in 3: await get_tree().process_frame
	var floats: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).map(func(f): return (f as UiFloatText).text)
	assert_bool(floats.any(func(t): return str(t).contains("coins"))).is_false()
	assert_int(rt.ui._card_queue.size()).is_equal(1)   # Line Cook waits behind the dish card
	rt.ui.close_modal()
	await get_tree().process_frame

func test_a_fish_dex_milestone_is_left_to_its_own_handler() -> void:
	rt.session.state_changed.emit(rt.session.view, [{"kind": "milestone", "id": "fishdex_10", "title": "", "coins": 0, "cabinet": 0, "decor": null}])
	for i in 2: await get_tree().process_frame
	# no Cookbook card for it: SGODOT-283's own Fish-dex card (test_p1_fishdex_milestones.gd)
	var cards := rt.ui.root.find_children("*", "UiRewardMoment", true, false)
	assert_bool(cards.all(func(m): return str((m as UiRewardMoment).event).begins_with("Fish-dex"))).is_true()
	rt.ui.close_modal()
	await get_tree().process_frame
