extends GdUnitTestSuite
## Camera unification at the pond (用户 via 奕星, 2026-10-09, as the mine in #129): the farm's size and pitch at zoom 1
## (65.8 px player at 360 × 800, 哪吒), the farm's yaw outdoors (14.5°, 442), the farm's pinch, and the screen kept on the decorated
## meadow — flush at the sides, the band between the HUD's second row and the quick bar / key on it (不知火舞 on 231).
## Pure maths and a 360 × 800 SubViewport: nothing reads the test window, so headless (640 × 640) runs the same
## (苏烈 on #127).

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")
const PondWalk := preload("res://modules/ponds/pond_walk.gd")
const PHONE := Vector2(360, 800)
const BAND := Rect2(0, 98, 360, 422)   # HUD row 2 … main key top at 360 × 800 in the pond (desktop shot, P0Ui.camera_band)
const KEYS := Rect2(249, 520, 95, 148)   # the action group's column under the band's bottom (P0Ui.key_column)

func test_the_pond_opens_at_the_farms_size_and_pitch_and_pinches_like_it() -> void:
	assert_float(P0Pond.PITCH_DEG).is_equal(FarmCamera.PITCH_DEG)
	assert_float(P0Pond.view_size(PHONE, 1.0)).is_equal_approx(6.72, 0.001)   # the farm at zoom 1
	assert_float(P0Pond.view_size(PHONE, 0.8)).is_equal_approx(8.4, 0.001)
	var pond = auto_free(P0Pond.new())   # not in the tree: only its camera fields
	assert_float(pond._zoom).is_equal(1.0)
	assert_float(P0Pond.view_size(PHONE, P0Pond.FAR_ZOOM)).is_equal_approx(9.882, 0.001)   # the open-water ponds' widest (374)
	assert_float(exp(pond._pinch._low)).is_equal_approx(0.68, 0.0001)   # past the farm's 0.8 (不知火舞 on 374)
	assert_float(exp(pond._pinch._high)).is_equal_approx(1.4, 0.0001)

## 43° down and, outdoors, the farm's yaw (the user, 197 LOCK-34 v2; SGODOT-442): turned 14.5° as the farm's camera.
func test_the_camera_looks_up_the_pond_at_43_degrees_turned_as_the_farm() -> void:
	var cam := _phone_camera(1.0)
	var forward := -cam.global_basis.z
	assert_float(rad_to_deg(asin(-forward.y))).is_equal_approx(43.0, 0.01)
	assert_float(rad_to_deg(atan2(-forward.x, -forward.z))).is_equal_approx(FarmCamera.YAW_DEG, 0.01)
	var farm := Camera3D.new()
	add_child(auto_free(farm))
	FarmCamera.place(farm, Vector3.ZERO)
	assert_vector(-farm.global_basis.z).is_equal_approx(forward, Vector3.ONE * 0.0001)   # the farm's very direction
	assert_vector(cam.global_basis.x).is_equal_approx(P0Pond.right_axis(), Vector3.ONE * 0.0001)
	assert_vector(cam.unproject_position(Vector3(6, 0, -8))).is_equal_approx(PHONE * 0.5, Vector2.ONE * 0.01)

