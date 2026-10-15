extends GdUnitTestSuite
## The recipe card in the kitchen (q(200) Batch Cook / q(201) Big Pot, row 99; SGODOT-282): the stepper and the Big Pot
## key on the card, what Cook sends (cook or batch_cook), the Rare / Legendary confirm, a batch's pots catching one
## after another, the pot card's ×N and servings tag, the filter row's six chips (B7 ⑨).

const FARMHOUSE := preload("res://scenes/p0/rooms/p0_farmhouse.gd")

var rt: P0Runtime
var sent: Array = []

func before_test() -> void:
	sent = []
	rt = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.transport = func(_method: int, _path: String, _body: Dictionary, cmd: Dictionary): sent.append(cmd)
	rt.session.view = _view()

func _page(id: String, name: String, rarity: int, tokens: Array, picks: Array, saved := {}) -> Dictionary:
	return {"id": id, "name": name, "rarity": rarity, "in": tokens, "known": true, "cooked": true, "can_cook": not picks.is_empty(),
		"slots": tokens.size(), "picks": picks, "saved": saved, "today": 0}

func _view(cooking_lv := 8, home := 6) -> Dictionary:
	return {
		"seq": 5,
		"energy": {"value": 120, "max": 200}, "bag": {"capacity": 25, "free": 18,
			"slots": [{"id": "fish_crucian", "qty": 5}, {"id": "fish_bass", "qty": 3}, {"id": "rock_salt", "qty": 3}]},
		"skills": {"cooking": {"level": cooking_lv, "xp": 40, "floor": 30, "next": 100}, "farming": {"level": 1}, "fishing": {"level": 1}},
		"homestead": {"level": home},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
		"items": {"fish_crucian": {"name": "Pond Crucian", "kind": "fish", "family": "W", "rarity": 1, "cook": true},
			"fish_bass": {"name": "Sea Bass", "kind": "fish", "family": "W", "rarity": 3, "cook": true},
			"rock_salt": {"name": "Rock Salt", "kind": "mineral", "family": "S", "rarity": 1, "cook": true}},
		"names": {"fish_crucian": "Pond Crucian", "fish_bass": "Sea Bass", "rock_salt": "Rock Salt",
			"dish_grilled_crucian": "Grilled Crucian", "dish_sea_bass_salt": "Sea Bass in Salt"},
		"cooking": {"slots": 3, "stoves": [{}, {}, {}], "big_pot": home >= 6, "batch": {"room": 6} if cooking_lv >= 8 else null,
			"conveniences": ["cook_again", "queue_two"] + (["batch_cook"] if cooking_lv >= 8 else []),
			"derive": [[1, 2, 3], [2, 3, 3], [3, 3, 4], [4, 4, 4]],
			"tiers": {"1": {"energy": 20, "ms": 5000}, "2": {"energy": 40, "ms": 15000}, "3": {"energy": 45, "ms": 30000}},
			"cookbook": [
				_page("dish_grilled_crucian", "Grilled Crucian", 1, ["fish_crucian"], [["fish_crucian"], ["fish_crucian"], ["fish_crucian"], ["fish_crucian"], ["fish_crucian"]]),
				_page("dish_sea_bass_salt", "Sea Bass in Salt", 3, ["fish_bass", "rock_salt"], [["fish_bass", "rock_salt"], ["fish_bass", "rock_salt"], ["fish_bass", "rock_salt"]])]},
	}

func _set_view(v: Dictionary) -> void:
	rt.session.view = v
	rt.session.set("_received_ms", Time.get_ticks_msec())

func _farmhouse() -> P0Room:
	var r: P0Room = FARMHOUSE.new()
	r.use_runtime = false
	add_child(r)
	auto_free(r)
	r.rt = rt
	rt.attach(r)
	await get_tree().process_frame
	var k: P0Kitchen = r.get("kitchen")
	k.persist_big = false   # nothing written to user:// here
	return r

func _open(page := "dish_grilled_crucian") -> P0Kitchen:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook", page)
	await get_tree().process_frame
	return k

func _close() -> void:
	rt.ui.close_modal()
	await get_tree().process_frame

# ---------------------------------------------------------------- the card

## B7 ⑨: the Cookbook's filter row is all six chips, each whole on screen (2318:125476).
func test_the_filter_row_keeps_all_six_chips() -> void:
	var k := await _open()
	var row := k.drawer.get("_book_chips") as Control
	var chips := row.find_children("*", "UiFilterChip", true, false)
	assert_array(chips.map(func(c): return (c as Button).text)).is_equal(["All", "Can cook", "Common", "Fine", "Rare", "Legendary"])
	var shown := (row.get_parent() as Control).get_global_rect()
	for c in chips:
		assert_bool(shown.grow(0.5).encloses((c as Control).get_global_rect())).override_failure_message((c as Button).text).is_true()
	await _close()

