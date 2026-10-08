extends GdUnitTestSuite
## MapDestination 1795:103793 (LOCK-24, SGODOT-234 A2): 40 disc with a 24 icon, the whole name under it (a plate only
## for the homestead), a StatusBadge over the disc's top-left for a map mark, ×N top-right (P1).

func _pin(text := "Lotus Tea House", plate := false) -> UiMapDestination:
	var d := UiMapDestination.new(P0Logic.icon("pot"), text, plate)
	d.theme = UiKit.theme()
	add_child(auto_free(d))
	return d

func test_disc_icon_and_the_whole_name_under_it() -> void:
	var d := _pin()
	await get_tree().process_frame
	assert_that(d._disc.size).is_equal(Vector2(40, 40))
	assert_that(d._icon.size).is_equal(Vector2(24, 24))
	assert_that(d._icon.position).is_equal(Vector2(8, 8))
	assert_str(d._label.text).is_equal("Lotus Tea House")
	assert_int(d._label.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	var l := d.label_size()
	assert_float(d.size.x).is_equal_approx(maxf(40.0, l.x), 0.5)   # a long name widens it, the disc stays centred
	assert_float(d._pin.position.x + 20.0).is_equal_approx(d.size.x * 0.5, 0.5)
	assert_float(d._label_box.position.y).is_equal(42.0)
	assert_that(d.anchor_offset()).is_equal(Vector2(d.size.x * 0.5, 40.0))
	var fp := d.footprint()
	assert_that([fp.position.y, fp.end.y]).is_equal([-40.0, 2.0 + l.y])

func test_only_the_homestead_has_a_plate() -> void:
	var plain := _pin()
	var home := _pin("Homestead", true)
	await get_tree().process_frame
	assert_that((plain._label_box.get_theme_stylebox(&"panel") as UiStyleBox).bg_color.a).is_equal(0.0)
	assert_that((home._label_box.get_theme_stylebox(&"panel") as UiStyleBox).bg_color).is_equal(UiTokens.COLOR_SURFACE)

func test_a_mark_hangs_a_status_badge_on_the_top_left() -> void:
	var d := _pin()
	assert_object(d._badge).is_null()
	d.mark = "request"
	assert_int(d._badge.state).is_equal(UiStatusBadge.State.REQUEST)
	assert_that(d._badge.position).is_equal(Vector2(-8, -8))
	d.mark = "deliverable"
	assert_int(d._badge.state).is_equal(UiStatusBadge.State.DELIVERABLE)
	d.mark = ""
	assert_bool(d._badge.visible).is_false()
	d.count = "×6"   # P1 clusters
	assert_bool(d._count.visible).is_true()
	assert_that(d._count.position).is_equal(Vector2(26, -4))
