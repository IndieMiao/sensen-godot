extends GdUnitTestSuite
## SGODOT-342 PR-2, the pin page's map (亚瑟 342 6418183a, plan A): the P0 map pushed in its pick mode over another map
## and popped leaves the one under it as it was — CityMapData's region provider still set, the map resumed (process,
## camera, the clear background), the stack as deep as before — and five rounds add no nodes. In its pick mode the map
## builds no city map, avatar or HUD, is never the runtime's world, keeps Back for the home pick, and converts a screen
## point and the earth both ways (flat, north up).

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const SF := "gn-5391959"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	for i in 2: await get_tree().process_frame
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _frames(n := 3) -> void:
	for i in n: await get_tree().process_frame

func _push_pick() -> Node:
	return AppRouter.push_instance(P0_MAP, {"home_pick": {"cluster": SF}})

func test_the_pick_map_over_a_map_leaves_it_as_it_was() -> void:
	var depth := AppRouter.instance_depth()
	var lower := AppRouter.push_instance(P0_MAP)
	await _frames()
	assert_bool(CityMapData.region_provider.is_valid()).is_true()
	var pick := _push_pick()
	await _frames()
	assert_bool(lower.process_mode == Node.PROCESS_MODE_DISABLED).is_true()   # suspended under it
	assert_bool(AppRouter.top_instance() == pick).is_true()
	AppRouter.pop_instance()
	await _frames()
	assert_bool(CityMapData.region_provider.is_valid()).override_failure_message("the pick map cleared the provider").is_true()
	assert_bool(lower.process_mode == Node.PROCESS_MODE_INHERIT).is_true()
	assert_bool(lower.cam.current).is_true()
	assert_bool(get_viewport().transparent_bg).is_true()
	assert_bool(P0Runtime.ensure().world == lower).is_true()   # the map under it is the world again (resume)
	assert_int(AppRouter.instance_depth()).is_equal(depth + 1)

func test_five_rounds_add_no_nodes() -> void:
	AppRouter.push_instance(P0_MAP)
	await _frames()
	_push_pick()
	await _frames()
	AppRouter.pop_instance()
	await _frames()
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 5:
		_push_pick()
		await _frames()
		AppRouter.pop_instance()
		await _frames()
	assert_float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)).is_equal(nodes)

func test_the_pick_map_is_the_camera_alone() -> void:
	var rt := P0Runtime.ensure()
	var world_before = rt.world
	var pick := _push_pick()
	await _frames(4)
	assert_bool(pick.picking()).is_true()
	assert_object(pick.city_map).is_null()
	assert_bool(pick._spawn_queue.is_empty() and pick._pawns.is_empty()).override_failure_message("an avatar was queued").is_true()
	assert_bool(pick.get_node("HUD").visible).is_false()
	assert_bool(rt.world == world_before).is_true()   # never rt.attach
	assert_float(pick.pitch).is_equal(0.0)
	assert_float(pick.bearing).is_equal(0.0)
	assert_bool(pick.is_back_navigation_locked()).is_true()   # Back is the home pick's; the map never pops itself
	assert_bool(AppRouter.top_instance() == pick).is_true()

func test_a_point_goes_to_the_earth_and_back() -> void:
	var pick := _push_pick()
	await _frames()
	var at := Vector2(180, 378)
	pick.pick_put(37.7712345678, -122.4312345678, at)
	var g: Array = pick.pick_geo_at(at)
	assert_float(g[0]).is_equal_approx(37.7712345678, 1e-9)
	assert_float(g[1]).is_equal_approx(-122.4312345678, 1e-9)
	var s: Vector2 = pick.pick_screen_of(37.7712345678, -122.4312345678)
	assert_float(s.distance_to(at)).is_less(0.01)
	# a km east is pick_px_per_m × 1000 px to the right
	var east: Vector2 = pick.pick_screen_of(37.7712345678, -122.4312345678 + 1000.0 / (111319.4908 * cos(deg_to_rad(37.7712345678))))
	assert_float(east.x - at.x).is_equal_approx(float(pick.pick_px_per_m()) * 1000.0, 0.5)
	assert_bool(pick.pick_dragging()).is_false()
	assert_bool(pick.pick_has_ground()).is_false()   # no native map here: the page lays its land

func test_the_camera_stays_in_the_circles_box_and_zooms_out_to_the_whole_circle() -> void:
	var pick := _push_pick()
	await _frames()
	pick.pick_area(37.76, -122.44, 10.0)
	pick.center_lat = 38.5
	pick.center_lng = -121.0
	pick._clamp_to_bounds()
	assert_float(pick.center_lat).is_equal_approx(37.76 + 10000.0 / 111319.4908, 1e-5)   # (pan_bounds is a Rect2: single precision, a decimetre)
	assert_float(pick.center_lng).is_equal_approx(-122.44 + 10000.0 / (111319.4908 * cos(deg_to_rad(37.76))), 1e-5)
	pick._set_zoom(2.0)
	pick._zoom_elastic = 0.0   # the rubber band past the floor springs back
	var across := float(pick.pick_px_per_m()) * 20000.0
	var vp: Vector2 = pick.get_viewport().get_visible_rect().size
	assert_float(across).is_less_equal(minf(vp.x, vp.y) - 2.0 * pick.PICK_FIT_PAD + 1.0)   # the whole circle fits
	assert_float(across).is_greater(minf(vp.x, vp.y) - 2.0 * pick.PICK_FIT_PAD - 20.0)

