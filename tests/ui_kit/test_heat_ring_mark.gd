extends GdUnitTestSuite
## HeatRing 483:355 (SGODOT-226, LOCK-20): the judged ring's dot sits on the track where the needle was when it was
## judged (用户 int10c, SGODOT-256 ⑩: it sat at a fixed top-right spot, not where the needle pointed).

func _tip(ring: UiHeatRing, t: float) -> Vector2:
	var ang := -PI * 0.5 + TAU * t
	return ring.size * 0.5 + Vector2(cos(ang), sin(ang)) * 46.0   # the track's centre line (r 42–50)

func test_the_dot_sits_where_the_needle_was_judged() -> void:
	var ring: UiHeatRing = auto_free(UiHeatRing.new())
	add_child(ring)
	for t in [0.0, 0.3, 0.55, 0.9, 1.0]:
		ring.turn = t
		ring.result = 1
		ring.mark_turn = t
		assert_vector(ring.mark_point()).override_failure_message(str(t)).is_equal_approx(_tip(ring, t), Vector2(0.01, 0.01))
	ring.mark_turn = 0.4   # judged at 0.4, the needle goes on turning: the dot stays put
	ring.turn = 0.8
	assert_vector(ring.mark_point()).is_equal_approx(_tip(ring, 0.4), Vector2(0.01, 0.01))
	ring.mark_turn = -1.0   # no judged turn known: on the needle
	assert_vector(ring.mark_point()).is_equal_approx(_tip(ring, 0.8), Vector2(0.01, 0.01))

## 不知火舞 on #131: once judged the needle stops on its dot until the ring folds; the dot is gold-deep for a hit, the
## disabled ink for a miss, with a surface edge, the track's width + 6 across.
func test_the_needle_stops_on_its_dot_once_judged() -> void:
	var ring: UiHeatRing = auto_free(UiHeatRing.new())
	add_child(ring)
	ring.turn = 0.8
	assert_float(ring.needle_turn()).is_equal(0.8)   # turning
	ring.result = 1
	ring.mark_turn = 0.4
	assert_float(ring.needle_turn()).is_equal(0.4)   # judged at 0.4: the needle waits there while the clock goes on
	ring.turn = 1.0
	assert_float(ring.needle_turn()).is_equal(0.4)
	ring.result = 0
	ring.mark_turn = 1.0   # went round untouched: stops at 12 o'clock with its dot
	assert_float(ring.needle_turn()).is_equal(1.0)
	assert_vector(ring.mark_point()).is_equal_approx(_tip(ring, 0.0), Vector2(0.01, 0.01))
	ring.result = -1   # the next ring
	ring.turn = 0.2
	assert_float(ring.needle_turn()).is_equal(0.2)
	assert_float(UiHeatRing._MARK * 2.0).is_equal(UiHeatRing._TRACK + 6.0)
