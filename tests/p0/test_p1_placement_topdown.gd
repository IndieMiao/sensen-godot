extends GdUnitTestSuite
## Placement's top-down view (用户 on 284 058639c7; 不知火舞 284 v2 6a751a9a; 哪吒 on #261): straight down with no yaw,
## 36 px a cell when it opens, two fingers zoom 17–56 px a cell; the real camera at 360 × 800 in a SubViewport.

const P0Farm := preload("res://scenes/p0/p0_farm.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")
const PHONE := Vector2(360, 800)

func _camera() -> Camera3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = FarmCamera.close_view_size(PHONE) * FarmCamera.P0_VIEW_K
	vp.add_child(cam)
	cam.make_current()
	return cam

## Two neighbouring cell centres on screen, in pixels.
func _cell_px(cam: Camera3D, bp: FarmBlueprint, at: Vector2i) -> float:
	return cam.unproject_position(bp.cell_to_world(at)).distance_to(cam.unproject_position(bp.cell_to_world(at + Vector2i(1, 0))))

func test_the_view_turns_straight_down_at_36_px_a_cell_and_pinches_to_56() -> void:
	var cam := _camera()
	var bp := P0Garden.blueprint()
	var focus := bp.cell_to_world(Vector2i(9, 7))
	P0Farm.place_top(cam, focus, 1.0, P0Farm.TOP_CELL_PX, bp.cell_m)
	assert_float(cam.global_basis.z.y).is_equal_approx(1.0, 0.001)   # looking straight down
	assert_float(cam.rotation.y).is_equal_approx(0.0, 0.001)         # no yaw: cells square on screen
	assert_float(_cell_px(cam, bp, Vector2i(9, 7))).is_equal_approx(36.0, 0.5)
	# the same row stays level on screen; the next row is straight below it (the farmhouse, back, is at the top)
	var a := cam.unproject_position(bp.cell_to_world(Vector2i(9, 7)))
	var b := cam.unproject_position(bp.cell_to_world(Vector2i(10, 7)))
	assert_float(a.y).is_equal_approx(b.y, 0.5)
	var px := P0Farm.top_cell_after(P0Farm.TOP_CELL_PX, 0.5)   # fingers apart: zoom in, stopped at 56
	assert_float(px).is_equal(56.0)
	P0Farm.place_top(cam, focus, 1.0, px, bp.cell_m)
	assert_float(_cell_px(cam, bp, Vector2i(9, 7))).is_equal_approx(56.0, 0.5)
	assert_float(P0Farm.top_cell_after(20.0, 2.0)).is_equal(17.0)   # fingers together: out, stopped at 17

func test_half_way_the_turn_is_between_the_two_views() -> void:
	var cam := _camera()
	var bp := P0Garden.blueprint()
	P0Farm.place_top(cam, bp.cell_to_world(Vector2i(9, 7)), 0.5, P0Farm.TOP_CELL_PX, bp.cell_m)
	var pitch := rad_to_deg(-cam.rotation.x)
	assert_float(pitch).is_between(FarmCamera.PITCH_DEG + 1.0, 89.0)
	assert_float(rad_to_deg(cam.rotation.y)).is_between(0.5, FarmCamera.YAW_DEG - 0.5)
