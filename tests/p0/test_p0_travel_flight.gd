extends GdUnitTestSuite
## q(147), SGODOT-299 (不知火舞 on 299 31c4ceb5 / 62931cdb): every cross-city arrival flies a fixed 3 s — up 0.5 s from
## where the camera is (no jump back to the city left) until both cities are in view, along 2 s, down 0.5 s to the
## overview. A cover takes every touch meanwhile and shows the city ahead and its km rolling; a tap after its first
## 0.5 s or Back lands it. The place chip and the avatar keep the city left until it lands. Every way out (landing,
## skip, Back, the background, the map left, the flight stopped by anything else) takes the cover down and frees the
## chip.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Map := preload("res://scenes/p0/p0_map.gd")
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const SF := "gn-5391959"
const LA := "gn-5368361"
const TOKYO := "gn-1850147"
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

## The map in Los Angeles' server view (here = LA, a return visit), the camera over LA's streets as a bubble's browse
## leaves it, and Fly pressed from San Francisco: the arrival flight about to start.
func _ready_to_arrive(m: Node) -> Dictionary:
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = {home = SF, here = LA, passes = {}, visits = {LA: {n = 1}}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}
	rt.session.view = v
	rt.ui.set_view(v)
	var la := P0Clusters.get_cluster(LA)
	m.center_lat = float(la.lat) + 0.01
	m.center_lng = float(la.lng) + 0.01
	m._set_zoom(13.0)
	m._origin_before = Vector2(37.77, -122.42)
	m._here_before = SF
	return saved

func _arrive(m: Node) -> void:
	m.on_arrival({kind = "arrival", cluster = LA, first = false, trip = 4, km = 559})

func _chip_city(rt: P0Runtime) -> String:
	rt.ui.set_view(rt.session.view)
	return str(rt.ui.hud.data.place.city)

func _cover(m: Node) -> P0TravelCover:
	var found := m.find_children("*", "P0TravelCover", true, false)
	return found[0] if not found.is_empty() else null

func _tap(cover: P0TravelCover) -> void:
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.position = Vector2(180, 500)
		e.pressed = pressed
		(cover.get_node("Shield") as Control).gui_input.emit(e)

func _overview() -> Dictionary:
	var r := P0Clusters.region(LA)
	return CityMapData.city(str(r.get("id", ""))).get("overview", {})

func test_an_arrival_rises_from_where_the_camera_is_and_lands_in_3_s() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var start := Vector2(m.center_lat, m.center_lng)
	_arrive(m)
	# no jump back to San Francisco: the camera is still where it was
	assert_float(Vector2(m.center_lat, m.center_lng).distance_to(start)).is_less(0.001)
	assert_bool(m.travelling()).is_true()
	var cover := _cover(m)
	assert_object(cover).is_not_null()
	assert_str(cover.title.text).is_equal("Los Angeles")
	assert_str(cover.distance.text).is_equal("0 km")
	assert_float(cover.hint.modulate.a).is_equal(0.0)   # no Tap to skip in the first 0.5 s
	assert_str(_chip_city(rt)).is_equal("San Francisco")   # the chip keeps the city left (q(147) ⑤)
	assert_bool(m.hide_self).is_true()   # the avatar leaves with the take-off (v2)
	assert_bool(m.farm_markers.visible).is_false()
	await get_tree().create_timer(1.5).timeout
	assert_bool(m.travelling()).is_true()
	assert_float(m.zoom).is_less(8.0)   # up at the overview of both cities
	assert_float(cover.hint.modulate.a).is_equal(1.0)
	assert_str(cover.distance.text).is_not_equal("0 km")
	var pose: Array = cover.plane_pose()   # the plane on its way, between the two cities' dots
	assert_bool(pose[0] != Vector2.INF).is_true()
	# q(152) ④: the route in the city view, over its fog and under its pins and bubbles; the plane over them
	var route := cover.route_view
	assert_object(route.get_parent()).is_same(m.city_map)
	assert_int(route.z_index).is_less(0)
	assert_int((m.city_map.fog as CanvasItem).z_index).is_less(route.z_index)
	assert_int((cover.plane_view.get_parent() as CanvasLayer).layer).is_equal(P0TravelCover.ROUTE_LAYER)
	assert_bool(cover.from_at != Vector2.INF and cover.to_at != Vector2.INF).is_true()
	await get_tree().create_timer(2.0).timeout   # 3.5 s in: landed
	assert_bool(m.travelling()).is_false()
	assert_bool(is_instance_valid(cover) and cover.is_inside_tree()).is_false()
	await get_tree().process_frame
	assert_bool(is_instance_valid(route)).is_false()   # the adopted route went with the cover
	var o := _overview()
	assert_float(m.center_lat).is_equal_approx(float(o.lat), 1e-6)
	assert_float(m.zoom).is_equal_approx(float(o.zoom), 1e-6)
	assert_str(_chip_city(rt)).is_equal("Los Angeles")
	assert_bool(m.hide_self).is_false()   # it stands in the city ahead, as the chip changes
	assert_bool(m.farm_markers.visible).is_true()
	assert_str(rt.ui.toast_text()).is_equal("Welcome back")
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

