extends GdUnitTestSuite
## q(153) (不知火舞 on 293 8f407417 / e5ec0cc0; the user's call 10-13): at the state and country views the city bubbles
## give way by priority — the city just opened > where the player is > home > the visited (most populous first, then
## id) > the rest. A bubble that runs into a higher city's bubble or dot hides whole; the visited and up keep their dot
## (a tap on it opens the city as the bubble does), the rest go with it. The top three never give way. A hidden bubble
## comes back 4 px clear; every dot draws under every bubble, the higher bubbles on top; a tap goes to the topmost.

const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const P0_MAP := "res://scenes/p0/p0_map.tscn"
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

func _city(name: String, box: Array) -> String:
	for c in P0Clusters.in_box(box[0], box[1], box[2], box[3], 0, 400):
		if str(c.get("name", "")) == name: return str(c.id)
	return ""

func _trip(home: String, here: String, visits: Array) -> Dictionary:
	var v := {}
	for c in visits: v[c] = {n = 1}
	return {home = home, here = here, visits = v, passes = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}

func test_the_cities_come_in_priority_order() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var sacramento := _city("Sacramento", [38.4, -121.7, 38.7, -121.3])
	var fresno := _city("Fresno", [36.6, -120.0, 36.9, -119.6])
	var bakersfield := _city("Bakersfield", [35.2, -119.2, 35.5, -118.8])
	for c in [sacramento, fresno, bakersfield]: assert_str(c).is_not_empty()
	var saved := _travel(rt, _trip(SF, LA, [LA, fresno, sacramento]))
	_look(m, 36.4, -120.3, 5.0)
	m.open_city_card(bakersfield)   # unexplored: its card opens, it comes first from now on
	rt.ui.close_modal()
	var ids: Array = m.city_regions().map(func(r): return P0Clusters.cluster_of_region(str(r.id)))
	var by_pop := [sacramento, fresno]
	by_pop.sort_custom(func(a, b): return int(P0Clusters.get_cluster(a).population) > int(P0Clusters.get_cluster(b).population))
	assert_array(ids.slice(0, 5)).is_equal([bakersfield, LA, SF] + by_pop)
	var tiers := func(cluster: String) -> Array:
		var r: Dictionary = P0Clusters.region(cluster)
		var st: Dictionary = m.city_bubble(str(r.id))
		return [st.dot_stays, st.keeps]
	for c in [bakersfield, LA, SF]: assert_array(tiers.call(c)).is_equal([true, true])
	for c in by_pop: assert_array(tiers.call(c)).is_equal([true, false])
	assert_int(ids.size()).is_greater(5)
	assert_array(tiers.call(str(ids[5]))).is_equal([false, false])   # the rest
	rt.session.view = saved

## The plan's own example (李元芳, 286 14c60178): home San Francisco, Concord and Fairfield visited. Concord's bubble
## runs into home's; Fairfield's runs into Concord's dot (Concord, the larger, comes first): home's bubble in full and
## three dots.
func test_the_bay_areas_bubbles_give_way_to_home_and_keep_their_dots() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var concord := _city("Concord", [37.9, -122.1, 38.1, -121.9])
	var fairfield := _city("Fairfield", [38.2, -122.2, 38.35, -121.95])
	assert_str(concord).is_not_empty()
	assert_str(fairfield).is_not_empty()
	assert_int(int(P0Clusters.get_cluster(concord).population)).is_greater(int(P0Clusters.get_cluster(fairfield).population))
	var saved := _travel(rt, _trip(SF, SF, [concord, fairfield]))
	_look(m, 37.9, -122.0, 6.0)
	m.city_map._update_bubbles()
	var b: Dictionary = m.city_map.bubbles
	var sf_id := str(P0Clusters.region(SF).id)
	assert_bool(b[sf_id].node.visible).is_true()
	for c in [concord, fairfield]:
		var id := str(P0Clusters.region(c).id)
		assert_bool(b[id].node.visible).override_failure_message("%s's bubble shows" % c).is_false()
		assert_bool(b[id].dot.visible).override_failure_message("%s's dot is gone" % c).is_true()
	assert_bool(b[sf_id].dot.visible).is_true()
	# no bubble left over another: none half hidden
	var shown: Array = []
	for id in b:
		if b[id].node.visible: shown.append(Rect2(b[id].node.position, b[id].node.size))
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			assert_bool((shown[i] as Rect2).intersects(shown[j])).is_false()
	rt.session.view = saved

