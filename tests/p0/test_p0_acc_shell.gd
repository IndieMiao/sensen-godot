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
	assert_object(P0SysScreen.BACKDROP).is_same(P0AccShell.BACKDROP)   # maintenance and update on the same cream (bot 733)

## Spec v1.1 §1.5: the keyboard up for a tapped field — the wordmark out; the card up only if the primary key is
## covered, till its foot is 12 over the keyboard; down, all back (250 ms ease-out).
func test_the_keyboard_fades_the_wordmark_and_lifts_the_card_only_when_the_key_is_covered() -> void:
	var page: P0AccName = auto_free(P0AccName.new(true))
	var kb := [0.0]
	page.keyboard_height = func() -> float: return kb[0]
	add_child(page)
	page.size = Vector2(360, 800)
	await await_idle_frame()
	var rest := page.card.position.y
	page.field.input.grab_focus()
	kb[0] = 120.0   # a short keyboard: the key is clear, only the wordmark goes
	await get_tree().create_timer(P0AccShell.KEYBOARD_S + 0.15).timeout
	assert_float(page.mark.modulate.a).is_equal_approx(0.0, 0.01)
	assert_float(page.card.position.y).is_equal(rest)
	kb[0] = 380.0   # a tall one covers the key: the card goes up till its foot is 12 over it
	await get_tree().create_timer(P0AccShell.KEYBOARD_S + 0.15).timeout
	var foot := page.go.get_global_rect().end.y - page.global_position.y
	assert_float(foot).is_equal_approx(800.0 - 380.0 - P0AccShell.KEY_CLEAR, 1.0)
	assert_float(page.card.position.y).is_less(rest)
	kb[0] = 0.0   # down: all back
	await get_tree().create_timer(P0AccShell.KEYBOARD_S + 0.15).timeout
	assert_float(page.mark.modulate.a).is_equal_approx(1.0, 0.01)
	assert_float(page.card.position.y).is_equal_approx(rest, 0.5)

func test_a_keyboard_with_no_field_tapped_moves_nothing() -> void:
	var page: P0AccName = auto_free(P0AccName.new(true))
	page.keyboard_height = func() -> float: return 380.0
	add_child(page)
	page.size = Vector2(360, 800)
	await get_tree().create_timer(P0AccShell.KEYBOARD_S + 0.15).timeout
	assert_float(page.mark.modulate.a).is_equal(1.0)
	assert_float(page.lift).is_equal(0.0)

func test_a_page_with_no_primary_keeps_its_own_row_over_the_keyboard() -> void:
	var s := P0AccShell.new()
	s.keyboard_height = func() -> float: return 380.0
	add_child(auto_free(s))
	s.size = Vector2(360, 800)
	s.add_title("Enter the code")
	s.add_gap(300)   # the row sits low: the keyboard covers it
	var field := UiTextField.new("Code")
	s.col.add_child(field)
	s.keep_above_keyboard = field
	await await_idle_frame()
	field.input.grab_focus()
	await get_tree().create_timer(P0AccShell.KEYBOARD_S + 0.15).timeout
	var foot := field.get_global_rect().end.y - s.global_position.y
	assert_float(foot).is_equal_approx(800.0 - 380.0 - P0AccShell.KEY_CLEAR, 1.0)