func test_a_tap_after_the_first_half_second_lands_at_once_one_before_does_not() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	_arrive(m)
	var cover := _cover(m)
	_tap(cover)   # the press that sent Fly is not a skip
	assert_bool(m.travelling()).is_true()
	await get_tree().create_timer(0.7).timeout
	_tap(cover)
	assert_bool(m.travelling()).is_false()
	assert_float(m.zoom).is_equal_approx(float(_overview().zoom), 1e-6)
	assert_str(_chip_city(rt)).is_equal("Los Angeles")
	assert_str(rt.ui.toast_text()).is_equal("Welcome back")
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

func test_back_lands_the_flight_and_never_leaves_the_map_mid_air() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	_arrive(m)
	assert_bool(m.is_back_navigation_locked()).is_true()   # in the first 0.5 s: held, not left
	assert_bool(m.travelling()).is_true()
	await get_tree().create_timer(0.7).timeout
	assert_bool(m.is_back_navigation_locked()).is_true()
	assert_bool(m.travelling()).is_false()
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

func test_the_background_or_a_stopped_tween_lands_it() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	_arrive(m)
	m.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(m.travelling()).is_false()
	assert_str(_chip_city(rt)).is_equal("Los Angeles")
	assert_bool(rt.ui.get("_hold_here") == "").is_true()
	rt.ui.clear_toast()
	# anything else stopping the flight's tween: the next frame lands it
	m._origin_before = Vector2(37.77, -122.42)
	m._here_before = SF
	_arrive(m)
	(m._trip.tween as Tween).kill()
	m.p0_frame(rt.session.view, 0.016)
	assert_bool(m.travelling()).is_false()
	assert_object(_cover(m)).is_null()
	await get_tree().process_frame   # the cover, off the map at once, is freed at the frame's end
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

func test_leaving_the_map_mid_flight_frees_the_chip() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	_arrive(m)
	assert_str(_chip_city(rt)).is_equal("San Francisco")
	m.get_parent().remove_child(m)
	assert_str(str(rt.ui.get("_hold_here"))).is_empty()
	assert_str(_chip_city(rt)).is_equal("Los Angeles")
	m.free()
	rt.session.view = saved
	rt.ui.set_view(saved)

func test_the_flight_frames_both_cities_at_its_top() -> void:
	var view := Vector2(360, 800)
	var f := P0TravelFlight.plan(34.06, -118.24, 13.0, 0.0, Vector2(37.77, -122.42), 34.05, -118.25, 11.0, 0.0, view)
	var top := f.sample(P0TravelFlight.UP_S)
	assert_float(top.z).is_equal_approx(f.top_zoom(), 1e-6)
	# both ends inside the view at the top zoom
	var span := 512.0 * pow(2.0, top.z)
	for p in [Vector2(37.77, -122.42), Vector2(34.05, -118.25)]:
		var dx: float = (MapGeoMath.mercator_x(p.y) - MapGeoMath.mercator_x(top.y)) * span
		var dy: float = (MapGeoMath.mercator_y(p.x) - MapGeoMath.mercator_y(top.x)) * span
		assert_float(absf(dx)).is_less(view.x * 0.5)
		assert_float(absf(dy)).is_less(view.y * 0.5)
	var start := f.sample(0.0)
	assert_float(start.x).is_equal_approx(34.06, 1e-4)   # it starts where the camera is
	assert_float(start.z).is_equal_approx(13.0, 1e-6)
	var end := f.sample(P0TravelFlight.TOTAL_S)
	assert_float(end.x).is_equal_approx(34.05, 1e-4)
	assert_float(end.z).is_equal_approx(11.0, 1e-6)
	assert_float(P0TravelFlight.TOTAL_S).is_equal(3.0)

