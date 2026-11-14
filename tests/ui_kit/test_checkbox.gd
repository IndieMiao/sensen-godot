extends GdUnitTestSuite
## UiCheckbox 9:104780: a 44-high row that is all key; its links say which and leave the box alone.

func _click(c: UiCheckbox) -> void:
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	c._gui_input(up)

func test_the_row_toggles_and_is_a_finger_high() -> void:
	var c: UiCheckbox = auto_free(UiCheckbox.new("I agree to the Terms of Service and Privacy Policy", ["Terms of Service", "Privacy Policy"]))
	c.size.x = 286
	add_child(c)
	await await_idle_frame()
	assert_bool(c.checked).is_false()
	assert_float(c.get_combined_minimum_size().y).is_greater_equal(UiTokens.SIZE_TOUCH)
	var said: Array[bool] = []
	c.toggled.connect(func(on: bool): said.append(on))
	_click(c)
	_click(c)
	assert_array(said).is_equal([true, false])
	assert_bool((c.find_child("Tick", true, false) as Control).visible).is_false()
	c.checked = true
	assert_bool((c.find_child("Tick", true, false) as Control).visible).is_true()

func test_a_link_says_which_and_leaves_the_box_as_it_was() -> void:
	var c: UiCheckbox = auto_free(UiCheckbox.new("I agree to the Terms of Service and Privacy Policy", ["Terms of Service", "Privacy Policy"]))
	add_child(c)
	var links: Array[int] = []
	c.link_pressed.connect(func(i: int): links.append(i))
	c.line.meta_clicked.emit(1)   # the line's tap on `Privacy Policy`
	_click(c)                     # … and the same tap reaching the row
	assert_array(links).is_equal([1])
	assert_bool(c.checked).is_false()
	assert_str(c.line.get_parsed_text()).is_equal("I agree to the Terms of Service and Privacy Policy")
