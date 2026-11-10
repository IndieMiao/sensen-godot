extends GdUnitTestSuite
## MapDestination 1795:103793 (LOCK-24, SGODOT-234 A2; Label=Short 2391:127664, q(137)): 40 disc with a 24 icon, the
## name under it — the homestead's whole on a plate, the others the short name (11 Bold, cream outline, at most 96) —
## a StatusBadge over the disc's top-left for a map mark, the online count (a person and the number) top-right.

func _pin(text := "Oak Tea House", plate := false) -> UiMapDestination:
	var d := UiMapDestination.new(P0Logic.icon("pot"), text, plate)
	d.theme = UiKit.theme()
	add_child(auto_free(d))
	return d

func test_disc_icon_and_the_short_name_under_it() -> void:
	var d := _pin("Oak")
	var home := _pin("Home", true)
	await get_tree().process_frame
	assert_that(d._disc.size).is_equal(Vector2(40, 40))
	assert_that(d._icon.size).is_equal(Vector2(24, 24))
	assert_that(d._icon.position).is_equal(Vector2(8, 8))
	assert_str(d._label.text).is_equal("Oak")
	# Label=Short (q(137)): 11 Bold dark, a cream outline, no plate, one line cut with an ellipsis past 96 px
	assert_str(d._label.theme_type_variation).is_equal(UiTokens.STYLE_C11_B)
	assert_that(d._label.get_theme_color(&"font_outline_color")).is_equal(UiTokens.COLOR_SURFACE)
	assert_int(d._label.get_theme_constant(&"outline_size")).is_equal(UiMapDestination._SHORT_HALO)
	assert_int(d._label.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	# the homestead keeps its plate, 10 Bold and its whole name
	assert_str(home._label.theme_type_variation).is_equal(UiTokens.STYLE_C10_B)
	assert_int(home._label.get_theme_constant(&"outline_size")).is_equal(0)
	assert_int(home._label.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	var long := _pin("Hummingbird Kingfisher Frangipani")
	await get_tree().process_frame
	assert_float(long.label_size().x).is_equal(UiMapDestination.SHORT_MAX_W)
	var l := d.label_size()
	assert_float(d.size.x).is_equal_approx(maxf(40.0, l.x), 0.5)   # a long name widens it, the disc stays centred
	assert_float(d._pin.position.x + 20.0).is_equal_approx(d.size.x * 0.5, 0.5)
	assert_float(d._label_box.position.y).is_equal(42.0)
	assert_that(d.anchor_offset()).is_equal(Vector2(d.size.x * 0.5, 40.0))
	var fp := d.footprint()
	assert_that([fp.position.y, fp.end.y]).is_equal([-40.0, 2.0 + l.y])

func test_only_the_homestead_has_a_plate() -> void:
	var plain := _pin()
	var home := _pin("Home", true)
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
## style token and padding (刘邦 on #100): the homestead's plate, the others' short name (q(137)).
func test_the_static_name_size_is_the_built_one() -> void:
	var names := ["Home", "Oak", "Union Square", "Hummingbird Kingfisher Frangipani"]
	var pins: Array = names.map(func(n): return _pin(n, n == "Home"))
	await get_tree().process_frame
	for i in names.size():
		assert_that((pins[i] as UiMapDestination).label_size()).append_failure_message(names[i]) \
			.is_equal(UiMapDestination.label_size_for(names[i], names[i] == "Home"))
	assert_that(UiMapDestination.label_size_for("")).is_equal(Vector2.ZERO)

## q(137) ③: who is in is the top-right count, a person and the number; none at 0.
func test_the_online_count_is_a_person_and_the_number() -> void:
	var d := _pin("Oak")
	assert_bool(d._count.visible).is_false()
	d.online = 3
	assert_bool(d._count.visible).is_true()
	assert_bool(d._count_person.visible).is_true()
	assert_object(d._count_person.texture).is_not_null()
	assert_str(d._count_label.text).is_equal("3")
	assert_that(d._count.position).is_equal(UiMapDestination._COUNT_AT)
	d.online = 0
	assert_bool(d._count.visible).is_false()

## int9: a name near the screen edge slides in; the disc keeps its place over the point.
func test_a_shifted_name_moves_only_the_name() -> void:
	var d := _pin("Mission Tackle Shop · 3 online")
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
	var d := _pin("Mission Market Square")
	await get_tree().process_frame
	var disc_at := d._pin.position
	d.label_above = true
	var l := d.label_size()
	assert_that(d._pin.position).is_equal(disc_at)
	assert_float(d._label_box.position.y).is_equal_approx(-2.0 - l.y, 0.01)
	var fp := d.footprint()
	assert_float(fp.position.y).is_equal_approx(-40.0 - 2.0 - l.y, 0.01)
	assert_float(fp.end.y).is_equal_approx(0.0, 0.01)

## 刘邦 on #111: a name over a marked disc clears the mark's badge (it pokes MARK_OVERHANG over the disc's top).
func test_a_name_over_a_marked_disc_clears_its_badge() -> void:
	var d := _pin("Reed Pond · Beginner pond")
	d.mark = "request"
	await get_tree().process_frame
	d.above_gap = UiMapDestination.above_gap_for(true)
	d.label_above = true
	var name_bottom := d._label_box.position.y + d.label_size().y
	var badge_top := d._pin.position.y + d._badge.position.y
	assert_float(name_bottom).is_less_equal(badge_top - UiMapDestination.LABEL_GAP + 0.01)
	assert_float(UiMapDestination.above_gap_for(false)).is_equal(UiMapDestination.LABEL_GAP)