## q(147) ⑥ (不知火舞 on 299): a first visit's +10 Energy — its float and the HUD's value — comes with the landing, not
## as the flight takes off; a skip lets it go at once with the welcome.
func test_the_arrivals_energy_waits_for_the_landing() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var before: Dictionary = rt.session.view.duplicate(true)
	before["energy"] = {value = 200, max = 200}
	before["travel"]["here"] = SF
	rt.ui.set_view(before)
	var after := before.duplicate(true)
	after["energy"] = {value = 210, max = 200}
	after["travel"]["here"] = LA
	rt.session.view = after
	rt._on_state(after, [{kind = "energy", delta = 10, reason = "first_visit"},
		{kind = "arrival", cluster = LA, first = true, trip = 4, km = 559}])
	assert_bool(m.travelling()).is_true()
	rt.ui.set_view(after)
	assert_int(int(rt.ui.hud.data.energy)).is_equal(200)   # still what it was in the air
	assert_int(rt.travel_floats.size()).is_equal(1)
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	assert_bool(m.travelling()).is_false()
	rt.ui.set_view(after)
	assert_int(int(rt.ui.hud.data.energy)).is_equal(210)
	assert_array(rt.travel_floats).is_empty()   # let go with the welcome
	assert_str(rt.ui.toast_text()).is_equal("Welcome to Los Angeles · Stamp collected")
	rt.ui.clear_toast()
	rt.ui.close_modal()
	rt.session.view = saved
	rt.ui.set_view(saved)

## Cut short (the map left mid-flight), the held Energy still floats and the HUD follows the view.
func test_leaving_mid_flight_lets_the_held_energy_go() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var before: Dictionary = rt.session.view.duplicate(true)
	before["energy"] = {value = 200, max = 200}
	rt.ui.set_view(before)
	var after := before.duplicate(true)
	after["energy"] = {value = 210, max = 200}
	rt.session.view = after
	rt._on_state(after, [{kind = "energy", delta = 10, reason = "first_visit"},
		{kind = "arrival", cluster = LA, first = true, trip = 4, km = 559}])
	assert_bool(rt.ui.energy_held()).is_true()
	m.get_parent().remove_child(m)
	assert_bool(rt.ui.energy_held()).is_false()
	assert_array(rt.travel_floats).is_empty()
	m.free()
	rt.session.view = saved
	rt.ui.set_view(saved)

## v2 (不知火舞 on 299): the route bows up by a fifth of the two cities' distance; it and the plane fade in over 0.2 s
## at 0.5 s and out over the landing; the plane flies it 0.5–2.5 s, the km rolling with it.
func test_the_route_bows_up_and_fades_with_the_flight() -> void:
	var a := Vector2(0, 100)
	var b := Vector2(200, 100)
	var c := P0TravelCover.arc_control(a, b)
	var mid := P0TravelCover.arc_at(a, c, b, 0.5)
	assert_float(mid.x).is_equal_approx(100.0, 1e-4)
	assert_float(100.0 - mid.y).is_equal_approx(40.0, 1e-4)   # up, a fifth of 200
	var c2 := P0TravelCover.arc_control(b, a)   # the other way: still up
	assert_float(P0TravelCover.arc_at(b, c2, a, 0.5).y).is_equal_approx(60.0, 1e-4)
	assert_float(P0TravelCover.route_alpha(0.4)).is_equal(0.0)
	assert_float(P0TravelCover.route_alpha(0.6)).is_equal_approx(0.5, 1e-4)
	assert_float(P0TravelCover.route_alpha(1.5)).is_equal(1.0)
	assert_float(P0TravelCover.route_alpha(2.75)).is_equal_approx(0.5, 1e-4)
	assert_float(P0TravelCover.route_alpha(3.0)).is_equal(0.0)
	assert_float(P0TravelFlight.plane_progress(0.5)).is_equal(0.0)
	assert_float(P0TravelFlight.plane_progress(2.5)).is_equal(1.0)
	assert_float(P0TravelFlight.plane_progress(1.5)).is_equal_approx(0.75, 1e-4)   # fast, then slowing
	# the plane is i-plane (279 a4ab1287), nose right: drawn at the route's heading as it is
	var cover := P0TravelCover.new()
	assert_str(str(cover._plane.get_meta("ui_source", ""))).ends_with("i-plane.svg")
	cover.free()

