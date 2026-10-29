extends GdUnitTestSuite
## SGODOT-275 travel, the free first version (plan v2 §11.8, q(108)): another city's bubble opens its travel card
## (free, its distance and Trip, first visit or return), Fly flies the camera to the city and sends `travel`, its reply
## (the server's arrival) welcomes (SGODOT-361); the avatar then stands in that city and the place chip reads "Tokyo · Arrived" (no Day Pass);
## a pond or outpost refused with pass_required / trip_expired opens the same card; going home sends `return_home`.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const P0Map := preload("res://scenes/p0/p0_map.gd")
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const SF := "gn-5391959"
const TOKYO := "gn-1850147"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	var s := P0Runtime.ensure().session
	s.transport = Callable()   # nothing held on the wire for the next test
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

## The map's session view with a travel block (the server's v5 shape), restored by the caller.
func _with_travel(rt: P0Runtime, travel: Dictionary) -> Dictionary:
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = travel
	rt.session.view = v
	return saved

## The first toast to show within `secs` (a flight lands, then welcomes).
func _toast_within(ui: P0Ui, secs: float) -> String:
	var t := 0.0
	while t < secs:
		if ui.toast_text() != "": return ui.toast_text()
		await get_tree().process_frame
		t += get_process_delta_time()
	return ui.toast_text()

## The travel commands on the wire, held: the test answers them (_answer); a city's places read fails at once.
var _wire: Array = []
func _hold_wire(rt: P0Runtime) -> void:
	_wire.clear()
	rt.session.transport = func(_method: int, _path: String, _body: Dictionary, cmd: Dictionary) -> void:
		if str(cmd.get("type", "")) == "travel": _wire.append(cmd)
		elif str(cmd.get("type", "")) == "city": P0CityPlaces.fail.call_deferred(str(cmd.cluster))   # never left waiting

func _answer(rt: P0Runtime, view: Dictionary, events: Array) -> void:
	var body := JSON.stringify({ok = true, state = view, events = events}).to_utf8_buffer()
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, 200, body, _wire.pop_front())

func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(l): return str((l as Label).text))

func test_another_citys_bubble_opens_its_silhouette_card_then_its_free_travel_card_and_fly_sends_travel() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	_hold_wire(rt)
	m.fly_to_city(TOKYO)
	# an unexplored city opens its silhouette card first (MAP-3-FREE); Travel details › opens the free travel card
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	(rt.ui.root.find_child("Link_Travel_details", true, false) as Button).pressed.emit()
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	var texts := _texts(rt.ui.root)
	# MAP-5 (q(257) ②): the city, its country, the trip and the first visit (no fares from this view: Cost · Free)
	assert_array(texts).contains(["Tokyo", "Japan", "Cost", "Free", "First visit · stamp + 10 Energy", "Return home is always free"])
	assert_bool(texts.any(func(t): return str(t).ends_with(" km · Trip 6"))).is_true()
	assert_dict(rt.here).is_equal({"space": "home", "place": ""})   # the card is not a trip: nothing sent yet
	assert_array(sent.filter(func(c): return str(c.get("type", "")) == "travel")).is_empty()
	var fly: Node = rt.ui.root.find_children("Primary", "", true, false)[0]
	assert_str(str(fly.label)).is_equal("Fly")
	fly.activated.emit()
	assert_array(sent.filter(func(c): return str(c.get("type", "")) == "travel").map(func(c): return str(c.to))).is_equal([TOKYO])
	assert_str(rt.ui.modal_kind).is_empty()
	assert_bool(m.travelling()).is_true()   # up at once, before any reply (q(261))
	m._call_back()
	await get_tree().process_frame   # the cover, off the map at once, is freed at the frame's end

func test_the_home_citys_bubble_opens_no_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	m.fly_to_city("san_francisco")
	assert_str((m.rt as P0Runtime).ui.modal_kind).is_empty()

