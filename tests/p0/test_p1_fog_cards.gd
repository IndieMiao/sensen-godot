extends GdUnitTestSuite
## q(212) (SGODOT-327): in a city not visited, every place pin is a silhouette and its tap — a Show on map landing on it,
## its Go — opens the city's silhouette card (MAP-3-FREE), pass or none: the fog first, the pass after. San Francisco's
## hand-written places are San Francisco's whatever the home; no POI is drawn in the fog; a city's card keeps no pin
## selected. q(213): a landmark card in P0 has no Enter scene.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const P0Map := preload("res://scenes/p0/p0_map.gd")
const SF := "gn-5391959"
const TOKYO := "gn-1850147"
const DENVER := "gn-5419384"
const LA := "gn-5368361"
const POST := "gn-5419384~post0"
const HUT := "gn-5419384~hut0"
const CABIN := "gn-5419384~cabin0"
const POND := "gn-5419384~pond0"
const PASS := {kind = "day", from = 1.0, until = 2_000_000_000.0}

## Denver as the server sends it (one of each kind kept for the test).
const CITY := {
	"ponds": ["gn-5419384~pond0"], "outposts": ["gn-5419384~post0", "gn-5419384~cabin0"], "residents": 6, "fish": [],
	"detail": {
		"ponds": [{"id": "gn-5419384~pond0", "name": "Sloan Pond", "lat": 39.73, "lng": -105.05, "site": "meadow_pond_v1",
			"template_id": "meadow_pond", "beginner": true}],
		"outposts": [
			{"id": "gn-5419384~post0", "role": "post", "name": "Denver Travel Post", "lat": 39.7392, "lng": -104.9903,
				"category": "Travel post · Coffee", "keeper": {"role": "Post Clerk", "name": "Tom", "look": "post_cool_0"},
				"residents": ["res_pip"], "art": "post_office", "anchors": "res://assets/p0/outposts/post.anchors.json", "capacity": 12},
			{"id": "gn-5419384~cabin0", "role": "market", "cabin": true, "name": "Aspen Cabin", "lat": 39.76, "lng": -105.0,
				"category": "Trading post · All counters", "keeper": {"role": "Trader", "name": "Ada", "look": "market_cool_0"},
				"residents": [], "art": "coffee_shop", "anchors": "res://assets/p0/outposts/tea.anchors.json", "capacity": 12}],
		"huts": [
			{"id": "gn-5419384~hut0", "role": "mine_hut", "name": "Golden Mine Hut", "lat": 39.7555, "lng": -105.2211,
				"category": "Mine hut · Old miner", "keeper": null, "residents": ["res_ivo"], "capacity": 12}]},
	"preview": {"cluster": DENVER, "name": "Denver"},
}

func before_test() -> void:
	P0CityPlaces.clear()
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	P0CityPlaces.clear()
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
	for i in 3: await get_tree().process_frame
	map.set_process(false)
	(map.rt as P0Runtime).ui.close_modal()
	P0CityPlaces.accept(DENVER, CITY)
	return map

## The travel block: home, visits and passes (a clean save is home San Francisco, nowhere else).
func _travel(m: Node, home := SF, visits := {}, passes := {}) -> void:
	var rt: P0Runtime = m.rt
	var v: Dictionary = rt.session.view.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = {home = home, here = home, visits = visits, passes = passes, stamps = [], fallback = {near3 = [], near10 = []},
		explorer = 0}
	rt.session.view = v

func _entry(id: String) -> Dictionary:
	if id == POND:
		return (CITY.detail.ponds[0] as Dictionary).merged({"kind": "pond", "cluster": DENVER})
	var e := P0Outposts.place_entry(P0Outposts.find(id))
	e["cluster"] = DENVER
	return e

func _settle() -> void:
	for i in 3: await get_tree().process_frame

## (1) A clean save: the market / post, pond, Mine Hut and cabin of a city not visited open its silhouette card.
func test_1_a_clean_save_opens_the_silhouette_card_from_every_place_pin() -> void:
	var m: Node = await _map()
	_travel(m)
	var rt: P0Runtime = m.rt
	for id in [POST, POND, HUT, CABIN]:
		assert_bool(bool(m._destination_style(_entry(id)).get("silhouette", false))).override_failure_message(id).is_true()
		m.city_map.select(_entry(id))
		assert_str(rt.ui.modal_kind).override_failure_message(id).is_equal("city_card")
		rt.ui.close_modal()
		await _settle()

