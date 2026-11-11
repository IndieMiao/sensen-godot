class_name P0Landing
extends RefCounted
## q(311) ④ (SGODOT-470): a visit's landing on the place the server picked. The world sends its places on the visit's
## first join (P0Online.start) and stands the player on `joined.spawn` when that first `joined` comes while the player has
## not moved; P0Runtime keeps the arrival cover up meanwhile (p0_landing_pending), WAIT_MS at most — past it the player
## stays on the spawn, a later `joined` moves nobody (the cover is gone, they would jump), and no later join sends places.

## How long the cover waits for the first `joined` (q(311) ④: 1.5 s, 后裔 may tune it on device).
const WAIT_MS := 1500
## Moved further than this since the places were sent: walked off, not landed.
const STILL_M := 0.05

var online: P0Online
var _until := -1   # Time.get_ticks_msec() the wait ends at; -1 none
var _from := Vector3.INF

## The visit's join is going out with `places` while the player stands at `at` (world): a wait when there is anywhere
## but the spawn to go.
func begin(o: P0Online, places: Array[Vector2], at: Vector3) -> void:
	online = o
	_from = at
	_until = Time.get_ticks_msec() + WAIT_MS if places.size() > 1 else -1

## Whether the cover should still wait (false past WAIT_MS, which also ends the wait).
func pending() -> bool:
	if _until < 0: return false
	if Time.get_ticks_msec() >= _until:
		over()
		return false
	return true

## No more waiting: the player stays where they are, and no later join of the visit sends places.
func over() -> void:
	_until = -1
	if online: online.forget_spawns()

## On a `joined`: where to stand the player now standing at `now` (room coordinates as the server's, the height kept),
## or INF to leave them — not the visit's first, the wait over, the player walked, or already there.
func target(info: Dictionary, now: Vector3) -> Vector3:
	var waiting := pending()
	_until = -1
	if not waiting or not bool(info.get("first", false)): return Vector3.INF
	var s = info.get("spawn")
	if not (s is Array and (s as Array).size() == 2): return Vector3.INF
	if Vector2(now.x - _from.x, now.z - _from.z).length() > STILL_M: return Vector3.INF
	var to := Vector3(float(s[0]), now.y, float(s[1]))
	return to if Vector2(to.x - now.x, to.z - now.z).length() > 0.01 else Vector3.INF
