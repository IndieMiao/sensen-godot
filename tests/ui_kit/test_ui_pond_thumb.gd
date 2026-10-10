extends GdUnitTestSuite
## PondThumb (Figma 2254:122909; 283 f74fafae / a08d2a5c): radius 12 at both sizes, the template's picture, a 22 px fish
## badge only where given (the Bite Board row), none on the pond card.

func test_the_row_thumb_has_its_template_and_the_badge() -> void:
	var t: UiPondThumb = auto_free(UiPondThumb.new("river", UiPondThumb.ROW, "fish_catfish"))
	assert_vector(t.custom_minimum_size).is_equal(Vector2(72, 56))
	assert_str(t.template_path()).ends_with("pond_thumb_river.png")
	assert_bool(t.badge_shown()).is_true()

func test_the_card_thumb_has_no_badge_and_unknown_templates_fall_back_to_pond() -> void:
	var t: UiPondThumb = auto_free(UiPondThumb.new("lake", UiPondThumb.CARD))
	assert_vector(t.custom_minimum_size).is_equal(Vector2(56, 44))
	assert_str(t.template_path()).ends_with("pond_thumb_pond.png")
	assert_bool(t.badge_shown()).is_false()
	assert_int(UiPondThumb.RADIUS).is_equal(12)