## The band's ground is inside the meadow — its four corners, through a real camera — and at an edge it stops flush:
## turned 14.5° (442) a corner, not a whole side, meets the meadow's side, far or near edge. Inside, the focus is free.
func test_the_band_stays_on_the_meadow_flush_at_its_edges() -> void:
	var art := PondScenery.MEADOW
	for zoom in [1.0, 0.8, P0Pond.FAR_ZOOM]:
		var cam := _phone_camera(zoom)
		for at in [Vector3(-2, 0, -8), Vector3(14, 0, -8), Vector3(6, 0, -18), Vector3(6, 0.2, -18), Vector3(6, 0, 1)]:   # 0.2: a raised bank
			P0Pond.place(cam, P0Pond.clamp_focus(at, cam.size, PHONE, BAND, art))
			var c := _band_corners(cam)   # on the ground, a raised bank's focus too
			for p in c: assert_bool(art.grow(0.001).has_point(p)).override_failure_message("%s %s at zoom %s" % [at, p, zoom]).is_true()
			var lo: Vector2 = c.reduce(func(m, p): return m.min(p), Vector2(INF, INF))
			var hi: Vector2 = c.reduce(func(m, p): return m.max(p), Vector2(-INF, -INF))
			if at.x < 0: assert_float(lo.x).is_equal_approx(art.position.x, 0.001)
			elif at.x > 12: assert_float(hi.x).is_equal_approx(art.end.x, 0.001)
			elif at.z < -15: assert_float(lo.y).is_equal_approx(art.position.y, 0.001)
			else: assert_float(hi.y).is_equal_approx(art.end.y, 0.001)
		var mid := P0Pond.clamp_focus(Vector3(6, 0, -5), cam.size, PHONE, BAND, art)   # inside every zoom's range (374)
		assert_vector(mid).is_equal(Vector3(6, 0, -5))

## Where the meadow can't fill the band along an axis, that axis holds the middle (不知火舞: 装得下就居中).
func test_a_meadow_smaller_than_the_band_holds_the_middle() -> void:
	var cam := _phone_camera(1.0)
	var small := Rect2(4, -9, 4, 3)
	P0Pond.place(cam, P0Pond.clamp_focus(Vector3(0, 0, 0), cam.size, PHONE, BAND, small))
	var c := _band_corners(cam)
	var lo: Vector2 = c.reduce(func(m, p): return m.min(p), Vector2(INF, INF))
	var hi: Vector2 = c.reduce(func(m, p): return m.max(p), Vector2(-INF, -INF))
	assert_vector((lo + hi) * 0.5).is_equal_approx(small.get_center(), Vector2.ONE * 0.001)   # the band's ground centred on it

## The opening shot (不知火舞 on 231; 442): feet OPENING_LIFT above the band's bottom edge — on it since the turn —
## centred across with no water to lean to, inside the safe box so the first steps don't move the camera; on a raised
## bank too. Past the meadow's edge the clamp still wins.
func test_the_opening_shot_puts_the_feet_on_the_key_line_and_inside_the_safe_box() -> void:
	var cam := _phone_camera(1.0)
	for player in [Vector3(6, 0, -1.6), Vector3(5, 0.2, -5.5)]:   # -5.5: turned, the band's top corner clears the far edge
		var focus := P0Pond.clamp_focus(P0Pond.opening_focus(player, cam.size, PHONE, BAND), cam.size, PHONE, BAND, PondScenery.MEADOW)
		P0Pond.place(cam, focus)
		var feet := cam.unproject_position(player)
		assert_float(feet.y).is_equal_approx(BAND.end.y - P0Pond.OPENING_LIFT, 0.01)
		assert_float(feet.x).is_equal_approx(PHONE.x * 0.5, 0.01)
		assert_bool(P0Follow.box(PHONE).has_point(feet)).is_true()
	P0Pond.place(cam, P0Pond.clamp_focus(P0Pond.opening_focus(Vector3(-1, 0, -8), cam.size, PHONE, BAND), cam.size, PHONE, BAND, PondScenery.MEADOW))
	var lo: Vector2 = _band_corners(cam).reduce(func(m, p): return m.min(p), Vector2(INF, INF))
	assert_float(lo.x).is_equal_approx(PondScenery.MEADOW.position.x, 0.001)   # at the side: flush

