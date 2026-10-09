extends GdUnitTestSuite
## Floats go through the kit UiFloatText (SGODOT-224; 李白 q(49): "亚瑟的 float_text 改调它"): tone and icon per
## kind, long copy wraps, and the floats of one server reply stack upward instead of overlapping.

const STORE := "user://test_p0_floats.json"

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _floats(ui: P0Ui) -> Array:
	return ui.root.get_children().filter(func(c): return c is UiFloatText and not c.is_queued_for_deletion())

func test_float_text_draws_its_tone_and_an_older_colour_reads_as_item() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	var xp := ui.float_text("+5 XP", Vector2(180, 400), UiFloatText.Tone.XP)
	assert_int(xp.tone).is_equal(UiFloatText.Tone.XP)
	assert_int(xp.layout).is_equal(UiFloatText.Layout.HUG)
	var wood := ui.float_text("+6 Timber", Vector2(180, 400), UiFloatText.Tone.ITEM, P0Logic.icon("wood"))
	assert_object(wood.icon).is_same(P0Logic.icon("wood"))
	# Callers from other PRs still pass a Color (mine, farm materials): drawn in the ITEM tone until 233 sorts them.
	var old := ui.float_text("Stored at home", Vector2(180, 400), Color("4f934b"))
	assert_int(old.tone).is_equal(UiFloatText.Tone.ITEM)
	var long := ui.float_text("It got away · Energy refunded (2 left today)", Vector2(180, 400), UiFloatText.Tone.ENERGY_GAIN)
	assert_int(long.layout).is_equal(UiFloatText.Layout.WRAP)
	assert_bool(xp.get_parent() == ui.root).is_true()

func test_one_replys_floats_stack_upward_in_their_tones() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var v := {"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []},
		"skills": {"farming": {"level": 2}}, "names": {"wood": "Timber"}}
	rt.session.view = v
	rt._on_state(v, [{"kind": "energy", "delta": -2, "reason": "till"},
		{"kind": "xp", "skill": "farming", "amount": 5, "percent": 100},
		{"kind": "item", "id": "wood", "delta": 6},
		{"kind": "coins", "delta": 12}])
	await get_tree().process_frame   # the reply's floats go out together at the end of the frame (queue_floats)
	var fl := _floats(rt.ui)
	# At most three lines (q(49) ①): the coins join the last one, nothing is dropped.
	assert_array(fl.map(func(f): return f.text)).is_equal(["−2 Energy", "+5 XP", "+6 Timber · +12 coins"])
	assert_array(fl.map(func(f): return f.tone)).is_equal([UiFloatText.Tone.ENERGY_COST, UiFloatText.Tone.XP,
		UiFloatText.Tone.ITEM])
	# Each line starts 28 above the previous one (stack_index), all from the same anchor.
	var bottoms := fl.map(func(f): return f._base_y + f.pivot_offset.y)   # where each started (it rises from there)
	assert_float(bottoms[0] - bottoms[1]).is_equal_approx(28.0, 0.5)
	assert_float(bottoms[1] - bottoms[2]).is_equal_approx(28.0, 0.5)

## q(49) ① (SGODOT-233): one kind is one line, in the order Energy → XP → items → coins → affinity; a held repeat's
## next reply adds into the line still up and bumps it instead of a new float.
func test_one_kind_one_line_in_order_and_a_repeat_bumps_in_place() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	var t := [1000]
	ui.float_clock = func(): return t[0]
	var at := Vector2(180, 500)
	var shown := ui.float_lines([
		{kind = "coins", key = "coins", amount = 14, fmt = "%s coins", tone = UiFloatText.Tone.COINS},
		{kind = "item", key = "wood", amount = 6, fmt = "%s Timber", tone = UiFloatText.Tone.ITEM},
		{kind = "xp", key = "%s XP", amount = 4, fmt = "%s XP", tone = UiFloatText.Tone.XP},
		{kind = "item", key = "stone", amount = 2, fmt = "%s Stone", tone = UiFloatText.Tone.ITEM},
		{kind = "xp", key = "%s XP", amount = 4, fmt = "%s XP", tone = UiFloatText.Tone.XP}], at)
	assert_array(shown.map(func(f): return f.text)).is_equal(["+8 XP", "+6 Timber · +2 Stone", "+14 coins"])
	t[0] += 400   # the next held harvest, before the lines fade
	var again := ui.float_lines([{kind = "xp", key = "%s XP", amount = 4, fmt = "%s XP", tone = UiFloatText.Tone.XP},
		{kind = "item", key = "wood", amount = 6, fmt = "%s Timber", tone = UiFloatText.Tone.ITEM}], at)
	assert_bool(again[0] == shown[0]).is_true()   # the same XP line, bumped
	# Items float per reply (each plot's own), only XP adds up across replies.
	assert_array(again.map(func(f): return f.text)).is_equal(["+12 XP", "+6 Timber"])
	assert_int(_floats(ui).size()).is_equal(4)
	t[0] += 700   # past the fade: a new line
	var later := ui.float_lines([{kind = "xp", key = "%s XP", amount = 4, fmt = "%s XP", tone = UiFloatText.Tone.XP}], at)
	assert_bool(later[0] == shown[0]).is_false()

