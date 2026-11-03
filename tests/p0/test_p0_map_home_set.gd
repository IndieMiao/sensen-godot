extends GdUnitTestSuite
## SGODOT-311 on the map: a home in a generated city (Tokyo) is pinned as the home city is — its own outposts always on
## the map, an `outpost:<role>` target is the home set's, the map frames the home set, and the runtime reads the home
## city's places once. A San Francisco home keeps its hand-written pins (test_p0_map_show and the rest).

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const HomeSet := preload("res://tests/p0/test_p0_home_set.gd")
const TOKYO := "gn-1850147"
const TOKYO_SET := ["gn-1850147~tackle0", "gn-1850147~tea0", "gn-1850147~post0", "gn-1850147~market0"]

var map: Node
var rt: P0Runtime

func before() -> void:
	P0CityPlaces.clear()
	P0CityPlaces.accept(TOKYO, HomeSet.CITY)   # the home city's places, in as the runtime reads them
	rt = P0Runtime.ensure()
	rt.here = {"space": "home", "place": ""}
	rt.session.view = HomeSet._tokyo_home()
	map = (load(P0_MAP) as PackedScene).instantiate()
	add_child(map)
	for i in 5: await get_tree().process_frame

func after_test() -> void:
	if rt != null and rt.session != null: rt.session.transport = Callable()

func after() -> void:
	if is_instance_valid(map): map.free()
	P0Runtime.free_instance_for_tests()
	P0CityPlaces.clear()

func test_an_outpost_role_is_the_home_sets() -> void:
	assert_str(str(map.place_for("outpost:market").get("id", ""))).is_equal("gn-1850147~market0")
	assert_str(str(map.place_for("outpost:tea").get("id", ""))).is_equal("gn-1850147~tea0")
	assert_str(str(map.place_for("outpost:sh_tea_1").get("id", ""))).is_equal("sh_tea_1")   # an id stays that place

func test_the_home_citys_pins_are_always_on_the_map() -> void:
	map._shown_cities.clear()   # whatever other cities the camera went over: home stays
	map._set_outpost_places()
	var ids: Array = (map.city_map.entries as Array).map(func(e): return str(e.get("id", "")))
	for id in TOKYO_SET: assert_array(ids).contains([id])

func test_the_map_frames_the_home_set() -> void:
	var ids: Array = map.frame_optional().map(func(e): return str(e.get("id", "")))
	assert_array(ids.filter(func(id): return str(id).begins_with("sh_"))).is_empty()
	for id in TOKYO_SET: assert_array(ids).contains([id])   # all four (an empty frame would pass the line above alone, 周瑜)

func test_the_runtime_reads_the_home_city_once() -> void:
	var asked: Array = []
	rt.session.transport = func(_m, path: String, _b, _meta): asked.append(path)
	P0CityPlaces.clear()
	rt._read_home_places(rt.session.view)
	rt._read_home_places(rt.session.view)   # still on its way: not asked twice
	assert_array(asked).is_equal(["/p0/city/" + TOKYO])
	P0CityPlaces.accept(TOKYO, HomeSet.CITY)
	rt._read_home_places(rt.session.view)   # in: never again
	assert_int(asked.size()).is_equal(1)
	# San Francisco's ponds and outposts are the client's own, its gathering spots the server's (v4q(4)): read too
	rt._read_home_places({"travel": {"home": "gn-5391959"}})
	assert_array(asked).is_equal(["/p0/city/" + TOKYO, "/p0/city/gn-5391959"])

## PR-3: the map opens over the home city, the Homestead pin on the spot picked with it, and home is flown to there.
func test_the_map_opens_over_the_home_city_with_the_farm_on_its_spot() -> void:
	assert_str(str(map.region.get("id", ""))).is_equal(TOKYO)
	var choice: Dictionary = map._resolve_farm_choice()
	assert_str(str(choice.region_id)).is_equal(TOKYO)
	assert_float(float(choice.location.lat)).is_equal_approx(35.6801, 1e-4)
	assert_float(float(choice.location.lng)).is_equal_approx(139.7102, 1e-4)
	assert_float(map.home_lat).is_equal_approx(35.6801, 0.01)   # where the map's home is

## 李元芳 on #451: the opening view keeps every framed pin and name clear of the right-hand keys (⌂, ⊕) — a Tokyo
## farm picked southeast of its home set opened with the Homestead under them.
func test_the_opening_view_keeps_pins_off_the_right_hand_keys() -> void:
	var market := P0Outposts.home(HomeSet._tokyo_home(), "market")
	var v := HomeSet._tokyo_home()
	v.home.farm = {"lat": float(market.lat) - 0.012, "lng": float(market.lng) + 0.016}   # ~2 km southeast
	rt.session.view = v
	var m: Node = (load(P0_MAP) as PackedScene).instantiate()
	add_child(m)
	for i in 5: await get_tree().process_frame
	var city: CityMapView = m.city_map
	city._shown_last = {"gn-1850147~tackle0": true}   # an earlier view showed the tackle shop: it would hold its place
	m.frame_home_set()
	assert_dict(city._shown_last).is_empty()   # 不知火舞 on #457: the opening view packs afresh at its own zoom
	assert_array(m.frame_key_rects()).is_not_empty()
	assert_bool(m.framed.any(func(it): return it.get("self_pin", false))).is_true()   # the Homestead (the avatar) is in
	for it in m.framed:
		var r = m._item_rect(it)
		if r == null: continue
		for k in m.frame_key_rects(): assert_bool((r as Rect2).intersects(k)).override_failure_message(str(it.get("id", "self"))).is_false()
	# 不知火舞 on #457: the pins then pack at this zoom — no two discs shown nearer than 36 px (q(137) ⑤), whatever an
	# earlier view had shown
	m._sync_farm_markers()
	city._update_markers()
	var shown: Array = city._dest_centres
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			assert_float((shown[i] as Vector2).distance_to(shown[j])).override_failure_message("discs %d %d" % [i, j]).is_greater_equal(CityMapView.DEST_NEAR)
	m.free()
	rt.session.view = HomeSet._tokyo_home()
