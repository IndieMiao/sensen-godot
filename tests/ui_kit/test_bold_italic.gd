extends GdUnitTestSuite
## UiKit.bold_italic (不知火舞 on 284): the Bite Board keeper's line and the Postcards' Kindred lines are Bold Italic —
## the bold token's font file at its own weight, slanted. A FontVariation over the bold FontVariation lost the weight
## and drew those lines thin.

const LINE := "Best friend on the whole route. Don't tell the pigeons."

func test_bold_italic_is_the_bold_weight_slanted() -> void:
	var f := UiKit.bold_italic()
	var bold := UiKit.font(&"bold") as FontVariation
	assert_bool(f.base_font is FontFile).is_true()   # never a variation over a variation
	assert_dict(f.variation_opentype).is_equal(bold.variation_opentype)
	assert_int(int(f.variation_opentype.values()[0])).is_equal(700)
	# slanted as Godot's FontVariation docs slant: Transform2D(1.0, slant, 0.0, 1.0, 0.0, 0.0)
	assert_float(f.variation_transform.x.y).is_equal_approx(UiKit.ITALIC_SKEW, 0.0001)
	assert_float(f.variation_transform.y.x).is_equal(0.0)
	assert_object(UiKit.bold_italic()).is_same(f)   # made once
	# drawn at the bold weight: as wide as Bold (the slant moves no advance), wider than Regular
	var w := func(font: Font) -> float: return font.get_string_size(LINE, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	assert_float(w.call(f)).is_equal_approx(w.call(bold), 0.01)
	assert_float(w.call(f)).is_greater(w.call(UiKit.font(&"regular")) + 2.0)
