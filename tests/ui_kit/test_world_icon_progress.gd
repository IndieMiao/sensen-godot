extends GdUnitTestSuite
## SGODOT-475 (不知火舞's gather-compact spec ① 1): UiWorldIconButton's cooling state — the same 28 disc, the icon at 16 and
## dimmed, the 2.5 arc on its track (the HUD buff circle's drawing); back to the plain button when ready.

func test_cooling_shrinks_and_dims_the_icon_and_shows_the_ring_and_ready_puts_it_back() -> void:
	var b: UiWorldIconButton = auto_free(UiWorldIconButton.new())
	add_child(b)
	b.icon = PlaceholderTexture2D.new()
	assert_float(b._glyph.size.x).is_equal(22.0)
	assert_bool(b._ring.visible).is_false()
	b.progress = 0.2
	assert_float(b._glyph.size.x).is_equal(UiWorldIconButton.PROGRESS_ICON)
	assert_float(b._glyph.modulate.a).is_equal_approx(UiWorldIconButton.PROGRESS_DIM, 0.001)
	assert_bool(b._ring.visible).is_true()
	assert_vector(b.drawn_rect().size).is_equal(Vector2(28, 28))   # the same disc: hosts place it as before
	b.progress = 1.5
	assert_float(b.progress).is_equal(1.0)   # clamped
	b.progress = -1.0
	assert_float(b._glyph.size.x).is_equal(22.0)
	assert_float(b._glyph.modulate.a).is_equal(1.0)
	assert_bool(b._ring.visible).is_false()