## Turned 14.5° (442), the opening leans toward the water's middle, the player no further off centre than the safe box
## allows — and no further than keeps the nearest gathering point OPENING_PIECE_PX inside the screen when it was in
## sight unleaned (上官婉儿: 1–3 points at the opening); a point already out of sight does not hold it back.
func test_the_opening_leans_toward_the_water_keeping_a_point_in_sight() -> void:
	var cam := _phone_camera(1.0)
	var player := Vector3(6.125, 0, -1.625)
	var box := P0Follow.box(PHONE)
	var water := player + P0Pond.right_axis() * 6.0 + P0Pond.ahead_axis() * 5.0   # well off to the right
	P0Pond.place(cam, P0Pond.opening_focus(player, cam.size, PHONE, BAND, water))
	assert_float(cam.unproject_position(player).x).is_equal_approx(box.position.x, 0.01)   # as far left as the box allows
	var piece := player - P0Pond.right_axis() * 2.0   # 2 m left of the player
	P0Pond.place(cam, P0Pond.opening_focus(player, cam.size, PHONE, BAND, water, piece))
	assert_float(cam.unproject_position(piece).x).is_equal_approx(P0Pond.OPENING_PIECE_PX, 0.01)   # held there
	assert_float(cam.unproject_position(player).x).is_greater(box.position.x)
	var far_piece := player - P0Pond.right_axis() * 8.0   # out of sight even unleaned: no hold
	P0Pond.place(cam, P0Pond.opening_focus(player, cam.size, PHONE, BAND, water, far_piece))
	assert_float(cam.unproject_position(player).x).is_equal_approx(box.position.x, 0.01)

## The player first (442, as the cathedral's #846): anywhere on q(297)'s walk — its far edge z −16 and its four corners
## included — with the meadow clamp on, the player stays PLAYER_SAFE_PX inside the screen's sides and feet to head inside
## the band (the HUD above, the keys below), at every zoom; the ground past the meadow shows instead.
func test_the_player_stays_on_screen_anywhere_on_the_walk() -> void:
	var walk := PondWalk.WALK
	for zoom in [1.0, 0.8, P0Pond.FAR_ZOOM, 1.4]:
		var cam := _phone_camera(zoom)
		for c in [walk.position, Vector2(walk.end.x, walk.position.y), walk.end, Vector2(walk.position.x, walk.end.y), Vector2(6, walk.position.y), Vector2(walk.position.x, -8)]:
			var player := Vector3(c.x, 0, c.y)
			P0Pond.place(cam, P0Pond.clamp_focus(player, cam.size, PHONE, BAND, PondScenery.MEADOW, player))
			var feet := cam.unproject_position(player)
			var head := cam.unproject_position(player + Vector3.UP * P0Pond.HEAD_M)
			var side := P0Pond.PLAYER_HALF_M * PHONE.x / cam.size
			var why := "%s at zoom %s: feet %s head %s" % [c, zoom, feet, head]
			assert_float(feet.x - side).override_failure_message(why).is_greater_equal(P0Pond.PLAYER_SAFE_PX - 0.01)
			assert_float(feet.x + side).override_failure_message(why).is_less_equal(PHONE.x - P0Pond.PLAYER_SAFE_PX + 0.01)
			assert_float(head.y).override_failure_message(why).is_greater_equal(BAND.position.y - 0.01)
			assert_float(feet.y).override_failure_message(why).is_less_equal(BAND.end.y + 0.01)

## 不知火舞 on 442 (Fern's lower right: the shoes touched the ⇄): standing on the action group's side of the screen, the
## feet keep KEY_GAP_PX over the column's top; on the other side the keys change nothing.
func test_by_the_keys_the_feet_keep_clear_of_the_switch() -> void:
	var walk := PondWalk.WALK
	for zoom in [1.0, P0Pond.FAR_ZOOM, 1.4]:
		var cam := _phone_camera(zoom)
		var right := Vector3(walk.end.x - 0.1, 0, walk.end.y - 0.1)
		P0Pond.place(cam, P0Pond.clamp_focus(right, cam.size, PHONE, BAND, PondScenery.MEADOW, right, KEYS))
		var feet := cam.unproject_position(right)
		assert_float(feet.x + P0Pond.PLAYER_HALF_M * PHONE.x / cam.size).is_greater_equal(KEYS.position.x - P0Pond.KEY_GAP_PX)
		assert_float(feet.y).override_failure_message("zoom %s feet %s" % [zoom, feet]).is_less_equal(KEYS.position.y - P0Pond.KEY_GAP_PX + 0.01)
		var left := Vector3(walk.position.x + 0.1, 0, walk.end.y - 0.1)
		assert_vector(P0Pond.clamp_focus(left, cam.size, PHONE, BAND, PondScenery.MEADOW, left, KEYS)).is_equal(
			P0Pond.clamp_focus(left, cam.size, PHONE, BAND, PondScenery.MEADOW, left))   # the left as before

