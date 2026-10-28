extends GdUnitTestSuite
## q(245)–q(247): independent sale-only crops, shared countdown formatting and actual Homestead Energy rewards.
const FAST := [
	{id = "crop_cress", name = "Cress", seed = "seed_cress", seed_name = "Cress Seeds", farming = 1, grow_s = 10, seed_price = 1, price = 1, energy = 2, xp = 2, first_xp = 10},
	{id = "crop_pea_shoots", name = "Pea Shoots", seed = "seed_pea_shoots", seed_name = "Pea Shoots Seeds", farming = 1, grow_s = 60, seed_price = 2, price = 3, energy = 2, xp = 2, first_xp = 10},
	{id = "crop_spinach", name = "Baby Spinach", seed = "seed_spinach", seed_name = "Baby Spinach Seeds", farming = 2, grow_s = 300, seed_price = 2, price = 3, energy = 2, xp = 2, first_xp = 10},
	{id = "crop_scallion", name = "Scallion", seed = "seed_scallion", seed_name = "Scallion Seeds", farming = 2, grow_s = 1200, seed_price = 3, price = 4, energy = 2, xp = 2, first_xp = 10},
	{id = "crop_bok_choy", name = "Bok Choy", seed = "seed_bok_choy", seed_name = "Bok Choy Seeds", farming = 3, grow_s = 3600, seed_price = 3, price = 4, energy = 2, xp = 2, first_xp = 10},
]

static func view(plots: Array = []) -> Dictionary:
	var v := {fast_crops = FAST.duplicate(true), crops = [], names = {}, items = {}, plots = plots,
		bag = {capacity = 25, slots = []}, energy = {value = 200, max = 200}, garden = {plots = 30}, coins = 100,
		skills = {farming = {level = 3}}, residents = {}, storage = {items = []}, firsts = ["harvest:crop_radish"]}
	for c in FAST:
		v.items[c.id] = {kind = "crop", sell = c.price, cook = false}
		v.items[c.seed] = {kind = "seed"}
		v.bag.slots.append({id = c.id, qty = 3})
		v.bag.slots.append({id = c.seed, qty = 3})
	return v

func test_five_crops_have_names_seed_costs_icons_and_static_duration_without_joining_normal_crops() -> void:
	var v := view()
	var times := ["10s", "1m", "5m", "20m", "1h"]
	for i in FAST.size():
		var c: Dictionary = FAST[i]
		assert_str(P0Logic.item_name(v, c.id)).is_equal(c.name)
		assert_str(P0Logic.item_name(v, c.seed)).is_equal(c.seed_name)
		assert_dict(P0Logic.crop(v, c.id)).is_equal(c)
		assert_dict(P0Logic.crop_for_seed(v, c.seed)).is_equal(c)
		assert_dict(P0Logic.quick_seed(v, c.id)).is_empty()   # not guide-only teaching seeds
		assert_object(P0Logic.icon(c.id)).is_not_null()
		assert_object(P0Logic.icon(c.seed)).is_not_null()
		assert_str(P0Logic.icon(c.id).resource_path).is_equal("res://assets/p0/icons/" + c.id + ".svg")
		assert_str(P0ItemInfo.grow_time(c)).is_equal(times[i])
		assert_array(P0ItemInfo.spec(v, c.seed, &"bag", {place = "home"}).facts).contains(["2 Energy per plot · Ready in " + times[i]])
		var action := P0Logic.main_action(v, {id = 0, state = "tilled"}, c.seed)
		assert_int(action.need).is_equal(2)
		assert_str(action.cmd.seed).is_equal(c.seed)
	assert_array(v.crops).is_empty()
	assert_dict(P0Logic.fast_crop(v, "crop_radish")).is_empty()
	assert_str(P0ItemInfo.grow_time({grow_h = 10.0 / 3600.0})).is_equal("10s")
	assert_str(P0ItemInfo.grow_time({grow_s = 59})).is_equal("59s")

func test_fast_crops_stay_in_produce_and_only_homestead_buys_them() -> void:
	var v := view()
	v.shops = {homestead = {sell = [{kind = "crop", rate = 1.0}]}, market = {sell = [{kind = "crop", rate = 0.8}]},
		travel = {sell = [{kind = "crop", rate = 1.0}]}}
	for c in FAST:
		assert_str(P0ItemInfo.kind_of(v, c.id)).is_equal("crop")
		assert_int(P0ItemInfo._sell_here(v, c.id, {counter = "homestead"})).is_equal(c.price)
		for counter in ["market", "travel"]: assert_int(P0ItemInfo._sell_here(v, c.id, {counter = counter})).is_equal(-1)
		assert_array(P0ItemInfo.spec(v, c.id, &"bag", {near = {id = "res_pip", name = "Pip"}}).buttons.map(func(b): return b.label)).not_contains(["Gift to Pip"])
		v.items[c.id].cook = true   # even an inconsistent item flag cannot leak the excluded series into Experiment
		assert_bool(P0KitchenLogic.can_add(v, [], c.id)).is_false()
	assert_array(P0KitchenLogic.experiment_items(v, [])).is_empty()

