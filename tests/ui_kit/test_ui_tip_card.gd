extends GdUnitTestSuite
## TipCard 1243:87540 (TUT-2, SGODOT-232 U6 / 235-B2): 296 wide, one line 48 / two lines 64, icon per tip, a tap emits.

func _card(text: String, key: Variant = null) -> UiTipCard:
	var c := UiTipCard.new()
	c.theme = UiKit.theme()
	add_child(auto_free(c))
	c.show_tip(text, key)
	return c

func test_one_line_is_48_and_two_lines_64_at_296_wide() -> void:
	var one := _card("Casting uses 5 Energy", "cast")
	var two := _card("Pick a seed, walk up to a plot and press Sow. Hold to keep sowing.", "sow")
	await await_idle_frame()
	assert_float(one.get_combined_minimum_size().x).is_equal(UiTipCard.WIDTH)
	assert_float(one.get_combined_minimum_size().y).is_equal_approx(48.0, 3.0)
	assert_float(two.get_combined_minimum_size().y).is_equal_approx(64.0, 4.0)

func test_each_tip_has_its_specimen_icon() -> void:
	assert_object(_card("x", "sow").icon_texture()).is_same(UiTipCard.ICONS.sow)
	assert_object(_card("x", "cook").icon_texture()).is_same(_card("y", "heat").icon_texture())   # both i-pot
	assert_object(_card("x", "cast").icon_texture()).is_same(_card("y", "eat").icon_texture())    # both i-energy
	assert_object(_card("x", "nope").icon_texture()).is_same(UiTipCard.DEFAULT_ICON)
	assert_object(_card("x").icon_texture()).is_same(UiTipCard.DEFAULT_ICON)

func test_a_tap_emits_tapped() -> void:
	var c := _card("Casting uses 5 Energy", "cast")
	var hits := [0]
	c.tapped.connect(func(): hits[0] += 1)
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	c._gui_input(tap)
	assert_int(hits[0]).is_equal(1)
