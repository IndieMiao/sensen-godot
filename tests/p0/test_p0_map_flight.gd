extends GdUnitTestSuite
## SGODOT-267 (the user's call: no jumps; 不知火舞 keeps 197 LOCK-24 / LOCK-08): the map's own camera moves — the home
## key, the recenter key and Show on map — fly the city's flight (MapFlight, cubic in-out), 0.35 s per unit of path
## between 0.6 and 1.2 s, and land as they did before: the recenter key lands at LOCATE_ZOOM from any zoom (q(158); it
## kept the zoom before) and selects nothing; Show on map
## selects its pin (its card) on landing, the homestead only flown to; the home key's own suite covers it. A touch on the
## map stops a flight where it is with nothing landing; the same move asked again while it flies is ignored and another
## one takes over.

const P0_MAP := "res://scenes/p0/p0_map.tscn"

var map: Node
var rt: P0Runtime

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	map = (load(P0_MAP) as PackedScene).instantiate()
	viewport.add_child(map)
	for i in 3: await get_tree().process_frame
	map.set_process(false)
	rt = map.rt

func after_test() -> void:
	if is_instance_valid(map) and rt.ui.has_modal(): rt.ui.close_modal()
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _here() -> Vector2: return Vector2(map.center_lat, map.center_lng)

## Waits for the flight to land (at most 2 s): the seconds it took from `started`.
func _landed(started: int) -> float:
	var until := Time.get_ticks_msec() + 2000
	while map._flight != null and map._flight.is_running() and Time.get_ticks_msec() < until: await get_tree().process_frame
	return (Time.get_ticks_msec() - started) / 1000.0

func _touch() -> void:   # a finger down on empty map and lifted without a tap of its own
	var down := InputEventScreenTouch.new()
	down.position = Vector2(60, 300)
	down.pressed = true
	map._unhandled_input(down)
	var up := InputEventScreenTouch.new()
	up.position = down.position
	up.canceled = true
	map._unhandled_input(up)

## The recenter key flies back to the player (here at the Tea House) at LOCATE_ZOOM (q(158), the user on 301) and
## selects nothing.
func test_the_recenter_key_flies_to_the_player_at_the_locate_zoom() -> void:
	var tea := P0Outposts.by_role("tea")
	rt.here = {"space": "outpost", "place": str(tea.id)}
	map._sync_here()
	map.fly_to(map.home_lat + 0.01, map.home_lng + 0.01)
	map._set_zoom(13.3)
	var from := _here()
	var started := Time.get_ticks_msec()
	map._city_action("recenter")
	await get_tree().create_timer(0.25).timeout
	assert_vector(_here()).is_not_equal(from)   # on its way, not a jump
	assert_float(_here().distance_to(Vector2(float(tea.lat), float(tea.lng)))).is_greater(1e-5)
	var took := await _landed(started)
	assert_float(took).is_between(0.6 - 0.05, 1.2 + 0.15)
	assert_float(map.center_lat).is_equal_approx(float(tea.lat), 1e-5)
	assert_float(map.center_lng).is_equal_approx(float(tea.lng), 1e-5)
	assert_float(map.zoom).is_equal_approx(map.LOCATE_ZOOM, 1e-6)
	assert_dict(map.city_map.selected).is_empty()
	assert_bool(rt.ui.has_modal()).is_false()

## q(158): from any zoom — the state view far out too — the recenter key lands on the player at LOCATE_ZOOM, in the same
## capped flight; during a cross-city flight it does nothing.
func test_the_recenter_key_comes_in_from_the_state_view_and_waits_out_a_cross_city_flight() -> void:
	map.center_lat = 38.3
	map.center_lng = -121.2
	map._set_zoom(6.0)
	var started := Time.get_ticks_msec()
	map._city_action("recenter")
	var took := await _landed(started)
	assert_float(took).is_less(1.2 + 0.15)
	assert_float(map.center_lat).is_equal_approx(map.home_lat, 1e-5)
	assert_float(map.center_lng).is_equal_approx(map.home_lng, 1e-5)
	assert_float(map.zoom).is_equal_approx(map.LOCATE_ZOOM, 1e-6)
	map.center_lat = 38.3
	map.center_lng = -121.2
	map._set_zoom(6.0)
	map._trip = {to_city = "gn-1850147"}   # in the air (P0TravelFlight's own suite flies it for real)
	map._city_action("recenter")
	assert_float(map.center_lat).is_equal_approx(38.3, 1e-9)
	assert_float(map.zoom).is_equal_approx(6.0, 1e-6)
	assert_bool(map._flight != null and map._flight.is_running()).is_false()   # nothing took off
	map._trip = {}

## Show on map flies to the pin and selects it on landing — its card, as before (LOCK-08) — never while it flies.
func test_show_on_map_flies_and_selects_the_pin_on_landing() -> void:
	var post := P0Outposts.by_role("post")
	var started := Time.get_ticks_msec()
	rt.ui.show_on_map.emit("outpost:post")
	await get_tree().create_timer(0.25).timeout
	assert_float(_here().distance_to(Vector2(float(post.lat), float(post.lng)))).is_greater(1e-5)
	assert_dict(map.city_map.selected).is_empty()   # not yet
	var took := await _landed(started)
	assert_float(took).is_between(0.6 - 0.05, 1.2 + 0.15)
	assert_float(map.center_lat).is_equal_approx(float(post.lat), 1e-6)
	assert_float(map.zoom).is_equal_approx(map.SHOW_ZOOM, 0.01)
	assert_str(str(map.city_map.selected.get("id", ""))).is_equal(str(post.id))
	assert_object(AppRouter.top_instance()).is_null()   # guidance only: nothing entered
	map.city_map.clear_selection()
	rt.ui.show_on_map.emit("home")   # the homestead: flown to, not selected (its pin would offer Enter)
	await _landed(Time.get_ticks_msec())
	assert_float(map.center_lat).is_equal_approx(map.home_lat, 1e-6)
	assert_dict(map.city_map.selected).is_empty()

## A touch on the map stops either flight where it is: no pin selected, no card.
func test_a_touch_stops_the_recenter_and_show_flights() -> void:
	for start in [func(): map._city_action("recenter"), func(): rt.ui.show_on_map.emit("outpost:post")]:
		map.fly_to(map.home_lat + 0.02, map.home_lng - 0.02)
		start.call()
		await get_tree().create_timer(0.25).timeout
		_touch()
		var stopped := _here()
		await get_tree().create_timer(1.4).timeout
		assert_vector(_here()).is_equal(stopped)
		assert_dict(map.city_map.selected).is_empty()
		assert_bool(rt.ui.has_modal()).is_false()

## The same move asked again while it flies is ignored (the same flight lands); another move takes over.
func test_the_same_move_again_is_ignored_and_another_takes_over() -> void:
	map.fly_to(map.home_lat + 0.02, map.home_lng + 0.02)
	rt.ui.show_on_map.emit("outpost:post")
	var flight: Tween = map._flight
	await get_tree().create_timer(0.2).timeout
	rt.ui.show_on_map.emit("outpost:post")
	assert_object(map._flight).is_same(flight)
	map._city_action("recenter")   # another move: it takes over, to the player at home
	assert_object(map._flight).is_not_same(flight)
	await _landed(Time.get_ticks_msec())
	assert_float(map.center_lat).is_equal_approx(map.home_lat, 1e-6)
	assert_dict(map.city_map.selected).is_empty()   # the post's landing never ran
