extends GdUnitTestSuite
## The underground backdrop (SGODOT-257) stays between the mine camera's clip planes wherever it is on screen (苏烈 on
## #173). R1 checked zoom 0.8 / 1.0 / 1.4 only, but FarmCamera.fit_ground_depth rounds far up to a half metre past the
## ground and steps the camera back along the view, so the far plane saws with the zoom. Swept here: the zooms the pinch
## can show, through the rubber band past both limits, including the zoom just past each step of far (where it sits
## nearest), every focus the framing allows across and down, both floors, at 360 × 800 and 360 × 780 (19.5:9). Each
## backdrop triangle is clipped to the screen (one pixel's slack) and its visible part's depth checked against near
## and far, the README's per-triangle check. The real camera code places the camera: a P0Mine without its runtime.
## P0_BACKDROP_DEPTH_FULL=1 sweeps at the report's density (zoom 0.01, focus 0.05 m) and adds three screens (MORE_SIZES);
## P0_BACKDROP_DEPTH_JSON=<path> writes the margins there.

const P0Mine := preload("res://scenes/p0/p0_mine.gd")
const ElasticZoom := preload("res://modules/p0/p0_elastic_zoom.gd")
const MIN_MARGIN := 0.05   # m, inside far
const SIZES := [Vector2i(360, 800), Vector2i(360, 780)]
## The full sweep's: the vivo V2509A (1080 × 2344 at the project's stretch, 360 × 781.3; an iPhone 14 Pro is 360 × 780.5)
## and R1's other two screens.
const MORE_SIZES := [Vector2i(360, 781), Vector2i(360, 840), Vector2i(412, 915)]

var full := OS.get_environment("P0_BACKDROP_DEPTH_FULL") == "1"
var zoom_step := 0.01 if full else 0.05
var across_step := 0.05 if full else 0.25   # m of focus x
var down_step := 0.1 if full else 0.25      # m of focus z, where the framing leaves any play down

## The mine with its world and camera but no runtime: no server view (no rock broken), no actor.
class Probe extends "res://scenes/p0/p0_mine.gd":
	func _ready() -> void:
		_build_light()

	func _view() -> Dictionary:
		return {}

## The backdrop's vertices along the camera's fixed axes, and its triangles, the one reaching deepest first.
class Relief:
	var u := PackedFloat64Array()   # along the camera's right
	var v := PackedFloat64Array()   # along its up
	var n := PackedFloat64Array()   # along its back: depth = camera's n − n
	var order := PackedInt32Array()
	var low := PackedFloat64Array()   # per entry of order: the triangle's lowest n (its deepest point)
	var high := -INF                  # the nearest vertex's n

	func _init(faces: PackedVector3Array, basis: Basis) -> void:
		for p in faces:
			u.append(p.dot(basis.x))
			v.append(p.dot(basis.y))
			n.append(p.dot(basis.z))
			high = maxf(high, n[n.size() - 1])
		var lows := {}
		var tris: Array = []
		for t in faces.size() / 3:
			lows[t] = minf(n[t * 3], minf(n[t * 3 + 1], n[t * 3 + 2]))
			tris.append(t)
		tris.sort_custom(func(a, b): return lows[a] < lows[b])
		for t in tris:
			order.append(t)
			low.append(lows[t])

	## The deepest camera depth of the backdrop inside the screen (half extents hx, hy about the camera), or -INF.
	func deepest(cu: float, cv: float, cn: float, hx: float, hy: float) -> float:
		var best := -INF
		for k in order.size():
			if cn - low[k] <= best: break   # nothing further down the list reaches deeper
			var t := order[k]
			var poly: Array[Vector3] = []
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for c in 3:
				var p := Vector3(u[t * 3 + c] - cu, v[t * 3 + c] - cv, cn - n[t * 3 + c])
				poly.append(p)
				lo = lo.min(Vector2(p.x, p.y))
				hi = hi.max(Vector2(p.x, p.y))
			if lo.x > hx or hi.x < -hx or lo.y > hy or hi.y < -hy: continue
			poly = Relief.clip(poly, 0, 1.0, hx)
			poly = Relief.clip(poly, 0, -1.0, hx)
			poly = Relief.clip(poly, 1, 1.0, hy)
			poly = Relief.clip(poly, 1, -1.0, hy)
			for p in poly: best = maxf(best, p.z)
		return best

	## Sutherland–Hodgman: the part of `poly` where s · p[axis] <= limit; depth (z) is linear along each edge.
	static func clip(poly: Array[Vector3], axis: int, s: float, limit: float) -> Array[Vector3]:
		var out: Array[Vector3] = []
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var da := s * a[axis] - limit
			var db := s * b[axis] - limit
			if da <= 0.0: out.append(a)
			if (da <= 0.0) != (db <= 0.0): out.append(a.lerp(b, da / (da - db)))
		return out

