extends GdUnitTestSuite
## MAP-8 Nearby cities (§11.8.1; the user on 10-13: this one page, the other three with P2; 不知火舞's rows): the ten
## clusters nearest home the save froze (travel.fallback.near10), nearest first, each with its name and state (the
## server's travel.admins, else its country), distance, trip tier, climate band, visited / stamped and landmark art. A
## row's tap closes the sheet and flies to the city, its card opening.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const P0ArrivalCard := preload("res://modules/p0/p0_arrival_card.gd")
const SF := "gn-5391959"
const LA := "gn-5368361"
const SALINAS := "gn-5391295"
const CONCORD := "gn-5339111"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _travel(extra := {}) -> Dictionary:
	var t := {home = SF, here = SF, passes = {}, visits = {}, stamps = [], explorer = 0,
		fallback = {near3 = [CONCORD, SALINAS, LA], near10 = [LA, CONCORD, SALINAS]}, admins = {SALINAS: "California"}}
	t.merge(extra, true)
	return {"now": 1_000_000_000.0, "travel": t}

func test_the_rows_come_nearest_first_with_what_the_sheet_shows() -> void:
	var view := _travel({visits = {LA: {n = 2}}, stamps = [{cluster = LA, kind = "landmark", at = 1.0, counted_on = "d"}]})
	var rows: Array = P0Travel.nearby(view)
	assert_array(rows.map(func(r): return str(r.cluster))).is_equal([CONCORD, SALINAS, LA])   # by km, not the list's order
	var concord: Dictionary = rows[0]
	assert_str(str(concord.name)).is_equal("Concord")
	assert_str(str(concord.region)).is_equal("United States")   # no state sent: its country
	assert_bool(concord.visited).is_false()
	assert_bool(concord.stamped).is_false()
	assert_str(str(concord.landmark)).is_empty()   # no landmark: its climate band
	assert_str(str(concord.climate)).is_equal("Temperate")
	var salinas: Dictionary = rows[1]
	assert_str(str(salinas.region)).is_equal("California")
	var t: Dictionary = P0Travel.trip(view, SALINAS)
	assert_int(int(salinas.km)).is_equal(int(t.km))
	assert_int(int(salinas.trip)).is_equal(int(t.trip))
	assert_str(str(salinas.trip_name)).is_equal(str(t.name))
	assert_bool(int(salinas.km) > int(concord.km)).is_true()
	var la: Dictionary = rows[2]
	assert_bool(la.visited).is_true()
	assert_bool(la.stamped).is_true()
	assert_str(str(la.landmark)).is_equal(P0Travel.landmark_stamp(LA))
	assert_str(str(la.landmark)).is_not_empty()   # Hollywood Sign (travel.landmarks)
	assert_array(P0Travel.nearby({})).is_empty()

func test_a_rows_tap_closes_the_sheet_and_opens_the_citys_card() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var m := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(m)
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v.merge(_travel(), true)
	rt.session.view = v
	P0ArrivalCard.open(rt.ui, {"title": "Nearby cities"}, func(): pass, "nearby")   # the sheet stand-in, until its frames
	assert_str(rt.ui.modal_kind).is_equal("nearby")
	m.open_nearby_city(SALINAS)
	assert_str(rt.ui.modal_kind).is_equal("city_card")   # unexplored: its silhouette card
	assert_str(m._card_city).is_equal(SALINAS)
	rt.ui.close_modal()
	rt.session.view = saved
