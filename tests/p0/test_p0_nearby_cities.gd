extends GdUnitTestSuite
## MAP-8 Nearby cities (§11.8.1; the user on 10-13: this one page, the other three with P2; 不知火舞's rows): the ten
## clusters nearest home the save froze (travel.fallback.near10), nearest first, each with its name and state (the
## server's travel.admins, else its country), distance, trip tier, climate band, visited / stamped and landmark art. A
## row's tap closes the sheet and flies to the city, its card opening.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
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

## q(208) ①: the server's travel.regions is the row's second part as shown — taken as it is, an empty one included
## (`Singapore`, no second part); a city it does not list falls back as before.
func test_the_servers_region_is_taken_as_it_is() -> void:
	var view := _travel({regions = {CONCORD: "California", LA: ""}})
	var rows: Array = P0Travel.nearby(view)
	assert_array(rows.map(func(r): return str(r.region))).is_equal(["California", "California", ""])

## q(210) ⑤: a server from before sends no regions — the row falls back to the country as P0Clusters writes it (CLDR's
## name, none for a city-only place), not the directory's own spelling.
func test_with_no_regions_the_row_writes_the_country_the_game_way() -> void:
	var view := _travel({admins = {}, fallback = {near3 = [], near10 = ["gn-745044", "gn-1668341"]}})
	var rows: Array = P0Travel.nearby(view)
	var by := {}
	for r in rows: by[str(r.cluster)] = str(r.region)
	assert_str(str(by["gn-745044"])).is_equal("Türkiye")   # Istanbul
	assert_str(str(by["gn-1668341"])).is_equal("")          # Taipei

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var m := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(m)
	return m

## MAP-8-ENTRY (2539:130770): the pill sits bottom left in Bag's row — 12 in, 196 × 44, 10 under the quick bar's top —
## and gives way to an open sheet as the right-hand keys do.
func test_the_pill_sits_in_bags_row_and_gives_way_to_a_sheet() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	m.p0_frame(rt.session.view, 0.0)
	var key: Button = m.nearby_key
	assert_object(key).is_not_null()
	assert_bool(key.visible).is_true()
	assert_vector(key.size).is_equal(Vector2(196, 44))
	assert_float(key.global_position.x).is_equal(12.0)
	assert_float(key.global_position.y).is_equal_approx(rt.ui.open_marker_area().end.y + 10.0, 0.01)   # the bar's top + 10
	assert_str((key.get_node("Words") as Label).text).is_equal("Nearby cities ›")
	assert_bool(m.bubble_clear_rects().any(func(r): return (r as Rect2).is_equal_approx(key.get_global_rect()))).is_true()
	P0ArrivalCard.open(rt.ui, {"title": "a card"}, func(): pass, "city_card")
	m.p0_frame(rt.session.view, 0.0)
	assert_bool(key.visible).is_false()
	rt.ui.close_modal()

## The pill opens the drawer — `Nearby cities`, `From San Francisco · …`, a row per city nearest first, the Close 44 —
## and a row's tap closes it and flies to that city, its card opening.
func test_the_pill_opens_the_drawer_and_a_row_flies_to_its_city() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v.merge(_travel(), true)
	rt.session.view = v
	rt.ui.set_view(v)
	m.nearby_key.pressed.emit()
	assert_str(rt.ui.modal_kind).is_equal("nearby")
	var drawer := rt.ui.root.find_children("*", "UiDrawer", true, false)[0] as UiDrawer
	assert_float(drawer.height).is_equal(447.0)
	assert_str((drawer.find_child("Title", true, false) as Label).text).is_equal("Nearby cities")
	assert_str((drawer.find_child("Subtitle", true, false) as Label).text).is_equal("From San Francisco · tap a city to see it on the map")
	var rows: Array = (drawer.find_child("Cities", true, false) as Node).get_children()
	assert_array(rows.map(func(r): return str((r as Node).get("row").cluster))).is_equal([CONCORD, SALINAS, LA])
	var salinas: Button = rows[1]
	salinas.pressed.emit()
	assert_str(rt.ui.modal_kind).is_equal("city_card")   # unexplored: its silhouette card, the drawer gone
	assert_str(m._card_city).is_equal(SALINAS)
	rt.ui.close_modal()
	rt.session.view = saved
	rt.ui.set_view(saved)

# ---------------------------------------------------------------- the row (CityRow, Figma row 85)
const CityRow := preload("res://scenes/p0/panels/p0_city_row.gd")

func _row(r: Dictionary) -> Button:
	var row: Button = CityRow.new(r)
	add_child(auto_free(row))
	return row