func after() -> void:
	P0Runtime.free_instance_for_tests()

## The zooms the pinch can show: the rubber band's farthest past either limit (raw zoom clamped at its slack).
func test_the_zoom_range_includes_the_rubber_band() -> void:
	var r := _zoom_range()
	assert_float(r.x).is_equal_approx(0.8 * exp(-ElasticZoom.ZOOM_ELASTIC * (1.0 - exp(-ElasticZoom.RAW_SLACK))), 0.0001)
	assert_float(r.y).is_equal_approx(1.4 * exp(ElasticZoom.ZOOM_ELASTIC * (1.0 - exp(-ElasticZoom.RAW_SLACK))), 0.0001)
	assert_bool(r.x < 0.72 and r.y > 1.56).is_true()

func test_the_backdrop_stays_inside_the_clip_planes_at_every_zoom_and_focus() -> void:
	var report := {"min_margin": MIN_MARGIN, "zoom_step": zoom_step, "across_step": across_step, "down_step": down_step,
		"cases": []}
	for size in SIZES + (MORE_SIZES if full else []):
		for floor_n in [1, 2]:
			var case: Dictionary = await _sweep(size, floor_n)
			report.cases.append(case)
			var worst: Dictionary = case.worst
			assert_float(worst.far_margin).override_failure_message("%dx%d floor %d: backdrop past far by %.3f m at %s" %
				[size.x, size.y, floor_n, -worst.far_margin, worst]).is_greater_equal(MIN_MARGIN)
			assert_float(case.near_margin).is_greater(0.0)
	var out := OS.get_environment("P0_BACKDROP_DEPTH_JSON")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
		f.close()

func _zoom_range() -> Vector2:
	var mine = auto_free(P0Mine.new())
	var low := ElasticZoom.new(exp(mine._pinch._low), exp(mine._pinch._high))
	low.pinch(1.0e6)    # fingers together, far past the limit
	var high := ElasticZoom.new(exp(mine._pinch._low), exp(mine._pinch._high))
	high.pinch(1.0e-6)  # fingers apart
	return Vector2(low.value, high.value)