## q(152) ② (§11.8.4 steps 5 then 7): a first visit lands with its stamp toast and +10 Energy; 1.5 s later the stamp
## has gone and the arrival card slides up, so the toast never lies over the card. A return only floats Welcome back.
func test_a_first_visit_stamps_first_and_its_card_comes_after() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	P0CityPlaces.accept(TOKYO, load("res://tests/p0/test_p0_city_places.gd").CITY)   # its places read, as on a phone
	m.on_arrival({kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8271})
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))   # down at once
	assert_str(rt.ui.toast_text()).is_equal("Welcome to Tokyo · Stamp collected")
	assert_str(rt.ui.modal_kind).is_not_equal("arrival_card")   # the stamp first
	await get_tree().create_timer(P0Map.STAMP_S * 0.5).timeout
	assert_str(rt.ui.modal_kind).is_not_equal("arrival_card")   # still the stamp's beat
	await get_tree().create_timer(P0Map.STAMP_S * 0.5 + 0.3).timeout
	assert_str(rt.ui.modal_kind).is_equal("arrival_card")   # then the card
	rt.ui.close_modal()
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## Leaving the map while the stamp says itself: no card comes, and nothing errs.
func test_leaving_during_the_stamp_brings_no_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	P0CityPlaces.accept(TOKYO, load("res://tests/p0/test_p0_city_places.gd").CITY)
	m.on_arrival({kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8271})
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	m.get_parent().remove_child(m)
	m.free()
	await get_tree().create_timer(P0Map.STAMP_S + 0.3).timeout
	assert_str(rt.ui.modal_kind).is_not_equal("arrival_card")
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## q(152) ③: far trips frame both ends in the safe area at the top — out as far as it takes, down to z 0.8 (near a
## whole-world view); a pair that does not fit even there stops at 0.8. The camera's centre far out is kept off the
## world's edges as Mapbox keeps it (#327), and the fit allows for that.
func test_a_long_trip_frames_both_ends_in_the_safe_area_down_to_0_8() -> void:
	var view := Vector2(360, 800)
	var safe := Rect2(32, 140, 296, 560)
	var sf := Vector2(37.77, -122.42)
	var tokyo := Vector2(35.68, 139.69)
	var f := P0TravelFlight.plan(sf.x, sf.y, 9.0, 0.0, sf, tokyo.x, tokyo.y, 11.0, 0.0, view, safe)
	assert_float(f.top_zoom()).is_greater_equal(P0TravelFlight.TOP_MIN_ZOOM)
	assert_float(f.top_zoom()).is_less(2.0)   # past the city map's floor
	var a := Vector2(MapGeoMath.mercator_x(sf.y), MapGeoMath.mercator_y(sf.x))
	var b := Vector2(MapGeoMath.mercator_x(tokyo.y), MapGeoMath.mercator_y(tokyo.x))
	var mid := Vector2(a.x + (fposmod(b.x - a.x + 0.5, 1.0) - 0.5) * 0.5, (a.y + b.y) * 0.5)
	assert_bool(P0TravelFlight.frames(a, b, mid, f.top_zoom(), view, safe)).is_true()
	assert_bool(P0TravelFlight.frames(a, b, mid, f.top_zoom() + 0.1, view, safe)).is_false()   # the closest that does
	# San Francisco to Cape Town does not fit even at 0.8: it stops there
	var cape := Vector2(-33.92, 18.42)
	var g := P0TravelFlight.plan(sf.x, sf.y, 9.0, 0.0, sf, cape.x, cape.y, 11.0, 0.0, view, safe)
	assert_float(g.top_zoom()).is_equal_approx(P0TravelFlight.TOP_MIN_ZOOM, 1e-6)
	assert_float(P0TravelFlight.TOTAL_S).is_equal(3.0)   # however far: 3 s

