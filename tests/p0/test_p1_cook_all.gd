extends GdUnitTestSuite
## Cook All (Cooking Lv8; COOK-P1-4 / COOK-EMPTY, q(4) / q(124), SGODOT-282): the model read from the server's preview,
## the sheet, the Cookbook strip's button, and the kitchen's firing — the pots catch one stove after another and what
## they took floats once over the Cookbook.

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

func _plan(reason = null) -> Dictionary:
	if reason != null: return {"pots": [], "uses": [], "stoves": 0, "reason": reason}
	return {"pots": [
		{"dish": "dish_grilled_crucian", "rarity": 2, "stove": 0, "when": "now"},
		{"dish": "dish_radish_salad", "rarity": 1, "stove": 1, "when": "now"},
		{"dish": "dish_radish_salad", "rarity": 1, "stove": 0, "when": "next"}],
		"uses": [{"token": "fish_crucian", "need": 1, "have": 3}, {"token": "F1", "need": 2, "have": 4}],
		"stoves": 2, "reason": null}

func _view(plan = _plan()) -> Dictionary:
	return {
		"seq": 5,
		"energy": {"value": 120, "max": 200}, "bag": {"capacity": 25, "free": 18,
			"slots": [{"id": "fish_crucian", "qty": 3}, {"id": "crop_radish", "qty": 4}]},
		"skills": {"cooking": {"level": 8, "xp": 40, "floor": 30, "next": 100}, "farming": {"level": 1}, "fishing": {"level": 1}},
		"homestead": {"level": 6},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
		"items": {"fish_crucian": {"name": "Pond Crucian", "kind": "fish", "family": "W", "rarity": 1, "cook": true},
			"crop_radish": {"name": "Radish", "kind": "crop", "family": "F", "rarity": 1, "cook": true}},
		"names": {"fish_crucian": "Pond Crucian", "crop_radish": "Radish", "rock_salt": "Rock Salt", "dish_grilled_crucian": "Grilled Crucian",
			"dish_radish_salad": "Radish Salad"},
		"cooking": {"slots": 3, "stoves": [{}, {}, {}], "conveniences": ["cook_again", "queue_two", "cook_all"],
			"derive": [[1, 2, 3], [2, 3, 3], [3, 3, 4], [4, 4, 4]],
			"tiers": {"1": {"energy": 20, "ms": 5000}, "2": {"energy": 40, "ms": 15000}, "3": {"energy": 70, "ms": 30000}},
			"cook_all": plan,
			"cookbook": [{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "rarity": 2, "in": ["fish_crucian"], "known": true,
				"cooked": true, "can_cook": true, "slots": 1},
				{"id": "dish_radish_salad", "name": "Radish Salad", "rarity": 1, "in": ["F1"], "known": true,
				"cooked": true, "can_cook": true, "slots": 1}]},
	}

func _busy_view() -> Dictionary:
	var v := _view(_plan("no_space"))
	var pot := {"id": 1, "dish": "dish_radish_salad", "ms": 5000, "elapsed": 1000, "ready_in": 4000, "heats": []}
	v.cooking.stoves = [pot.merged({"queued": {"id": 2, "dish": "dish_radish_salad", "rarity": 1, "ms": 5000}}),
		pot.merged({"id": 3}, true).merged({"queued": {"id": 4, "dish": "dish_radish_salad", "rarity": 1, "ms": 5000}}),
		pot.merged({"id": 5}, true).merged({"queued": {"id": 6, "dish": "dish_radish_salad", "rarity": 1, "ms": 5000}})]
	return v

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
	return r

# ---------------------------------------------------------------- the model

func test_before_cooking_lv8_there_is_no_cook_all() -> void:
	var v := _view()
	v.cooking.erase("cook_all")
	assert_dict(P0KitchenLogic.cook_all(v)).is_empty()
	v.cooking["cook_all"] = null   # the server sends null before Lv8
	assert_dict(P0KitchenLogic.cook_all(v)).is_empty()

func test_the_plan_reads_the_servers_preview_in_firing_order() -> void:
	var m := P0KitchenLogic.cook_all(_view())
	assert_str(str(m.button)).is_equal("")
	assert_bool(m.empty).is_false()
	assert_array(m.rows.map(func(r): return [r.name, r.rarity_word, r.where])).is_equal([
		["Grilled Crucian", "Fine", "Stove 1 · now"], ["Radish Salad", "Common", "Stove 2 · now"],
		["Radish Salad", "Common", "Stove 1 · next"]])
	assert_str(str(m.body)).is_equal("3 pots on 2 stoves · ingredients come out of your Bag now")
	assert_str(str(m.label)).is_equal("Cook All · 3 pots")
	assert_str(str(m.rule)).is_equal("Rare → Fine → Common · up to 2 of a dish · no Legendary")

