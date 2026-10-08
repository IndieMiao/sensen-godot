extends GdUnitTestSuite
## InboxNotice 1860:104768 (BAG-5-2 482:146, q(87)): 282 × 74, the main's text positions and styles, a tap emits.

const PARCEL := preload("res://assets/p0/icons/parcel.svg")

func _card(spec: Dictionary) -> UiInboxNotice:
	var c := UiInboxNotice.new()
	c.theme = UiKit.theme()
	add_child(auto_free(c))
	c.show_notice(spec, PARCEL)
	return c

func test_it_lays_out_as_the_main() -> void:
	var c := _card({title = "Sent to Inbox", item = "Perch", quantity = "×7", line = "Expires in 24h"})
	await await_idle_frame()
	assert_vector(c.size).is_equal(Vector2(282, 74))
	var box: UiStyleBox = c.get_theme_stylebox(&"panel")
	assert_object(box.bg_color).is_equal(UiTokens.COLOR_SURFACE)
	assert_float(box.corner_radius.x).is_equal(float(UiTokens.RADIUS_CARD))
	assert_float(box.border_width).is_equal(0.0)
	var at := func(l: Control) -> Vector2: return l.get_global_rect().position - c.get_global_rect().position
	assert_vector(at.call(c._icon)).is_equal(Vector2(10, 12))   # i-parcel 24 at (10, 12)
	assert_vector(c._icon.size).is_equal(Vector2(24, 24))
	assert_vector(at.call(c._title)).is_equal(Vector2(42, 8))
	assert_vector(at.call(c._item)).is_equal(Vector2(42, 28))
	assert_float(at.call(c._line).y).is_equal(49.0)
	assert_float(c._qty.get_global_rect().end.x - c.get_global_rect().position.x).is_equal(268.0)   # ×N ends at 268
	assert_float(c._qty.size.x).is_equal(c._qty.get_minimum_size().x)   # never clipped
	assert_float(c._qty.size.x).is_greater(8.0)
	assert_float(at.call(c._qty).y).is_equal(28.0)
	assert_str(c._title.theme_type_variation).is_equal(UiTokens.STYLE_C12_XB)
	assert_str(c._item.theme_type_variation).is_equal(UiTokens.STYLE_C11_B)
	assert_str(c._qty.theme_type_variation).is_equal(UiTokens.STYLE_C12_XB)
	assert_str(c._line.theme_type_variation).is_equal(UiTokens.STYLE_C10_B)
	assert_object(c._line.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)

func test_the_longest_lines_stay_inside_the_card() -> void:
	# q(87): the longest dish name and `+12 more · Claim a parcel first` fit (李白 measured; 146 / 176 px in the main).
	var c := _card({title = "Inbox full · waiting", item = "Herb Grilled Fish ★★", quantity = "×12", line = "+12 more · Claim a parcel first"})
	await await_idle_frame()
	assert_vector(c.size).is_equal(Vector2(282, 74))
	for l in [c._item, c._line]:
		assert_float((l as Label).get_minimum_size().x).is_less_equal((l as Label).size.x)

func _touch(c: UiInboxNotice, pressed: bool, at: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.pressed = pressed
	t.position = at
	c._gui_input(t)

func test_a_tap_emits_tapped_and_a_drag_does_not() -> void:
	var c := _card({title = "Sent to Inbox", item = "Perch", quantity = "×7", line = "Expires in 24h"})
	var hits := [0]
	c.tapped.connect(func(): hits[0] += 1)
	_touch(c, true, Vector2(100, 30))
	_touch(c, false, Vector2(102, 31))
	assert_int(hits[0]).is_equal(1)
	_touch(c, true, Vector2(100, 30))
	_touch(c, false, Vector2(100, 30 + GestureArbiter.TAP_SLOP + 30))
	assert_int(hits[0]).is_equal(1)
