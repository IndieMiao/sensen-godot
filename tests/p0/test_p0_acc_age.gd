extends GdUnitTestSuite
## ACC-AGE v1.1 (SGODOT-491, spec v1.1 A, row 158): the key says what is missing in order, Continue asks `Born in …?`
## for every answer, Yes says old enough or not (14 by the year), Change keeps the page as it was.

func _page() -> P0AccAge:
	var p := P0AccAge.new(2026)
	p.animate = false
	add_child(auto_free(p))
	p.size = Vector2(360, 800)
	return p

func test_the_key_says_what_is_missing_first() -> void:
	var p := _page()
	await await_idle_frame()
	assert_str(p.go.label).is_equal("Pick your birth year")
	assert_bool(p.go.disabled).is_true()
	p.consent.checked = true
	p.consent.toggled.emit(true)
	assert_str(p.go.label).is_equal("Pick your birth year")   # the year first, ticked or not
	p.consent.checked = false
	p.consent.toggled.emit(false)
	p.wheel.pick(2001)
	assert_str(p.go.label).is_equal("Agree to continue")
	assert_bool(p.go.disabled).is_true()
	p.consent.checked = true
	p.consent.toggled.emit(true)
	assert_str(p.go.label).is_equal("Continue")
	assert_bool(p.go.disabled).is_false()

func test_continue_asks_born_in_and_yes_says_the_answer() -> void:
	for c in [[2001, true], [2012, true], [2013, false], [2026, false]]:
		var p := _page()
		var said: Array[bool] = []
		p.agreed.connect(func(ok: bool): said.append(ok))
		p.wheel.pick(int(c[0]))
		p.consent.checked = true
		p.consent.toggled.emit(true)
		p.go.activated.emit()
		assert_object(p.confirm).is_not_null()
		assert_str((p.confirm.find_child("Title", true, false) as Label).text).is_equal("Born in %d?" % int(c[0]))
		assert_bool((p.confirm.find_child("Body", true, false) as Control).visible).is_false()
		assert_array(said).is_empty()   # nothing said before Yes
		p.confirm.move.activated.emit()
		assert_array(said).is_equal([bool(c[1])])
		assert_object(p.confirm).is_null()

func test_change_closes_the_card_on_the_page_as_it_was() -> void:
	var p := _page()
	var said: Array[bool] = []
	p.agreed.connect(func(ok: bool): said.append(ok))
	p.wheel.pick(1990)
	p.consent.checked = true
	p.consent.toggled.emit(true)
	p.go.activated.emit()
	p.confirm.cancel.activated.emit()
	assert_object(p.confirm).is_null()
	assert_array(said).is_empty()
	assert_int(p.wheel.year).is_equal(1990)
	assert_bool(p.consent.checked).is_true()
	assert_str(p.go.label).is_equal("Continue")

func test_a_grey_key_asks_nothing_and_links_say_which() -> void:
	var p := _page()
	p.go.activated.emit()
	assert_object(p.confirm).is_null()
	var links: Array[String] = []
	p.link_pressed.connect(func(w: String): links.append(w))
	p.consent.line.meta_clicked.emit(0)
	p.consent.line.meta_clicked.emit(1)
	assert_array(links).is_equal(["terms", "privacy"])