func test_uses_sum_the_slots_and_a_tag_reads_without_its_any() -> void:
	var m := P0KitchenLogic.cook_all(_view())
	assert_array(m.uses.map(func(u): return [u.name, u.have, u.need])).is_equal([["Pond Crucian", 3, 1], ["Common vegetable", 4, 2]])
	assert_object(m.uses[1].icon).is_same(UiItemCell.family_icon("F"))   # the family's icon, as the pot slots show it
	assert_object(m.uses[0].icon).is_not_null()

func test_nothing_to_cook_greys_the_button_with_the_gap() -> void:
	var m := P0KitchenLogic.cook_all(_view(_plan("nothing_to_cook")))
	assert_str(str(m.button)).is_equal("Nothing to cook")   # D-10 / LOCK-10: the gap on the button, no empty sheet
	assert_bool(m.empty).is_false()

func test_every_stove_and_queue_taken_is_the_empty_sheet() -> void:
	var m := P0KitchenLogic.cook_all(_busy_view())
	assert_str(str(m.button)).is_equal("")
	assert_bool(m.empty).is_true()
	assert_array(m.stoves.map(func(s): return [s.title, s.state, s.detail])).is_equal([
		["Stove 1", "Busy", "Queue full"], ["Stove 2", "Busy", "Queue full"], ["Stove 3", "Busy", "Queue full"]])
	assert_array(m.facts).is_equal([["Stoves", "3/3"], ["Queues", "3/3"]])

# ---------------------------------------------------------------- the sheet

func test_the_plan_sheet_lists_each_pot_its_uses_and_the_decision() -> void:
	var sheet: P0CookAllSheet = auto_free(P0CookAllSheet.new(P0KitchenLogic.cook_all(_view())))
	add_child(sheet)
	await get_tree().process_frame
	var rows := sheet.find_child("Plan", true, false)
	assert_int(rows.get_child_count()).is_equal(3)
	assert_str((rows.get_child(2).find_child("Where", true, false) as Label).text).is_equal("Stove 1 · next")
	var uses := sheet.find_child("Uses", true, false)
	assert_int(uses.find_children("*", "UiNeedTile", true, false).size()).is_equal(2)
	assert_str((sheet.find_child("Body", true, false) as Label).text).is_equal("3 pots on 2 stoves · ingredients come out of your Bag now")
	assert_str(sheet.cook_button.label).is_equal("Cook All · 3 pots")
	assert_float(sheet.height).is_less_equal(P0CookAllSheet.HEIGHT_MAX)
	assert_object(sheet.find_child("Details", true, false)).is_null()   # no Details › (不知火舞 on #289)
	var said: Array = []
	sheet.confirmed.connect(func(): said.append("confirmed"))
	sheet.cook_button.pressed.emit()
	assert_array(said).is_equal(["confirmed"])

func test_the_empty_sheet_shows_the_stoves_and_a_grey_all_stoves_busy() -> void:
	var sheet: P0CookAllSheet = auto_free(P0CookAllSheet.new(P0KitchenLogic.cook_all(_busy_view())))
	add_child(sheet)
	await get_tree().process_frame
	assert_object(sheet.cook_button).is_null()
	assert_int(sheet.find_child("Stoves", true, false).get_child_count()).is_equal(3)
	var busy: UiCommandButton = sheet.find_children("*", "UiCommandButton", true, false)[0]
	assert_str(busy.text).is_equal("All stoves busy")
	var said: Array = []
	sheet.unavailable.connect(func(r: String): said.append(r))
	sheet.back.connect(func(): said.append("back"))
	busy.pressed.emit()
	(sheet.find_children("*", "UiDismissButton", true, false)[0] as BaseButton).pressed.emit()   # `Kitchen`
	assert_array(said).is_equal(["All stoves busy", "back"])
	assert_object(sheet.find_child("Details", true, false)).is_null()

# ---------------------------------------------------------------- the strip and the firing

func test_the_cookbook_strip_shows_cook_all_from_lv8_and_greys_it_with_the_gap() -> void:
	var v := _view()
	v.cooking.erase("cook_all")
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook")
	assert_bool((k.drawer.get("_cook_all") as Control).visible).is_false()
	rt.ui.close_modal()
	await get_tree().process_frame
	_set_view(_view(_plan("nothing_to_cook")))
	k.open("cookbook")
	var button: UiCommandButton = k.drawer.get("_cook_all")
	assert_bool(button.visible).is_true()
	assert_str(button.text).is_equal("Nothing to cook")
	k.open_cook_all()   # greyed: no sheet (no empty sheet, LOCK-10)
	assert_object(k.cook_all_sheet).is_null()
	rt.ui.close_modal()
	await get_tree().process_frame

