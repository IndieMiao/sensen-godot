class_name P0TravelFlight
extends RefCounted
## The cross-city flight's camera (q(147), SGODOT-299; 不知火舞 on 299 31c4ceb5, 62931cdb): a fixed 3 s, whatever the
## Trip — up 0.5 s from where the camera is until the city left and the city ahead are both in view (at most country
## or continent), along 2.0 s to the city ahead (fast, then slowing), down 0.5 s to its overview (q(25)). Up and down
## ease in and out. No jump back to the city left first: the camera may already be over the city ahead (a bubble's
## browse), and it rises from there.

const UP_S := 0.5
const FLY_S := 2.0
const DOWN_S := 0.5
const TOTAL_S := UP_S + FLY_S + DOWN_S

## The overview is never further out than this, nor closer in than a step under the nearer of the two ends.
const TOP_MIN_ZOOM := 1.5

var _c0: Vector2   # mercator x, y
var _mid: Vector2
var _c1: Vector2
var _z0 := 0.0
var _top := 0.0
var _z1 := 0.0
var _b0 := 0.0
var _turn := 0.0

## from_*: the camera now; left: the city left (lat, lng); to_*: the overview ahead. view: the map's logical size.
static func plan(from_lat: float, from_lng: float, from_zoom: float, from_bearing: float, left: Vector2,
		to_lat: float, to_lng: float, to_zoom: float, to_bearing: float, view: Vector2) -> P0TravelFlight:
	var f := P0TravelFlight.new()
	f._c0 = _merc(from_lat, from_lng)
	f._c1 = _merc(to_lat, to_lng)
	var a := _merc(left.x, left.y)
	var dx := fposmod(f._c1.x - a.x + 0.5, 1.0) - 0.5   # the short way round
	var dy := f._c1.y - a.y
	f._mid = Vector2(a.x + dx * 0.5, a.y + dy * 0.5)
	# both ends in view, with room for the pill and the HUD: 70 % of the width, 55 % of the height
	var fit := INF
	if absf(dx) > 1e-9: fit = minf(fit, log(0.7 * view.x / (512.0 * absf(dx))) / log(2.0))
	if absf(dy) > 1e-9: fit = minf(fit, log(0.55 * view.y / (512.0 * absf(dy))) / log(2.0))
	f._z0 = from_zoom
	f._z1 = to_zoom
	var high := minf(from_zoom, to_zoom) - 1.0   # a step out at least; from far out already (z ≈ 2) it may be under 1.5 (周瑜 on #325)
	f._top = clampf(fit, minf(TOP_MIN_ZOOM, high), high)
	f._b0 = from_bearing
	f._turn = wrapf(to_bearing - from_bearing, -180.0, 180.0)
	return f

## The camera at `t` seconds: Vector4(lat, lng, zoom, bearing).
func sample(t: float) -> Vector4:
	var c: Vector2
	var z: float
	if t < UP_S:
		var s := _ease(t / UP_S)
		c = _c0.lerp(_wrap_near(_mid, _c0), s)
		z = lerpf(_z0, _top, s)
	elif t < UP_S + FLY_S:
		var s := (t - UP_S) / FLY_S
		s = 1.0 - (1.0 - s) * (1.0 - s)   # fast, then slowing
		c = _mid.lerp(_wrap_near(_c1, _mid), s)
		z = _top
	else:
		var s := _ease(clampf((t - UP_S - FLY_S) / DOWN_S, 0.0, 1.0))
		c = _c1
		z = lerpf(_top, _z1, s)
	if t >= TOTAL_S:
		c = _c1
		z = _z1
	var ll := _geo(c)
	return Vector4(ll.x, ll.y, z, _b0 + _turn * clampf(t / TOTAL_S, 0.0, 1.0))

## The highest the camera goes (the overview of both ends).
func top_zoom() -> float:
	return _top

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
