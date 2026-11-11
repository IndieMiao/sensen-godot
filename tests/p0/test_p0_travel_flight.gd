extends GdUnitTestSuite
## q(147), SGODOT-299 (不知火舞 on 299 31c4ceb5 / 62931cdb): every cross-city trip flies a fixed 3 s — up 0.5 s from
## where the camera is (no jump back to the city left) until both cities are in view, along 2 s, down 0.5 s to the
## overview. A cover takes every touch meanwhile and shows the city ahead and its km rolling; a tap after its first
## 0.5 s or Back lands it. The place chip and the avatar keep the city left until it lands. Every way out (landing,
## skip, Back, the background, the map left, the flight stopped by anything else) takes the cover down and frees the
## chip. SGODOT-361 (q(261), 不知火舞 on 361 9146d012): it takes off as Fly is pressed; landed before the reply it waits
## under the cover, and a failure, a refusal or no reply in 8 s calls it back to where Fly was pressed.

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
	var s := P0Runtime.ensure().session
	s.transport = Callable()   # the wire as it was: nothing held for the next test
	s.busy = false
	s._inflight = {}
	s._queue = []
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

## The map in San Francisco's server view (here = SF; Los Angeles visited before, so a return), the camera over Los
## Angeles' streets as a bubble's browse leaves it: Fly about to be pressed. here = LA: the player in Los Angeles.
func _ready_to_arrive(m: Node, here := SF) -> Dictionary:
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["save_version"] = 7   # a b1 server's (an older one's reply is maintenance, P0Session.save_too_old)
	v["travel"] = {home = SF, here = here, passes = {}, visits = {LA: {n = 1}}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}
	rt.session.view = v
	rt.ui.set_view(v)
	var la := P0Clusters.get_cluster(LA)
	m.center_lat = float(la.lat) + 0.01
	m.center_lng = float(la.lng) + 0.01
	m._set_zoom(13.0)
	return saved

## Fly for Los Angeles, its reply in at once (the reply before the landing, as on a phone).
func _arrive(m: Node) -> void:
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559})

var _wire: Array = []   # the travel commands sent and not answered yet: the test answers them

## Requests held on the wire: travel waits for _answer / _drop; a city's places read fails (none in these tests).
## A read the session sent over the real wire before (its 30 s refresh, between tests the wire is the real one) is
## dropped first: failing later it would take the travel queued behind it down with it, as a network failure does.
func _hold_wire(rt: P0Runtime) -> void:
	var s := rt.session
	for h in s.get_children():
		if h is HTTPRequest and h.request_completed.get_connections().any(func(c): return c.callable.get_method() == "_on_done"):
			h.cancel_request()
			h.queue_free()
	s.busy = false
	s._inflight = {}
	s._queue = []
	_wire.clear()
	rt.session.transport = func(_method: int, _path: String, _body: Dictionary, cmd: Dictionary) -> void:
		if str(cmd.get("type", "")) == "travel": _wire.append(cmd)
		elif str(cmd.get("type", "")) == "city": P0CityPlaces.fail.call_deferred(str(cmd.cluster))

## Fly pressed for ev.cluster from where the view says, its `travel` held; with `answer` the server's reply at once —
## `view` (else the view moved there, the city visited) and `events` (else the arrival alone).
func _fly(m: Node, ev: Dictionary, events := [], view := {}, answer := true) -> void:
	var rt: P0Runtime = m.rt
	_hold_wire(rt)
	m._take_off(str(ev.cluster), int(ev.get("km", 0)))
	if answer: _answer(rt, view if not view.is_empty() else _moved(rt.session.view, str(ev.cluster)), [ev] if events.is_empty() else events)

## The server's view after a travel there: here = it, visited once more, its Day Pass.
static func _moved(v: Dictionary, cluster: String) -> Dictionary:
	var w := v.duplicate(true)
	var t: Dictionary = w.get_or_add("travel", {})
	t["here"] = cluster
	var visits: Dictionary = t.get_or_add("visits", {})
	visits[cluster] = {n = int((visits.get(cluster, {}) as Dictionary).get("n", 0)) + 1}
	(t.get_or_add("passes", {}) as Dictionary)[cluster] = {kind = "day", from = 1.0, until = float(w.get("now", 0.0)) + 24 * 3_600_000.0}
	return w

## The held travel's reply, through the session as from the server: taken with `events`, or refused with `code`.
func _answer(rt: P0Runtime, view: Dictionary, events := [], code := "") -> void:
	var body := {"ok": code == "", "state": view.merged({"save_version": 7})}   # a b1 server's (P0Session.save_too_old)
	if code == "": body["events"] = events
	else: body["code"] = code
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify(body).to_utf8_buffer(), _wire.pop_front())

