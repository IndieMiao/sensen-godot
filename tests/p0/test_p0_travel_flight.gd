extends GdUnitTestSuite
## q(147), SGODOT-299 (不知火舞 on 299 31c4ceb5 / 62931cdb): every cross-city arrival flies a fixed 3 s — up 0.5 s from
## where the camera is (no jump back to the city left) until both cities are in view, along 2 s, down 0.5 s to the
## overview. A cover takes every touch meanwhile and shows the city ahead and its km rolling; a tap after its first
## 0.5 s or Back lands it. The place chip and the avatar keep the city left until it lands. Every way out (landing,
## skip, Back, the background, the map left, the flight stopped by anything else) takes the cover down and frees the
## chip.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const SF := "gn-5391959"
const LA := "gn-5368361"

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
	assert_bool(cover.from_at != Vector2.INF and cover.to_at != Vector2.INF).is_true()
	await get_tree().create_timer(2.0).timeout   # 3.5 s in: landed
	assert_bool(m.travelling()).is_false()
	assert_bool(is_instance_valid(cover) and cover.is_inside_tree()).is_false()
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