func test_today_last_five_minutes_tick_for_every_crop_and_fast_crops_have_no_action_rows() -> void:
	var v := view()
	v.names.crop_lettuce = "Lettuce"
	for ms in [300001, 300000, 299000, 10000, 9999, 1000]:
		var expected := "6m" if ms > 300000 else P0Logic.duration(ms)
		for c in ["crop_lettuce", "crop_cress", "crop_quick_radish"]:
			assert_str(P0Logic.ripe_in(v, c, ms)).is_equal(expected)
	for c in FAST:
		v.plots = [{id = 0, state = "growing", crop = c.id, ready_in = 8000}, {id = 1, state = "growing", crop = c.id, ready_in = 9000}]
		var name := "Scallions" if c.name == "Scallion" else str(c.name)
		var rows := P0Logic.today_rows(v)
		assert_array(rows.map(func(r): return r.line)).contains([name + " ready in 0:08"])
		assert_array(P0Logic.today_rows(P0Logic.project(v, 1000)).map(func(r): return r.line)).contains([name + " ready in 0:07"])
		v.plots.resize(1)
		assert_array(P0Logic.today_rows(v).map(func(r): return r.line)).contains([str(c.name) + " ready in 0:08"])
		v.plots[0].state = "ready"
		assert_bool(P0Logic.today_rows(v).any(func(r): return str(r.get("dot", "")).begins_with("harvest:") or str(r.line).contains(c.name))).is_false()
		v.plots[0].state = "sown"
		assert_bool(P0Logic.today_rows(v).any(func(r): return str(r.line).begins_with("Water "))).is_false()

func test_fast_crops_never_schedule_or_trigger_a_crop_notification() -> void:
	var v := view()
	for i in FAST.size(): v.plots.append({id = i, state = "growing", crop = FAST[i].id, ready_in = FAST[i].grow_s * 1000})
	var now := float(Time.get_unix_time_from_datetime_string("2026-10-28T12:00:00")) * 1000.0
	assert_dict(P0Notify.plan(v, now, 0)).is_empty()
	assert_str(P0Notify.ask_question(v)).is_empty()
	v.plots.append({id = 7, state = "growing", crop = "crop_lettuce", ready_in = 600000})
	v.names.crop_lettuce = "Lettuce"
	assert_float(P0Notify.plan(v, now, 0).at).is_equal(now + 600000)
	assert_str(P0Notify.plan(v, now, 0).title).is_equal("Lettuce ready to harvest")
	assert_str(P0Notify.ask_question(v)).is_equal(P0Notify.ASK_CROPS)

func test_fast_crops_render_at_their_fixed_duration_with_distinct_tints_and_cannot_be_fertilized() -> void:
	var v := view()
	for i in FAST.size(): v.plots.append({id = i, state = "growing", crop = FAST[i].id, ready_in = FAST[i].grow_s * 500})
	var cells := P0Garden.cells(v, 1000000)
	var codes := ["B", "B", "L", "H", "L"]
	for i in FAST.size():
		var slot: Dictionary = cells[P0Garden.cell_id(P0Garden.cell_of(i))]
		assert_str(slot.crop).is_equal(codes[i])
		assert_int(int(slot.ready_at) - int(slot.watered_at)).is_equal(FAST[i].grow_s * 1000)
		assert_int(CropField.stage_of(slot, 1000000)).is_equal(1)
		assert_bool(slot.tint != Color.WHITE).is_true()
		assert_str(P0Logic.main_action(v, v.plots[i], "fert_compost").verb).is_equal("Growing")
		assert_str(P0Logic.main_action(v, v.plots[i], "fert_compost").sub).is_equal("Ready in " + P0Logic.duration(FAST[i].grow_s * 500))
	assert_bool(cells[P0Garden.cell_id(P0Garden.cell_of(0))].tint != cells[P0Garden.cell_id(P0Garden.cell_of(1))].tint).is_true()

func test_home_banner_shows_actual_energy_and_keeps_full_for_level_five_onward() -> void:
	for level in [2, 3, 4]:
		for gain in [40, 15, 0]:
			var banner := P0Logic.home_moment({energy = {max = 220}}, {level = level, energy = gain})
			assert_str(banner.subtitle).is_equal("Max Energy 220" + (" · +%d Energy" % gain if gain > 0 else ""))
	for level in [5, 10]:
		assert_str(P0Logic.home_moment({energy = {max = 240}}, {level = level, energy = 0}).subtitle).is_equal("Max Energy 240 · Energy full")