## The held travel never got an answer (the network).
func _drop(rt: P0Runtime) -> void:
	rt._net_fails = 0   # one failure, not the suite's background reads' too (they count toward Offline)
	rt.ui.offline = false
	if is_instance_valid(rt.ui._sys): rt.ui._sys.visible = false
	rt.session._finish(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray(), _wire.pop_front())

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
	assert_str(rt.ui.toast_text()).is_equal("Welcome back · Day Pass 24h")
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## 哪吒 on #335: the map's view keeps its fog at CityMapView.FOG_Z from the start, under everything it draws; a flight's
## cover only puts its own route in between and leaves the fog as it is.
func test_the_fog_sits_at_its_own_z_before_any_flight() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var fog := m.city_map.fog as CanvasItem
	assert_int(fog.z_index).is_equal(CityMapView.FOG_Z)
	assert_int(fog.z_index).is_less(P0TravelCover.ROUTE_Z)
	for c in m.city_map.get_children():
		if c != fog and c is CanvasItem: assert_int((c as CanvasItem).z_index).is_greater(fog.z_index)
	var cover := P0TravelCover.new()
	m.add_child(cover)
	cover.adopt_route(m.city_map)
	assert_int(fog.z_index).is_equal(CityMapView.FOG_Z)
	cover.queue_free()

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
	assert_str(rt.ui.toast_text()).is_equal("Welcome back · Day Pass 24h")
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
	rt.session.view = before
	rt.ui.set_view(before)
	var after := _moved(before, LA)
	after["energy"] = {value = 210, max = 200}
	var arrival := {kind = "arrival", cluster = LA, first = true, trip = 4, km = 559}
	_fly(m, arrival, [{kind = "energy", delta = 10, reason = "first_visit"}, arrival], after)
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
	rt.session.view = before
	rt.ui.set_view(before)
	var after := _moved(before, LA)
	after["energy"] = {value = 210, max = 200}
	var arrival := {kind = "arrival", cluster = LA, first = true, trip = 4, km = 559}
	_fly(m, arrival, [{kind = "energy", delta = 10, reason = "first_visit"}, arrival], after)
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
	_fly(m, {kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8271})
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

## 哪吒 on #338: another flight setting off during the stamp's beat — here a return to Los Angeles, landed at once —
## takes the first visit's card with it: Tokyo's card never comes up over Los Angeles.
func test_another_flight_during_the_stamp_takes_its_card_away() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	P0CityPlaces.accept(TOKYO, load("res://tests/p0/test_p0_city_places.gd").CITY)
	_fly(m, {kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8271})
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))   # Tokyo: its stamp's 1.5 s begin
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 6, km = 8800})
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))   # down in Los Angeles inside Tokyo's beat
	assert_bool(m.travelling()).is_false()
	await get_tree().create_timer(P0Map.STAMP_S).timeout   # past Tokyo's beat
	assert_str(rt.ui.modal_kind).is_not_equal("arrival_card")
	rt.ui.close_modal()   # one left open would sit over the next test
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
	_fly(m, {kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8271})
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
	_fly(m, {kind = "arrival", cluster = TOKYO, first = false, trip = 6, km = 8271})
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
	var saved := _ready_to_arrive(m, LA)   # in Los Angeles
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(str(cmd.get("type", ""))))
	m.p0_return("farm")   # the place chip's way home
	assert_bool(m.travelling()).is_true()
	assert_str(_cover(m).title.text).is_equal("Home")
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
	var saved := _ready_to_arrive(m, LA)   # in Los Angeles
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
	var saved := _ready_to_arrive(m)
	var first: Dictionary = rt.session.view.duplicate(true)   # the session's view is read-only (SGODOT-260 Q3): a changed copy in its place
	first.travel.visits = {}   # Los Angeles a first visit
	rt.session.view = first
	var region := str(P0Clusters.region(LA).id)
	_fly(m, {kind = "arrival", cluster = LA, first = true, trip = 4, km = 559})   # the reply's view counts the visit
	assert_bool(rt.session.view.travel.visits.has(LA)).is_true()
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

## 周瑜 on #345: far out at a high latitude the map keeps the world's top edge off the screen and moves the centre
## toward the equator; the flight held and landed from the centre it asked for, not the one shown, so the city ahead
## did not come in from where the overview showed it. Every sample is now a centre the map shows as asked, and the
## landing runs from the overview as shown: the city ahead's offset on screen shrinks from there to nothing.
func test_a_high_latitude_flight_lands_from_the_overview_the_map_shows() -> void:
	var view := Vector2(360, 800)
	var safe := Rect2(32, 140, 296, 560)
	var reykjavik := Vector2(64.15, -21.94)
	var vancouver := Vector2(49.28, -123.12)
	var f := P0TravelFlight.plan(reykjavik.x, reykjavik.y, 9.0, 0.0, reykjavik, vancouver.x, vancouver.y, 11.0, 0.0, view, safe)
	assert_bool(f.holds()).is_true()
	var a := Vector2(MapGeoMath.mercator_x(reykjavik.y), MapGeoMath.mercator_y(reykjavik.x))
	var b := Vector2(MapGeoMath.mercator_x(vancouver.y), MapGeoMath.mercator_y(vancouver.x))
	var mid := Vector2(a.x + (fposmod(b.x - a.x + 0.5, 1.0) - 0.5) * 0.5, (a.y + b.y) * 0.5)
	var held := P0TravelFlight.kept(mid, f.top_zoom(), view)
	assert_float(held.y - mid.y).is_greater(0.01)   # the case: the map moves this overview's centre
	var merc := func(at: Vector4) -> Vector2: return Vector2(MapGeoMath.mercator_x(at.y), MapGeoMath.mercator_y(at.x))
	for i in 91:
		var t := P0TravelFlight.TOTAL_S * i / 90.0
		var at := f.sample(t)
		var c: Vector2 = merc.call(at)
		assert_float(absf(P0TravelFlight.kept(c, at.z, view).y - c.y)).override_failure_message("moved at %.2f s" % t).is_less(1e-6)
	var top: Vector2 = merc.call(f.sample(P0TravelFlight.UP_S + 0.5))
	assert_float(absf(top.y - held.y)).is_less(1e-5)   # held where the map shows it
	var start := (b - held) * 512.0 * pow(2.0, f.top_zoom())   # Vancouver on screen at the top
	for i in 11:
		var s := i / 10.0
		var at := f.sample(P0TravelFlight.UP_S + P0TravelFlight.FLY_S + P0TravelFlight.DOWN_S * s)
		var c: Vector2 = merc.call(at)
		var d := Vector2(fposmod(b.x - c.x + 0.5, 1.0) - 0.5, b.y - c.y) * 512.0 * pow(2.0, at.z)
		var eased := s * s * (3.0 - 2.0 * s)
		assert_float(d.distance_to(start * (1.0 - eased))).override_failure_message("off by %.1f px at %.1f" % [d.distance_to(start * (1.0 - eased)), s]).is_less(1.0)