## B7 ⑨ (不知火舞 on 286 6e15f758): the Cookbook's filter row is all six chips — All · Can cook · Common · Fine · Rare ·
## Legendary, each whole on screen (2318:125476) — and Cook All is no longer at its right end.
func test_the_filter_row_keeps_all_six_chips_and_cook_all_is_off_it() -> void:
	var d := await _drawer(_view())
	var row := d.get("_book_chips") as Control
	var chips := row.find_children("*", "UiFilterChip", true, false)
	assert_array(chips.map(func(c): return (c as Button).text)).is_equal(["All", "Can cook", "Common", "Fine", "Rare", "Legendary"])
	var shown := (row.get_parent() as Control).get_global_rect()   # the chips' scroll window
	for c in chips:
		var r := (c as Control).get_global_rect()
		assert_bool(shown.grow(0.5).encloses(r)).override_failure_message("%s at %s outside %s" % [(c as Button).text, r, shown]).is_true()
	var cook_all := d.get("_cook_all") as Control
	assert_bool(cook_all.visible).is_true()
	assert_bool(row.get_parent().is_ancestor_of(cook_all)).is_false()

## The button stands on its own and moves where the frame puts it (不知火舞 on 286: A the heading by ×, B its own row on
## top of the Cookbook page); it is shown from Cooking Lv8 on the Cookbook only, greyed `Nothing to cook` in either place.
func test_cook_all_moves_between_the_heading_and_its_own_row() -> void:
	var d := await _drawer(_view())
	var cook_all := d.get("_cook_all") as UiCommandButton
	var close := d.find_children("*", "UiCloseButton", true, false)[0] as Control
	d.cook_all_at = P0KitchenDrawer.CookAllAt.HEADING
	for i in 2: await get_tree().process_frame
	assert_object(cook_all.get_parent()).is_same(close.get_parent())
	assert_int(cook_all.get_index()).is_equal(close.get_index() - 1)
	assert_bool(cook_all.is_visible_in_tree()).is_true()
	d.tab = "experiment"
	assert_bool(cook_all.is_visible_in_tree()).is_false()
	d.tab = "cookbook"
	d.cook_all_at = P0KitchenDrawer.CookAllAt.ROW
	for i in 2: await get_tree().process_frame
	assert_bool(d.get("_cookbook").is_ancestor_of(cook_all)).is_true()
	assert_float(cook_all.get_global_rect().end.y).is_less_equal((d.get("_titles") as Control).get_global_rect().position.y)
	d.view = _view(_plan("nothing_to_cook"))
	d.refresh()
	assert_str(cook_all.text).is_equal("Nothing to cook")
	assert_bool(cook_all.is_visible_in_tree()).is_true()
	var before := _view()
	before.cooking.erase("cook_all")
	d.view = before
	d.refresh()
	assert_bool(cook_all.is_visible_in_tree()).is_false()
	assert_bool((cook_all.get_parent() as Control).visible).is_false()   # no empty row left behind

func _drawer(v: Dictionary) -> P0KitchenDrawer:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var d := P0KitchenDrawer.new(v)
	d.animate = false
	host.add_child(d)
	for i in 3: await get_tree().process_frame
	return d

