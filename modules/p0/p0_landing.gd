class_name P0Landing
extends RefCounted
## q(311) ④ (SGODOT-470): a visit's landing on the place the server picked. The world sends its places on the visit's
## first join (P0Online.start) and stands the player on `joined.spawn` when that first `joined` comes while the player has
## not moved; P0Runtime keeps the arrival cover up meanwhile (p0_landing_pending), WAIT_MS at most once the room's socket
## is open — past it the player stays on the spawn, a later `joined` moves nobody (the cover is gone, they would jump),
## and no later join sends places. Each step says so in the log (`P0 q311`).

## How long the cover waits for the first `joined` once the socket is open (q(311) ④: 1.5 s) — and at least MIN_FRAMES
## frames run meanwhile (周瑜 on #988): a slow first load (gs66, 11-11: 4 s between a landmark's attach and its first
## frame) has long frames, and one 4 s frame ate the whole wait though the room answered at once; counted in frames too,
## a stall is one frame, before the socket opens or after.
const WAIT_MS := 1500
## … and before the socket is open, at most this long (and MIN_FRAMES) from the join's going out: a room that does not
## answer keeps the cover up no longer than that on any phone.
const CONNECT_MS := 2000
const MIN_FRAMES := 20
## Moved further than this since the places were sent: walked off, not landed.
const STILL_M := 0.05

var online: P0Online
var room := ""
var _until := -1   # Time.get_ticks_msec() the wait ends at; -1 none
var _t0 := 0       # when the places went out (or were expected)
var _from := Vector3.INF
var _frame0 := 0   # Engine.get_process_frames() the current wait began at

## A world that works its places out once its first read is in (a pond: the day's gathering points and trees) or its
## ground is in (a landmark's navigation) expects the join: the cover waits for it too, EXPECT_MS at most, until begin.
const EXPECT_MS := 3000
func expect() -> void:
	_t0 = Time.get_ticks_msec()
	_until = _t0 + EXPECT_MS
	_frame0 = Engine.get_process_frames()

## The visit's join is going out with `places` while the player stands at `at` (world): a wait when there is anywhere
## but the spawn to go.
func begin(o: P0Online, places: Array[Vector2], at: Vector3) -> void:
	online = o
	room = o.outpost
	_from = at
	_t0 = Time.get_ticks_msec()
	_until = _t0 + CONNECT_MS if places.size() > 1 else -1
	_frame0 = Engine.get_process_frames()
	print("P0 q311 %s: %d place%s%s" % [room, places.size(), "" if places.size() == 1 else "s", ", waiting" if places.size() > 1 else ""])
	if places.size() > 1 and not o.connection_changed.is_connected(_on_connection):
		o.connection_changed.connect(_on_connection)
		o.unreachable.connect(_on_no_room)
		o.failed.connect(_on_no_room.unbind(1))

## The room refused us or cannot be reached (不知火舞 on #988: no waiting then — only a socket still opening, no answer
## yet, waits CONNECT_MS): the cover goes at once, the player stays on the spawn.
func _on_no_room() -> void:
	if _until < 0: return
	print("P0 q311 %s: connection failed (refused or unreachable) after %d ms, stays on the spawn" % [room, Time.get_ticks_msec() - _t0])
	over()

func _on_connection(up: bool) -> void:
	if not up or _until < 0: return
	_until = Time.get_ticks_msec() + WAIT_MS
	_frame0 = Engine.get_process_frames()
	print("P0 q311 %s: connected after %d ms" % [room, Time.get_ticks_msec() - _t0])

## Whether the cover should still wait (false past the wait — its time and MIN_FRAMES both — which also ends it).
func pending() -> bool:
	if _until < 0: return false
	if Time.get_ticks_msec() >= _until and Engine.get_process_frames() - _frame0 >= MIN_FRAMES:
		print("P0 q311 %s: no joined in time (%d ms), stays on the spawn" % [room, Time.get_ticks_msec() - _t0])
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
	if not bool(info.get("first", false)): return Vector3.INF
	var s = info.get("spawn")
	var ms := Time.get_ticks_msec() - _t0
	if not waiting:
		print("P0 q311 %s: joined after %d ms, not waiting: left where they are" % [room, ms])
		return Vector3.INF
	if not (s is Array and (s as Array).size() == 2): return Vector3.INF
	if Vector2(now.x - _from.x, now.z - _from.z).length() > STILL_M:
		print("P0 q311 %s: joined after %d ms, walked off: left" % [room, ms])
		return Vector3.INF
	var to := Vector3(float(s[0]), now.y, float(s[1]))
	var there := Vector2(to.x - now.x, to.z - now.z).length() <= 0.01
	print("P0 q311 %s: joined after %d ms, %s" % [room, ms, "on the spawn" if there else "landed at (%.2f, %.2f)" % [to.x, to.z]])
	return Vector3.INF if there else to
