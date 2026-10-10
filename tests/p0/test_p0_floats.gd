extends GdUnitTestSuite
## Floats go through the kit UiFloatText (SGODOT-224; 李白 q(49): "亚瑟的 float_text 改调它"): tone and icon per
## kind, long copy wraps, and the floats of one server reply stack upward instead of overlapping.

const STORE := "user://test_p0_floats.json"

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _floats(ui: P0Ui) -> Array:
	return ui.root.get_children().filter(func(c): return c is UiFloatText and not c.is_queued_for_deletion())

func test_float_text_draws_its_tone() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	var xp := ui.float_text("+5 XP", Vector2(180, 400), UiFloatText.Tone.XP)
	assert_int(xp.tone).is_equal(UiFloatText.Tone.XP)
	assert_int(xp.layout).is_equal(UiFloatText.Layout.HUG)
	var wood := ui.float_text("+6 Timber", Vector2(180, 400), UiFloatText.Tone.ITEM, P0Logic.icon("wood"))
	assert_object(wood.icon).is_same(P0Logic.icon("wood"))
	# A tone only (刘邦 on #158): no Color fallback any more; nothing gained reads MUTED.
	var none := ui.float_text("Missed · still cooking", Vector2(180, 400), UiFloatText.Tone.MUTED)
	assert_int(none.tone).is_equal(UiFloatText.Tone.MUTED)
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
	assert_int(_floats(rt.ui)[0].tone).is_equal(UiFloatText.Tone.MUTED)   # nothing gained: secondary ink (不知火舞 on #158)
	assert_array(await said.call([{"kind": "xp", "skill": "cooking", "amount": 0, "percent": 100, "nth": 4}])).is_equal(["No XP · 4th today"])
	assert_array(await said.call([{"kind": "xp", "skill": "cooking", "amount": 3, "percent": 75, "nth": 1}])).is_equal(["+3 Cooking XP · 75%"])
	assert_array(await said.call([{"kind": "xp", "skill": "cooking", "amount": 0, "percent": 100}])).is_empty()   # no pot place: nothing, as before

## A wide line from near a side moves in (SGODOT-289: a trap's three fish from the bank ran off the right edge): it stays
## SPACE_PAGE clear of both sides; a line in the middle stays where it was asked.
func test_a_wide_float_stays_inside_the_screen() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view({"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []}, "skills": {}})
	ui.set_surface("pond")
	var lines := ui.float_lines([{kind = "item", key = "trap_fish", text = "River Perch ×1 · Common Carp ×1 · Arctic Char ×1",
		tone = UiFloatText.Tone.ITEM}], Vector2(ui.root.size.x - 40, 420))
	var f: UiFloatText = lines[0]
	# its sides at rest (×1.0) and at the peak, the pill grown from its pivot (不知火舞 on #284: inside 16–344 throughout)
	for k in [1.0, f._peak]:
		var left: float = f.position.x + f.pivot_offset.x * (1.0 - k / 1.3)
		assert_float(left + f.size.x * k / 1.3).is_less_equal(ui.root.size.x - UiTokens.SPACE_PAGE + 0.5)
		assert_float(left).is_greater_equal(UiTokens.SPACE_PAGE - 0.5)
	var mid: UiFloatText = ui.float_lines([{kind = "coins", key = "coins", amount = 5, fmt = "%s coins"}], Vector2(180, 420))[0]
	assert_float(mid.position.x + mid.pivot_offset.x).is_equal_approx(180.0, 0.5)

## Item lines hold two items at most (q(124) ①; 不知火舞 on #284): a third goes on a float line of its own above, the
## first pair on top, every line its own float; XP stays at the bottom and the lines count to the cap of three.
func test_three_items_make_two_lines_of_their_own() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view({"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []}, "skills": {}})
	ui.set_surface("pond")
	var parts := [{kind = "xp", key = "trap_xp", amount = 7, fmt = "%s XP", tone = UiFloatText.Tone.XP}]
	for n in ["River Perch ×1", "Common Carp ×1", "Arctic Char ×1"]: parts.append({kind = "item", key = n, text = n})
	var lines: Array = ui.float_lines(parts, Vector2(180, 420))
	assert_array(lines.map(func(f): return (f as UiFloatText).text)).is_equal(["+7 XP", "Arctic Char ×1", "River Perch ×1 · Common Carp ×1"])
	var heights: Array = lines.map(func(f): return (f as UiFloatText).shown_size().y)
	assert_float(float(heights[1])).is_equal_approx(float(heights[2]), 0.5)   # one line each, the same height
	assert_bool((lines[2] as UiFloatText).text.ends_with("·")).is_false()

## Split item lines would pass the cap of three (an Energy line too): the items stay one line in their own order and
## join as q(49)'s overflow does, never reordered by the split.
func test_items_past_the_cap_stay_one_line_in_their_order() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view({"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []}, "skills": {}})
	ui.set_surface("pond")
	var parts := [{kind = "energy", key = "energy", amount = 20, fmt = "%s Energy"},
		{kind = "xp", key = "trap_xp", amount = 7, fmt = "%s XP", tone = UiFloatText.Tone.XP}]
	for n in ["River Perch ×1", "Common Carp ×1", "Arctic Char ×1"]: parts.append({kind = "item", key = n, text = n})
	var lines: Array = ui.float_lines(parts, Vector2(180, 420))
	assert_array(lines.map(func(f): return (f as UiFloatText).text)).is_equal(["+20 Energy", "+7 XP", "River Perch ×1 · Common Carp ×1 · Arctic Char ×1"])

## The lines a split item group makes pop as one block (不知火舞 on #289, Cook All's `−5 Pond Crucian · −2 Wild Herb` /
## `−2 Radish`): they start together, each its own height and FLOAT_GROUP_GAP apart, growing from the lowest line, so
## they never meet — at the pop's peak or at rest — and neither shows up after the other.
func test_a_split_item_group_pops_together_and_its_lines_never_meet() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view({"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []}, "skills": {}})
	ui.set_surface("pond")
	var parts := [{kind = "xp", key = "trap_xp", amount = 7, fmt = "%s XP", tone = UiFloatText.Tone.XP}]
	for n in ["River Perch ×1", "Common Carp ×1", "Arctic Char ×1"]: parts.append({kind = "item", key = n, text = n})
	var lines: Array = ui.float_lines(parts, Vector2(180, 420))
	var low: UiFloatText = lines[1]
	var high: UiFloatText = lines[2]
	for i in 16:
		await get_tree().create_timer(0.05).timeout
		assert_float(low.group_rise).is_equal(0.0)   # the lower line rests where it is played; the upper one on it
		assert_float(high.group_rise).is_equal_approx(low.shown_size().y + P0Ui.FLOAT_GROUP_GAP, 0.1)
		# one start: they fade in and scale together (a wide line's peak may be capped a little lower, 336 px)
		assert_float(high.modulate.a).is_equal_approx(low.modulate.a, 0.001)
		assert_float(high.scale.y).is_equal_approx(low.scale.y, 0.01)
		var low_pill := low.get_child(0) as Control
		var high_pill := high.get_child(0) as Control
		var low_top := (low_pill.get_global_transform() * Vector2.ZERO).y
		var high_bottom := (high_pill.get_global_transform() * Vector2(0, high_pill.size.y)).y
		assert_float(high_bottom).is_less_equal(low_top + 0.01)   # never meet
		if i == 15:   # at rest: FLOAT_GROUP_GAP apart
			assert_float(low_top - high_bottom).is_equal_approx(P0Ui.FLOAT_GROUP_GAP, 0.1)