## The map goes past its floor (z 2) only in the air, and lands on the city's overview.
func test_the_map_goes_out_past_its_floor_only_in_the_air() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	assert_float(m._minimum_zoom()).is_equal(2.0)
	m.center_lat = 37.77
	m.center_lng = -122.42
	m._set_zoom(9.0)
	P0CityPlaces.accept(TOKYO, load("res://tests/p0/test_p0_city_places.gd").CITY)
	m.on_arrival({kind = "arrival", cluster = TOKYO, first = false, trip = 6, km = 8271})
	assert_float(m._minimum_zoom()).is_less(2.0)
	await get_tree().create_timer(1.0).timeout   # at the top
	assert_float(m.zoom).is_less(2.0)
	await get_tree().create_timer(2.4).timeout   # landed
	assert_bool(m.travelling()).is_false()
	assert_float(m._minimum_zoom()).is_equal(2.0)
	assert_float(m.zoom).is_greater_equal(2.0)
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## q(152) ①: every way home (the place chip here; the Homestead card's Go home and the home city's bubble come to the
## same _open_my_farm) flies the same 3 s from another city, the pill saying Homestead, landing by the homestead's pin;
## nothing is sent until it lands. At home it opens the farm as ever, no flight.
func test_going_home_from_another_city_flies_first() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)   # in Los Angeles
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(str(cmd.get("type", ""))))
	m.p0_return("farm")   # the place chip's way home
	assert_bool(m.travelling()).is_true()
	assert_str(_cover(m).title.text).is_equal("Homestead")
	assert_array(sent).is_empty()
	assert_str(_chip_city(rt)).is_equal("Los Angeles")   # the city left, until it lands
	m.open_farm = func(): pass   # the farm opens as far as this: the test stays on the map
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))   # down at once
	assert_bool(m.travelling()).is_false()
	assert_float(m.center_lat).is_equal_approx(m.home_lat, 1e-6)
	assert_float(m.zoom).is_equal_approx(P0Map.SHOW_ZOOM, 1e-6)
	assert_array(sent).is_equal(["return_home"])
	assert_str(_chip_city(rt)).is_equal("San Francisco")
	rt.ui.hold_here("")
	rt.ui.clear_toast()
	# at home: the farm opens as ever, no flight
	rt.session.view = saved
	rt.ui.set_view(saved)
	AppRouter._navigation_pending = false
	sent.clear()
	var home_view: Dictionary = saved.duplicate(true)
	home_view["travel"] = {home = SF, here = SF, passes = {}, visits = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}
	rt.session.view = home_view
	AppRouter._navigation_pending = true
	m._enter_farm()   # as _open_my_farm does at home (the router held: it goes no further)
	AppRouter._navigation_pending = false
	assert_bool(m.travelling()).is_false()
	rt.session.view = saved
	rt.ui.set_view(saved)

## 李元芳 on 279 45546042: the flight takes 3 s of real time even when frames are slow (the engine caps a frame's step,
## so a flight stepped by frames stretched — 9.5 s at 400 ms a frame).
class SlowFrames extends Node:
	func _process(_d: float) -> void: OS.delay_msec(400)

func test_the_flight_takes_3_s_of_real_time_on_slow_frames() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var slow := SlowFrames.new()
	add_child(auto_free(slow))
	var t0 := Time.get_ticks_msec()
	_arrive(m)
	while m.travelling() and Time.get_ticks_msec() - t0 < 12000: await get_tree().process_frame
	var took := Time.get_ticks_msec() - t0
	slow.queue_free()
	assert_bool(m.travelling()).is_false()
	assert_int(took).is_less(3000 + 900)   # 3 s, give or take a slow frame or two
	assert_float(m.zoom).is_equal_approx(float(_overview().zoom), 1e-6)   # landed where it lands
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## 周瑜 on #341: a home flight that lands while another way out is under way (or another scene is over the map) does not
## go home — nothing is sent, the farm does not open; and a card open when it takes off is closed first.
func test_a_home_flight_landing_mid_navigation_goes_nowhere() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)   # in Los Angeles
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(str(cmd.get("type", ""))))
	var opened := [0]
	m.open_farm = func(): opened[0] += 1
	m._open_place_card(m.home_entry(), m.place_card(m.home_entry()))
	assert_bool(rt.ui.has_modal()).is_true()
	m.p0_return("farm")
	assert_bool(rt.ui.has_modal()).is_false()   # the card is gone before it flies
	await get_tree().create_timer(0.7).timeout
	AppRouter._navigation_pending = true   # another way out under way as it lands
	_tap(_cover(m))
	AppRouter._navigation_pending = false
	assert_bool(m.travelling()).is_false()
	assert_array(sent).is_empty()
	assert_int(opened[0]).is_equal(0)
	assert_str(_chip_city(rt)).is_equal("Los Angeles")   # still where they were
	rt.session.view = saved
	rt.ui.set_view(saved)

