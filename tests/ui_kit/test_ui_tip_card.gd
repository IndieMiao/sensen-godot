extends GdUnitTestSuite
## TipCard 1243:87540 (TUT-2, SGODOT-232 U6 / 235-B2): 296 wide, one line 48 / two lines 64, icon per tip, a tap emits.

func _card(text: String, icon: Texture2D = null) -> UiTipCard:
	var c := UiTipCard.new()
	c.theme = UiKit.theme()
	add_child(auto_free(c))
	c.show_tip(text, icon)
	return c

func test_one_line_is_48_and_two_lines_64_at_296_wide() -> void:
	var one := _card("Casting uses 5 Energy")
	var two := _card("Pick a seed, walk up to a plot and press Sow. Hold to keep sowing.")
	await await_idle_frame()
	assert_float(one.get_combined_minimum_size().x).is_equal(UiTipCard.WIDTH)
	assert_float(one.get_combined_minimum_size().y).is_equal(48.0)
	assert_float(two.get_combined_minimum_size().y).is_equal_approx(64.0, 4.0)

## One copy of each icon in the app (不知火舞 on 235-B2): the owner passes the shared icon; none = the main's sprout.
func test_the_icon_is_the_owners_or_the_mains_default_sprout() -> void:
	var energy: Texture2D = load("res://assets/p0/icons/energy.svg")
	assert_object(_card("x", energy).icon_texture()).is_same(energy)
	assert_object(_card("x").icon_texture()).is_same(UiTipCard.DEFAULT_ICON)
	assert_object(UiTipCard.DEFAULT_ICON).is_same(load("res://assets/ui/kit_icons/sprout.svg"))

func _touch(c: UiTipCard, pressed: bool, at: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.pressed = pressed
	t.position = at
	c._gui_input(t)

## On release within the slop (刘邦 on #110): a press that drags on, toward the joystick, leaves the card up.
func test_a_tap_emits_tapped_on_release_and_a_drag_does_not() -> void:
	var c := _card("Casting uses 5 Energy")
	var hits := [0]
	c.tapped.connect(func(): hits[0] += 1)
	_touch(c, true, Vector2(40, 20))
	assert_int(hits[0]).is_equal(0)   # not on press
	_touch(c, false, Vector2(44, 22))
	assert_int(hits[0]).is_equal(1)
	_touch(c, true, Vector2(40, 20))
	_touch(c, false, Vector2(40, 20 + GestureArbiter.TAP_SLOP + 30))
	assert_int(hits[0]).is_equal(1)
