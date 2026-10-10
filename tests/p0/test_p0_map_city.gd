extends GdUnitTestSuite
## SGODOT-270 (q(106)): P0's one home city moves from Shanghai to San Francisco, a data change read through P0City. The
## map opens there: its region and city data (regions.json, assets/map/cities/san_francisco.json with the four San
## Francisco landmarks), the homestead at its farm point (sh_a placed in Noe Valley, in the region), the home city's
## bubble at the farthest zoom, and the first session's opening view holding the homestead, Fern Pond with its ! and the
## Tackle Shop. Another city's bubble browses there since SGODOT-275 (test_p0_map_browse).

const P0City := preload("res://modules/p0/p0_city.gd")
const P0_MAP := "res://scenes/p0/p0_map.tscn"

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

func test_the_home_city_is_san_francisco() -> void:
	assert_str(P0City.region()).is_equal("san_francisco")
	var region := FarmRegions.load_default().region("san_francisco")
	assert_str(str(region.get("geonames_id", ""))).is_equal("gn-5391959")
	assert_bool(CityMapData.has_city("san_francisco")).is_true()
	var ids := CityMapData.landmarks("san_francisco").map(func(p): return str(p.id))
	for id in ["golden_gate_bridge", "fishermans_wharf", "alcatraz_island", "painted_ladies"]: assert_array(ids).contains([id])

## The map opens in the home city with the homestead at its farm point: sh_a placed there and in its region, so the map
## lands on it (MapPoc._land_on_own_farm checks the farm's region).
func test_the_map_opens_on_the_homestead_in_san_francisco() -> void:
	var m := _map()
	for i in 5: await get_tree().process_frame
	assert_str(str(m.region.get("id", ""))).is_equal("san_francisco")
	var at := P0City.farm_at()
	assert_float(float(m.home_lat)).is_equal_approx(at.x, 1e-5)
	assert_float(float(m.home_lng)).is_equal_approx(at.y, 1e-4)
	var bp := FarmBlueprint.load_choice(m._resolve_farm_choice())
	assert_str(bp.region_id).is_equal("san_francisco")
	assert_array(m.city_regions().map(func(r): return str(r.id))).contains(["san_francisco"])

## The first session's opening view (Pond Catch taken: Fern Pond wears its !) holds the homestead, Fern Pond and the
## Tackle Shop 250 m from it — in the frame; the Tackle Shop's pin may give way to Fern Pond's (269, 不知火舞 on 270).
func test_the_first_sessions_opening_view_holds_home_fern_pond_and_the_tackle_shop() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := rt.session.view
	var v := saved.duplicate(true)
	v["map_markers"] = [{"place": P0City.beginner_pond(), "kind": "request", "why": {"request": "req_pond_catch", "tracked": true}}]
	rt.session.view = v
	m.p0_frame(v, 0.0)
	m.frame_home_set()
	var safe: Rect2 = m.frame_safe_rect()
	var pond: Dictionary = (m.city_map.entries as Array).filter(func(e): return str(e.get("id", "")) == P0City.beginner_pond())[0]
	var tackle := P0Outposts.by_role("tackle")
	for p in [[m.home_lat, m.home_lng, "home"], [pond.lat, pond.lng, "Fern Pond"], [tackle.lat, tackle.lng, "Tackle Shop"]]:
		var at = m.geo_to_screen(float(p[0]), float(p[1]))
		assert_object(at).override_failure_message("%s not projected" % p[2]).is_not_null()
		assert_bool(safe.has_point(at)).override_failure_message("%s outside the opening view" % p[2]).is_true()
	rt.session.view = saved
