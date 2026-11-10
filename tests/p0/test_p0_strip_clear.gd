extends GdUnitTestSuite
## SGODOT-473 (LOCK-07 ff03be3f, 197 86e94ab9): a world name strip kept clear of the player — the farm's exit and the
## ponds' gathering points: over the head or upper body at its mark it rises at once, its bottom HEAD_PX over the head;
## not over them it eases back over BACK_S; a strip not open asks nothing of the player.

const StripClear := preload("res://modules/p0/p0_strip_clear.gd")
const H := 32.0   # UiWorldNameBar._H

## A strip 120 × 32 whose mark (its centre) is at y 300, x 200–320.
func _strip() -> Rect2: return Rect2(200, 300 - H * 0.5, 120, H)

func test_over_the_head_it_rises_at_once_clear_of_it() -> void:
	var c := StripClear.new()
	var body := Rect2(220, 280, 40, 100)   # head at 280, upper body to 330: under the strip
	var lift := c.step(1.0 / 30.0, _strip(), 300.0, func(): return body)
	assert_float(300.0 + lift + H * 0.5).is_equal_approx(280.0 - StripClear.HEAD_PX, 0.01)   # its bottom 6 px over the head

func test_beside_or_below_it_stays_at_its_mark() -> void:
	var c := StripClear.new()
	assert_float(c.step(0.1, _strip(), 300.0, func(): return Rect2(400, 280, 40, 100))).is_equal(0.0)   # off to its side
	assert_float(c.step(0.1, _strip(), 300.0, func(): return Rect2(220, 340, 40, 100))).is_equal(0.0)   # the head under the strip's foot

func test_once_clear_it_eases_back_then_rests_at_its_mark() -> void:
	var c := StripClear.new()
	var up := c.step(0.0, _strip(), 300.0, func(): return Rect2(220, 280, 40, 100))
	var mid := c.step(StripClear.BACK_S * 0.5, _strip(), 300.0, func(): return Rect2(400, 280, 40, 100))
	assert_float(mid).is_greater(up)
	assert_float(mid).is_less(0.0)
	assert_float(c.step(StripClear.BACK_S, _strip(), 300.0, func(): return Rect2(400, 280, 40, 100))).is_equal(0.0)

func test_a_strip_not_open_never_asks_for_the_player_and_reset_puts_it_back() -> void:
	var c := StripClear.new()
	var asked := [0]
	assert_float(c.step(0.1, Rect2(), 300.0, func(): asked[0] += 1; return Rect2())).is_equal(0.0)
	assert_int(asked[0]).is_equal(0)   # no screen box worked out for a strip not up (the pond: most frames)
	c.step(0.0, _strip(), 300.0, func(): return Rect2(220, 280, 40, 100))
	c.reset()
	assert_float(c.lift).is_equal(0.0)
