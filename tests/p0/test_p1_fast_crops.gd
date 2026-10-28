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

func test_new_icon_imports_have_distinct_native_uids_and_resolve_to_the_expected_texture() -> void:
	var seen := {}
	for c in FAST:
		for id in [c.id, c.seed]:
			var path: String = "res://assets/p0/icons/" + str(id) + ".svg"
			var config := ConfigFile.new()
			assert_int(config.load(path + ".import")).is_equal(OK)
			var encoded := str(config.get_value("remap", "uid", ""))
			var uid := ResourceUID.text_to_id(encoded)
			assert_int(uid).is_not_equal(ResourceUID.INVALID_ID)
			assert_bool(seen.has(uid)).is_false()
			seen[uid] = true
			assert_str(ResourceUID.id_to_text(uid)).is_equal(encoded)   # importer metadata, independent of an editor UID cache
			assert_str(P0Logic.icon(str(id)).resource_path).is_equal(path)

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

func test_growing_key_uses_seconds_for_fast_crops_last_five_minutes_and_keeps_quick_radish() -> void:
	var v := view()
	var expected := ["Ready in 0:10", "Ready in 1:00", "Ready in 5:00", "Ready in 20m", "Ready in 1h"]
	for i in FAST.size():
		var p := {id = 0, state = "growing", crop = FAST[i].id, ready_in = FAST[i].grow_s * 1000}
		assert_str(P0Logic.main_action(v, p, "").sub).is_equal(expected[i])
	assert_str(P0Logic.main_action(v, {id = 0, state = "growing", crop = "crop_scallion", ready_in = 1199000}, "").sub).is_equal("Ready in 20m")
	v.quick_seeds = [{id = "crop_quick_radish", seed = "seed_quick_radish", grow_s = 45}]
	assert_str(P0Logic.main_action(v, {id = 0, state = "growing", crop = "crop_quick_radish", ready_in = 45000}, "").sub).is_equal("Ready in 0:45")

func test_growing_key_and_today_share_five_minute_boundary_for_all_crop_kinds() -> void:
	var v := view()
	var ids := ["crop_lettuce", "crop_apple", "crop_quick_radish"]
	for c in FAST: ids.append(c.id)
	for id in ids:
		for sample in [[300001, "6m"], [300000, "5:00"], [299001, "5:00"], [299000, "4:59"],
			[60000, "1:00"], [59000, "0:59"], [10000, "0:10"], [1500, "0:02"], [1, "0:01"],
			[1200000, "20m"], [7200000, "2h"], [71880000, "19h 58m"]]:
			var p := {id = 0, crop = id, state = "growing", ready_in = sample[0], tree = id == "crop_apple"}
			var a := P0Logic.main_action(v, p, "")
			var time: String = sample[1]
			assert_str(a.sub).is_equal(time if time.contains(" ") else "Ready in " + time)
			assert_str(P0Logic.ripe_in(v, id, sample[0])).is_equal(time)
			assert_str(a.verb).is_equal("Growing")
			assert_bool(a.enabled).is_false()
			assert_dict(a.cmd).is_empty()

func test_growing_key_ticks_with_today_on_client_projection_and_yields_to_harvest() -> void:
	for id in ["crop_cress", "crop_lettuce", "crop_apple", "crop_quick_radish"]:
		var v := view([{id = 0, crop = id, state = "growing", ready_in = 10000, tree = id == "crop_apple"}])
		v.names[id] = "Test Crop"
		for second in range(10):
			var now := P0Logic.project(v, second * 1000)
			var a := P0Logic.main_action(now, now.plots[0], "")
			var time := "0:%02d" % (10 - second)
			assert_str(a.sub).is_equal("Ready in " + time)
			assert_array(P0Logic.today_rows(now).map(func(r): return r.line)).contains(["Test Crop ready in " + time])
		var ripe := P0Logic.project(v, 10000)
		assert_str(P0Logic.main_action(ripe, ripe.plots[0], "").verb).is_equal("Pick" if id == "crop_apple" else "Harvest")

func test_legacy_today_line_keeps_fast_countdowns_but_never_targets_fast_ready_or_sown_plots() -> void:
	var v := view()
	for c in FAST:
		v.plots = [{id = 0, state = "growing", crop = c.id, ready_in = 8000}]
		assert_str(P0Logic.today_line(v)).is_equal(("Scallions" if c.name == "Scallion" else str(c.name)) + " ready in 0:08")
		for state in ["ready", "sown"]:
			v.plots[0].state = state
			assert_str(P0Logic.today_line(v)).is_equal("Sow your first plot")
	v.names.crop_lettuce = "Lettuce"
	v.plots.append({id = 1, state = "ready", crop = "crop_lettuce"})
	assert_str(P0Logic.today_line(v)).is_equal("Lettuce ready to harvest")
	v.plots[1].state = "sown"
	assert_str(P0Logic.today_line(v)).is_equal("Water what you sowed")

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
	var codes := ["B", "B", "L", "B", "L"]
	for i in FAST.size():
		var slot: Dictionary = cells[P0Garden.cell_id(P0Garden.cell_of(i))]
		assert_str(slot.crop).is_equal(codes[i])
		assert_int(int(slot.ready_at) - int(slot.watered_at)).is_equal(FAST[i].grow_s * 1000)
		assert_int(CropField.stage_of(slot, 1000000)).is_equal(1)
		assert_bool(slot.tint != Color.WHITE).is_true()
		assert_str(P0Logic.main_action(v, v.plots[i], "fert_compost").verb).is_equal("Growing")
		assert_str(P0Logic.main_action(v, v.plots[i], "fert_compost").sub).is_equal(P0Logic.key_ready(FAST[i].grow_s * 500))
	assert_bool(cells[P0Garden.cell_id(P0Garden.cell_of(0))].tint != cells[P0Garden.cell_id(P0Garden.cell_of(1))].tint).is_true()

func test_home_banner_shows_actual_energy_and_keeps_full_for_level_five_onward() -> void:
	for level in [2, 3, 4]:
		assert_str(P0Logic.home_moment({energy = {max = 220}}, {level = level}).subtitle).is_equal("Max Energy 220 · Energy full")   # legacy field absent, not a reported zero
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
	assert_int(field.cell_counts().B).is_equal(3)
	assert_int(field.cell_counts().L).is_equal(2)
	assert_int(field.cell_counts().H).is_equal(0)
	assert_int(field.cell_counts().C).is_equal(0)   # Scallion must not expose the mature carrot's orange detail
	# Read the actual submitted colors, not the dummy RenderingServer's all-zero headless readback.
	assert_bool(field._mm.B.instance_colors[0] != field._mm.B.instance_colors[1]).is_true()
	var tint: Color = P0Garden.FAST_TINTS.crop_cress
	var ghost := field.ghost(P0Garden.cell_of(0), "B", CropField.STAGES - 1, tint)
	auto_free(ghost)
	var batch: CropField.ColorBatch = ghost.get_child(0)
	assert_that(batch.instance_colors[0]).is_equal(tint)   # CPU values retain all RGBA channels without GPU quantization
	field.sync({}, 1000)
	assert_int(field._mm.B.instance_colors.size()).is_equal(0)
	assert_int(field._mm.L.instance_colors.size()).is_equal(0)
	assert_that(batch.instance_colors[0]).is_equal(tint)   # harvest copy outlives the field's cleared batch

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
