extends GdUnitTestSuite
## Camera unification at the pond (用户 via 奕星, 2026-10-09, as the mine in #129): the farm's size and pitch at zoom 1
## (65.8 px player at 360 × 800, 哪吒), the pond's own yaw 0, the farm's pinch, and the screen kept on the decorated
## meadow — flush at the sides, the band between the HUD's second row and the quick bar / key on it (不知火舞 on 231).
## Pure maths and a 360 × 800 SubViewport: nothing reads the test window, so headless (640 × 640) runs the same
## (苏烈 on #127).

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")
const PHONE := Vector2(360, 800)
const BAND := Rect2(0, 98, 360, 422)   # HUD row 2 … main key top at 360 × 800 in the pond (desktop shot, P0Ui.camera_band)

func test_the_pond_opens_at_the_farms_size_and_pitch_and_pinches_like_it() -> void:
	assert_float(P0Pond.PITCH_DEG).is_equal(FarmCamera.PITCH_DEG)
	assert_float(P0Pond.view_size(PHONE, 1.0)).is_equal_approx(6.72, 0.001)   # the farm at zoom 1
	assert_float(P0Pond.view_size(PHONE, 0.8)).is_equal_approx(8.4, 0.001)
	var pond = auto_free(P0Pond.new())   # not in the tree: only its camera fields
	assert_float(pond._zoom).is_equal(1.0)
	assert_float(P0Pond.view_size(PHONE, P0Pond.FAR_ZOOM)).is_equal_approx(9.882, 0.001)   # the open-water ponds' widest (374)
	assert_float(exp(pond._pinch._low)).is_equal_approx(0.68, 0.0001)   # past the farm's 0.8 (不知火舞 on 374)
	assert_float(exp(pond._pinch._high)).is_equal_approx(1.4, 0.0001)

func test_the_camera_looks_up_the_pond_at_43_degrees() -> void:
	var cam := _phone_camera(1.0)
	var forward := -cam.global_basis.z
	assert_float(rad_to_deg(asin(-forward.y))).is_equal_approx(43.0, 0.01)
	assert_float(forward.x).is_equal_approx(0.0, 0.0001)                 # yaw 0 kept (奕星): straight up the pond
	assert_vector(cam.unproject_position(Vector3(6, 0, -8))).is_equal_approx(PHONE * 0.5, Vector2.ONE * 0.01)

func test_the_sides_stop_flush_with_the_meadow() -> void:
	var size := P0Pond.view_size(PHONE, 1.0)
	var art := PondScenery.MEADOW
	var left := P0Pond.clamp_focus(Vector3(-2, 0, -8), size, PHONE, BAND, art)
	assert_float(left.x - size * 0.5).is_equal_approx(art.position.x, 0.0001)
	var right := P0Pond.clamp_focus(Vector3(14, 0, -8), size, PHONE, BAND, art)
	assert_float(right.x + size * 0.5).is_equal_approx(art.end.x, 0.0001)
	assert_float(P0Pond.clamp_focus(Vector3(6, 0, -8), size, PHONE, BAND, art).x).is_equal(6.0)   # inside: free

## Checked through a real camera: the band's top row meets the meadow's far edge, its bottom row the near edge.
func test_the_band_stops_on_the_meadows_far_and_near_edges() -> void:
	var art := PondScenery.MEADOW
	for zoom in [1.0, 0.8, P0Pond.FAR_ZOOM]:
		var cam := _phone_camera(zoom)
		for at in [Vector3(6, 0, -18), Vector3(6, 0.2, -18)]:   # 0.2: standing on a raised bank
			var far := P0Pond.clamp_focus(at, cam.size, PHONE, BAND, art)
			P0Pond.place(cam, far)
			assert_float(_ground(cam, BAND.position.y).z).is_equal_approx(art.position.y, 0.001)
		var near := P0Pond.clamp_focus(Vector3(6, 0, 1), cam.size, PHONE, BAND, art)
		P0Pond.place(cam, near)
		assert_float(_ground(cam, BAND.end.y).z).is_equal_approx(art.end.y, 0.001)
		var mid := P0Pond.clamp_focus(Vector3(6, 0, -5), cam.size, PHONE, BAND, art)   # inside every zoom's range (374)
		assert_float(mid.z).is_equal(-5.0)

