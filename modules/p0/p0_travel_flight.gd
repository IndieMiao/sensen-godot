class_name P0TravelFlight
extends RefCounted
## The cross-city flight's camera (q(147), SGODOT-299; 不知火舞 on 299 31c4ceb5, 62931cdb): a fixed 3 s, whatever the
## Trip — up 0.5 s from where the camera is until the city left and the city ahead are both in view (q(152) ③), then
## 2.0 s where only the plane flies and the camera holds that overview (q(156); a pair that does not fit even at the
## floor pans along instead, fast then slowing), down 0.5 s to the city's overview (q(25)). Up and down ease in and
## out. No jump back to the city left first: the camera may already be over the city ahead (a bubble's browse), and it
## rises from there.

const UP_S := 0.5
const FLY_S := 2.0
const DOWN_S := 0.5
const TOTAL_S := UP_S + FLY_S + DOWN_S

## The overview is never further out than this (q(152) ③: near a whole-world view; a pair nearly opposite on the globe
## stops here, its route coming in from the edge), nor closer in than a step under the nearer of the two ends.
const TOP_MIN_ZOOM := 0.8
## How finely the overview's zoom is searched.
const FIT_STEP := 0.05

var _c0: Vector2   # mercator x, y
var _mid: Vector2
## The camera over the two ends at the top as the map shows it: _mid with its y kept off the world's edges (周瑜 on
## #345: far out at a high latitude the map moved the centre toward the equator, and the landing, reckoned from _mid,
## did not run from where the camera stood).
var _held: Vector2
var _c1: Vector2
var _view := Vector2.ZERO
var _z0 := 0.0
var _top := 0.0
var _z1 := 0.0
var _b0 := 0.0
var _turn := 0.0
## Both ends fit at the top (q(156)): the camera holds the overview through the flight and only the plane moves.
var _hold := false

## from_*: the camera now; left: the city left (lat, lng); to_*: the overview ahead. view: the map's logical size;
## safe: where both ends must stand at the top, in the same units (q(152) ③ / q(157) ①: 32 in from each side, from the
## pill's bottom to 8 over the right-hand keys); none: the middle 70 % × 55 %. bubbles: [[lat, lng], Rect2 from that
## point] — the two cities' bubbles, which stand whole in `within` at the top too (q(157) ②).
static func plan(from_lat: float, from_lng: float, from_zoom: float, from_bearing: float, left: Vector2,
		to_lat: float, to_lng: float, to_zoom: float, to_bearing: float, view: Vector2, safe := Rect2(),
		bubbles := [], within := Rect2()) -> P0TravelFlight:
	var f := P0TravelFlight.new()
	f._c0 = _merc(from_lat, from_lng)
	f._c1 = _merc(to_lat, to_lng)
	var a := _merc(left.x, left.y)
	var dx := fposmod(f._c1.x - a.x + 0.5, 1.0) - 0.5   # the short way round
	var dy := f._c1.y - a.y
	f._mid = Vector2(a.x + dx * 0.5, a.y + dy * 0.5)
	f._z0 = from_zoom
	f._z1 = to_zoom
	# The closest zoom (a step out at least) that shows both ends in the safe area, the camera over their middle as the
	# map draws it far out — its centre kept off the world's top and bottom edges as Mapbox keeps it (#327).
	var area := safe if safe.has_area() else Rect2(view * Vector2(0.15, 0.225), view * Vector2(0.7, 0.55))
	var marks: Array = []   # [Mercator point, rect from it]
	for b in bubbles: marks.append([_merc((b[0] as Vector2).x, (b[0] as Vector2).y), b[1]])
	var high := minf(from_zoom, to_zoom) - 1.0   # from far out already (z ≈ 2) it may be under the floor (周瑜 on #325)
	var low := minf(TOP_MIN_ZOOM, high)
	f._top = low
	# by whole steps down to the floor itself: steps summed as floats came out a hair under it, and a pair fitting only
	# at the floor never got tried there
	var steps := maxi(0, ceili((high - low) / FIT_STEP - 1e-6))
	for i in steps + 1:
		var z := maxf(low, high - i * FIT_STEP)
		if frames(a, f._c1, f._mid, z, view, area, marks, within):
			f._top = z
			f._hold = true
			break
	f._view = view
	f._held = kept(f._mid, f._top, view)
	f._b0 = from_bearing
	f._turn = wrapf(to_bearing - from_bearing, -180.0, 180.0)
	return f