## (2) A pass without a visit (a debug save: the server writes both on arrival) is still the fog: the pin, and both
## ways of going (the place card's Go, a pond's Go), open the silhouette card.
func test_2_a_pass_without_a_visit_opens_the_silhouette_card() -> void:
	var m: Node = await _map()
	_travel(m, SF, {}, {DENVER: PASS})
	var rt: P0Runtime = m.rt
	m.city_map.select(_entry(HUT))
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	rt.ui.close_modal()
	m._on_place_requested(_entry(POST))
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	rt.ui.close_modal()
	m._on_city_pond_requested(_entry(POND))
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	assert_object(AppRouter.top_instance()).is_null()   # nothing entered
	rt.ui.close_modal()

## (3) Visited with a pass: the place's own card, its name and Go.
func test_3_visited_with_a_pass_opens_the_place_card() -> void:
	var m: Node = await _map()
	_travel(m, SF, {DENVER: {n = 1}}, {DENVER: PASS})
	var rt: P0Runtime = m.rt
	assert_bool(bool(m._destination_style(_entry(HUT)).get("silhouette", false))).is_false()
	m.city_map.select(_entry(HUT))
	assert_str(rt.ui.modal_kind).is_equal("place_card")
	rt.ui.close_modal()

## (4) Visited, the pass run out: the city's travel card.
func test_4_visited_without_a_pass_opens_the_travel_card() -> void:
	var m: Node = await _map()
	_travel(m, SF, {DENVER: {n = 1}}, {DENVER: {kind = "day", from = 1.0, until = 2.0}})
	var rt: P0Runtime = m.rt
	m.city_map.select(_entry(POST))
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	rt.ui.close_modal()

## (5) Show on map into a city not visited (a cross-city request's place): where it lands — its pin selected — opens
## the silhouette card, not the place's.
func test_5_show_on_map_into_the_fog_opens_the_silhouette_card() -> void:
	var m: Node = await _map()
	_travel(m)
	var rt: P0Runtime = m.rt
	var landing: Dictionary = m.place_for("outpost:" + HUT)   # show_place flies here, then selects it
	assert_str(str(landing.id)).is_equal(HUT)
	m.city_map.select(landing)
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	rt.ui.close_modal()

## (6) A home elsewhere: San Francisco's hand-written places are San Francisco's — silhouettes, its silhouette card.
func test_6_san_franciscos_written_places_are_its_own_with_a_home_elsewhere() -> void:
	var m: Node = await _map()
	_travel(m, TOKYO)
	var rt: P0Runtime = m.rt
	var tea := P0Outposts.place_entry(P0Outposts.find("sh_tea_1"))
	assert_str(P0Map.cluster_of_entry(tea)).is_equal(SF)
	assert_str(P0Map.cluster_of_entry({"id": "pond_san_francisco_01"})).is_equal(SF)
	assert_bool(bool(m._destination_style(tea).get("silhouette", false))).is_true()
	m.city_map.select(tea)
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	assert_str(m._card_city).is_equal(SF)
	rt.ui.close_modal()
	_travel(m, TOKYO, {SF: {n = 1}}, {SF: PASS})   # visited: its card as ever
	m.city_map.select(tea)
	assert_str(rt.ui.modal_kind).is_equal("place_card")
	rt.ui.close_modal()

## (7) A silhouette card and a travel card are the city's, not the pin's (不知火舞 on 327, 11ca174e): the pin is not
## selected while one is up — a tap only presses it — so it is never left raised when the card closes (×, Keep browsing,
## a tap outside, Back), through Travel details › too. A place card or pond card keeps its pin selected while it is up
## and lets go when it closes, as before.
func test_7_the_pin_is_not_kept_selected_by_a_citys_card() -> void:
	var m: Node = await _map()
	_travel(m)
	var rt: P0Runtime = m.rt
	var city: CityMapView = m.city_map
	m.center_lat = 39.7555   # the hut on screen, its pin drawn
	m.center_lng = -105.2211
	m.zoom = 15.0
	m._show_city_places(P0CityPlaces.city(DENVER), DENVER)
	m._update_cameras()
	m._sync_farm_markers()
	city._update_markers()
	assert_array(city.displayed.map(func(mk): return str(mk.entry.id))).contains([HUT])
	city.select(_entry(HUT))   # a tap on the silhouette
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	assert_dict(city.selected).is_empty()   # the card is up, the pin not selected
	await get_tree().create_timer(0.4).timeout   # the press over
	assert_float(float(city.markers[HUT].get("focus", 1.0))).is_equal_approx(1.0, 0.001)   # its size: not left raised
	rt.ui.close_modal()
	await _settle()
	assert_dict(m.city_map.selected).is_empty()
	# Show on map landing on it, and Travel details › on to the travel card: still none
	m.city_map.select(m.place_for("outpost:" + HUT))
	rt.ui.close_modal()
	m.open_travel(DENVER)
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	assert_dict(m.city_map.selected).is_empty()
	rt.ui.close_modal()
	# a visited city's travel card (the pass run out): the same, and Back closes it by itself
	_travel(m, SF, {DENVER: {n = 1}}, {})
	m.city_map.select(_entry(POST))
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	assert_dict(m.city_map.selected).is_empty()
	rt.ui.back_modal()
	assert_str(rt.ui.modal_kind).is_equal("")
	assert_dict(m.city_map.selected).is_empty()
	# visited with a pass: the place card holds its pin while it is up, and lets it go on closing
	_travel(m, SF, {DENVER: {n = 1}}, {DENVER: PASS})
	m.city_map.select(_entry(HUT))
	assert_str(rt.ui.modal_kind).is_equal("place_card")
	assert_str(str(m.city_map.selected.get("id", ""))).is_equal(HUT)
	rt.ui.close_modal()
	await _settle()
	assert_dict(m.city_map.selected).is_empty()