## q(157) ② (不知火舞 on 299): both cities' bubbles stand whole at the top — 8 in from the screen's sides, over the safe
## area's bottom — so a pair whose bubbles reach out goes further out than its dots alone need. San Francisco – Tokyo
## fits only at the floor (z 0.8) with San Francisco's bubble: the search reaches the floor itself (周瑜 / 亚瑟: steps
## summed as floats stopped at 0.85 from z 11, and such a pair panned instead of holding).
func test_the_top_frames_both_bubbles_whole_down_to_the_floor_itself() -> void:
	var view := Vector2(360, 800)
	var safe := Rect2(32, 160, 296, 412)
	var within := Rect2(8, 160, 344, 412)
	var sf := Vector2(37.77, -122.42)
	var tokyo := Vector2(35.68, 139.69)
	var bubbles := [[sf, Rect2(-49, 6, 98, 40)], [tokyo, Rect2(-35, 6, 70, 40)]]
	var bare := P0TravelFlight.plan(sf.x, sf.y, 11.0, 0.0, sf, tokyo.x, tokyo.y, 11.0, 0.0, view, safe)
	assert_bool(bare.holds()).is_true()
	assert_float(bare.top_zoom()).is_greater(0.9)   # the dots alone
	var f := P0TravelFlight.plan(sf.x, sf.y, 11.0, 0.0, sf, tokyo.x, tokyo.y, 11.0, 0.0, view, safe, bubbles, within)
	assert_bool(f.holds()).is_true()
	assert_float(f.top_zoom()).is_equal_approx(P0TravelFlight.TOP_MIN_ZOOM, 1e-6)
	var top := f.sample(P0TravelFlight.UP_S + 1.0)
	var c := Vector2(MapGeoMath.mercator_x(top.y), MapGeoMath.mercator_y(top.x))
	var scale := 512.0 * pow(2.0, top.z)
	for b in bubbles:
		var p := Vector2(MapGeoMath.mercator_x((b[0] as Vector2).y), MapGeoMath.mercator_y((b[0] as Vector2).x))
		var at := view * 0.5 + Vector2(fposmod(p.x - c.x + 0.5, 1.0) - 0.5, p.y - c.y) * scale
		var r: Rect2 = b[1]
		assert_bool(within.encloses(Rect2(at + r.position, r.size))).override_failure_message("%s's bubble cut" % b[0]).is_true()
		assert_bool(safe.has_point(at)).is_true()

const SALINAS := "gn-5391295"

## q(157) (李元芳 on 279 eaf31aca): San Francisco → Salinas, due south, held its overview with Salinas under the home key
## and its bubble not drawn. The safe area's bottom is 8 over the home key now; at the top both ends stand over it and
## both cities' bubbles show whole, clear of the right-hand keys.
func test_a_trip_south_frames_both_ends_and_their_bubbles_over_the_keys() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = {home = SF, here = SF, passes = {}, visits = {SALINAS: {n = 1}}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}
	rt.session.view = v
	rt.ui.set_view(v)
	m.center_lat = 37.77
	m.center_lng = -122.42
	m._set_zoom(11.0)
	_fly(m, {kind = "arrival", cluster = SALINAS, first = false, trip = 2, km = 138})
	var home_key: Rect2 = m.city_map.home_key.get_global_rect()
	var keys := home_key.merge(m.city_map.recenter.get_global_rect())
	assert_float(m.safe_bottom()).is_less_equal(home_key.position.y - 8.0)
	assert_bool((m._trip.plan as P0TravelFlight).holds()).is_true()
	m._trip.start_us = Time.get_ticks_usec() - 1_500_000   # 1.5 s in: the top
	m._travel_at(0.0)
	m.city_map._update_bubbles()
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	for cluster in [SF, SALINAS]:
		var id := str(P0Clusters.region(cluster).id)
		var node: Control = m.city_map.bubbles[id].node
		assert_bool(node.visible).override_failure_message("%s's bubble not drawn" % id).is_true()
		var r := node.get_global_rect()
		assert_float(r.position.x).is_greater_equal(8.0 - 0.5)
		assert_float(r.end.x).is_less_equal(vp.x - 8.0 + 0.5)
		assert_float(r.end.y).is_less_equal(m.safe_bottom() + 0.5)
		assert_bool(r.intersects(keys)).is_false()
	for p in [Vector2(37.77, -122.42), Vector2(36.67774, -121.6555)]:
		var at = m.geo_to_screen(p.x, p.y)
		assert_float((at as Vector2).y).is_less(m.safe_bottom())
	m._travel_land()
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame   # the cover goes

