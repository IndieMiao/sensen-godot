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
	assert_array(again.map(func(f): return f.text)).is_equal(["+12 XP", "+12 Timber · +2 Stone"])
	assert_int(_floats(ui).size()).is_equal(3)
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
	assert_float(f.position.y + f.pivot_offset.y - f.shown_size().y - UiFloatText._RISE).is_greater_equal(hud_bottom - 0.5)

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