## int6 (李元芳): a float near the top never rises over the HUD rows.
func test_a_float_stays_under_the_hud() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view({"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []},
		"skills": {"farming": {"level": 2, "xp": 60, "floor": 50, "next": 150}}})
	ui.set_surface("farm")
	assert_bool(ui.hud.visible).is_true()
	var f := ui.float_text("+5 Cooking XP ★", Vector2(180, 60), UiFloatText.Tone.XP)
	var hud_bottom := float(UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H) + ui.safe_top()
	# Its start (bottom centre) is low enough that the top of the rise clears the HUD.
	assert_float(f.position.y + f.pivot_offset.y - f.shown_size().y - UiFloatText._RISE).is_greater_equal(hud_bottom + P0Ui.FLOAT_HUD_GAP - 0.5)
	# A whole group counts: its top line (two places up) still clears the HUD by 8 at the top of its rise.
	var group := ui.float_lines([
		{kind = "energy", key = "energy", amount = -2, fmt = "%s Energy"},
		{kind = "xp", key = "%s XP", amount = 5, fmt = "%s XP", tone = UiFloatText.Tone.XP},
		{kind = "coins", key = "coins", amount = 12, fmt = "%s coins", tone = UiFloatText.Tone.COINS}], Vector2(180, 60))
	var top_line: UiFloatText = group[2]
	assert_float(top_line._base_y - UiFloatText._RISE).is_greater_equal(hud_bottom + P0Ui.FLOAT_HUD_GAP - 0.5)

## 不知火舞 233: pushed down, a group never sits on an open drawer (or the bar / the key): only the first line stays,
## the rest joined into it.
func test_no_room_under_the_hud_joins_the_group_into_one_line() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view({"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []},
		"skills": {"farming": {"level": 2, "xp": 60, "floor": 50, "next": 150}}})
	ui.set_surface("farm")
	var hud_bottom := float(UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H) + ui.safe_top()
	# A drawer whose top leaves room for one pushed-down line, not three.
	var open := UiDrawer.new(ui.root.size.y - (hud_bottom + P0Ui.FLOAT_HUD_GAP + 30.0 + UiFloatText._RISE + 20.0))
	open.animate = false
	ui._open_modal(open, 0.32, true)
	await get_tree().process_frame
	var parts := [{kind = "energy", key = "energy", amount = -2, fmt = "%s Energy"},
		{kind = "xp", key = "%s XP", amount = 5, fmt = "%s XP", tone = UiFloatText.Tone.XP},
		{kind = "coins", key = "coins", amount = 12, fmt = "%s coins", tone = UiFloatText.Tone.COINS}]
	var shown := ui.float_lines(parts, Vector2(180, 40))   # a head near the top: the group is pushed down
	assert_int(shown.size()).is_equal(1)
	assert_str(shown[0].text).is_equal("−2 Energy · +5 XP · +12 coins")