## q(157) (不知火舞 on 299): in the air the city left counts as where the player is and the city ahead as the one just
## opened (q(153)), so neither's bubble gives way — Los Angeles, only visited, too; on landing they read as ever.
func test_in_the_air_neither_ends_bubble_gives_way() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = {home = SF, here = LA, passes = {}, visits = {LA: {n = 1}, TOKYO: {n = 1}}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}
	rt.session.view = v
	rt.ui.set_view(v)
	_fly(m, {kind = "arrival", cluster = TOKYO, first = false, trip = 4, km = 8800})
	var keeps := func(cluster: String) -> bool:
		m.city_regions()
		return bool(m.city_bubble(str(P0Clusters.region(cluster).id)).keeps)
	assert_bool(keeps.call(LA)).is_true()
	assert_bool(keeps.call(TOKYO)).is_true()
	m._travel_land()
	assert_bool(keeps.call(LA)).is_false()   # visited again
	assert_bool(keeps.call(TOKYO)).is_true()   # where the player is
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame   # the cover goes

const RENO := "gn-5511077"

## 周瑜 on #348: a first visit's city ahead reads Unexplored all through the flight (q(147) ⑤), so its bubble is
## measured so for the top's fit too — measured as Visited (narrower), a short-named city near the side could have its
## wider Unexplored bubble run past the 8 px margin. San Francisco → Reno, a first visit: the bubble the flight measured
## reads Unexplored and is the one it shows at the top, whole.
func test_a_first_visits_city_ahead_is_measured_as_it_shows_unexplored() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = {home = SF, here = SF, passes = {}, visits = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}
	rt.session.view = v
	rt.ui.set_view(v)
	m.center_lat = 37.77
	m.center_lng = -122.42
	m._set_zoom(11.0)
	_fly(m, {kind = "arrival", cluster = RENO, first = true, trip = 2, km = 300})
	var b: Dictionary = m.city_map.bubbles[str(P0Clusters.region(RENO).id)]
	assert_str(b.count.text).is_equal("Unexplored")   # as the flight measured it, before any frame
	var measured: Vector2 = (b.node as Control).size
	m._trip.start_us = Time.get_ticks_usec() - 1_500_000   # 1.5 s in: the top
	m._travel_at(0.0)
	m.city_map._update_bubbles()
	assert_str(b.count.text).is_equal("Unexplored")
	assert_bool((b.node as Control).visible).is_true()
	assert_vector((b.node as Control).size).is_equal(measured)   # the one it shows
	var r := (b.node as Control).get_global_rect()
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	assert_float(r.position.x).is_greater_equal(8.0 - 0.5)
	assert_float(r.end.x).override_failure_message("Reno's bubble ends at %.1f of %.0f" % [r.end.x, vp.x]).is_less_equal(vp.x - 8.0 + 0.5)
	assert_float(r.end.y).is_less_equal(m.safe_bottom() + 0.5)
	m._travel_land()
	rt.ui.clear_toast()
	await get_tree().create_timer(1.8).timeout   # past the stamp's beat: its card, closed
	rt.ui.close_modal()
	rt.session.view = saved
	rt.ui.set_view(saved)

func test_an_arrival_in_a_city_the_table_does_not_have_lets_go() -> void:
	# q(189) / 亚瑟 on #387: a closed country's city (Pyongyang) is not in the client's table; an arrival there holds no
	# flight and draws no cover (an arrival never takes off by itself now: Fly does, SGODOT-361)
	var m := _map()
	await get_tree().process_frame
	m.on_arrival({kind = "arrival", cluster = "gn-1871859", first = true, trip = 6, km = 9000})
	assert_object(_cover(m)).is_null()
	assert_bool(m.travelling()).is_false()


# ---------------------------------------------------------------- SGODOT-361: Fly takes off, the reply lands it (q(261))
## Where the camera was as Fly was pressed, to compare a call-back with.
func _camera(m: Node) -> Array:
	return [m.center_lat, m.center_lng, m.zoom, m.city_bearing, str(m.region.get("id", ""))]

func _assert_camera(m: Node, was: Array) -> void:
	assert_float(m.center_lat).is_equal_approx(float(was[0]), 1e-9)
	assert_float(m.center_lng).is_equal_approx(float(was[1]), 1e-9)
	assert_float(m.zoom).is_equal_approx(float(was[2]), 1e-6)
	assert_float(m.city_bearing).is_equal_approx(float(was[3]), 1e-6)
	assert_str(str(m.region.get("id", ""))).is_equal(str(was[4]))

## Called back (9146d012 ②): in the same frame the cover is gone and the avatar back, the chip and Energy free.
func _assert_called_back(m: Node, was: Array) -> void:
	assert_bool(m.travelling()).is_false()
	assert_object(_cover(m)).is_null()
	_assert_camera(m, was)
	assert_bool(m.hide_self).is_false()
	assert_bool(m.farm_markers.visible).is_true()
	assert_str(str(m.rt.ui.get("_hold_here"))).is_empty()
	assert_bool(m.rt.ui.energy_held()).is_false()