## S1 / S6 / S7b / S7: the stepper from Cooking Lv8, the Big Pot key from Homestead Lv6, each on its own; Cook stays put.
func test_the_stepper_and_the_key_come_each_with_their_own_level() -> void:
	for c in [[8, 6, true, true], [7, 6, false, true], [8, 5, true, false], [7, 5, false, false]]:
		_set_view(_view(c[0], c[1]))
		var k := await _open()
		var stepper := k.drawer.get("_stepper") as Control
		var key := k.drawer.get("_book_key") as Control
		var cook := k.drawer.get("_recipe_button") as Control
		assert_that([stepper.visible, key.visible]).override_failure_message(str(c)).is_equal([c[2], c[3]])
		assert_that(Rect2(cook.position, cook.size)).is_equal(Rect2(256, 59, 68, 44))
		await _close()

## q(200): + to 3 pots and Cook sends batch_cook from this stove; the pots catch one after another, this stove's pot is
## watched, and what the batch took floats once as one item group.
func test_a_batch_sends_batch_cook_and_its_pots_catch_one_after_another() -> void:
	var k := await _open()
	k.drawer.dev_batch(3)
	assert_int(k.drawer.batch_n).is_equal(3)
	assert_array(k.get("_pot_card").slots().map(func(s): return (s as UiPotSlot).quantity)).is_equal(["×3"])
	k.drawer.dev_cook()
	assert_array(sent).is_equal([{"type": "batch_cook", "recipe": "dish_grilled_crucian", "pots": 3, "stove": 0, "big": []}])
	assert_bool(k.batch_pending).is_true()
	var after := _view()
	after.seq = 6
	after.cooking.stoves = [{"id": 7, "dish": "dish_grilled_crucian", "ms": 5000, "elapsed": 0, "ready_in": 5000, "heats": []},
		{"id": 8, "dish": "dish_grilled_crucian", "ms": 5000, "elapsed": 0, "ready_in": 5000, "heats": []},
		{"id": 9, "dish": "dish_grilled_crucian", "ms": 5000, "elapsed": 0, "ready_in": 5000, "heats": []}]
	_set_view(after)
	var floats_before := rt.ui.root.find_children("*", "UiFloatText", true, false).size()
	rt.session.state_changed.emit(after, [
		{"kind": "item", "id": "fish_crucian", "delta": -1}, {"kind": "pot", "id": 7, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "stove": 0},
		{"kind": "item", "id": "fish_crucian", "delta": -1}, {"kind": "pot", "id": 8, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "stove": 1},
		{"kind": "item", "id": "fish_crucian", "delta": -1}, {"kind": "pot", "id": 9, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "stove": 2}])
	for i in 3: await get_tree().process_frame
	assert_bool(k.batch_pending).is_false()
	assert_str(k.phase).is_equal("watch")   # this stove's pot, watched as a Cook's
	var lines: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).slice(floats_before).map(func(f): return (f as UiFloatText).text)
	assert_array(lines).contains(["−3 Pond Crucian"])
	k.stop_watching()
	await get_tree().process_frame

func test_a_refused_batch_gives_cook_back() -> void:
	var k := await _open()
	k.drawer.dev_batch(2)
	k.drawer.dev_cook()
	assert_bool(k.batch_pending).is_true()
	(k.room as P0Room).p0_event({"kind": "refused", "code": "no_room", "cmd": {"type": "batch_cook"}}, rt.session.view)
	assert_bool(k.batch_pending).is_false()
	assert_bool(k.get("_cook_sent")).is_false()
	await _close()

## q(200) ⑤: + at its limit says what stops one more pot.
func test_the_stepper_at_its_limit_says_why() -> void:
	var said: Array = []
	var k := await _open()
	k.drawer.unavailable.connect(func(t: String): said.append(t))
	k.drawer.dev_batch(9)
	assert_int(k.drawer.batch_n).is_equal(5)
	assert_array(said).contains(["Ingredients for 5" + P0KitchenLogic.NBSP + "pots"])
	await _close()

# ---------------------------------------------------------------- the Big Pot (q(201))