## One screen size and floor: the margins at every zoom and focus. far_margin = far − the deepest visible backdrop.
func _sweep(size: Vector2i, floor_n: int) -> Dictionary:
	var store := "user://test_p0_mine_backdrop_depth.json"
	var vp := SubViewport.new()
	vp.size = size
	add_child(vp)
	var ui := P0Ui.new()
	ui.quick_store = store
	vp.add_child(ui)
	await await_idle_frame()
	ui.set_view({"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000}, "bag": {"capacity": 25, "free": 25,
		"slots": [{"id": "torch", "qty": 2}]}, "plots": [], "coins": 40, "skills": {}, "rest": {"used": 0, "limit": 1, "resets_in": 1},
		"inbox": {"parcels": [], "letters": []}})
	ui.set_mode("mine")
	ui.set_surface("mine")
	await await_idle_frame()
	var mine := Probe.new()
	vp.add_child(mine)
	mine._build_floor(floor_n)
	mine._band = ui.camera_band()   # what _camera_band takes from rt.ui in the game
	mine._focus = P0Mine.Layout.SPAWN
	mine._update_camera()
	var faces := PackedVector3Array()
	for g in mine.backdrop.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = (g as MeshInstance3D).global_transform
		for p in (g as MeshInstance3D).mesh.get_faces(): faces.append(xf * p)
	var relief := Relief.new(faces, mine.cam.global_basis)
	var y0: float = P0Mine.Layout.SPAWN.y
	var zr := _zoom_range()
	var zooms: Array[float] = [zr.x, zr.y, 0.8, 1.0, 1.4]
	var z := snappedf(zr.x, zoom_step) + zoom_step
	while z < zr.y:
		zooms.append(z)
		z += zoom_step
	zooms.sort()
	# far steps down by a half metre as the zoom closes in; it sits nearest the ground just past each step
	var extra: Array[float] = []
	for i in zooms.size() - 1:
		var a := zooms[i]
		var b := zooms[i + 1]
		if is_equal_approx(_far_at(mine, a), _far_at(mine, b)): continue
		for _k in 40:
			var m := (a + b) * 0.5
			if is_equal_approx(_far_at(mine, m), _far_at(mine, zooms[i])): a = m
			else: b = m
		extra.append(b)
	zooms.append_array(extra)
	zooms.sort()
	var worst := {"far_margin": INF}
	var per_zoom: Array = []
	var near_margin := INF
	var views := 0
	for zoom in zooms:
		mine._zoom = zoom
		var zoom_worst := {"zoom": zoom, "far_margin": INF}
		mine._focus = Vector3(0, y0, -1000)
		mine._update_camera()
		var z_lo: float = mine._focus.z
		mine._focus = Vector3(0, y0, 1000)
		mine._update_camera()
		var z_hi: float = mine._focus.z
		for fz in _steps(z_lo, z_hi, down_step):
			mine._focus = Vector3(-1000, y0, fz)
			mine._update_camera()
			var x_lo: float = mine._focus.x
			mine._focus = Vector3(1000, y0, fz)
			mine._update_camera()
			var x_hi: float = mine._focus.x
			for fx in _steps(x_lo, x_hi, across_step):
				mine._focus = Vector3(fx, y0, fz)
				mine._update_camera()
				views += 1
				var cam: Camera3D = mine.cam
				var c := cam.global_position
				var half := cam.get_camera_projection().get_viewport_half_extents()
				var px := 2.0 * half.x / size.x
				var cn := c.dot(relief_axis(cam, 2))
				near_margin = minf(near_margin, cn - relief.high - cam.near)
				var deep := relief.deepest(c.dot(relief_axis(cam, 0)), c.dot(relief_axis(cam, 1)), cn, half.x + px, half.y + px)
				if deep == -INF: continue
				var margin := cam.far - deep
				if margin < zoom_worst.far_margin:
					zoom_worst = {"zoom": zoom, "far_margin": margin, "focus_x": fx, "focus_z": fz, "far": cam.far, "near": cam.near}
		per_zoom.append(zoom_worst)
		if zoom_worst.far_margin < worst.far_margin:
			worst = zoom_worst.duplicate()
			worst["at_limits"] = zoom >= 0.8 - 0.0001 and zoom <= 1.4 + 0.0001
	var in_limits := INF
	for w in per_zoom:
		if w.zoom >= 0.8 - 0.0001 and w.zoom <= 1.4 + 0.0001: in_limits = minf(in_limits, w.far_margin)
	vp.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store))
	return {"size": [size.x, size.y], "floor": floor_n, "views": views, "zooms": zooms.size(), "worst": worst,
		"worst_within_0_8_to_1_4": in_limits, "near_margin": near_margin, "per_zoom": per_zoom}

## The camera's right (0), up (1) and back (2): fixed by the pitch and yaw, the axes the relief was measured along.
static func relief_axis(cam: Camera3D, i: int) -> Vector3:
	return cam.global_basis[i]

func _far_at(mine, zoom: float) -> float:
	mine._zoom = zoom
	mine._focus = P0Mine.Layout.SPAWN
	mine._update_camera()
	return mine.cam.far

## from..to in `step`s, both ends included; one value when they meet.
static func _steps(from: float, to: float, step: float) -> Array[float]:
	var out: Array[float] = [from]
	if to - from < 0.001: return out
	var x := from + step
	while x < to - 0.001:
		out.append(x)
		x += step
	out.append(to)
	return out