func test_fly_takes_off_before_any_reply_and_the_reply_in_the_air_lands_with_it() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	assert_bool(m.travelling()).is_true()   # up at once: nothing waits for the server
	assert_object(_cover(m)).is_not_null()
	assert_array(_wire.map(func(c): return [str(c.type), str(c.to)])).is_equal([["travel", LA]])
	assert_str(_cover(m).distance.text).is_equal("0 km")   # the card's trip: rolls to 559 km
	await get_tree().create_timer(1.0).timeout
	_answer(rt, _moved(rt.session.view, LA), [{kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}])
	assert_bool(m.travelling()).is_true()   # in the air still: it lands on time
	assert_str(_chip_city(rt)).is_equal("San Francisco")
	await get_tree().create_timer(2.3).timeout
	assert_bool(m.travelling()).is_false()
	assert_str(_chip_city(rt)).is_equal("Los Angeles")
	assert_str(rt.ui.toast_text()).is_equal("Welcome back · Day Pass 24h")
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## ① (9146d012): down with the reply still out it waits under the cover — no Tap to skip, Back and taps do nothing, the
## chip, avatar and Energy as in the air; 1.5 s down the hint line says Taking longer than usual…; the reply lands it.
## 不知火舞 60a1508e ①: while the cover is up the chip never follows the server, a read that brings here = LA first too.
func test_landed_before_the_reply_it_waits_under_the_cover_until_it_comes() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	_fly(m, {kind = "arrival", cluster = LA, first = true, trip = 4, km = 559}, [], {}, false)
	var cover := _cover(m)
	await get_tree().create_timer(0.7).timeout
	_tap(cover)   # skipped: down, and waiting
	assert_bool(m.travelling()).is_true()
	assert_bool(is_instance_valid(cover) and cover.is_inside_tree()).is_true()
	assert_float(m.zoom).is_equal_approx(float(_overview().zoom), 1e-6)   # the camera at the overview
	assert_str(cover.distance.text).is_equal("559 km")
	assert_float(cover.hint.modulate.a).is_equal(0.0)   # no Tap to skip
	assert_bool(cover.skippable()).is_false()
	_tap(cover)
	assert_bool(m.is_back_navigation_locked()).is_true()   # Back is held and does nothing
	assert_bool(m.travelling()).is_true()
	assert_bool(m.hide_self).is_true()
	# a read before the travel's reply already says Los Angeles: the chip keeps San Francisco while the cover is up
	var there := _moved(rt.session.view, LA)
	rt.session.view = there
	rt.ui.set_view(there)
	assert_str(_chip_city(rt)).is_equal("San Francisco")
	m._trip.wait_us = Time.get_ticks_usec() - 1_400_000
	m._travel_watch(0.0)
	assert_float(cover.hint.modulate.a).is_equal(0.0)   # not yet 1.5 s
	m._trip.wait_us = Time.get_ticks_usec() - 1_600_000
	m._travel_watch(0.0)
	assert_str(cover.hint.text).is_equal("Taking longer than usual…")
	assert_float(cover.hint.modulate.a).is_equal(1.0)
	assert_bool(m.travelling()).is_true()
	assert_str(_chip_city(rt)).is_equal("San Francisco")
	_answer(rt, there, [{kind = "arrival", cluster = LA, first = true, trip = 4, km = 559}])
	assert_bool(m.travelling()).is_false()   # down in the same frame, with the welcome
	assert_str(_chip_city(rt)).is_equal("Los Angeles")
	assert_bool(m.hide_self).is_false()
	assert_str(rt.ui.toast_text()).is_equal("Welcome to Los Angeles · Stamp collected")
	await get_tree().create_timer(P0Map.STAMP_S + 0.3).timeout
	rt.ui.close_modal()
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## ② (9146d012): a network failure, in the air or landed waiting, calls it back in the same frame to where Fly was
## pressed — place, zoom, bearing and the city — with the cover, avatar, chip and Energy as before it; SYS-CMD-FAIL says
## so (q(75)), no toast, no stamp, no card.
func test_a_failed_travel_calls_the_flight_back_in_the_same_frame() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var was := _camera(m)
	_fly(m, {kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8271}, [], {}, false)
	await get_tree().create_timer(1.0).timeout   # in the air
	_drop(rt)
	_assert_called_back(m, was)
	assert_str(rt.ui.sys_text()).is_equal("Didn't go through · try again")
	assert_str(rt.ui.toast_text()).is_empty()
	assert_str(_chip_city(rt)).is_equal("San Francisco")
	await get_tree().process_frame
	# landed waiting, the same
	_fly(m, {kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8271}, [], {}, false)
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	assert_bool(m.travelling()).is_true()
	_drop(rt)
	_assert_called_back(m, was)
	await get_tree().create_timer(P0Map.STAMP_S + 0.3).timeout
	assert_str(rt.ui.modal_kind).is_not_equal("arrival_card")
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## 奕星 on q(261) ①: 8 s counted from Fly by the map itself, not the session's timeout (a travel queued behind another
## command has its 8 s on the wire start later). ② a success that comes after the call-back flies nowhere; 不知火舞
## 60a1508e ②: with the cover gone the chip follows the server — the server did move the player, so it says Los Angeles.
func test_no_reply_8_s_from_fly_calls_it_back_and_a_late_reply_flies_nowhere() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var was := _camera(m)
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	m._trip.start_us = Time.get_ticks_usec() - 7_900_000
	m._travel_watch(0.0)
	assert_bool(m.travelling()).is_true()
	m._trip.start_us = Time.get_ticks_usec() - 8_100_000   # 8 s since Fly, in the air or down: called back
	m._travel_watch(0.0)
	_assert_called_back(m, was)
	assert_bool(rt.session.busy).is_true()   # the request is still out: the map did not wait for its timeout
	_answer(rt, _moved(rt.session.view, LA), [{kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}])
	assert_bool(m.travelling()).is_false()   # no take-off now
	assert_object(_cover(m)).is_null()
	_assert_camera(m, was)
	assert_str(rt.ui.toast_text()).is_empty()   # no welcome either
	assert_str(_chip_city(rt)).is_equal("Los Angeles")   # the chip follows the server again
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame   # the cover, off the map at once, is freed at the frame's end