## 亚瑟 on #495 ②: the pin stays lifted while the map slides or zooms on after the finger lifts.
func test_a_slide_after_the_finger_counts_as_dragging() -> void:
	var pick := _push_pick()
	await _frames()
	assert_bool(pick.pick_dragging()).is_false()
	pick._fling_vel = Vector3(50, 0, 0)
	assert_bool(pick.pick_settling()).is_true()
	assert_bool(pick.pick_dragging()).is_true()
	pick._fling_vel = Vector3.ZERO
	pick._touch_count = 1
	assert_bool(pick.pick_settling()).is_false()   # a finger on it: dragging, not settling
	assert_bool(pick.pick_dragging()).is_true()
	pick._touch_count = 0

## 亚瑟 on #495 ①: a city the client's cluster table does not know gets no map (the page keeps its flat one).
func test_an_unknown_city_gets_no_pick_map() -> void:
	var rt := P0Runtime.ensure()
	var depth := AppRouter.instance_depth()
	assert_object(rt._open_pick_map("gn-0000000-nowhere")).is_null()
	assert_int(AppRouter.instance_depth()).is_equal(depth)
	var m = rt._open_pick_map(SF)
	assert_object(m).is_not_null()
	assert_int(AppRouter.instance_depth()).is_equal(depth + 1)
	rt.close_pick_map()
	assert_int(AppRouter.instance_depth()).is_equal(depth)

## Build here mid-slide (不知火舞 342 35e97397): pick_stop ends the slide where it is.
func test_pick_stop_ends_the_slide() -> void:
	var pick := _push_pick()
	await _frames()
	pick._fling_vel = Vector3(80, 0, 0)
	pick._zoom_vel = 0.5
	assert_bool(pick.pick_settling()).is_true()
	var lat: float = pick.center_lat
	pick.pick_stop()
	assert_bool(pick.pick_settling()).is_false()
	assert_bool(pick.pick_dragging()).is_false()
	await _frames(2)
	assert_float(pick.center_lat).is_equal(lat)

## PR-2b (340 §4; 不知火舞 342 bce34a87): HOME-WELCOME's flight — the city's centre held at the given point while the
## camera goes from the globe to the city view, then done; 0 s at once.
func test_the_welcome_flight_holds_the_city_at_its_point() -> void:
	var pick := _push_pick()
	await _frames()
	var c: Array = pick.region.center
	var at := Vector2(180, 300)
	var landed := []
	pick.pick_fly(11.0, 0.2, at, func(): landed.append(1))
	assert_float(pick.zoom).is_equal(pick.PICK_GLOBE_ZOOM)
	assert_bool(pick.pick_flying()).is_true()
	assert_bool(pick.pick_settling()).is_true()
	await get_tree().create_timer(0.1).timeout
	var mid: Vector2 = pick.pick_screen_of(float(c[0]), float(c[1]))
	assert_float(mid.distance_to(at)).is_less(0.5)   # held at its point all the way
	await get_tree().create_timer(0.25).timeout
	assert_array(landed).is_equal([1])
	assert_float(pick.zoom).is_equal_approx(11.0, 1e-6)
	assert_bool(pick.pick_flying()).is_false()
	pick.pick_fly(11.0, 0.0, at, func(): landed.append(2))
	assert_array(landed).is_equal([1, 2])
	assert_float((pick.pick_screen_of(float(c[0]), float(c[1])) as Vector2).distance_to(at)).is_less(0.5)

## Start here on the card's map: the pin page's start glides in to PICK_ZOOM under the tip; the pin stays up meanwhile.
func test_the_pin_page_start_glides_in_from_the_city_view() -> void:
	var pick := _push_pick()
	await _frames()
	pick.pick_fly(11.0, 0.0, Vector2(180, 300))
	var tip := Vector2(180, 378)
	pick.pick_frame(37.7712, -122.4312, tip, 0.2)
	assert_bool(pick.pick_settling()).is_true()
	assert_bool(pick.pick_dragging()).is_true()
	await get_tree().create_timer(0.35).timeout
	assert_bool(pick.pick_settling()).is_false()
	assert_float(pick.zoom).is_equal_approx(pick.PICK_ZOOM, 1e-6)
	var g: Array = pick.pick_geo_at(tip)
	assert_float(g[0]).is_equal_approx(37.7712, 1e-7)
	assert_float(g[1]).is_equal_approx(-122.4312, 1e-7)
	pick.pick_frame(37.76, -122.44, tip)   # 0 s: at once
	assert_bool(pick.pick_settling()).is_false()
	assert_float((pick.pick_geo_at(tip)[0] as float)).is_equal_approx(37.76, 1e-7)