## Whether at zoom `z`, the camera over `mid` (Mercator x, y; its y kept off the world's edges), both `a` and `b` stand in
## `area` of a `view` (the map's logical size), and each of `marks` ([Mercator point, rect from it]) wholly in `within`.
static func frames(a: Vector2, b: Vector2, mid: Vector2, z: float, view: Vector2, area: Rect2, marks := [],
		within := Rect2()) -> bool:
	var scale := 512.0 * pow(2.0, z)
	var c := kept(mid, z, view)
	var at := func(p: Vector2) -> Vector2: return view * 0.5 + Vector2(fposmod(p.x - c.x + 0.5, 1.0) - 0.5, p.y - c.y) * scale
	for p in [a, b]:
		if not area.has_point(at.call(p)): return false
	for m in marks:
		var r: Rect2 = m[1]
		if not within.encloses(Rect2(at.call(m[0]) + r.position, r.size)): return false
	return true

## A camera centre (Mercator x, y) as the map shows it at zoom `z` in a `view` (logical size): its y kept so the world's
## top and bottom edges stay off the screen (Mapbox's HEIGHT_ONLY, mirrored by map_poc._constrain_lat).
static func kept(c: Vector2, z: float, view: Vector2) -> Vector2:
	var half := view.y * 0.5 / (512.0 * pow(2.0, z))
	return Vector2(c.x, 0.5 if half >= 0.5 else clampf(c.y, half, 1.0 - half))

## The camera at `t` seconds: Vector4(lat, lng, zoom, bearing) — always a centre the map shows as it is asked.
func sample(t: float) -> Vector4:
	var c: Vector2
	var z: float
	if t < UP_S:
		var s := _ease(t / UP_S)
		c = _c0.lerp(_wrap_near(_held, _c0), s)
		z = lerpf(_z0, _top, s)
	elif t < UP_S + FLY_S:
		var s := (t - UP_S) / FLY_S
		s = 1.0 - (1.0 - s) * (1.0 - s)   # fast, then slowing
		# q(156): both ends in view, the camera holds there and only the plane flies; only a pair that does not fit
		# even at the floor pans along with it
		c = _held if _hold else _held.lerp(_wrap_near(_c1, _held), s)
		z = _top
	else:
		var s := _ease(clampf((t - UP_S - FLY_S) / DOWN_S, 0.0, 1.0))
		z = lerpf(_top, _z1, s)
		if _hold:
			# down from the held overview toward the city ahead: its point slides from where the overview shows it to the
			# screen's centre as the zoom grows (its offset on screen shrinking smoothly), so it never leaves the view
			var c1 := _wrap_near(_c1, _held)
			c = c1 - (c1 - _held) * pow(2.0, _top - z) * (1.0 - s)
		else:
			c = _c1
	if t >= TOTAL_S:
		c = _c1
		z = _z1
	if _view != Vector2.ZERO: c = kept(c, z, _view)
	var ll := _geo(c)
	return Vector4(ll.x, ll.y, z, _b0 + _turn * clampf(t / TOTAL_S, 0.0, 1.0))

## The highest the camera goes (the overview of both ends).
func top_zoom() -> float:
	return _top

## Whether the camera holds the overview through the flight (both ends fit, q(156)).
func holds() -> bool:
	return _hold

## How far along the route the plane is at `t` seconds (0 at the city left, 1 at the city ahead): 0.5–2.5 s, eased as
## the camera's flight (fast, then slowing); the km on the pill rolls with it (q(147) v2).
static func plane_progress(t: float) -> float:
	var s := clampf((t - UP_S) / FLY_S, 0.0, 1.0)
	return 1.0 - (1.0 - s) * (1.0 - s)

static func _ease(s: float) -> float:
	return s * s * (3.0 - 2.0 * s)

static func _merc(lat: float, lng: float) -> Vector2:
	return Vector2(MapGeoMath.mercator_x(lng), MapGeoMath.mercator_y(lat))

static func _geo(m: Vector2) -> Vector2:
	return Vector2(rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * m.y)))), wrapf(m.x * 360.0 - 180.0, -180.0, 180.0))

## `p` moved by whole turns to lie nearest `ref` in x (the short way round the date line).
static func _wrap_near(p: Vector2, ref: Vector2) -> Vector2:
	return Vector2(ref.x + fposmod(p.x - ref.x + 0.5, 1.0) - 0.5, p.y)