## 盘古 on 422: the pond's own projection (for the opening screen before its camera stands there) is the camera's.
func test_its_projection_is_the_cameras() -> void:
	for zoom in [1.0, P0Pond.FAR_ZOOM]:
		var cam := _phone_camera(zoom)
		var focus := Vector3(5.3, 0.1, -4.2)
		P0Pond.place(cam, focus)
		for p in [Vector3(6.125, 0, -1.625), Vector3(9.0, 1.8, -3.0), Vector3(0.5, 0.4, -12.0)]:
			assert_vector(P0Pond.project(p, focus, cam.size, PHONE)).is_equal_approx(cam.unproject_position(p), Vector2.ONE * 0.01)

## 奕星 / 盘古 on #906: the wild's dressing is judged on one reference screen, the same on every phone — the pond's
## camera band and action keys as P0Ui lays them out at 360 × 800 (so a change to the HUD shows here).
func test_the_dressings_reference_screen_is_the_huds_at_360_by_800() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(P0Pond.REF_VIEW)
	add_child(auto_free(vp))
	var ui := P0Ui.new()
	ui.quick_store = "user://test_pond_ref_screen.json"
	vp.add_child(ui)
	await get_tree().process_frame
	ui.set_mode("fish", "Fern Pond")
	ui.set_surface("pond")
	ui.set_view({"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000}, "coins": 40, "skills": {},
		"bag": {"capacity": 25, "free": 24, "slots": []}, "plots": [], "names": {}})
	for i in 3: await get_tree().process_frame
	assert_object(ui.camera_band()).is_equal(P0Pond.REF_BAND)
	assert_array(ui.key_rects()).is_equal(P0Pond.REF_KEYS)
	assert_object(ui.key_column()).is_equal(P0Pond.REF_COLUMN)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_pond_ref_screen.json"))

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
## The band's four corners on the ground (x, z).
func _band_corners(cam: Camera3D) -> Array:
	var out := []
	for at in [BAND.position, Vector2(BAND.end.x, BAND.position.y), BAND.end, Vector2(BAND.position.x, BAND.end.y)]:
		var o := cam.project_ray_origin(at)
		var d := cam.project_ray_normal(at)
		var p := o + d * (-o.y / d.y)
		out.append(Vector2(p.x, p.z))
	return out

## #917 (李元芳 / 周瑜: the wild's ground heavy per pixel on GLES): only under gl_compatibility the pond draws its 3D at
## 0.8; the scale it found is put back on leaving.
func test_on_gles_the_pond_draws_its_3d_at_0_8_and_gives_the_scale_back() -> void:
	assert_float(P0Pond.pond_scale_3d("gl_compatibility")).is_equal(P0Pond.GLES_SCALE_3D)
	assert_float(P0Pond.GLES_SCALE_3D).is_equal(0.8)
	for method in ["forward_plus", "mobile", "dummy"]:
		assert_bool(P0Pond.pond_scale_3d(method) < 0.0).override_failure_message(method).is_true()
	var vp := SubViewport.new()
	add_child(vp)
	vp.scaling_3d_scale = 1.0
	var was := P0Pond.set_scale_3d(vp, P0Pond.pond_scale_3d("gl_compatibility"))
	assert_float(vp.scaling_3d_scale).is_equal_approx(0.8, 0.001)
	P0Pond.set_scale_3d(vp, was)
	assert_float(vp.scaling_3d_scale).is_equal_approx(1.0, 0.001)
	vp.queue_free()