## (8) The first visit's Show local pond lands on the pond of a city now visited: its pond card, not a silhouette's.
func test_8_show_local_pond_lands_on_a_visited_citys_pond() -> void:
	var m: Node = await _map()
	_travel(m, SF, {DENVER: {n = 1}}, {DENVER: PASS})
	var rt: P0Runtime = m.rt
	m.city_map.select(_entry(POND))
	assert_str(rt.ui.modal_kind).is_not_equal("city_card")
	assert_str(rt.ui.modal_kind).is_not_equal("travel_card")
	rt.ui.close_modal()

## (9) No POI in the fog (MAP-2): drawn only within an explored city's hole; a visited city's as ever.
func test_9_no_poi_in_a_city_not_visited() -> void:
	var m: Node = await _map()
	_travel(m)
	var denver_cafe := {"kind": "poi", "id": "poi-d", "lat": 39.74, "lng": -104.99}
	var sf_cafe := {"kind": "poi", "id": "poi-s", "lat": 37.7749, "lng": -122.4194}
	var far := {"kind": "poi", "id": "poi-n", "lat": 40.0, "lng": -110.0}   # nowhere near a city explored
	assert_bool(m.city_map.poi_shown.is_valid()).is_true()   # the map asks P0 for each POI
	assert_bool(m.poi_shown(denver_cafe)).is_false()
	assert_bool(m.poi_shown(sf_cafe)).is_true()   # home
	assert_bool(m.poi_shown(far)).is_false()
	_travel(m, SF, {DENVER: {n = 1}}, {})
	assert_bool(m.poi_shown(denver_cafe)).is_true()   # visited: its POIs, their cards as ever
	assert_bool(m.poi_shown(far)).is_false()
	# what the map draws (周瑜 on #468): a Denver POI on screen in the fog is not drawn, visited it is
	_travel(m)
	var city: CityMapView = m.city_map
	city.entries = []
	city.live_pois = [{"id": "poi-d", "kind": "poi", "name": "Cafe", "lat": 39.74, "lng": -104.99, "art": "shop", "rank": 1}]
	m.center_lat = 39.74
	m.center_lng = -104.99
	m.zoom = 15.0
	m.bearing = 18.0
	m._update_cameras()
	m._sync_farm_markers()
	city._update_markers()
	assert_array(city.displayed.map(func(mk): return str(mk.entry.id))).not_contains(["poi-d"])   # in the fog: none
	_travel(m, SF, {DENVER: {n = 1}}, {})
	city._shown_last.clear()
	city._update_markers()
	assert_array(city.displayed.map(func(mk): return str(mk.entry.id))).contains(["poi-d"])   # visited: drawn

## q(213): a landmark card in P0 is its name and kind alone — no Enter scene even for Griffith Observatory (Los
## Angeles' authored scene), and a request for it goes nowhere.
func test_a_landmark_card_has_no_enter_scene() -> void:
	var m: Node = await _map()
	_travel(m)
	assert_bool(m.city_map.landmark_scenes).is_false()
	m.region = P0Clusters.region(LA)
	assert_str(str(m.region.id)).is_equal("los_angeles")
	var griffith := {"kind": "landmark", "id": "griffith_observatory", "name": "Griffith Observatory", "category": "Observatory",
		"lat": 34.1184, "lng": -118.3004}
	m.city_map.select(griffith)
	assert_bool(m.city_map.info.visible).is_true()
	assert_bool(m.city_map.info_action.visible).is_false()
	m._on_city_landmark_requested(griffith)
	assert_object(AppRouter.top_instance()).is_null()
	m.city_map.clear_selection()
