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

## The city map packs pins by label_size_for before any pin exists: it measures what a built pin draws, in its own
## style token (STYLE_C10_B) and plate padding (刘邦 on #100).
func test_the_static_name_size_is_the_built_one() -> void:
	var names := ["Homestead", "Lotus Tea House · 3 online", "Reed Pond · Beginner pond · 1.2 km", "Xuhui Tackle Shop"]
	var pins: Array = names.map(func(n): return _pin(n, n == "Homestead"))
	await get_tree().process_frame
	for i in names.size():
		assert_that((pins[i] as UiMapDestination).label_size()).append_failure_message(names[i]) \
			.is_equal(UiMapDestination.label_size_for(names[i]))
	assert_that(UiMapDestination.label_size_for("")).is_equal(Vector2.ZERO)

## int9: a name near the screen edge slides in; the disc keeps its place over the point.
func test_a_shifted_name_moves_only_the_name() -> void:
	var d := _pin("Xuhui Tackle Shop · 3 online")
	await get_tree().process_frame
	var disc_at := d._pin.position
	var name_at := d._label_box.position
	d.label_shift = 30.0
	assert_that(d._pin.position).is_equal(disc_at)
	assert_float(d._label_box.position.x).is_equal_approx(name_at.x + 30.0, 0.01)
	assert_float(d.footprint().end.x).is_equal_approx(d.label_size().x * 0.5 + 30.0, 0.01)

func test_status_badge_state_of_a_key() -> void:
	assert_int(UiStatusBadge.state_of("request")).is_equal(UiStatusBadge.State.REQUEST)
	assert_int(UiStatusBadge.state_of("deliverable")).is_equal(UiStatusBadge.State.DELIVERABLE)
	assert_int(UiStatusBadge.state_of("")).is_equal(-1)

## The city map's second place for a name: over the disc (不知火舞 on 234 A2); the disc keeps its place.
func test_a_name_over_the_disc() -> void:
	var d := _pin("Xuhui Market Square")
	await get_tree().process_frame
	var disc_at := d._pin.position
	d.label_above = true
	var l := d.label_size()
	assert_that(d._pin.position).is_equal(disc_at)
	assert_float(d._label_box.position.y).is_equal_approx(-2.0 - l.y, 0.01)
	var fp := d.footprint()
	assert_float(fp.position.y).is_equal_approx(-40.0 - 2.0 - l.y, 0.01)
	assert_float(fp.end.y).is_equal_approx(0.0, 0.01)
