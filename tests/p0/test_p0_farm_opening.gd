extends GdUnitTestSuite
## The farm's opening shot keeps the farmhouse's mark clear of the HUD (李元芳 int12-pre on 256): on a phone the status-bar
## inset brings the HUD down over the roof while the 3D view stays, the mark's anchor fell above P0Ui.marker_area and the
## `!` — hidden there — only showed after a few steps. The real farm (blueprint, farmhouse, walk-in point) and its camera
## at 360 × 800 in a SubViewport, so headless runs the same.

const P0Farm := preload("res://scenes/p0/p0_farm.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")
const PHONE := Vector2(360, 800)
const BAR_TOP := 708.0   # the quick bar's top at 360 × 800 (P0Ui.marker_area's bottom, desktop)

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

func _farm() -> Dictionary:
	var bp := P0Garden.blueprint()
	var spawn := PlayerMover.new(bp, BlueprintGrid.new(bp)).position
	var house := bp.cell_to_world(bp.anchor("house"))
	return {spawn = spawn, mark = house + P0Farm.HOME_MARK, focus = P0Farm.opening_point(bp, house)}

func _area(inset: float) -> Rect2:
	var top := UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + inset
	return Rect2(0, top, PHONE.x, BAR_TOP - top)

func test_the_opening_shot_keeps_the_farmhouse_mark_below_the_hud_on_a_notched_phone() -> void:
	var cam := _camera()
	var f := _farm()
	for inset in [38.0, 60.0]:   # the int12-pre emulator; a deeper notch
		var area := _area(inset)
		FarmCamera.place(cam, (f.focus as Vector3) + Vector3.UP * 0.7)
		assert_float(cam.unproject_position(f.mark).y).override_failure_message("inset %d: the case" % inset) \
			.is_less(area.position.y + P0Farm.MARK_ROOM)   # as reported: the mark under the HUD
		var fitted: Vector3 = P0Farm.opening_focus(cam, f.focus, f.mark, f.spawn, area)
		FarmCamera.place(cam, fitted + Vector3.UP * 0.7)
		assert_float(cam.unproject_position(f.mark).y).is_equal_approx(area.position.y + P0Farm.MARK_ROOM, 0.05)
		assert_bool(area.has_point(cam.unproject_position(f.mark))).is_true()                       # so it shows
		assert_float(cam.unproject_position(f.spawn).y).is_less_equal(area.end.y - P0Farm.FEET_ROOM)  # feet above the bar

## Without an inset the mark is clear already: the polished farm's opening shot stays exactly as it was.
func test_without_an_inset_the_opening_shot_is_unchanged() -> void:
	var cam := _camera()
	var f := _farm()
	FarmCamera.place(cam, (f.focus as Vector3) + Vector3.UP * 0.7)
	assert_vector(P0Farm.opening_focus(cam, f.focus, f.mark, f.spawn, _area(0.0))).is_equal(f.focus)

func test_guide_opening_frames_pip_teaching_beds_and_player_without_changing_zoom() -> void:
	var cam := _camera()
	var f := _farm()
	var bp := P0Garden.blueprint()
	var points: Array[Vector3] = [f.spawn, bp.cell_to_world(P0Farm.FarmGuide.STAND) + Vector3(0, 2.2, 0),
		bp.cell_to_world(P0Garden.cell_of(0)), bp.cell_to_world(P0Garden.cell_of(1))]
	var zoom := cam.size
	FarmCamera.place(cam, (f.focus as Vector3) + Vector3.UP * 0.7)
	var focus := P0Farm.guide_opening_focus(cam, f.focus, points, _area(0.0))
	FarmCamera.place(cam, focus + Vector3.UP * 0.7)
	for point in points: assert_bool(_area(0.0).has_point(cam.unproject_position(point))).is_true()
	assert_float(cam.size).is_equal(zoom)

## The move is capped by the feet: never closer than FEET_ROOM to the quick bar, even when the mark can't clear.
func test_the_shift_stops_before_the_feet_reach_the_quick_bar() -> void:
	var area := Rect2(0, 136, 360, 572)   # 136 … 708
	assert_float(P0Farm.opening_shift(140.0, 572.0, area)).is_equal(20.0)    # 136 + 24 − 140
	assert_float(P0Farm.opening_shift(170.0, 572.0, area)).is_equal(0.0)     # clear already
	assert_float(P0Farm.opening_shift(100.0, 680.0, area)).is_equal(12.0)    # room 708 − 16 − 680 = 12 < 60 needed
	assert_float(P0Farm.opening_shift(100.0, 700.0, area)).is_equal(0.0)     # no room at all: left as it is

