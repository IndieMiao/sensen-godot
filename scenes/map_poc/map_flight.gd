class_name MapFlight
extends RefCounted
## 跨城飞行路径（van Wijk & Nuij 2003，与 Mapbox flyTo 同一套公式）：先拉远、平移、再拉近，
## 让屏幕上的平移速度大致恒定。坐标在 Web Mercator 归一化空间 [0,1) 里插值，经度走最短方向。

const RHO := 1.42
const MIN_DURATION := 0.6
const MAX_DURATION := 3.0

var _x0 := 0.0
var _y0 := 0.0
var _dx := 0.0
var _dy := 0.0
var _z0 := 0.0
var _z1 := 0.0
var _w0 := 1.0
var _u1 := 0.0
var _r0 := 0.0
var _k := 1.0
var _degenerate := false
## 路径总长（van Wijk 的 S，无量纲）。
var length := 0.0

## view_w_logical：地图视口宽度（Mapbox 逻辑像素），决定"拉远到多高才看得到两端"。
static func plan(lat0: float, lng0: float, z0: float, lat1: float, lng1: float, z1: float, view_w_logical: float) -> MapFlight:
	var f := MapFlight.new()
	f._x0 = MapGeoMath.mercator_x(lng0)
	f._y0 = MapGeoMath.mercator_y(lat0)
	f._dx = fposmod(MapGeoMath.mercator_x(lng1) - f._x0 + 0.5, 1.0) - 0.5
	f._dy = MapGeoMath.mercator_y(lat1) - f._y0
	f._z0 = z0
	f._z1 = z1
	var w0 := view_w_logical / (512.0 * pow(2.0, z0))
	var w1 := view_w_logical / (512.0 * pow(2.0, z1))
	f._w0 = w0
	f._u1 = sqrt(f._dx * f._dx + f._dy * f._dy)
	var rho2 := RHO * RHO
	if f._u1 > 1e-9:
		var b0 := (w1 * w1 - w0 * w0 + rho2 * rho2 * f._u1 * f._u1) / (2.0 * w0 * rho2 * f._u1)
		var b1 := (w1 * w1 - w0 * w0 - rho2 * rho2 * f._u1 * f._u1) / (2.0 * w1 * rho2 * f._u1)
		f._r0 = log(sqrt(b0 * b0 + 1.0) - b0)
		var r1 := log(sqrt(b1 * b1 + 1.0) - b1)
		f.length = (r1 - f._r0) / RHO
	if f._u1 <= 1e-9 or not is_finite(f.length):
		f._degenerate = true
		f._k = -1.0 if w1 < w0 else 1.0
		f.length = absf(log(w1 / w0)) / RHO
	return f

func duration() -> float:
	return clampf(length * 0.35, MIN_DURATION, MAX_DURATION)

## t ∈ [0,1]（已缓动的进度）→ Vector3(lat, lng, zoom)。
func sample(t: float) -> Vector3:
	t = clampf(t, 0.0, 1.0)
	if t >= 1.0: return _at(1.0, _z1)
	var s := t * length
	var frac: float
	var z: float
	if _degenerate:
		frac = t
		z = _z0 + (-_k * RHO * s) / log(2.0) if length > 0.0 else lerpf(_z0, _z1, t)
	else:
		var rho2 := RHO * RHO
		var w := cosh(_r0) / cosh(_r0 + RHO * s)
		frac = _w0 * ((cosh(_r0) * tanh(_r0 + RHO * s) - sinh(_r0)) / rho2) / _u1
		z = _z0 + log(1.0 / w) / log(2.0)
	return _at(frac, z)

func _at(frac: float, z: float) -> Vector3:
	var x := _x0 + _dx * frac
	var y := _y0 + _dy * frac
	var lat := rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * y))))
	var lng := wrapf(x * 360.0 - 180.0, -180.0, 180.0)
	return Vector3(lat, lng, z)