func test_cook_all_sends_closes_the_sheet_and_fires_the_pots_one_after_another() -> void:
	_set_view(_view())
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook")
	(k.drawer.get("_cook_all") as UiCommandButton).pressed.emit()
	assert_object(k.cook_all_sheet).is_not_null()
	k.cook_all_sheet.cook_button.pressed.emit()
	assert_array(sent.map(func(c): return c.type)).is_equal(["cook_all"])
	assert_bool(k.cook_all_pending).is_true()
	await get_tree().process_frame
	assert_bool(is_instance_valid(k.cook_all_sheet)).is_false()
	assert_str(k.phase).is_equal("compose")   # back on the Cookbook
	var after := _view()
	after.seq = 6
	after.cooking.stoves = [{"id": 7, "dish": "dish_grilled_crucian", "ms": 15000, "elapsed": 0, "ready_in": 15000, "heats": []},
		{"id": 8, "dish": "dish_radish_salad", "ms": 5000, "elapsed": 0, "ready_in": 5000, "heats": []}, {}]
	_set_view(after)
	var floats_before := rt.ui.root.find_children("*", "UiFloatText", true, false).size()
	rt.session.state_changed.emit(after, [
		{"kind": "item", "id": "fish_crucian", "delta": -1},
		{"kind": "pot", "id": 7, "dish": "dish_grilled_crucian", "rarity": 2, "ms": 15000, "stove": 0},
		{"kind": "item", "id": "crop_radish", "delta": -1},
		{"kind": "pot", "id": 8, "dish": "dish_radish_salad", "rarity": 1, "ms": 5000, "stove": 1},
		{"kind": "item", "id": "crop_radish", "delta": -1},
		{"kind": "item", "id": "rock_salt", "delta": -1, "from": "storage"},   # the Spice Rack's part is taken too
		{"kind": "pot", "id": 9, "dish": "dish_radish_salad", "rarity": 1, "ms": 5000, "stove": 0, "queued": true}])
	for i in 3: await get_tree().process_frame
	assert_bool(k.cook_all_pending).is_false()
	assert_str(k.phase).is_equal("compose")   # no watch, no card: the Cookbook stays
	assert_bool(rt.ui.has_modal()).is_true()
	var lines: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).slice(floats_before).map(func(f): return (f as UiFloatText).text)
	# one item group, what the pots took — the rack's Rock Salt too — two a line (q(124) ①)
	assert_array(lines).contains_exactly_in_any_order(["−1 Pond Crucian · −2 Radish", "−1 Rock Salt"])
	assert_bool(k.stage.is_cooking()).is_true()   # stove 1 (the working stove) caught at once
	await get_tree().create_timer(P0Kitchen.COOK_ALL_FIRE_S + 0.05).timeout   # stove 2 a beat later
	rt.ui.close_modal()
	await get_tree().process_frame

func test_a_refused_cook_all_clears_the_wait() -> void:
	_set_view(_view())
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook")
	k.open_cook_all()
	k.cook_all_sheet.cook_button.pressed.emit()
	assert_bool(k.cook_all_pending).is_true()
	r.p0_event({"kind": "refused", "code": "stove_busy", "cmd": {"type": "cook_all"}}, rt.session.view)
	assert_bool(k.cook_all_pending).is_false()
	rt.ui.close_modal()
	await get_tree().process_frame

func test_back_closes_the_sheet_first_then_the_drawer() -> void:
	_set_view(_view())
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook")
	k.open_cook_all()
	assert_object(k.cook_all_sheet).is_not_null()
	rt.ui.back_modal()
	await get_tree().process_frame
	assert_bool(is_instance_valid(k.cook_all_sheet)).is_false()
	assert_str(k.phase).is_equal("compose")   # the Cookbook is still open
	rt.ui.back_modal()
	await get_tree().process_frame
	assert_str(k.phase).is_equal("idle")

func test_a_single_cooks_ingredients_say_nothing_and_do_not_reach_the_result_card() -> void:
	_set_view(_view())
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	assert_bool(k.on_event({"kind": "item", "id": "crop_radish", "delta": -1})).is_false()
	assert_array(k.get("_events")).is_empty()

func test_the_drawer_heading_leaves_out_the_queue_and_drops_the_level_before_cutting_the_state() -> void:
	# 不知火舞 on #289: after Cook All the Cookbook stays on a stove that cooks with a pot queued behind it. The heading
	# reads `Stove 1/3 › · Cooking Lv8 · Cooking 0:12` (no `· Queued 1`), never cut short, never wider than the screen;
	# with the row still too long `Cooking Lv8` steps aside and the state stays.
	var v := _view()
	v.cooking.stoves = [{"id": 7, "dish": "dish_grilled_crucian", "ms": 15000, "elapsed": 3000, "ready_in": 12000, "heats": [],
		"queued": {"id": 9, "dish": "dish_radish_salad", "rarity": 1, "ms": 5000}}, {}, {}]
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook")
	await get_tree().process_frame
	var state: Label = k.drawer.get("_state")
	var level: Label = k.drawer.get("_level")
	assert_str(state.text).is_equal("Cooking 0:12")
	assert_bool(level.visible).is_true()
	assert_float(k.drawer.size.x).is_less_equal(rt.ui.root.size.x)
	assert_int(state.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	state.text = "Cooking 59:59 " + "x".repeat(400)   # a state that leaves no room for the level, whatever the window
	k.drawer.call("_fit_heading")
	assert_bool(level.visible).is_false()
	rt.ui.close_modal()
	await get_tree().process_frame