func test_home_panel_reads_reduced_gates_and_does_not_add_a_one_time_energy_reward_row() -> void:
	for rule in [[2, 40, 3], [3, 80, 4], [4, 300, 6], [5, 750, 8]]:
		var level: int = rule[0]
		var v := view()
		v.homestead = {level = level - 1, next = {level = level, coins = {need = rule[1] + 40, have = 2000},
			skills = {need = rule[2], have = 10}, materials = [{id = "wood", name = "Timber", need = 6, have = 6}],
			energy = 200 + (level - 1) * 10, meals = 200 + (level - 1) * 10, unlocks = [], can_upgrade = true}}
		var panel := P0Logic.home_panel(v)
		assert_int(panel.tiles[1].need).is_equal(rule[1] + 40)   # displayed wallet need includes the retained floor
		assert_int(panel.tiles[2].need).is_equal(rule[2])
		assert_bool(panel.changes.any(func(row): return str(row.text).contains("+40"))).is_false()
		assert_str(panel.footer).is_equal("Upgrading is free of Energy" + (" · fills Energy to the new max" if level >= 5 else ""))

func test_reused_plant_batches_keep_each_fast_crop_tint_and_the_harvest_copy() -> void:
	var v := view()
	for i in FAST.size(): v.plots.append({id = i, state = "ready", crop = FAST[i].id})
	var field: CropField = auto_free(CropField.new(P0Garden.blueprint()))
	add_child(field)
	field.sync(P0Garden.cells(v, 1000), 1000)
	assert_int(field.cell_counts().B).is_equal(2)
	assert_int(field.cell_counts().L).is_equal(2)
	assert_int(field.cell_counts().H).is_equal(1)
	assert_bool(field._mm.B.multimesh.get_instance_color(0) != field._mm.B.multimesh.get_instance_color(1)).is_true()
	var tint: Color = P0Garden.FAST_TINTS.crop_cress
	var ghost := field.ghost(P0Garden.cell_of(0), "B", CropField.STAGES - 1, tint)
	auto_free(ghost)
	var shown: Color = ghost.get_child(0).multimesh.get_instance_color(0)
	assert_float(absf(shown.r - tint.r)).is_less_equal(1.0 / 255.0)
	assert_float(absf(shown.b - tint.b)).is_less_equal(1.0 / 255.0)

func test_homestead_reward_updates_hud_without_an_extra_energy_float() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	var files := ["user://test_fast_home_bar.json", "user://test_fast_home_tips.json"]
	rt.ui.quick_store = files[0]
	rt.ui.tips_path = files[1]
	rt.session.transport = func(_m, _p, _b, _c): pass
	add_child(rt)
	await get_tree().process_frame
	rt.set_process(false)
	rt.session.set_process(false)
	var v := view()
	v.homestead = {level = 2}
	v.energy = {value = 190, max = 210}
	var before := v.duplicate(true)
	before.energy = {value = 150, max = 200}
	rt.ui.set_view(before)
	rt.session.view = v
	rt._on_state(v, [{kind = "energy", reason = "homestead", delta = 40}, {kind = "homestead", level = 2, energy = 40, unlocks = []}])
	assert_str(rt.ui.hud._energy_value.text).is_equal("150/210")
	rt.ui.hud._energy_tween.pause()
	rt.ui.hud._energy_tween.custom_step(0.15)
	assert_float(rt.ui.hud._energy_shown).is_greater(150.0)
	assert_float(rt.ui.hud._energy_shown).is_less(190.0)
	rt.ui.hud._energy_tween.custom_step(0.2)
	assert_str(rt.ui.hud._energy_value.text).is_equal("190/210")
	for i in 4: await get_tree().process_frame
	assert_int(rt.ui.view.energy.value).is_equal(190)
	var floats := rt.ui.root.get_children().filter(func(n): return n is UiFloatText and not n.is_queued_for_deletion())
	assert_bool(floats.any(func(n): return n.text.contains("Energy"))).is_false()
	assert_bool(rt.ui.find_children("*", "UiMomentBanner", true, false).size() > 0).is_true()
	for file in files: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))

func test_fast_crop_harvest_floats_keep_mass_names_and_pluralize_merged_scallions() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	var files := ["user://test_fast_float_bar.json", "user://test_fast_float_tips.json"]
	rt.ui.quick_store = files[0]
	rt.ui.tips_path = files[1]
	rt.session.transport = func(_m, _p, _b, _c): pass
	add_child(rt)
	await get_tree().process_frame
	rt.set_process(false)
	rt.session.set_process(false)
	var v := view()
	rt.session.view = v
	for c in FAST:
		rt.ui._live_floats.clear()
		for n in rt.ui.root.get_children():
			if n is UiFloatText: n.queue_free()
		rt._on_state(v, [{kind = "item", id = c.id, delta = 1}])
		for i in 2: await get_tree().process_frame
		assert_str(rt.ui._live_floats.item.node.text).is_equal("+1 " + str(c.name))
		var merged: Dictionary = rt.ui._live_floats.item.parts.duplicate(true)
		P0Ui._float_add(merged, merged[c.id].duplicate())
		assert_str(P0Ui._float_line_text(merged)).is_equal("+2 " + ("Scallions" if c.name == "Scallion" else str(c.name)))
	for file in files: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