## Visited with a landmark (Los Angeles): the art as it is on its band's ground, its city stamp in the slot. Visited
## without one (San Jose): the band's glyph in its colour, the passport's seal. Never visited: grey ground, the art at
## saturation 0 or the glyph #A9ACA6, a dashed slot. The third line's glyph keeps its colour either way.
func test_a_row_reads_visited_landmark_seal_and_never_visited() -> void:
	var base := {cluster = "x", name = "San Jose", region = "California", km = 68, trip = 2, trip_name = "Nearby",
		climate = "Temperate", visited = true, stamped = true, landmark = ""}
	var sj := _row(base)
	assert_str((sj.find_child("Name", true, false) as Label).text).is_equal("San Jose")
	assert_str((sj.find_child("Region", true, false) as Label).text).is_equal(" · California")
	assert_str((sj.find_child("Trip", true, false) as Label).text).is_equal("68 km · Trip 2 · Nearby")
	assert_that((sj.get("thumb").get_theme_stylebox("panel") as StyleBoxFlat).bg_color).is_equal(Color("E3EFD9"))
	var art: ShaderMaterial = sj.get("thumb_art").material
	assert_int(int(art.get_shader_parameter(&"mode"))).is_equal(1)
	assert_that(art.get_shader_parameter(&"tint")).is_equal(Color("5E8C4A"))
	assert_str(str(sj.get("slot").get("kind"))).is_equal("seal")
	assert_bool(sj.get("thumb_art").texture != null).is_true()   # i-climate-temperate
	var la := _row(base.merged({name = "Los Angeles", climate = "Subtropical", landmark = P0Travel.landmark_stamp(LA)}, true))
	assert_that((la.get("thumb").get_theme_stylebox("panel") as StyleBoxFlat).bg_color).is_equal(Color("FBE7C6"))
	assert_int(int((la.get("thumb_art").material as ShaderMaterial).get_shader_parameter(&"mode"))).is_equal(0)
	assert_str(str(la.get("slot").get("kind"))).is_equal("landmark")
	var away := _row(base.merged({visited = false, stamped = false, landmark = P0Travel.landmark_stamp(LA)}, true))
	assert_that((away.get("thumb").get_theme_stylebox("panel") as StyleBoxFlat).bg_color).is_equal(Color("ECEBE6"))
	assert_int(int((away.get("thumb_art").material as ShaderMaterial).get_shader_parameter(&"mode"))).is_equal(2)
	assert_str(str(away.get("slot").get("kind"))).is_equal("empty")
	var glyph_away := _row(base.merged({visited = false, climate = "Tropical"}, true))
	assert_that((glyph_away.get("thumb_art").material as ShaderMaterial).get_shader_parameter(&"tint")).is_equal(Color("A9ACA6"))
	var line_glyph: TextureRect = glyph_away.find_child("Glyph", true, false)
	assert_that((line_glyph.material as ShaderMaterial).get_shader_parameter(&"tint")).is_equal(Color("2E8A6E"))   # coloured anyway
	for band in ["temperate", "subtropical", "tropical", "cool"]: assert_object(GameUi.icon("i-climate-" + band)).is_not_null()
	assert_object(GameUi.icon("i-stamp-seal")).is_not_null()
	assert_float(sj.custom_minimum_size.y).is_equal(72.0)

## A long name (周瑜 on #361: 272 clusters run to 20 letters or more) in the drawer's 328: the state gives way, the name
## ends in an ellipsis, and the slot and the `›` stay inside the row. A short one keeps its state beside it.
func test_a_long_name_hides_the_state_and_keeps_the_slot_in() -> void:
	var long := _row({cluster = "gn-3651297", name = "Santo Domingo de los Colorados", region = "Santo Domingo de los Tsáchilas",
		km = 4021, trip = 6, trip_name = "Long Haul", climate = "Tropical", visited = false, stamped = false, landmark = ""})
	var short := _row({cluster = "x", name = "San Jose", region = "California", km = 68, trip = 2, trip_name = "Nearby",
		climate = "Temperate", visited = true, stamped = true, landmark = ""})
	for row in [long, short]: (row as Control).size = Vector2(328, 72)
	for i in 3: await get_tree().process_frame
	for row in [long, short]:
		var edge := (row as Control).get_global_rect().end.x
		assert_float(edge).is_equal(328.0)
		assert_bool((row.get("slot") as Control).get_global_rect().end.x <= edge).is_true()
		assert_bool((row.find_child("Chevron", true, false) as Control).get_global_rect().end.x <= edge).is_true()
	assert_bool((long.find_child("Region", true, false) as Label).visible).is_false()
	var name_l: Label = long.find_child("Name", true, false)
	assert_int(name_l.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	var full := name_l.get_theme_font(&"font").get_string_size(name_l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_l.get_theme_font_size(&"font_size")).x
	assert_bool(name_l.size.x < full).is_true()   # cut, with its ellipsis
	assert_bool(name_l.get_global_rect().end.x <= (long.get("slot") as Control).get_global_rect().position.x).is_true()
	assert_int((long.find_child("Trip", true, false) as Label).text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	var region: Label = short.find_child("Region", true, false)
	assert_bool(region.visible).is_true()
	var sj: Label = short.find_child("Name", true, false)
	assert_float(region.get_global_rect().position.x).is_equal_approx(sj.get_global_rect().end.x, 0.01)   # straight after the name

## q(210): the travel card's title writes the country as the city rows do — CLDR's English name, and the city alone for
## the places that read it alone and for a name that holds its country (q(209) ②).
func test_the_travel_cards_title_writes_the_country_as_the_rows_do() -> void:
	var title := func(id: String) -> String: return load("res://scenes/p0/p0_map.gd").travel_title(P0Clusters.get_cluster(id))
	assert_str(title.call("gn-745044")).is_equal("Istanbul, Türkiye")
	assert_str(title.call("gn-1668341")).is_equal("Taipei")   # q(210) ③ (b)
	assert_str(title.call("gn-3530597")).is_equal("Mexico City")   # q(209) ②
	assert_str(title.call("gn-1819729")).is_equal("Hong Kong")
	assert_str(title.call("gn-2643743")).is_equal("London, United Kingdom")
	assert_str(title.call("gn-693805")).is_equal("Simferopol")   # q(211), a disputed city by id
	assert_bool(P0Clusters.names_country("Iranshahr", "Iran")).is_false()
	assert_bool(P0Clusters.names_country("Santiago de Cuba", "Cuba")).is_true()
	assert_bool(P0Clusters.names_country("Kinshasa", "Congo (DRC)")).is_false()
