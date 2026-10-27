extends RefCounted
## 341 aa0e971b: seven taps within 3 seconds, then a 2-second hold. No intermediate visual feedback.
const TAPS := 7
const WINDOW_MS := 3000
const HOLD_MS := 2000
var count := 0
var first := -1
var armed_until := -1
var down_at := Vector2.INF
var down_ms := -1
var holding := false

func reset() -> void:
	count = 0
	first = -1
	armed_until = -1
	down_at = Vector2.INF
	down_ms = -1
	holding = false

func press(at: Vector2, now: int) -> void:
	if armed_until >= now:
		holding = true
	elif armed_until >= 0:
		reset()
	elif first >= 0 and now - first > WINDOW_MS:
		reset()
	down_at = at
	down_ms = now

func move(at: Vector2) -> void:
	if down_at != Vector2.INF and at.distance_to(down_at) > GestureArbiter.TAP_SLOP: reset()

func release(at: Vector2, now: int) -> void:
	if down_at == Vector2.INF: return
	if holding or at.distance_to(down_at) > GestureArbiter.TAP_SLOP:
		reset()
		return
	if first < 0 or now - first > WINDOW_MS:
		count = 0
		first = down_ms
	count += 1
	down_at = Vector2.INF
	down_ms = -1
	if count == TAPS: armed_until = now + WINDOW_MS

func tick(now: int) -> bool:
	if not holding or down_ms < 0 or now - down_ms < HOLD_MS: return false
	reset()
	return true
