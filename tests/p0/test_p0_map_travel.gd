extends GdUnitTestSuite
## SGODOT-275 travel, the free first version (plan v2 §11.8, q(108)): another city's bubble opens its travel card
## (free, its distance and Trip, first visit or return), Fly sends `travel`, the server's arrival flies the camera to
## the city and welcomes; the avatar then stands in that city and the place chip reads "Tokyo · Arrived" (no Day Pass);
## a pond or outpost refused with pass_required / trip_expired opens the same card; going home sends `return_home`.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const SF := "gn-5391959"
const TOKYO := "gn-1850147"

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

## The map's session view with a travel block (the server's v5 shape), restored by the caller.
func _with_travel(rt: P0Runtime, travel: Dictionary) -> Dictionary:
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = travel
	rt.session.view = v
	return saved

func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(l): return str((l as Label).text))

func test_another_citys_bubble_opens_its_free_travel_card_and_fly_sends_travel() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	m.fly_to_city(TOKYO)
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	var texts := _texts(rt.ui.root)
	assert_array(texts).contains(["Tokyo, Japan", "Unexplored", "Free", "First visit · stamp + 10 Energy", "Fly"])
	assert_bool(texts.any(func(t): return str(t).ends_with(" km · Trip 6 · Intercontinental"))).is_true()
	assert_dict(rt.here).is_equal({"space": "home", "place": ""})   # the card is not a trip: nothing sent yet
	assert_array(sent.filter(func(c): return str(c.get("type", "")) == "travel")).is_empty()
	var fly: Node = rt.ui.root.find_children("Primary", "", true, false)[0]
	fly.activated.emit()
	assert_array(sent.filter(func(c): return str(c.get("type", "")) == "travel").map(func(c): return str(c.to))).is_equal([TOKYO])
	assert_str(rt.ui.modal_kind).is_empty()

func test_the_home_citys_bubble_opens_no_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	m.fly_to_city("san_francisco")
	assert_str((m.rt as P0Runtime).ui.modal_kind).is_empty()

func test_an_arrival_flies_there_and_the_player_stands_in_that_city() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _with_travel(rt, {home = SF, here = TOKYO, passes = {TOKYO: {kind = "day", from = 1.0, until = 2_000_000_000.0}},
		visits = {TOKYO: {n = 1}}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	m.on_arrival({kind = "arrival", cluster = TOKYO, first = true, trip = 6, km = 8815})
	assert_str(str(m.region.get("id", ""))).is_equal(TOKYO)
	assert_bool(m.away()).is_true()
	var tokyo := P0Clusters.get_cluster(TOKYO)
	var at: Vector2 = m._origin()
	assert_float(at.x).is_equal_approx(float(tokyo.lat), 1e-4)
	assert_float(at.y).is_equal_approx(float(tokyo.lng), 1e-4)
	await get_tree().create_timer(5.5).timeout   # Trip 6: a 5 s flight, then the welcome
	assert_str(rt.ui.toast_text()).is_equal("Welcome to Tokyo · Stamp collected")
	rt.ui.clear_toast()
	m.on_arrival({kind = "arrival", cluster = TOKYO, first = false, trip = 6, km = 8815})
	await get_tree().create_timer(5.5).timeout
	assert_str(rt.ui.toast_text()).is_equal("Welcome back")   # q(108): a return only floats Welcome back
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
	assert_array(_texts(rt.ui.root)).contains(["8,815 km · Trip 6 · Intercontinental"])
	rt.ui.close_modal()
	rt._on_refused("trip_expired", {"preview": {"cluster": TOKYO}}, {})
	assert_str(rt.ui.modal_kind).is_equal("travel_card")

func test_going_home_from_another_city_sends_return_home_and_welcomes_home() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	var saved := _with_travel(rt, {home = SF, here = TOKYO, passes = {}, visits = {TOKYO: {n = 1}}, stamps = [],
		fallback = {near3 = [], near10 = []}, explorer = 0})
	m._return_home()
	assert_array(sent.map(func(c): return str(c.get("type", "")))).contains(["return_home"])
	assert_str(rt.ui.toast_text()).is_equal("Welcome home")
	rt.session.view = saved
	sent.clear()
	rt.ui.clear_toast()
	m._return_home()   # at home: nothing
	assert_array(sent).is_empty()
	assert_str(rt.ui.toast_text()).is_empty()
