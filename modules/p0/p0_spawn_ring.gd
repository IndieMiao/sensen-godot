class_name P0SpawnRing
extends RefCounted
## q(311) (SGODOT-470; 用户 bot 677, 补注 1): where a newcomer may stand in a room the others are in — its spawn, then two
## rings round it, in the order the server tries them (it stands the newcomer on the first nobody is near, rooms.ts).
## Each ring has six places 60° apart, none straight ahead or behind (a person in front hides the one behind): 2 right,
## 3 left (on the first one's line across the screen), 4 right-behind, 5 left-behind, 6 right-in-front, 7 left-in-front;
## "behind" is further from the camera (up the screen). A place is left out when the room's own check says no (walkable,
## seen whole, off seats and keepers, clear of the door key and the name strips, out of the way out's reach; q(311) ②).

const RINGS: Array[float] = [0.75, 1.5]
## Degrees from the screen's right towards "behind": right, left, right-behind, left-behind, right-in-front, left-in-front.
const ANGLES: Array[float] = [0.0, 180.0, 60.0, 120.0, 300.0, 240.0]
## The server reads this many (rooms.ts SPAWN_CANDIDATES_MAX): the spawn and the two rings.
const MAX := 13
## LOCK-34 v2 (197 00a0ca99): a person stands this far (px on the 360-wide screen) from the door key, a name strip, a
## seat icon.
const CLEAR_PX := 8.0
## A person's outline for those checks (安其拉's on 474: legs ±0.15, the body and arms ±0.32, the head ±0.22 m) — the
## widest of it, from the feet to the top of the head.
const HALF_WIDTH_M := 0.32
const HEIGHT_M := 1.75

## The ground's right and behind as the camera sees them (unit, y 0): its x axis, and its forward laid flat.
static func axes(cam: Camera3D) -> Array[Vector3]:
	var right := Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
	var behind := Vector3(-cam.global_basis.z.x, 0, -cam.global_basis.z.z).normalized()
	return [right, behind]

## The rings' places round `spawn`, in order (12, the spawn not among them), at the spawn's height.
static func ring(spawn: Vector3, right: Vector3, behind: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for r in RINGS:
		for a in ANGLES:
			var t := deg_to_rad(a)
			out.append(spawn + (right * cos(t) + behind * sin(t)) * r)
	return out

## The places sent on the visit's first join (x / z): the spawn, then each ring place `ok` (Callable(Vector3) -> bool)
## lets through, in order.
static func places(spawn: Vector3, right: Vector3, behind: Vector3, ok: Callable) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(spawn.x, spawn.z)]
	for p in ring(spawn, right, behind):
		if ok.call(p): out.append(Vector2(p.x, p.z))
	return out

## A person standing at `feet` on screen (px): from the feet to the top of the head, as wide as the widest of them.
static func person_rect(cam: Camera3D, feet: Vector3) -> Rect2:
	var right := axes(cam)[0] * HALF_WIDTH_M
	var pts := [feet - right, feet + right, feet - right + Vector3.UP * HEIGHT_M, feet + right + Vector3.UP * HEIGHT_M]
	var r := Rect2(cam.unproject_position(pts[0]), Vector2.ZERO)
	for p in pts.slice(1): r = r.expand(cam.unproject_position(p))
	return r

## Whether a person at `feet` keeps CLEAR_PX (on a 360-wide screen) from each of `rects` (screen px), and is on screen.
static func clear_of(cam: Camera3D, feet: Vector3, rects: Array) -> bool:
	var view := cam.get_viewport().get_visible_rect().size
	var me := person_rect(cam, feet)
	if not Rect2(Vector2.ZERO, view).encloses(me): return false
	var gap := CLEAR_PX * view.x / 360.0
	for r in rects:
		if (r as Rect2).grow(gap).intersects(me): return false
	return true