## stale_state goes again once, quietly (the flight flies on); a second one is a failure: called back with SYS-CMD-FAIL.
func test_stale_state_sends_travel_again_once_then_calls_it_back() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var was := _camera(m)
	if is_instance_valid(rt.ui._sys): rt.ui._sys.visible = false   # an earlier test's line still up
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	_answer(rt, rt.session.view, [], "stale_state")
	assert_bool(m.travelling()).is_true()
	assert_array(_wire.map(func(c): return str(c.to))).is_equal([LA])   # sent again
	assert_str(rt.ui.sys_text()).is_not_equal("Didn't go through · try again")   # quietly
	rt.ui.offline = false   # the suite's background reads may have put Offline up: the line below is this one's
	_answer(rt, rt.session.view, [], "stale_state")
	_assert_called_back(m, was)
	assert_array(_wire).is_empty()   # not a third time
	assert_str(rt.ui.sys_text()).is_equal("Didn't go through · try again")
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame   # the cover, off the map at once, is freed at the frame's end

## A refusal (the client's city table not the server's): called back, the runtime's toast as for any refusal.
func test_a_refused_travel_calls_it_back_with_the_runtimes_toast() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var was := _camera(m)
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	_answer(rt, rt.session.view, [], "unknown_city")
	_assert_called_back(m, was)
	assert_str(rt.ui.toast_text()).is_equal("Can't do that (unknown_city)")
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame   # the cover, off the map at once, is freed at the frame's end

## ③ (9146d012): taken with no arrival (already there with a pass): it lands as a return — Welcome back only.
func test_taken_without_an_arrival_it_lands_as_a_return() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	assert_bool(m.travelling()).is_true()
	_answer(rt, _moved(rt.session.view, LA), [])
	assert_bool(m.travelling()).is_false()
	assert_str(_chip_city(rt)).is_equal("Los Angeles")
	assert_str(rt.ui.toast_text()).is_equal("Welcome back · Day Pass 24h")
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## ④ (q(261)): under the cover the HUD's coins stay what they were too, and follow the view once it is down.
func test_under_the_cover_the_huds_coins_hold_too() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var before: Dictionary = rt.session.view.duplicate(true)
	before["coins"] = 230
	before["energy"] = {value = 142, max = 210}
	rt.session.view = before
	rt.ui.set_view(before)
	var after := _moved(before, LA)
	after["coins"] = 110   # what a fare would take (q(256) / (257) bring it): the HUD waits for the landing
	after["energy"] = {value = 112, max = 210}
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], after)
	rt.ui.set_view(after)
	assert_int(int(rt.ui.hud.data.coins)).is_equal(230)
	assert_int(int(rt.ui.hud.data.energy)).is_equal(142)
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	rt.ui.set_view(after)
	assert_int(int(rt.ui.hud.data.coins)).is_equal(110)
	assert_int(int(rt.ui.hud.data.energy)).is_equal(112)
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## ⑦ (q(261)): a toast said under the cover waits until it is down and the welcome has said itself; SYS lines do not.
func test_a_toast_under_the_cover_waits_for_the_welcome() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559})
	rt.ui.toast("Somewhere else")
	assert_str(rt.ui.toast_text()).is_empty()   # held
	rt.ui.show_sys(UiSysBanner.Kind.CMD_FAIL, "A line", 3.0)
	assert_str(rt.ui.sys_text()).is_equal("A line")   # not held
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	assert_str(rt.ui.toast_text()).is_equal("Welcome back · Day Pass 24h")   # the welcome first
	await get_tree().create_timer(ToastLayer.duration_ms("Welcome back · Day Pass 24h") / 1000.0 + 0.2).timeout
	assert_str(rt.ui.toast_text()).is_equal("Somewhere else")   # then what waited
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)

## ⑤ (q(261)): maintenance (503) or update_required (426) in the air calls it back too, their whole-screen card over it.
func test_maintenance_in_the_air_calls_it_back() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var was := _camera(m)
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	var body := JSON.stringify({code = "maintenance", back_at = 0}).to_utf8_buffer()
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, 503, body, _wire.pop_front())
	_assert_called_back(m, was)
	rt._unblock()
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame   # the cover, off the map at once, is freed at the frame's end