## The key switches the current stove: kept by the kitchen, the next cook asks for double, the pot card says
## `2 servings` and its slot ×2, and the stove's name strip reads Big Pot while it is empty.
func test_the_big_pot_key_switches_this_stove() -> void:
	var k := await _open()
	assert_bool(k.drawer.big_pot_key().on).is_false()
	k.drawer.dev_big_pot()
	assert_array(k.big_stoves).is_equal([0])
	assert_bool(k.drawer.big_pot_key().on).is_true()
	var card: UiPotCard = k.get("_pot_card")
	assert_str(card.tag).is_equal("2" + P0KitchenLogic.NBSP + "servings")
	assert_array(card.slots().map(func(s): return (s as UiPotSlot).quantity)).is_equal(["×2"])
	assert_str(str(FARMHOUSE.stove_marker(rt.session.current(), 0, true).fact)).is_equal("Big Pot")
	assert_str(str(FARMHOUSE.stove_marker(rt.session.current(), 1, false).fact)).is_equal("Empty")
	k.drawer.dev_cook()
	assert_array(sent).is_equal([{"type": "cook", "recipe": "dish_grilled_crucian", "stove": 0, "double": true}])
	await _close()

## S8: picking what to queue on a Big Pot stove that cooks, the pot card's corner reads `Big Pot`, not a count.
func test_a_cooking_big_pot_stove_reads_big_pot_on_the_pot_card() -> void:
	var v := _view()
	v.cooking.stoves = [{"id": 7, "dish": "dish_grilled_crucian", "ms": 5000, "elapsed": 0, "ready_in": 5000, "heats": []}, {}, {}]
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.big_stoves = [0]
	k.set("_big_loaded", true)
	k.open("cookbook", "dish_grilled_crucian")
	await get_tree().process_frame
	assert_str((k.get("_pot_card") as UiPotCard).tag).is_equal("Big Pot")
	await _close()

## Picking what to queue (Queue next ›) on a cooking stove: the grey key's toast is up on screen.
func test_the_grey_key_toast_shows_while_picking_what_to_queue() -> void:
	var v := _view()
	var pot := {"id": 7, "dish": "dish_grilled_crucian", "ms": 60000, "elapsed": 1000, "ready_in": 59000, "heats": []}
	v.cooking.stoves = [pot, {}, {}]
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(pot)
	await get_tree().process_frame
	k.open_queue()
	await get_tree().process_frame
	assert_str(k.phase).is_equal("compose")
	k.drawer.select_page("dish_grilled_crucian")
	k.drawer.dev_big_pot()
	for i in 3: await get_tree().process_frame
	assert_str(rt.ui.toast_text()).is_equal("Swap pots when the stove is empty")
	await _close()

## Greyed while this stove is cooking; a tap says so and never flips it.
func test_the_key_greys_while_the_stove_cooks() -> void:
	var v := _view()
	v.cooking.stoves = [{"id": 7, "dish": "dish_grilled_crucian", "ms": 5000, "elapsed": 0, "ready_in": 5000, "heats": []}, {}, {}]
	_set_view(v)
	var said: Array = []
	var k := await _open()
	k.drawer.unavailable.connect(func(t: String): said.append(t))
	var key := k.drawer.get("_book_key") as UiBigPotKey
	assert_that([key.visible, key.enabled]).is_equal([true, false])
	key.press()
	assert_array(said).is_equal(["Swap pots when the stove is empty"])
	assert_bool(key.on).is_false()
	await _close()

# ---------------------------------------------------------------- the Rare / Legendary confirm (§7.2, q(200) ⑦)

func test_a_rare_ingredient_asks_first_and_a_batch_says_what_it_uses() -> void:
	var k := await _open("dish_sea_bass_salt")
	k.drawer.dev_cook()
	assert_array(sent).is_empty()
	assert_object(k.confirm_sheet).is_not_null()
	assert_str((k.confirm_sheet.find_child("Title", true, false) as Label).text).is_equal("Cook with Sea Bass?")
	assert_object(k.confirm_sheet.find_child("Line", true, false)).is_null()   # one pot: no line
	assert_str(k.confirm_sheet.cook_button.text).is_equal("Cook")
	rt.ui.back_modal()   # Back closes the confirm first, the card stays
	await get_tree().process_frame
	assert_bool(is_instance_valid(k.confirm_sheet)).is_false()
	assert_str(k.phase).is_equal("compose")
	k.drawer.dev_batch(3)
	k.drawer.dev_cook()
	assert_str((k.confirm_sheet.find_child("Line", true, false) as Label).text).is_equal(
		"Uses Sea Bass ×3 and Rock Salt ×3 for 3" + P0KitchenLogic.NBSP + "pots.")
	assert_str(k.confirm_sheet.cook_button.text).is_equal("Cook · 3" + P0KitchenLogic.NBSP + "pots")
	k.confirm_sheet.cook_button.activated.emit()
	assert_array(sent.map(func(c): return [c.type, c.get("pots", 1)])).is_equal([["batch_cook", 3]])
	await _close()

func test_a_common_cook_asks_nothing() -> void:
	var k := await _open()
	k.drawer.dev_cook()
	assert_object(k.confirm_sheet).is_null()
	assert_array(sent.map(func(c): return c.type)).is_equal(["cook"])
	await _close()
