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
	var fl := _floats(rt.ui)
	assert_array(fl.map(func(f): return f.text)).is_equal(["−2 Energy", "+5 XP", "+6 Timber", "+12 coins"])
	assert_array(fl.map(func(f): return f.tone)).is_equal([UiFloatText.Tone.ENERGY_COST, UiFloatText.Tone.XP,
		UiFloatText.Tone.ITEM, UiFloatText.Tone.COINS])
	# Each line starts 28 above the previous one (stack_index), all from the same anchor.
	var bottoms := fl.map(func(f): return f.position.y + f.pivot_offset.y)
	assert_float(bottoms[0] - bottoms[1]).is_equal_approx(28.0, 0.5)
	assert_float(bottoms[1] - bottoms[2]).is_equal_approx(28.0, 0.5)
