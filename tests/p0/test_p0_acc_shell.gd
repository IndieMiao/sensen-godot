extends GdUnitTestSuite
## ACC-SHELL (SGODOT-491, 不知火舞's account spec v1 §0.1): on the 360 × 800 frame the wordmark at y 84, the farm art
## from y 330, the card 16 from the sides (328 wide) with its top at y 170, as tall as what is in it; no HUD, no ✕, and
## it takes every touch.

func _shell(h := 800.0) -> P0AccShell:
	var s := P0AccShell.new()
	add_child(auto_free(s))
	s.size = Vector2(360, h)
	return s

func test_the_frame_s_places() -> void:
	var s := _shell()
	s.add_title("What year were you born?")
	s.add_gap(24)
	var key := s.add_primary("Pick your birth year")
	await await_idle_frame()
	assert_vector(s.card.position).is_equal(Vector2(16, 170))
	assert_float(s.card.size.x).is_equal(328.0)
	assert_float(s.mark.position.y).is_equal(84.0)
	assert_float(s.mark.position.x + s.mark.size.x * 0.5).is_equal_approx(180.0, 1.0)
	assert_float((s.find_child("Backdrop", false, false) as Control).position.y).is_equal(330.0)
	assert_float(key.size.y).is_equal(48.0)
	assert_float(key.size.x).is_equal(286.0)   # ACC-AGE 633:197016: 21 in each side
	assert_float(s.col.position.y + key.position.y + key.size.y + 21.0).is_equal(s.card.size.y)   # the key's bottom 21 above the card's
	assert_float(s.col.position.y).is_equal(25.0)   # the title at y 25
	assert_int(s.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)

func test_the_card_grows_with_what_is_in_it_and_the_art_keeps_to_the_screen() -> void:
	var s := _shell(900.0)
	s.add_title("Before you start")
	await await_idle_frame()
	var one := s.card.size.y
	s.add_gap(8)
	s.add_body("Gensen is an online game with other players. We have zero tolerance for objectionable content or abusive behavior.")
	await await_idle_frame()
	assert_float(s.card.size.y).is_greater(one + 8.0 + 30.0)   # the line wraps to two rows or more
	assert_float((s.find_child("Backdrop", false, false) as Control).position.y).is_equal(roundf(330.0 * 900.0 / 800.0))
	assert_float(s.card.position.y).is_equal(170.0)   # the card's top stays where the frame has it
