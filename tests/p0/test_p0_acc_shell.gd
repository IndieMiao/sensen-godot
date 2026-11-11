extends GdUnitTestSuite
## ACC-SHELL (SGODOT-491, 不知火舞's account spec v1.1 §0.1, C): on the 360 × 800 frame the brand cream (scheme 3) over
## the whole screen, the wordmark at y 84, the card 16 from the sides (328 wide) with its top at y 170, as tall as what
## is in it; no HUD, no ✕, and it takes every touch.

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
	var art := s.find_child("Backdrop", false, false) as Control
	assert_vector(art.position).is_equal(Vector2.ZERO)   # the art the 360 × 800 frame itself
	assert_vector(art.size).is_equal(Vector2(360, 800))
	assert_float(key.size.y).is_equal(48.0)
	assert_float(key.size.x).is_equal(286.0)   # ACC-AGE 633:197016: 21 in each side
	assert_float(s.col.position.y + key.position.y + key.size.y + 21.0).is_equal(s.card.size.y)   # the key's bottom 21 above the card's
	assert_float(s.col.position.y).is_equal(25.0)   # the title at y 25
	assert_int(s.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)

func test_the_card_grows_with_what_is_in_it_and_the_art_keeps_to_the_screen_s_foot() -> void:
	var s := _shell(900.0)
	s.add_title("Before you start")
	await await_idle_frame()
	var one := s.card.size.y
	s.add_gap(8)
	s.add_body("Gensen is an online game with other players. We have zero tolerance for objectionable content or abusive behavior.")
	await await_idle_frame()
	assert_float(s.card.size.y).is_greater(one + 8.0 + 30.0)   # the line wraps to two rows or more
	var art := s.find_child("Backdrop", false, false) as Control
	assert_vector(art.position).is_equal(Vector2(0, 100))   # a tall screen: the art on its foot, the cream above
	assert_vector(art.size).is_equal(Vector2(360, 800))
	assert_object((s.find_child("Surface", false, false) as ColorRect).color).is_equal(P0AccShell.GROUND)
	s.size = Vector2(360, 780)   # 19.5:9 (row 159 661:199048): the art's cream top cut, its foot on the screen's
	await await_idle_frame()
	assert_float(art.position.y + art.size.y).is_equal(780.0)
	assert_float(s.card.position.y).is_equal(170.0)   # the card's top stays where the frame has it

## The art is one to swap (the user 11-11: the first launch's art to change): `backdrop` takes another.
func test_the_backdrop_can_be_swapped() -> void:
	var s := _shell()
	var art := s.find_child("Backdrop", false, false) as TextureRect
	assert_object(art.texture).is_same(P0AccShell.BACKDROP)
	var other := GradientTexture2D.new()   # 64 × 64
	s.backdrop = other
	assert_object(art.texture).is_same(other)
	assert_vector(art.size).is_equal(Vector2(360, 360))   # laid out by its own shape
	assert_object(P0SysScreen.BACKDROP).is_not_same(P0AccShell.BACKDROP)   # the game's other system screens keep the farm
