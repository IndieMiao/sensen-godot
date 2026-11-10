extends RefCounted
## A world name strip kept clear of the player (LOCK-07 ff03be3f; 不知火舞 / 上官婉儿 on 443, the farm's exit first; 197
## 86e94ab9, the ponds' gathering points with U2, SGODOT-473): while the strip, at its mark, would cover the player's head
## or upper body on screen, it rises — its bottom HEAD_PX over the head's top — at once; once it would not, it eases back
## to its mark over BACK_S. One per strip shown; step() each frame, its `lift` (≤ 0 px, screen up) added to the mark.

const HEAD_PX := 6.0
const BACK_S := 0.12

var lift := 0.0
var _from := 0.0   # where it was when it started back
var _t := -1.0     # s into easing back (< 0: not easing)

## `strip`: the open strip's rect now (P0Ui.name_bar_rect; empty when it is not open); `centre`: its mark's screen y;
## `body`: the player on screen (P0Actor.screen_box), asked only while the strip is open.
func step(dt: float, strip: Rect2, centre: float, body: Callable) -> float:
	var want := 0.0
	if strip.has_area():
		strip.position.y = centre - strip.size.y * 0.5   # where it is at its mark
		var box: Rect2 = body.call()
		var upper := Rect2(box.position, Vector2(box.size.x, box.size.y * 0.5))   # the head and the upper body
		if strip.intersects(upper): want = minf(0.0, box.position.y - HEAD_PX - UiWorldNameBar._H * 0.5 - centre)
	if want <= lift:
		lift = want
		_t = -1.0
		return lift
	if _t < 0.0:
		_from = lift
		_t = 0.0
	_t += dt
	var k := clampf(_t / BACK_S, 0.0, 1.0)
	lift = lerpf(_from, want, ease(k, -2.0))
	if k >= 1.0: _t = -1.0
	return lift

## Back at its mark at once (another strip takes its place).
func reset() -> void:
	lift = 0.0
	_t = -1.0