## A world's own lines of the same reply (a gather's `+6 Timber · Stored`) join the runtime's in one batch.
func test_a_worlds_lines_join_the_replys_batch() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	var at := Vector2(180, 500)
	ui.queue_floats([{kind = "xp", key = "%s XP", amount = 4, fmt = "%s XP", tone = UiFloatText.Tone.XP},
		{kind = "item", key = "bait_worm", amount = 2, fmt = "%s Worm Bait", tone = UiFloatText.Tone.ITEM}], at)
	ui.queue_floats([{kind = "item", key = "+6 Timber · Stored", text = "+6 Timber · Stored", tone = UiFloatText.Tone.ITEM},
		{kind = "energy", key = "fee", text = "Floor 2 · −2 Energy", tone = UiFloatText.Tone.ENERGY_COST}], at)
	assert_int(_floats(ui).size()).is_equal(0)
	await get_tree().process_frame
	var fl := _floats(ui)
	assert_array(fl.map(func(f): return f.text)).is_equal(["Floor 2 · −2 Energy", "+4 XP", "+2 Worm Bait · +6 Timber · Stored"])
	assert_int(fl[0].tone).is_equal(UiFloatText.Tone.ENERGY_COST)

## E-04 / §4.8.3 (SGODOT-233): a held harvest's XP stays one line that counts its plants, wherever the player walks;
## each plot's item still floats on its own, and the first harvest of a crop says so on its own line.
func test_a_held_harvest_counts_its_plants_in_one_xp_line() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var v := {"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []},
		"skills": {"farming": {"level": 1, "xp": 20}}, "names": {"crop_radish": "Radish"}}
	rt.session.view = v
	var t := [5000]
	rt.ui.float_clock = func(): return t[0]
	rt.ui.fab_held = true
	rt._on_state(v, [{"kind": "first", "what": "harvest:crop_radish", "xp": 10},
		{"kind": "xp", "skill": "farming", "amount": 10, "percent": 100},
		{"kind": "xp", "skill": "farming", "amount": 2, "percent": 100},
		{"kind": "item", "id": "crop_radish", "delta": 1}])
	await get_tree().process_frame
	var first := _floats(rt.ui).map(func(f): return f.text)
	assert_array(first).is_equal(["+2 XP", "First harvest! +10 XP · Radish", "+1 Radish"])
	for i in 19:   # nineteen more plots, a labour beat apart, the player moving on
		t[0] += 700
		rt._on_state(v, [{"kind": "xp", "skill": "farming", "amount": 2, "percent": 100}, {"kind": "item", "id": "crop_radish", "delta": 1}])
		await get_tree().process_frame
	var xp: Array = _floats(rt.ui).filter(func(f): return f.text.ends_with("plants"))
	assert_int(xp.size()).is_equal(1)
	assert_str(xp[0].text).is_equal("+40 XP · 20 plants")
	rt.ui.fab_held = false

## q(94) / 李白 copy audit A4: a pot's XP says which pot of its page today it is — the 2nd `+3 Cooking XP · 2nd today`
## (no percentage on top), the 3rd on `No XP · 3rd today` though it earns nothing; other XP keeps its `· 75%`.
func test_a_pots_xp_float_says_the_2nd_and_3rd_of_its_page_today() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var t := [1000]
	rt.ui.float_clock = func(): return t[0]
	var v := {"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []},
		"skills": {"cooking": {"level": 2}}}
	rt.session.view = v
	var said := func(events: Array) -> Array:
		t[0] += 5000   # a new reply well after the last line faded: its own float
		for f in _floats(rt.ui): f.free()
		rt._on_state(v, events)
		await get_tree().process_frame
		return _floats(rt.ui).map(func(f): return f.text)
	assert_array(await said.call([{"kind": "xp", "skill": "cooking", "amount": 3, "percent": 75, "nth": 2}])).is_equal(["+3 Cooking XP · 2nd today"])
	assert_array(await said.call([{"kind": "xp", "skill": "cooking", "amount": 0, "percent": 100, "nth": 3}])).is_equal(["No XP · 3rd today"])
	assert_array(await said.call([{"kind": "xp", "skill": "cooking", "amount": 0, "percent": 100, "nth": 4}])).is_equal(["No XP · 4th today"])
	assert_array(await said.call([{"kind": "xp", "skill": "cooking", "amount": 3, "percent": 75, "nth": 1}])).is_equal(["+3 Cooking XP · 75%"])
	assert_array(await said.call([{"kind": "xp", "skill": "cooking", "amount": 0, "percent": 100}])).is_empty()   # no pot place: nothing, as before
