extends RefCounted
## Visible XZ outline of an imported prop mesh, measured from its triangles.
## `triangles`: top-down projection of the whole model (the card's visible outline).
## `solid_points`: model points a walker's centre must never reach — every vertex
## for shrubs and rocks; for trees, trunk and root cross-sections below the canopy.
## `hull` (trees): convex hull of the trunk cross-section at `top`, spanning the
## root flare rather than dipping between buttress roots.
const TRUNK_BAND_M := 0.6  # below the lowest canopy of the three tree models
const SLICE_STEP_M := 0.01
var triangles: Array[PackedVector2Array] = []
var hull := PackedVector2Array()
var solid_points := PackedVector2Array()

static func xz(v: Vector3) -> Vector2: return Vector2(v.x, v.z)

static func slice(faces: PackedVector3Array, height: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, faces.size(), 3):
		for j in 3:
			var a := faces[i+j]
			var b := faces[i+(j+1)%3]
			if (a.y > height) != (b.y > height): points.append(xz(a.lerp(b, (height-a.y)/(b.y-a.y))))
	return points

static func slice_heights(top: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	var h := SLICE_STEP_M * 0.5
	while h < top:
		heights.append(h)
		h += SLICE_STEP_M
	heights.append(top)
	return heights

static func fan(polygon: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var index := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, index.size(), 3):
		out.append(PackedVector2Array([polygon[index[i]], polygon[index[i+1]], polygon[index[i+2]]]))
	return out

func _init(mesh: Mesh, tree: bool, top := TRUNK_BAND_M) -> void:
	var faces := mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var t := PackedVector2Array([xz(faces[i]), xz(faces[i+1]), xz(faces[i+2])])
		if absf((t[1]-t[0]).cross(t[2]-t[0])) > 1e-10: triangles.append(t)
		if not tree: solid_points.append_array(t)
	if not tree: return
	hull = Geometry2D.convex_hull(slice(faces, top))
	hull.remove_at(hull.size() - 1)
	for h in slice_heights(TRUNK_BAND_M): solid_points.append_array(slice(faces, h))

func inside(p: Vector2) -> bool:
	for t in triangles:
		if Geometry2D.point_is_inside_triangle(p, t[0], t[1], t[2]): return true
	return false

func in_hull(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p, hull)

## Farthest point from `center` along `direction` accepted by `test`, sampled every millimetre.
func reach(center: Vector2, direction: Vector2, test: Callable) -> float:
	var t := 2.0
	while t > 0.0 and not test.call(center + direction * t): t -= 0.001
	return maxf(t, 0.0)

## Farthest solid point from `center`.
func spread(center: Vector2) -> float:
	var far := 0.0
	for p in solid_points: far = maxf(far, p.distance_to(center))
	return far
