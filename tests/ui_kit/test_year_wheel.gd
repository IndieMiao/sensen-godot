extends GdUnitTestSuite
## UiYearWheel (V5, 383 50108c43): the voice age card's wheel, out on its own for the first launch's AGE page (SGODOT-491).
## It opens on this year with nothing picked; a stop says the year (picked); show_year puts it back without a word.

func _wheel() -> UiYearWheel:
	var w := UiYearWheel.new(2026)
	w.animate = false
	w.size = Vector2(328, UiYearWheel.WHEEL_H)
	add_child(auto_free(w))
	return w

func test_opens_on_this_year_with_nothing_picked_and_a_hundred_years() -> void:
	var w := _wheel()
	assert_int(w.centred()).is_equal(2026)
	assert_int(w.year).is_equal(0)
	assert_int(w.year_at(0)).is_equal(1927)
	w.pick(1800)   # out of the wheel: the oldest it has
	assert_int(w.year).is_equal(1927)

func test_a_stop_says_the_year_and_show_year_does_not() -> void:
	var w := _wheel()
	var said: Array[int] = []
	w.picked.connect(func(y: int): said.append(y))
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_down.pressed = true
	w.wheel_input(wheel_down)   # the mouse wheel up: a year earlier
	assert_array(said).is_equal([2025])
	w.show_year(2001)   # the AGE page's Change: back where it was, nothing new picked
	assert_int(w.centred()).is_equal(2001)
	assert_int(w.year).is_equal(2001)
	assert_array(said).is_equal([2025])

func test_rows_and_offsets_go_back_and_forth() -> void:
	for d in [-2.0, -1.5, -1.0, -0.4, 0.0, 0.7, 1.0, 1.6, 2.0]:
		assert_float(UiYearWheel.rows_at(UiYearWheel.offset_of(d))).is_equal_approx(d, 0.0001)
