extends GdUnitTestSuite
## After a pinch the mine camera eases back to a player it left outside the safe box (李元芳 int12, 奕星): the zoom about
## the fingers pushed the player half off the screen at a room's end, and the camera held until they walked. With the
## player still inside the box, the pinched framing stays; while the fingers are down, or the zoom is still springing
## back from past a limit, nothing eases.

const P0Mine := preload("res://scenes/p0/p0_mine.gd")
const VIEW := Vector2(360, 800)
const DT := 1.0 / 60.0

## The mine with its world and camera but no runtime (no server view, no rig: the camera reads the actor's position).
class Probe extends "res://scenes/p0/p0_mine.gd":
	func _ready() -> void:
		_build_light()

	func _view() -> Dictionary:
		return {}

func after() -> void:
	P0Runtime.free_instance_for_tests()

## A mine at `at`, opened at zoom `zoom` (the pinch at rest there).
func _mine(at: Vector3, zoom := 0.8) -> Probe:
	var vp := SubViewport.new()
	vp.size = Vector2i(VIEW)
	add_child(auto_free(vp))
	var mine := Probe.new()
	vp.add_child(mine)
	mine._build_floor(1)
	var actor := P0Actor.new()
	mine.add_child(actor)
	mine.actor = actor
	actor.mover = PlayerMover.new(mine.bp, mine.grid)
	actor.teleport(at)
	mine._pinch = P0Mine.ElasticZoom.new(0.8, 1.4, zoom)
	mine._zoom = zoom
	mine._focus = at
	mine._update_camera()
	return mine

func _run(mine: Probe, seconds: float) -> void:
	for i in roundi(seconds / DT): mine._follow(DT)

func _screen(mine: Probe) -> Vector2:
	return mine.cam.unproject_position(mine.actor.position)

func _in_box(mine: Probe) -> bool:
	return P0Follow.box(VIEW).has_point(_screen(mine))

## Closer about a point far from the player: they leave the box; once the fingers lift, the camera eases back (P0Follow's
## 0.6 s), not straight away.
func test_a_pinch_that_leaves_the_player_outside_the_safe_box_eases_back() -> void:
	var mine := _mine(Vector3(5.0, 0, -3.6))
	assert_bool(_in_box(mine)).is_true()
	mine.p0_zoom(0.8 / 1.4, Vector2(4, 400))   # from the widest view, closer about the screen's left edge
	mine.p0_zoom_end()
	assert_bool(_in_box(mine)).override_failure_message("the pinch should push the player out: %s" % _screen(mine)).is_false()
	var pushed := _screen(mine).distance_to(VIEW * 0.5)
	_run(mine, 0.2)
	assert_bool(mine._cam_follow.held).is_false()
	assert_float(_screen(mine).distance_to(VIEW * 0.5)).is_less(pushed)   # on its way …
	assert_bool(_in_box(mine)).is_false()                                  # … eased, not a jump
	_run(mine, 0.8)
	assert_bool(_in_box(mine)).is_true()
	assert_float(mine._zoom).is_equal_approx(1.4, 0.0001)                  # the zoom the player chose stays

## The int12 case: at the room's right end the framing stops at the art's edge, so the player may stay off the box's
## middle, but the camera comes back to them, feet and head on screen.
func test_at_the_rooms_end_the_player_comes_back_on_screen() -> void:
	var mine := _mine(Vector3(8.9, 0, -3.6))   # R1's right view
	mine.p0_zoom(0.8 / 1.4, Vector2(4, 400))
	mine.p0_zoom_end()
	var pushed := _screen(mine).distance_to(VIEW * 0.5)
	_run(mine, 1.0)
	var feet := _screen(mine)
	var head := mine.cam.unproject_position(mine.actor.position + Vector3.UP * 1.8)
	assert_float(feet.distance_to(VIEW * 0.5)).is_less(pushed)
	for p in [feet, head]:
		assert_bool(Rect2(Vector2.ZERO, VIEW).grow(-40.0).has_point(p)).override_failure_message("off screen: %s" % p).is_true()

## A pinch about the player keeps them inside the box: the pinched framing holds until they walk.
func test_a_pinch_that_keeps_the_player_in_the_box_holds() -> void:
	var mine := _mine(Vector3(5.0, 0, -3.6))
	mine.p0_zoom(0.8 / 1.3, _screen(mine))
	mine.p0_zoom_end()
	assert_bool(_in_box(mine)).is_true()
	var cam := mine.cam.global_position
	_run(mine, 1.0)
	assert_bool(mine._cam_follow.held).is_true()
	assert_bool(mine.cam.global_position.is_equal_approx(cam)).is_true()

## Past 1.4 the zoom springs back first (about the same point); the camera eases only once it has settled.
func test_past_the_limit_the_spring_back_comes_first() -> void:
	var mine := _mine(Vector3(5.0, 0, -3.6))
	mine.p0_zoom(0.8 / 1.9, Vector2(4, 400))
	mine.p0_zoom_end()
	assert_float(mine._zoom).is_greater(1.45)
	_run(mine, 0.05)
	assert_bool(mine._cam_follow.held).is_true()   # still springing back
	_run(mine, 1.5)
	assert_float(mine._zoom).is_equal_approx(1.4, 0.001)
	assert_bool(mine._cam_follow.held).is_false()
	assert_bool(_in_box(mine)).is_true()

## Fingers still down: the stretch and the framing stay however long they rest.
func test_nothing_eases_while_the_fingers_are_down() -> void:
	var mine := _mine(Vector3(5.0, 0, -3.6))
	mine.p0_zoom(0.8 / 1.4, Vector2(4, 400))
	var cam := mine.cam.global_position
	_run(mine, 2.0)
	assert_bool(mine._cam_follow.held).is_true()
	assert_bool(mine.cam.global_position.is_equal_approx(cam)).is_true()
	assert_bool(_in_box(mine)).is_false()