## 周瑜 on #560: called back after 8 s, then off to another city at once — the first travel's late arrival comes in the
## new flight's air and leaves what it holds alone (the chip, Energy and coins); the new one lands with its own reply.
func test_a_late_arrival_leaves_another_flights_hold_alone() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var held: Dictionary = rt.session.view.duplicate(true)   # the session's view is read-only (SGODOT-260 Q3): a changed copy in its place
	held["energy"] = {value = 142, max = 210}
	rt.session.view = held
	rt.ui.set_view(held)
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	m._trip.start_us = Time.get_ticks_usec() - 8_100_000
	m._travel_watch(0.0)   # called back, Los Angeles' travel still out
	assert_bool(m.travelling()).is_false()
	var la_travel: Dictionary = _wire.pop_front()
	m._take_off(TOKYO, 8271)   # off to Tokyo at once: its travel queues behind Los Angeles'
	assert_bool(m.travelling()).is_true()
	assert_str(_chip_city(rt)).is_equal("San Francisco")
	var late := _moved(rt.session.view, LA)
	late["energy"] = {value = 152, max = 210}
	var body := JSON.stringify({ok = true, state = late,
		events = [{kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}]}).to_utf8_buffer()
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, 200, body, la_travel)   # Los Angeles' late reply, Tokyo in the air
	assert_bool(m.travelling()).is_true()
	assert_str(str(rt.ui.get("_hold_here"))).is_equal(SF)   # still held
	assert_str(_chip_city(rt)).is_equal("San Francisco")
	assert_bool(rt.ui.energy_held()).is_true()
	assert_int(int(rt.ui.hud.data.energy)).is_equal(142)   # the HUD as when Tokyo's flight took off
	assert_array(_wire.map(func(c): return str(c.to))).is_equal([TOKYO])   # Tokyo's travel now on the wire
	_answer(rt, _moved(rt.session.view, TOKYO), [{kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8271}])
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	assert_bool(m.travelling()).is_false()
	assert_str(_chip_city(rt)).is_equal("Tokyo")
	assert_str(rt.ui.toast_text()).is_equal("Welcome to Tokyo · Stamp collected")
	await get_tree().create_timer(P0Map.STAMP_S + 0.3).timeout
	rt.ui.close_modal()
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame

## q(261) ④ / q(256) (SGODOT-367, 不知火舞 on 367 ec5f2daa ⑤): the fare's floats wait for the cover too and come in
## the reply's order with the first visit's +10 — `−30 Energy`, `−120 coins`, `+10 Energy` — as one group on landing.
func test_the_fares_floats_come_with_the_landing_in_order() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var first: Dictionary = rt.session.view.duplicate(true)   # the session's view is read-only (SGODOT-260 Q3): a changed copy in its place
	first.travel.visits = {}
	rt.session.view = first
	var arrival := {kind = "arrival", cluster = LA, first = true, trip = 4, km = 559, paid = {energy = 30, coins = 120}, renewed = true}
	_fly(m, arrival, [{kind = "energy", delta = -30, reason = "travel"}, {kind = "coins", delta = -120, reason = "travel"},
		{kind = "energy", delta = 10, reason = "first_visit"}, arrival])
	assert_array(rt.travel_floats.map(func(p): return [str(p.kind), int(p.amount)])).is_equal([["energy", -30], ["coins", -120], ["energy_bonus", 10]])
	# three lines, from the bottom: −30 Energy, −120 coins, +10 Energy (never one `−20 Energy`)
	var lines: Array = rt.ui.float_lines(rt.travel_floats, Vector2(180, 400))
	assert_int(lines.size()).is_equal(3)
	assert_array(lines.map(func(f): return str((f as UiFloatText).text))).is_equal(["−30 Energy", "−120 coins", "+10 Energy"])
	for f in lines: (f as Node).queue_free()
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	assert_array(rt.travel_floats).is_empty()   # let go with the landing
	await get_tree().create_timer(P0Map.STAMP_S + 0.3).timeout
	rt.ui.close_modal()
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame

## q(261) ⑤: a fare the server would not take (another device spent the coins) calls the flight back and says what a
## tap on Fly says (q(318): the fare, the coins' with the 40 the wallet keeps; Info, not the runtime's fallback), and
## opens no Energy card.
func test_a_refused_fare_calls_it_back_and_says_the_gap() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)
	var was := _camera(m)
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	var body := JSON.stringify({ok = false, code = "not_enough_coins", detail = {need = 10, have = 150, cost = 120, floor = 40},
		state = rt.session.view}).to_utf8_buffer()
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, 200, body, _wire.pop_front())
	_assert_called_back(m, was)
	assert_str(rt.ui.toast_text()).is_equal("Need 120 coins\nkeep 40 after the trip")   # two lines at its ` · `
	assert_int(rt.ui._toasts.current_severity()).is_equal(ToastLayer.Severity.INFO)
	assert_str(rt.ui.modal_kind).is_not_equal("energy_card")
	rt.ui.clear_toast()
	_fly(m, {kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}, [], {}, false)
	body = JSON.stringify({ok = false, code = "not_enough_energy", detail = {need = 11, have = 19, cost = 30}, state = rt.session.view}).to_utf8_buffer()
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, 200, body, _wire.pop_front())
	assert_bool(m.travelling()).is_false()
	assert_str(rt.ui.toast_text()).is_equal("Need 30 Energy")   # the fare
	assert_int(rt.ui._toasts.current_severity()).is_equal(ToastLayer.Severity.INFO)
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame

const FARES := {energy = [0, 10, 20, 30, 40, 50, 60], coins = [0, 20, 60, 120, 200, 300, 500]}