## q(147) ⑤ (不知火舞 on #340): a first visit's city changes on landing, with the chip and the stamp — in the air its
## bubble still says Unexplored and the fog has no hole for it, though the server's reply already counts the visit.
func test_a_first_visits_city_reads_unexplored_until_it_lands() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)   # the server's view: here = LA, LA visited (the arrival's own reply)
	var region := str(P0Clusters.region(LA).id)
	assert_str(str(m.city_bubble(region).text)).is_equal("Visited")
	m.on_arrival({kind = "arrival", cluster = LA, first = true, trip = 4, km = 559})
	assert_str(str(m.city_bubble(region).text)).is_equal("Unexplored")   # in the air
	m._fog_key = ""
	var la := P0Clusters.get_cluster(LA)
	var la_at = m.geo_to_screen(float(la.lat), float(la.lng))
	for h in m.fog_holes():
		if la_at != null: assert_float((h.at as Vector2).distance_to((la_at as Vector2) - m.city_map.global_position)).is_greater(1.0)
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))   # down
	assert_str(str(m.city_bubble(region).text)).is_equal("Visited")   # with the chip and the stamp
	rt.ui.clear_toast()
	await get_tree().create_timer(1.8).timeout   # past the stamp's beat: its card, closed
	rt.ui.close_modal()
	rt.session.view = saved
	rt.ui.set_view(saved)

## q(156): when both ends fit, the camera holds the overview through the 2 s flight and only the plane moves (it reaches
## the city ahead as the flight ends); the 0.5 s landing pans and zooms in, the city ahead sliding to the centre without
## leaving the view. A pair that does not fit even at the floor pans along as before. Still 3 s.
func test_both_ends_in_view_the_camera_holds_the_overview_through_the_flight() -> void:
	var view := Vector2(360, 800)
	var safe := Rect2(32, 140, 296, 560)
	var sf := Vector2(37.77, -122.42)
	var tokyo := Vector2(35.68, 139.69)
	var f := P0TravelFlight.plan(sf.x, sf.y, 9.0, 0.0, sf, tokyo.x, tokyo.y, 11.0, 0.0, view, safe)
	assert_bool(f.holds()).is_true()
	var top := f.sample(P0TravelFlight.UP_S)
	for t in [0.8, 1.5, 2.2, P0TravelFlight.UP_S + P0TravelFlight.FLY_S - 0.01]:
		var at := f.sample(t)
		assert_float(at.x).is_equal_approx(top.x, 1e-6)   # held
		assert_float(at.y).is_equal_approx(top.y, 1e-6)
		assert_float(at.z).is_equal_approx(top.z, 1e-6)
	assert_float(P0TravelFlight.plane_progress(P0TravelFlight.UP_S + P0TravelFlight.FLY_S)).is_equal(1.0)   # there as the flight ends
	# the landing: Tokyo's point on screen moves to the centre, nearer every step, and stays in view
	var b := Vector2(MapGeoMath.mercator_x(tokyo.y), MapGeoMath.mercator_y(tokyo.x))
	var last := INF
	for i in 11:
		var t := P0TravelFlight.UP_S + P0TravelFlight.FLY_S + P0TravelFlight.DOWN_S * i / 10.0
		var at := f.sample(t)
		var c := Vector2(MapGeoMath.mercator_x(at.y), MapGeoMath.mercator_y(at.x))
		var d := Vector2(fposmod(b.x - c.x + 0.5, 1.0) - 0.5, b.y - c.y) * 512.0 * pow(2.0, at.z)
		assert_bool(Rect2(-view * 0.5, view).has_point(d)).override_failure_message("Tokyo off screen at %.2f s" % t).is_true()
		assert_float(d.length()).is_less_equal(last + 0.5)
		last = d.length()
	assert_float(last).is_less(1.0)   # at the centre on landing
	# San Francisco to Cape Town does not fit even at 0.8: it pans along
	var cape := Vector2(-33.92, 18.42)
	var g := P0TravelFlight.plan(sf.x, sf.y, 9.0, 0.0, sf, cape.x, cape.y, 11.0, 0.0, view, safe)
	assert_bool(g.holds()).is_false()
	assert_float(absf(g.sample(1.0).y - g.sample(2.0).y)).is_greater(1e-3)   # its centre moves through the flight
