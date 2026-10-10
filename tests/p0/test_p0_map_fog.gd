extends GdUnitTestSuite
## SGODOT-275 fog (plan v2 §11.7, three states, the user's call 10-10): the world under a grey veil but for the explored
## cities (home, visited; Second Home when the server sets one), city bubbles saying Unexplored / Visited / Second Home,
## and a pond or outpost of a city without a pass opening its travel card instead of going in. Colour only: nothing is
## hidden, and the veil clears at street zoom.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Map := preload("res://scenes/p0/p0_map.gd")
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const MapFogLayer := preload("res://modules/map/map_fog_layer.gd")
const SF := "gn-5391959"
const TOKYO := "gn-1850147"
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

func _travel(rt: P0Runtime, travel: Dictionary) -> Dictionary:
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = travel
	rt.session.view = v
	return saved

func _look(m: Node, lat: float, lng: float, z: float) -> void:
	m.center_lat = lat
	m.center_lng = lng
	m._set_zoom(z)
	m.pitch = 0.0
	m._zoom_elastic = 0.0

func test_three_states_from_the_travel_block() -> void:
	var v := {"travel": {home = SF, here = SF, visits = {TOKYO: {n = 1}}, second_homes = [LA]}}
	assert_str(P0Travel.fog(v, SF)).is_equal("explored")
	assert_str(P0Travel.fog(v, TOKYO)).is_equal("explored")
	assert_str(P0Travel.fog(v, LA)).is_equal("second_home")
	assert_str(P0Travel.fog(v, "gn-1816670")).is_equal("unexplored")   # Beijing
	assert_array(P0Travel.explored(v)).contains_exactly_in_any_order([SF, TOKYO, LA])

func test_the_veil_holes_the_explored_cities_only_and_clears_at_street_zoom() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _travel(rt, {home = SF, here = SF, visits = {}, passes = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	_look(m, 36.0, -120.3, 5.0)   # California: San Francisco and Los Angeles on screen
	var holes: Array = m.fog_holes()
	var vp := Rect2(Vector2.ZERO, Vector2(360, 800))
	for p in [m.geo_to_screen(37.7749, -122.4194), m.geo_to_screen(34.0522, -118.2437)]:
		assert_bool(vp.has_point((p as Vector2) - m.city_map.global_position)).is_true()
	assert_int(holes.size()).is_equal(1)   # home only: Los Angeles is not explored
	var sf = m.geo_to_screen(37.7749, -122.4194)
	assert_float((holes[0].at as Vector2).distance_to((sf as Vector2) - m.city_map.global_position)).is_less(40.0)
	assert_float(float(holes[0].r)).is_greater(2.0)
	rt.session.view.travel.visits = {LA: {n = 1}}
	assert_int(m.fog_holes().size()).is_equal(2)
	var fog: ColorRect = m.city_map.fog
	m.city_map._update_fog()
	assert_bool(fog.visible).is_true()
	assert_int(fog.get_index()).is_equal(0)   # under every pin, bubble and name
	assert_int(fog.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	_look(m, 37.7558, -122.4345, 15.0)
	m.city_map._update_fog()
	assert_bool(fog.visible).is_false()   # street zoom: no veil
	assert_float(MapFogLayer.strength(11.0)).is_equal(1.0)
	assert_float(MapFogLayer.strength(14.0)).is_equal(0.0)
	rt.session.view = saved

func test_city_bubbles_say_their_state() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _travel(rt, {home = SF, here = SF, visits = {TOKYO: {n = 1}}, second_homes = [LA], passes = {}, stamps = [],
		fallback = {near3 = [], near10 = []}, explorer = 0})
	var state: Callable = m.city_map.bubble_state
	assert_str(str(state.call("san_francisco"))).is_equal("explored")
	assert_str(str(state.call(TOKYO))).is_equal("explored")
	assert_str(str(state.call("los_angeles"))).is_equal("second_home")
	assert_str(str(state.call("gn-1816670"))).is_equal("unexplored")
	rt.session.view = saved

func test_a_pin_of_a_city_without_a_pass_opens_its_travel_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var saved := _travel(rt, {home = SF, here = SF, visits = {}, passes = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	assert_str(P0Map.cluster_of_entry({"id": TOKYO + "~pond0"}, SF)).is_equal(TOKYO)
	assert_str(P0Map.cluster_of_entry({"id": "pond_san_francisco_01"}, SF)).is_equal(SF)
	assert_bool(m._travel_first({"kind": "pond", "id": TOKYO + "~pond0"})).is_true()
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	rt.ui.close_modal()
	assert_bool(m._travel_first({"kind": "pond", "id": "pond_san_francisco_01"})).is_false()   # the home city's: as ever
	assert_bool(m._travel_first({"kind": "place", "id": "home"})).is_false()
	rt.session.view.travel.passes = {TOKYO: {kind = "day", from = 1.0, until = 2_000_000_000.0}}
	assert_bool(m._travel_first({"kind": "pond", "id": TOKYO + "~pond0"})).is_false()   # a pass: go in
	rt.session.view = saved