## q(318) (李元芳 0.3.8; the user's bot 740 / 741): Fly on the travel card is always lit. Short of the fare a tap keeps
## the card and says so in an Info toast 8 over the card's top edge, not over its rows (the coins first, the fare with
## the 40 the wallet keeps, two lines at its ` · `), nothing sent; the card's `You have` follows the HUD while it is
## open; with enough, the same tap flies.
func test_fly_short_of_the_fare_stays_on_the_card_and_says_so() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m)   # a return to Los Angeles: the half fare
	var v: Dictionary = rt.session.view.duplicate(true)
	v.travel.fares = FARES
	v.coins = 60
	v.energy = {value = 200, max = 200}
	rt.session.view = v
	rt.ui.set_view(v)
	_hold_wire(rt)
	rt.ui.clear_toast()
	m.open_travel(LA)
	var f: Dictionary = load("res://modules/p0/p0_travel.gd").fare(v, LA)
	assert_int(int(f.coins)).is_equal(60)
	var rows := {}
	for r in m._travel_card.find_children("*", "UiFactRow", true, false): rows[str(r.label).get_slice(" · ", 0)] = [str(r.label), str(r.value)]
	assert_array(rows.Coins).is_equal(["Coins · You have 60", "60"])
	assert_array(rows.Energy).is_equal(["Energy · You have 200", str(f.energy)])
	var fly := m._travel_card.find_child("Primary", true, false) as UiCommandButton
	assert_str(fly.label).is_equal("Fly")
	assert_str(fly.reason).is_empty()   # lit: no gap on it
	fly.activated.emit()
	assert_str(rt.ui.modal_kind).is_equal("travel_card")   # stays
	assert_str(rt.ui.toast_text()).is_equal("Need 60 coins\nkeep 40 after the trip")
	assert_int(rt.ui._toasts.current_severity()).is_equal(ToastLayer.Severity.INFO)
	var card := m._travel_card.get_meta(&"toast_over_card") as Control
	assert_object(rt.ui._toasts._anchor.get_ref()).is_same(card)   # over the card, not the quick bar's spot
	var toast: Control = rt.ui._toasts._panel
	assert_float(toast.position.y + toast.size.y).is_equal_approx(rt.ui._toasts.anchor_top() - 8.0, 0.5)
	assert_float(toast.position.x).is_equal(16.0)
	assert_bool(m.travelling()).is_false()
	assert_array(_wire).is_empty()
	# both short: the coins' only
	rt.ui.clear_toast()
	var both := v.duplicate(true)
	both.energy = {value = 5, max = 200}
	rt.session.view = both
	fly.activated.emit()
	assert_str(rt.ui.toast_text()).is_equal("Need 60 coins\nkeep 40 after the trip")
	# coins from elsewhere while it is open: `You have` follows, then the same tap flies
	var rich := v.duplicate(true)
	rich.coins = 100
	rt.session.view = rich
	rt.ui.set_view(rich)
	m.p0_frame(rich, 0.0)
	var coins_row: UiFactRow = null
	for r in m._travel_card.find_children("*", "UiFactRow", true, false): if str(r.label).begins_with("Coins"): coins_row = r
	assert_str(coins_row.label).is_equal("Coins · You have 100")
	rt.ui.clear_toast()
	fly.activated.emit()
	assert_str(rt.ui.toast_text()).is_empty()
	assert_bool(m.travelling()).is_true()
	_answer(rt, _moved(rich, LA), [{kind = "arrival", cluster = LA, first = false, trip = 4, km = 559}])
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame

## q(257) ⑤ (SGODOT-367): in Los Angeles, its pass running out says so once with its return fare; at home, or once
## said, nothing.
func test_the_pass_of_the_city_the_player_is_in_ending_says_so_once() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m, LA)
	var v: Dictionary = rt.session.view.duplicate(true)
	v.travel.fares = FARES
	v.travel.passes = {LA: {kind = "day", from = 1.0, until = float(v.now) + 60_000.0}}
	rt.ui.clear_toast()
	rt._watch_day_pass(v)
	assert_str(rt.ui.toast_text()).is_empty()
	v.now = float(v.now) + 61_000.0   # ran out
	rt._watch_day_pass(v)
	var f := load("res://modules/p0/p0_travel.gd").fare(v, LA) as Dictionary
	assert_str(rt.ui.toast_text()).is_equal("Day Pass ended · Re-entry\n%d Energy · %d coins" % [int(f.energy), int(f.coins)])
	rt.ui.clear_toast()
	rt._watch_day_pass(v)
	assert_str(rt.ui.toast_text()).is_empty()   # once
	rt.session.view = saved
	rt.ui.set_view(saved)

## q(261) ⑦: said under a flight's cover, it waits — and once landed in another city, it is not said.
func test_a_pass_ended_under_the_cover_is_not_said_in_another_city() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _ready_to_arrive(m, LA)
	rt.ui.clear_toast()
	_fly(m, {kind = "arrival", cluster = TOKYO, first = false, trip = 6, km = 8800}, [], {}, false)
	rt.ui.toast_in_city("Day Pass ended · Re-entry 15 Energy · 60 coins", LA)
	assert_str(rt.ui.toast_text()).is_empty()   # held
	_answer(rt, _moved(rt.session.view, TOKYO), [{kind = "arrival", cluster = TOKYO, first = false, trip = 6, km = 8800}])
	await get_tree().create_timer(0.7).timeout
	_tap(_cover(m))
	await get_tree().create_timer(ToastLayer.duration_ms("Welcome back · Day Pass 24h") / 1000.0 + 0.3).timeout
	assert_str(rt.ui.toast_text()).is_not_equal("Day Pass ended · Re-entry 15 Energy · 60 coins")
	assert_bool(rt.ui.toast_text().begins_with("Day Pass ended")).is_false()
	rt.ui.clear_toast()
	rt.session.view = saved
	rt.ui.set_view(saved)
	await get_tree().process_frame
