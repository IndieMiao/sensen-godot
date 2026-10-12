extends ColorRect
## The map's fog (plan v2 §11.7.1–11.7.3, SGODOT-275): a full-screen grey veil under the pins, bubbles and names, with a
## soft hole round every explored city, so explored cities read in full colour and the rest of the world is greyed. Only
## colouring: it takes no touches and hides nothing — city names, bubbles, online counts and friends draw over it, and
## what can be entered is decided by the server's passes. The host gives the holes each frame ({at: Vector2 px,
## r: float px}, or a tilted map's ellipse from ground_hole); with none it stays clear (Journey has no fog). It stays at
## every zoom (不知火舞 on #227: a neighbour city's pins would otherwise turn full colour up close); inside an explored
## city its hole covers the screen.

const SHADER := preload("res://modules/map/shaders/map_fog.gdshader")
const MAX_HOLES := 64
## The design's veil (不知火舞 on 279 6c0377f7): COLOR_SECONDARY at 40 %; the earlier light blue-grey washed out over the
## pale Mapbox base on the phone. On the device only the opacity is tuned (35–45 %), never the colour.
const FOG := Color(UiTokens.COLOR_SECONDARY, 0.40)

var holes: Array = []
var _mat: ShaderMaterial

func _init() -> void:
	name = "MapFog"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # the host may place it over the whole screen instead

## Holes in the host's pixels ({at, r}), shifted by `offset` into this layer's (the host draws inside the safe area, the
## veil covers the whole screen); hidden when the host has no fog. The shader is only fed when something changed.
var _applied: Array = []
var _applied_k := -1.0
var _applied_offset := Vector2.INF

func apply(new_holes: Array, _zoom: float, enabled: bool, offset := Vector2.ZERO) -> void:
	var k := 1.0 if enabled else 0.0
	visible = k > 0.0
	if not visible: return
	if is_same(new_holes, _applied) and k == _applied_k and offset == _applied_offset and _mat.get_shader_parameter("size") == size:
		return
	_applied = new_holes
	_applied_k = k
	_applied_offset = offset
	holes = new_holes.slice(0, MAX_HOLES)
	var packed: Array = []
	var shapes: Array = []
	for h in holes:
		var cn := conic_of(h)
		packed.append(Vector4(h.at.x + offset.x, h.at.y + offset.y, cn[0], cn[1]))
		shapes.append(Vector4(cn[2], cn[3], cn[4], float(h.get("r_min", h.r))))
	while packed.size() < MAX_HOLES:
		packed.append(Vector4.ZERO)
		shapes.append(Vector4.ZERO)
	_mat.set_shader_parameter("holes", packed)
	_mat.set_shader_parameter("shapes", shapes)
	_mat.set_shader_parameter("count", holes.size())
	_mat.set_shader_parameter("size", size)
	_mat.set_shader_parameter("fog_color", Color(FOG, FOG.a * k))

## A hole's edge as a conic in the layer's pixels about its `at`: Q(x, y) = a x² + 2b xy + c y² + 2d x + 2e y − 1, below 0
## inside, as [a, b, c, d, e]. A plain circle ({at, r}) is a = c = 1/r².
static func conic_of(hole: Dictionary) -> PackedFloat64Array:
	if hole.has("conic"): return hole.conic
	var r := maxf(1.0, float(hole.r))
	return PackedFloat64Array([1.0 / (r * r), 0.0, 1.0 / (r * r), 0.0, 0.0])

## How far `p` (the layer's px) is outside the hole's edge, negative inside; to first order (Q / |∇Q|), as the shader
## feathers it.
static func edge_distance(hole: Dictionary, p: Vector2) -> float:
	var k := conic_of(hole)
	var x := float(p.x - hole.at.x)
	var y := float(p.y - hole.at.y)
	var q := k[0] * x * x + 2.0 * k[1] * x * y + k[2] * y * y + 2.0 * k[3] * x + 2.0 * k[4] * y - 1.0
	var gx := 2.0 * (k[0] * x + k[1] * y + k[3])
	var gy := 2.0 * (k[1] * x + k[2] * y + k[4])
	return q / maxf(1e-12, sqrt(gx * gx + gy * gy))

