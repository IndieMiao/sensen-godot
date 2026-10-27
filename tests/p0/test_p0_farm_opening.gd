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