## Where the meadow can't fill the band along an axis, that axis holds the middle (不知火舞: 装得下就居中).
func test_a_meadow_smaller_than_the_band_holds_the_middle() -> void:
	var size := P0Pond.view_size(PHONE, 1.0)
	var small := Rect2(4, -9, 4, 3)
	var c := P0Pond.clamp_focus(Vector3(0, 0, 0), size, PHONE, BAND, small)
	assert_float(c.x).is_equal_approx(6.0, 0.0001)
	var cam := _phone_camera(1.0)
	P0Pond.place(cam, c)
	var top := _ground(cam, BAND.position.y).z
	var bottom := _ground(cam, BAND.end.y).z
	assert_float((top + bottom) * 0.5).is_equal_approx(-7.5, 0.001)   # the band's ground centred on the meadow

## The opening shot (不知火舞 on 231): feet 40 px above the band's bottom edge, centred across, inside the safe box so the
## first steps don't move the camera; on a raised bank too. Past the meadow's edge the clamp still wins.
func test_the_opening_shot_puts_the_feet_40_px_above_the_key_and_inside_the_safe_box() -> void:
	var cam := _phone_camera(1.0)
	for player in [Vector3(6, 0, -1.6), Vector3(5, 0.2, -8)]:
		var focus := P0Pond.clamp_focus(P0Pond.opening_focus(player, cam.size, PHONE, BAND), cam.size, PHONE, BAND, PondScenery.MEADOW)
		P0Pond.place(cam, focus)
		var feet := cam.unproject_position(player)
		assert_float(feet.y).is_equal_approx(BAND.end.y - P0Pond.OPENING_LIFT, 0.01)
		assert_float(feet.x).is_equal_approx(PHONE.x * 0.5, 0.01)
		assert_bool(P0Follow.box(PHONE).has_point(feet)).is_true()
	var edge := P0Pond.clamp_focus(P0Pond.opening_focus(Vector3(-1, 0, -8), cam.size, PHONE, BAND), cam.size, PHONE, BAND, PondScenery.MEADOW)
	assert_float(edge.x - cam.size * 0.5).is_equal_approx(PondScenery.MEADOW.position.x, 0.0001)   # at the side: flush

## The whole pond in one view at the farthest zoom (美术总监 / 奕星): every shape's water is narrower than the screen and
## shallower than the band's ground there.
func test_every_pond_fits_the_band_at_the_farthest_zoom() -> void:
	var size := P0Pond.view_size(PHONE, P0Pond.FAR_ZOOM)
	var depth := BAND.size.y / (PHONE.x / size) / sin(deg_to_rad(P0Pond.PITCH_DEG))
	for t in ["crescent", "gourd", "meander"]:
		var poly: Array = SystemPonds.template(t).polygon
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in poly:
			lo = Vector2(minf(lo.x, p[0]), minf(lo.y, p[1]))
			hi = Vector2(maxf(hi.x, p[0]), maxf(hi.y, p[1]))
		assert_float(hi.x - lo.x).is_less(size)
		assert_float(hi.y - lo.y).is_less(depth)
		assert_bool(PondScenery.MEADOW.encloses(Rect2(lo, hi - lo))).is_true()

func _phone_camera(zoom: float) -> Camera3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	vp.disable_3d = false
	add_child(auto_free(vp))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = P0Pond.view_size(PHONE, zoom)
	vp.add_child(cam)
	cam.make_current()
	P0Pond.place(cam, Vector3(6, 0, -8))
	return cam

## The ground point (y 0) under a screen row, at the middle column.
func _ground(cam: Camera3D, row: float) -> Vector3:
	var at := Vector2(PHONE.x * 0.5, row)
	var o := cam.project_ray_origin(at)
	var d := cam.project_ray_normal(at)
	return o + d * (-o.y / d.y)