## The hole for a ground circle of `radius` round a city, as the map draws the ground (SGODOT-298): `ground` four points
## on the ground about the city (any unit, the radius's), `screen` where the map draws them, relative to `at`, the
## city's own screen point. Flat, the circle stays a circle; tilted, the camera's perspective draws it as an ellipse,
## narrower on the far side, and a circle of the flat scale missed the map (at z 11 its far edge 0.60 of the map's,
## its near edge 1.29). The ground plane reaches the screen through a projective map, found from the four points; the
## circle's conic is carried through it. `r` (a bound for culling) and `r_min` (for the feather) are the farthest and
## nearest of `rim`, the circle's points the map draws (relative to `at`). {} when the points do not fix a map.
static func ground_hole(at: Vector2, ground: Array, screen: Array, radius: float, rim: Array) -> Dictionary:
	var h := _homography(ground, screen)
	if h.is_empty(): return {}
	var inv := _inverse3(h)
	if inv.is_empty(): return {}
	# C' = H⁻ᵀ · diag(1, 1, −R²) · H⁻¹, the circle x² + y² = R² on the screen
	var d := [1.0, 1.0, -radius * radius]
	var c := []
	for i in 3:
		for j in 3:
			var sum := 0.0
			for m in 3: sum += float(inv[m * 3 + i]) * d[m] * float(inv[m * 3 + j])
			c.append(sum)
	var f: float = c[8]
	if f >= 0.0: return {}   # the city's own point is not inside: not a map the camera draws
	var conic := PackedFloat64Array([c[0] / -f, c[1] / -f, c[4] / -f, c[2] / -f, c[5] / -f])
	var far := 0.0
	var near := INF
	for v in rim:
		far = maxf(far, (v as Vector2).length())
		near = minf(near, (v as Vector2).length())
	return {at = at, r = far, r_min = near, conic = conic}

## The projective map (row-major 3 × 3, last 1) taking the four `from` points to `to`; [] when they do not fix one.
static func _homography(from: Array, to: Array) -> Array:
	var a: Array = []
	var b: Array = []
	for i in 4:
		var x := float(from[i].x)
		var y := float(from[i].y)
		var u := float(to[i].x)
		var v := float(to[i].y)
		a.append([x, y, 1.0, 0.0, 0.0, 0.0, -u * x, -u * y])
		b.append(u)
		a.append([0.0, 0.0, 0.0, x, y, 1.0, -v * x, -v * y])
		b.append(v)
	var h := _solve(a, b)
	if h.is_empty(): return []
	h.append(1.0)
	return h

## Gaussian elimination with partial pivoting (f64 throughout); [] when singular.
static func _solve(a: Array, b: Array) -> Array:
	var n := b.size()
	var m: Array = []
	for i in n:
		var row: Array = (a[i] as Array).duplicate()
		row.append(b[i])
		m.append(row)
	for col in n:
		var pivot := col
		for r in range(col + 1, n):
			if absf(m[r][col]) > absf(m[pivot][col]): pivot = r
		if absf(m[pivot][col]) < 1e-12: return []
		var t = m[col]
		m[col] = m[pivot]
		m[pivot] = t
		for r in n:
			if r == col: continue
			var k: float = m[r][col] / m[col][col]
			if k == 0.0: continue
			for c in range(col, n + 1): m[r][c] -= k * m[col][c]
	var out: Array = []
	for i in n: out.append(m[i][n] / m[i][i])
	return out

## A row-major 3 × 3's inverse; [] when singular.
static func _inverse3(m: Array) -> Array:
	var a: float = m[0]; var b: float = m[1]; var c: float = m[2]
	var d: float = m[3]; var e: float = m[4]; var f: float = m[5]
	var g: float = m[6]; var h: float = m[7]; var i: float = m[8]
	var det := a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
	if absf(det) < 1e-18: return []
	return [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
		(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
		(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]
