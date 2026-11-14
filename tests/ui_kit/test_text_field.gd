extends GdUnitTestSuite
## UiTextField 9:104839: an error in red in place of the helper till the text changes; a cap in letters as the eye
## counts them.

func test_an_error_takes_the_helper_line_till_the_text_changes() -> void:
	var f: UiTextField = auto_free(UiTextField.new("Name", "Your name", "2–16 letters or numbers"))
	add_child(f)
	assert_str(f.helper_line.text).is_equal("2–16 letters or numbers")
	f.set_error("That name isn't allowed")
	assert_str(f.helper_line.text).is_equal("That name isn't allowed")
	assert_object(f.helper_line.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_DANGER)
	f.input.text = "Mira"
	f.input.text_changed.emit("Mira")
	assert_str(f.helper_line.text).is_equal("2–16 letters or numbers")

func test_the_cap_counts_letters_not_code_points() -> void:
	assert_int(UiTextField.graphemes("Mira")).is_equal(4)
	assert_int(UiTextField.graphemes("é")).is_equal(1)            # é as e and its accent
	assert_int(UiTextField.graphemes("👍🏽")).is_equal(1)                # a thumb and its skin tone
	assert_int(UiTextField.graphemes("田中花子")).is_equal(4)
	var f: UiTextField = auto_free(UiTextField.new())
	add_child(f)
	f.max_graphemes = 4
	f.input.text = "Mira"
	f.input.text_changed.emit("Mira")
	f.input.text = "Miras"
	f.input.text_changed.emit("Miras")
	assert_str(f.text).is_equal("Mira")   # the fifth letter does not go in
