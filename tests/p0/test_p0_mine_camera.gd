extends GdUnitTestSuite
## Camera unification (用户 via 奕星, 2026-10-09; target 哪吒: 65.8 px at 360 × 800): the P0 mine frames the player like
## the farm at zoom 1, pinches like the farm, and keeps its view inside the room's art — fixed along an axis where the
## band is wider than the room, following inside the walls along the other.

const P0Mine := preload("res://scenes/p0/p0_mine.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")

func test_an_empty_range_keeps_its_middle_else_clamps() -> void:
	assert_float(P0Mine.clamp_or_centre(3.0, 5.0, 1.0)).is_equal(3.0)    # band wider than the room: fixed at the middle
	assert_float(P0Mine.clamp_or_centre(9.0, 5.0, 1.0)).is_equal(3.0)
	assert_float(P0Mine.clamp_or_centre(0.5, 1.0, 5.0)).is_equal(1.0)    # past the left wall: back to it
	assert_float(P0Mine.clamp_or_centre(6.0, 1.0, 5.0)).is_equal(5.0)
	assert_float(P0Mine.clamp_or_centre(2.5, 1.0, 5.0)).is_equal(2.5)    # inside: the safe box follows freely

func test_the_mine_opens_at_the_farms_size_and_pinches_like_it() -> void:
	var vp := Vector2(360, 800)
	assert_float(FarmCamera.player_scale_size(vp, FarmCamera.PITCH_DEG)).is_equal_approx(6.72, 0.001)   # farm zoom 1
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	assert_bool(src.contains("var _zoom := 1.0")).is_true()
	assert_bool(src.contains("ElasticZoom.new(0.8, 1.4)")).is_true()
	assert_bool(src.contains("FarmCamera.player_scale_size(")).is_true()

func test_the_room_is_the_floors_walls() -> void:
	var art: Node3D = preload("res://modules/mining/mine_art.gd").floor_scenery(1, true)
	add_child(auto_free(art))
	var room := P0Mine._walls_box(art)
	assert_bool(room.size.x > 10.0 and room.size.z > 9.0).is_true()     # the carved walls, not a crate or a lantern
	assert_float(room.size.y).is_less(2.0)                             # wall tops, not the elevator frame
