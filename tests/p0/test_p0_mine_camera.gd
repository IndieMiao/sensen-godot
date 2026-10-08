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

## Across (不知火舞 on 231, the rooms' SIDE_MARGIN of #127): art wider than the screen stops with its outer edge 18 px
## from the side; art narrower than the space between the margins sits in the middle.
func test_the_sides_stop_with_the_art_18_px_from_the_screen_edge() -> void:
	var m := P0Room.SIDE_MARGIN
	assert_float(m).is_equal(18.0)
	assert_float(P0Mine.side_shift(-300.0, 500.0, 360.0, m)).is_equal(0.0)         # covers with room to spare: follows
	assert_float(P0Mine.side_shift(40.0, 900.0, 360.0, m)).is_equal(-22.0)         # left edge 40 px in: back to 18
	assert_float(P0Mine.side_shift(-600.0, 300.0, 360.0, m)).is_equal(42.0)        # right edge 60 px in: back to 18
	assert_float(P0Mine.side_shift(100.0, 200.0, 360.0, m)).is_equal(30.0)         # narrower: centred

func test_the_mine_opens_at_the_farms_size_and_pinches_like_it() -> void:
	var vp := Vector2(360, 800)
	assert_float(FarmCamera.player_scale_size(vp, FarmCamera.PITCH_DEG)).is_equal_approx(6.72, 0.001)   # farm zoom 1
	var mine = auto_free(P0Mine.new())   # not in the tree: only its camera fields
	assert_float(mine._zoom).is_equal(1.0)
	assert_float(mine._pinch.value).is_equal_approx(1.0, 0.0001)
	assert_float(exp(mine._pinch._low)).is_equal_approx(0.8, 0.0001)    # the farm's ElasticZoom range
	assert_float(exp(mine._pinch._high)).is_equal_approx(1.4, 0.0001)

func test_the_room_is_the_floors_walls() -> void:
	var art: Node3D = preload("res://modules/mining/mine_art.gd").floor_scenery(1, true)
	add_child(auto_free(art))
	var room := P0Mine._walls_box(art)
	assert_bool(room.size.x > 10.0 and room.size.z > 9.0).is_true()     # the carved walls, not a crate or a lantern
	assert_float(room.size.y).is_less(2.0)                             # wall tops, not the elevator frame

## Opening a panel that folds the quick bar and the key away keeps the band the room is framed in (苏烈 on #129).
func test_a_panel_keeps_the_band_the_room_is_framed_in() -> void:
	var store := "user://test_p0_mine_camera.json"
	var ui := P0Ui.new()
	ui.quick_store = store
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view({"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000}, "bag": {"capacity": 25, "free": 25,
		"slots": [{"id": "torch", "qty": 2}]}, "plots": [], "coins": 40, "skills": {}, "rest": {"used": 0, "limit": 1, "resets_in": 1},
		"inbox": {"parcels": [], "letters": []}})
	ui.set_mode("mine")
	ui.set_surface("mine")
	await await_idle_frame()
	var mine = auto_free(P0Mine.new())
	var vp := Vector2(360, 800)
	var before: Rect2 = mine._camera_band(ui, vp)
	assert_bool(before.has_area()).is_true()
	ui.open_inbox()
	await await_idle_frame()
	assert_bool(ui.has_modal()).is_true()
	assert_that(ui.camera_band()).is_not_equal(before)        # the live band does stretch under the panel …
	assert_that(mine._camera_band(ui, vp)).is_equal(before)   # … the room stays framed in the one from before it
	ui.close_modal()
	await await_idle_frame()
	assert_that(mine._camera_band(ui, vp)).is_equal(before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store))