func test_the_city_opened_where_the_player_is_and_home_never_give_way() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var concord := _city("Concord", [37.9, -122.1, 38.1, -121.9])
	var fairfield := _city("Fairfield", [38.2, -122.2, 38.35, -121.95])
	var saved := _travel(rt, _trip(SF, concord, [concord]))
	_look(m, 37.9, -122.0, 6.0)
	m.open_city_card(fairfield)
	rt.ui.close_modal()
	m.city_map._update_bubbles()
	var b: Dictionary = m.city_map.bubbles
	for c in [fairfield, concord, SF]:
		assert_bool(b[str(P0Clusters.region(c).id)].node.visible).override_failure_message("%s gave way" % c).is_true()
	# stacked by priority: the city opened on top, then where the player is, then home; every dot under every bubble
	var top := func(c: String) -> int: return (b[str(P0Clusters.region(c).id)].node as Node).get_index()
	assert_int(top.call(fairfield)).is_greater(top.call(concord))
	assert_int(top.call(concord)).is_greater(top.call(SF))
	var lowest_bubble := INF
	var highest_dot := -INF
	for id in b:
		if b[id].node.visible: lowest_bubble = minf(lowest_bubble, (b[id].node as Node).get_index())
		if b[id].dot.visible: highest_dot = maxf(highest_dot, (b[id].dot as Node).get_index())
	assert_float(highest_dot).is_less(lowest_bubble)
	rt.session.view = saved

## Two bubbles of a bare view (no host lists them): a hidden one comes back 4 px clear, a shown one stays until they
## touch; a dot under a higher bubble draws under it, and a tap there opens the bubble's city.
func test_a_hidden_bubble_comes_back_4_px_clear_and_a_dot_under_a_bubble_gives_it_the_tap() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look(m, 37.5, -120.0, 4.0)   # the country view: bubbles take taps
	var v: Control = m.city_map
	for id in ["q153_a", "q153_b"]: v.bubbles[id] = v._make_bubble(id)
	var a: Dictionary = v.bubbles["q153_a"]
	var b: Dictionary = v.bubbles["q153_b"]
	var states := {"q153_a": {keeps = true, dot_stays = true}, "q153_b": {keeps = false, dot_stays = true}}
	var order := ["q153_a", "q153_b"]
	(a.node as Control).size = Vector2(80, 40)
	(b.node as Control).size = Vector2(80, 40)
	(a.node as Control).position = Vector2(100, 300)
	(a.dot as Control).position = Vector2(135, 289)
	var place := func(gap: float) -> bool:   # b's bubble `gap` px right of a's (negative: overlapping)
		(b.node as Control).position = Vector2(180 + gap, 300)
		(b.dot as Control).position = Vector2(180 + gap + 35, 289)
		for n in [a.node, a.dot, b.node, b.dot]: (n as Control).visible = true
		v._yield_bubbles(order, states)
		return (b.node as Control).visible
	assert_bool(place.call(-1.0)).is_false()
	assert_bool((b.dot as Control).visible).is_true()   # its dot stays
	assert_bool(place.call(2.0)).is_false()   # 2 px clear: not yet
	assert_bool(place.call(4.0)).is_true()
	assert_bool(place.call(1.0)).is_true()   # shown: it holds while they do not touch
	assert_bool(place.call(-1.0)).is_false()
	# b's dot on a's bubble: drawn under it, and the tap there opens a
	(b.node as Control).position = Vector2(100, 500)
	(b.dot as Control).position = Vector2(135, 310)
	for n in [a.node, a.dot, b.node, b.dot]: (n as Control).visible = true
	v._yield_bubbles(order, states)
	assert_int((b.dot as Node).get_index()).is_less((a.node as Node).get_index())
	var asked: Array = []
	for c in v.city_requested.get_connections(): v.city_requested.disconnect(c.callable)
	v.city_requested.connect(func(id): asked.append(str(id)))
	assert_bool(v.activate_bubble_at(v.global_position + Vector2(140, 315))).is_true()
	assert_bool(v.activate_bubble_at(v.global_position + Vector2(140, 515))).is_true()   # b's own bubble, off a's
	assert_array(asked).is_equal(["q153_a", "q153_b"])
	for id in order:
		(v.bubbles[id].node as Node).queue_free()
		(v.bubbles[id].dot as Node).queue_free()
		v.bubbles.erase(id)
	await get_tree().process_frame