func test_fly_flies_there_and_the_player_stands_in_that_city() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _with_travel(rt, {home = SF, here = SF, passes = {}, visits = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	var there: Dictionary = rt.session.view.duplicate(true)
	there.travel = {home = SF, here = TOKYO, passes = {TOKYO: {kind = "day", from = 1.0, until = 2_000_000_000.0}},
		visits = {TOKYO: {n = 1}}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}
	_hold_wire(rt)
	m._take_off(TOKYO, 8815)
	_answer(rt, there, [{kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8815}])
	assert_str(str(m.region.get("id", ""))).is_equal(TOKYO)
	assert_bool(m.away()).is_true()
	var tokyo := P0Clusters.get_cluster(TOKYO)
	var at: Vector2 = m._origin()
	assert_float(at.x).is_equal_approx(float(tokyo.lat), 1e-4)
	assert_float(at.y).is_equal_approx(float(tokyo.lng), 1e-4)
	assert_str(await _toast_within(rt.ui, 7.0)).is_equal("Welcome to Tokyo · Stamp collected")   # q(147): a fixed 3 s flight at any Trip, then the welcome
	rt.ui.clear_toast()
	rt.ui.close_modal()
	_hold_wire(rt)
	m._take_off(TOKYO, 8815)
	_answer(rt, there, [{kind = "arrival", cluster = TOKYO, first = false, trip = 6, km = 8815}])
	assert_str(await _toast_within(rt.ui, 7.0)).is_equal("Welcome back")   # q(108): a return only floats Welcome back
	rt.session.view = saved

func test_away_the_chip_reads_the_arrived_city_with_no_day_pass() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _with_travel(rt, {home = SF, here = TOKYO, passes = {TOKYO: {kind = "day", from = 1.0, until = 2_000_000_000.0}},
		visits = {TOKYO: {n = 1}}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	rt.ui.set_view(rt.session.view)
	var place: Dictionary = rt.ui.hud.data.place
	assert_str(str(place.city)).is_equal("Tokyo")
	assert_str(str(place.space)).is_equal("Arrived")
	assert_int(int(place.kind)).is_equal(UiHud.PlaceKind.FOREIGN)
	assert_str(str(place.day_pass)).is_empty()
	rt.session.view = saved
	rt.ui.set_view(saved)

func test_a_place_refused_without_a_pass_opens_that_citys_travel_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt._on_refused("pass_required", {"message": "Pass required", "preview": {"cluster": TOKYO, "name": "Tokyo", "km": 8815,
		"trip": 6, "trip_name": "Intercontinental", "first_visit": true}}, {"type": "cast", "space": "pond", "place": TOKYO + "~pond0"})
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	assert_array(_texts(rt.ui.root)).contains(["8,815 km · Trip 6"])   # the server's preview: its km and trip
	rt.ui.close_modal()
	rt._on_refused("trip_expired", {"preview": {"cluster": TOKYO}}, {})
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	rt.ui.close_modal()
	# q(256) ④: a pass, but the player is not in that city — the same card (MAP-5-RETURN), at the return fare
	rt._on_refused("travel_required", {"message": "Travel first", "preview": {"cluster": TOKYO}}, {"type": "enter"})
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	rt.ui.close_modal()

func test_going_home_from_another_city_sends_return_home_and_welcomes_home() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	rt.ui.clear_toast()   # the runtime's UI is shared across the suite: no Welcome back left from the arrival test
	var saved := _with_travel(rt, {home = SF, here = TOKYO, passes = {}, visits = {TOKYO: {n = 1}}, stamps = [],
		fallback = {near3 = [], near10 = []}, explorer = 0})
	m._return_home()
	assert_array(sent.map(func(c): return str(c.get("type", "")))).contains(["return_home"])
	assert_str(await _toast_within(rt.ui, 1.0)).is_equal("Welcome home")
	# 司空震 on 286: going home opens the farm behind a loading cover; the welcome waits for it to go
	rt.ui.clear_toast()
	rt._arrive = {path = "res://scenes/p0/p0_farm.tscn", place = "Homestead", shot = null, t0 = Time.get_ticks_msec()}
	rt.toast_on_arrival("Welcome home")
	for i in 3: await get_tree().process_frame
	assert_str(rt.ui.toast_text()).is_empty()   # not under the cover
	rt._end_arrival()
	assert_str(rt.ui.toast_text()).is_equal("Welcome home")
	rt.session.view = saved
	sent.clear()
	rt.ui.clear_toast()
	m._return_home()   # at home: nothing
	assert_array(sent).is_empty()
	assert_str(rt.ui.toast_text()).is_empty()

## 蒙恬 on #220: away in another city, the home city's bubble is going home (return_home, Welcome home), not a trip.
## q(152) ①: it flies home first — nothing is sent in the air; on landing return_home goes and the farm opens.
func test_away_the_home_citys_bubble_goes_home_not_a_trip() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	rt.ui.close_modal()   # the runtime's UI is shared across the suite: no card left from another test
	rt.ui.clear_toast()
	var saved := _with_travel(rt, {home = SF, here = TOKYO, passes = {}, visits = {TOKYO: {n = 1}}, stamps = [],
		fallback = {near3 = [], near10 = []}, explorer = 0})
	m.fly_to_city("san_francisco")
	assert_str(rt.ui.modal_kind).is_not_equal("travel_card")
	assert_bool(m.travelling()).is_true()
	assert_array(sent).is_empty()   # nothing in the air (苏烈: a flight cut short leaves the player where they are)
	var cover: P0TravelCover = m.find_children("*", "P0TravelCover", true, false)[0]
	assert_str(cover.title.text).is_equal("Homestead")
	m.open_farm = func(): pass   # the farm opens as far as this: the test stays on the map
	await get_tree().create_timer(3.3).timeout   # landed
	assert_bool(m.travelling()).is_false()
	assert_array(sent.map(func(c): return str(c.get("type", "")))).is_equal(["return_home"])
	rt.ui.set_view(rt.session.view)
	assert_str(str(rt.ui.hud.data.place.city)).is_equal("San Francisco")   # the chip says home from the landing
	assert_str(await _toast_within(rt.ui, 1.0)).is_equal("Welcome home")
	rt.ui.hold_here("")
	rt.session.view = saved

## MAP-3-FREE (§11.8.3, Figma 482:403): climate, trip and local time, then the city's ponds / outposts / residents from
## the server's generator (its preview), "–" until they are in; Keep browsing closes it.
func test_the_silhouette_card_reads_the_city_and_fills_in_its_places() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _with_travel(rt, {home = SF, here = SF, passes = {}, visits = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	var empty: Dictionary = P0Map.city_card(rt.session.view, TOKYO, {})
	assert_str(str(empty.title)).is_equal("Tokyo")
	assert_str(str(empty.state)).is_equal("Unexplored")
	assert_str(str(empty.effect)).is_equal("Preview the city before traveling.")
	assert_array(empty.facts.map(func(f): return str(f[0]))).is_equal(["Climate", "Trip", "Local time"])
	assert_str(str(empty.facts[0][1])).is_equal("Temperate")
	assert_str(str(empty.facts[1][1])).is_equal("6 · Intercontinental")
	assert_str(str(empty.facts[2][1])).is_equal("–")
	assert_array(empty.rows.map(func(r): return str(r.quantity))).is_equal(["–", "–", "–"])
	var city := {"preview": {"cluster": TOKYO, "trip": 6, "km": 8278, "trip_name": "Intercontinental", "utc_offset_min": 540,
		"counts": {"ponds": 4, "outposts": 9, "residents": 9}}}
	var full: Dictionary = P0Map.city_card(rt.session.view, TOKYO, city)
	assert_array(full.rows.map(func(r): return "%s %s" % [r.quantity, r.unit])).is_equal(["4 ponds", "9 outposts", "9 residents"])
	# local time = the view's clock + the city's offset: 1_000_000_000 ms (1970-01-12 13:46:40 UTC) + 9 h
	assert_str(str(full.facts[2][1])).is_equal("22:46")
	assert_str(str(full.dismiss)).is_equal("Keep browsing")
	rt.ui.close_modal()
	m.open_city_card(TOKYO)
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	(rt.ui.root.find_child("Dismiss", true, false) as Button).pressed.emit()
	assert_str(rt.ui.modal_kind).is_empty()
	rt.ui.close_modal()
	rt.session.view = saved