## The opening fits the area as it is with the HUD and the quick bar up, so a panel open on arrival (hiding both) leaves
## nothing to catch up on when it closes (后裔 on #166).
func test_the_open_marker_area_is_the_marker_area_with_the_hud_up() -> void:
	var ui := P0Ui.new()
	ui.quick_store = "user://test_p0_farm_opening.json"
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.hud.visible = true   # a bare UI starts with its HUD hidden; a world's set_mode shows it
	ui._bar.visible = true
	await get_tree().process_frame
	var shown := ui._marker_area()
	assert_bool(shown.has_area()).is_true()
	assert_that(ui.open_marker_area()).is_equal(shown)
	ui.hud.visible = false
	ui._bar.visible = false
	assert_float(ui._marker_area().position.y).is_equal(0.0)   # covered: the live area changes …
	assert_that(ui.open_marker_area()).is_equal(shown)         # … the opening's does not
	ui._bar.visible = true
	var drawer := Control.new()   # the Bag drawer takes the bar into itself, near the top of the screen
	drawer.position = Vector2(0, 200)
	ui._kit.add_child(drawer)
	ui.dock_bar_into(drawer)
	await get_tree().process_frame
	assert_that(ui.open_marker_area()).is_equal(shown)   # its place, not where the drawer holds it (int12-pre shot)
	ui.undock_bar()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_p0_farm_opening.json"))

## 农场林地 A (上官婉儿, pending the user's pick): the farm rests at REST_ZOOM 0.8 — the opening starts there and zooms out
## only as far as its beds need, walking eases a zoomed-out opening back to it, never past it, and a pinch is the player's
## (walking no longer pulls it back); the first pinch picks up at the rest zoom, not at 1.0.
func test_the_farm_rests_at_the_woodland_zoom_and_a_pinch_picks_up_there() -> void:
	var farm = P0Farm.new()
	assert_float(farm._zoom).is_equal(P0Farm.REST_ZOOM)
	assert_float(P0Farm.REST_ZOOM).is_equal(0.8)
	assert_float(farm._pinch.value).is_equal_approx(P0Farm.REST_ZOOM, 0.0001)
	farm.free()

func test_walking_eases_a_wide_opening_back_to_the_rest_zoom_and_a_pinch_stays() -> void:
	var z := 0.53   # Lv8's 22 beds
	for i in 120: z = P0Farm.ease_to_rest(z, 1.0 / 60.0)
	assert_float(z).is_equal(P0Farm.REST_ZOOM)   # there in 2 s, not on to 1.0
	assert_float(P0Farm.ease_to_rest(P0Farm.REST_ZOOM, 1.0)).is_equal(P0Farm.REST_ZOOM)
	var farm = P0Farm.new()
	farm._opening_zoom = true
	farm.p0_zoom(0.9)
	assert_bool(farm._opening_zoom).is_false()   # the player's zoom from here
	farm.free()


## SGODOT-465 (the user 11-10, bot 641 「农场点地 ok」): a tap on the open ground walks there; on an open bed it walks to the
## walkway behind it (plotface's stand) and sows nothing; a bed not open yet is grass.
func test_a_ground_tap_walks_there_and_a_bed_tap_to_the_path_in_front() -> void:
	var bp := P0Garden.blueprint()
	var grass := bp.cell_to_world(Vector2i(12, 8)) + Vector3(0.1, 0, 0.1)
	assert_vector(P0Farm.tap_target(bp, grass, 8)).is_equal(grass)
	var bed := P0Garden.cell_of(5)   # Lv1's eight beds: 0–7
	var front := bp.cell_to_world(bed + P0Farm.BED_FRONT)
	assert_vector(P0Farm.tap_target(bp, bp.cell_to_world(bed), 8)).is_equal(front)
	assert_float(front.z).is_less(bp.cell_to_world(bed).z)   # beyond it from the camera: the bed stays in sight
	assert_bool(bp.is_walkable(bed + P0Farm.BED_FRONT)).is_true()   # the path between the rows
	var shut := bp.cell_to_world(P0Garden.cell_of(32))   # not open at Lv1: grass to the player
	assert_vector(P0Farm.tap_target(bp, shut, 8)).is_equal(shut)

## 周瑜 on #947: the joystick takes over a tapped walk, so letting go does not turn the player to the bed.
func test_the_joystick_ends_a_tapped_walk() -> void:
	var farm = P0Farm.new()
	farm._tap_walk = true
	farm._tap_face = Vector3(1, 0, 1)
	farm.p0_joystick(Vector2(1, 0))
	assert_bool(farm._tap_walk).is_false()
	farm.free()

