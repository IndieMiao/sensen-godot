extends GdUnitTestSuite

func _panel() -> SelectPanel:
	var p: SelectPanel = auto_free(SelectPanel.new())
	add_child(p)
	p.set_candidates([
		{"id": "a", "name": "甲", "preview": null},
		{"id": "b", "name": "乙", "preview": null},
		{"id": "c", "name": "丙", "preview": null}])
	return p

func test_three_cards_same_capacity_text() -> void:
	var p := _panel()
	assert_int(p.card_count()).is_equal(3)
	for card in p.cards():
		assert_bool((card as Button).text.ends_with(SelectPanel.CAPACITY_TEXT)).is_true()
	assert_bool(p.confirm_button.disabled).is_true()

func test_focus_and_confirm_emit() -> void:
	var p := _panel()
	var focused: Array = []
	var confirmed: Array = []
	p.candidate_focused.connect(func(id): focused.append(id))
	p.confirmed.connect(func(id): confirmed.append(id))
	(p.cards()[1] as Button).emit_signal("pressed")
	assert_that(focused).is_equal(["b"])
	assert_str(p.focused_id).is_equal("b")
	assert_bool(p.confirm_button.disabled).is_false()
	p.confirm_button.emit_signal("pressed")
	assert_that(confirmed).is_equal(["b"])

func test_focus_api_marks_card_pressed() -> void:
	var p := _panel()
	p.focus("c")
	assert_bool((p.cards()[2] as Button).button_pressed).is_true()
	assert_str(p.focused_id).is_equal("c")
