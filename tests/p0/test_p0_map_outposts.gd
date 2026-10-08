extends GdUnitTestSuite
## int6 C30 (李元芳): at the city overview the outpost pins were packed away — behind ponds, landmarks and the
## player's own avatar — so the Travel Post could only be found by zooming in. q(72): P0 does not aggregate; every
## outpost keeps one pin at every zoom, `Lotus Tea House · 3 online` (just the name with no one in). The packing
## order is the selected pin, a pin wearing a map marker (q(48)), outposts, then the rest (蒙恬 on C30), and a tap
## on an outpost pin drawn over the player's avatar opens the outpost (SGODOT-224).

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const NEAREST_POND := "pond_shanghai_05"   # Reed Pond (p0_map.gd)
const OVERVIEW := Vector2(31.228, 121.478)   # assets/map/cities/shanghai.json overview (zoom 12.2, bearing 18)

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

func _look(m: Node, at: Vector2, zoom: float, bearing := 18.0) -> Array:
	m.center_lat = at.x
	m.center_lng = at.y
	m.zoom = zoom
	m.bearing = bearing
	m._update_cameras()
	m._sync_farm_markers()
	var city: CityMapView = m.city_map
	city._update_markers()
	return city.displayed.map(func(mk): return str(mk.entry.id))

func _outposts() -> Array: return P0Outposts.all().map(func(o): return str(o.id))

func test_every_outpost_shows_at_the_city_overview() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	assert_int(_outposts().size()).is_equal(4)
	for zoom in [12.2, 11.5, 13.0]:
		assert_array(_look(m, OVERVIEW, zoom)).append_failure_message("zoom %s" % zoom).contains(_outposts())

## Home sits among three of them (Xuhui) and Reed Pond: the outposts show beside the player's own avatar.
func test_the_outposts_by_home_show_beside_the_players_avatar() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	for zoom in [12.2, 13.0, 14.0]:   # further in, the three are off a phone screen around home
		assert_array(_look(m, Vector2(m.home_lat, m.home_lng), zoom, 0.0)).append_failure_message("zoom %s" % zoom) \
			.contains(["sh_tea_1", "sh_market_1", "sh_tackle_1"])

## The Show on map target (the selected pin) is never packed away: Reed Pond, 200 m from the Tackle Shop.
func test_the_selected_pond_shows_next_to_an_outpost() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var reed: Dictionary = city.entries.filter(func(e): return str(e.id) == NEAREST_POND)[0]
	city.selected = reed   # what select() leaves for the packing (select() also prewarms the pond scene)
	assert_array(_look(m, OVERVIEW, 12.2)).contains([NEAREST_POND, "sh_tackle_1"])
	city.selected = {}

## q(48) markers pack first: of two pins on one spot, the one wearing a marker stays, whatever the id order says.
func test_a_pin_wearing_a_marker_packs_first() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var at := Vector2(m.home_lat + 0.03, m.home_lng + 0.03)   # clear of home and the outposts
	city.entries = []
	city.live_pois = [{"id": "a_shop", "kind": "poi", "name": "A", "lat": at.x, "lng": at.y, "art": "shop", "rank": 1},
		{"id": "z_shop", "kind": "poi", "name": "Z", "lat": at.x, "lng": at.y, "art": "shop", "rank": 1, "marker": "request"}]
	assert_array(_look(m, at, 15.0)).contains_exactly(["z_shop"])
	city.live_pois[1].erase("marker")
	city._shown_last.clear()
	assert_array(_look(m, at, 15.0)).contains_exactly(["a_shop"])   # without it the id order decides

## q(72): the name with the people in, just the name with no one.
func test_an_outpost_pin_says_who_is_in() -> void:
	var tea := P0Outposts.by_role("tea")
	var m := _map()
	for i in 3: await get_tree().process_frame
	var city: CityMapView = m.city_map
	assert_str(city._label_text(P0Outposts.place_entry(tea, 3))).is_equal("Lotus Tea House · 3 online")
	assert_str(city._label_text(P0Outposts.place_entry(tea, 0))).is_equal("Lotus Tea House")

## An outpost pin drawn over the player's avatar takes the tap (蒙恬 on C30): it is selected, not the avatar.
func test_a_tap_on_an_outpost_over_the_avatar_opens_the_outpost() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)
	var city: CityMapView = m.city_map
	var tea: Dictionary = city.displayed.filter(func(mk): return str(mk.entry.id) == "sh_tea_1")[0]
	var screen: Vector2 = (tea.anchor as Vector2) + Vector2(0, -20) + city.global_position   # on its artwork
	assert_bool(city.activate_place_at(screen)).is_true()
	assert_str(str(city.selected.get("id", ""))).is_equal("sh_tea_1")
	assert_bool(city.activate_place_at(Vector2(4, 4))).is_false()   # nowhere near an outpost

func _labels(m: Node) -> Dictionary:   # outpost id -> its label, for the outposts on screen
	var out := {}
	for mk in (m.city_map as CityMapView).displayed:
		if mk.entry.kind == "place": out[str(mk.entry.id)] = mk.label
	return out

## 不知火舞 on C30: outpost labels never overlap; the one nearest home keeps its label, the others fold only their
## label (the pin stays) and come back once zooming in parts them.
func test_outpost_labels_never_overlap_and_the_nearest_home_keeps_its_label() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var home := Vector2(m.home_lat, m.home_lng)
	var by_home: Array = P0Outposts.all().duplicate()
	by_home.sort_custom(func(a, b): return city._home_distance(a) < city._home_distance(b))
	var shown_at := {}
	for zoom in [12.2, 13.0, 14.0, 15.0]:
		_look(m, home, zoom, 0.0)
		var labels := _labels(m)
		# Every pin on screen stays (the far Travel Post leaves the screen from z14 on).
		assert_array(labels.keys()).append_failure_message("zoom %s" % zoom).contains(["sh_tea_1", "sh_market_1", "sh_tackle_1"])
		var rects: Array = city._place_labels
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				assert_bool((rects[i] as Rect2).intersects(rects[j])).append_failure_message("zoom %s" % zoom).is_false()
		assert_int(rects.size()).is_equal(labels.values().filter(func(l): return (l as Label).visible).size())
		assert_bool((labels[str(by_home[0].id)] as Label).visible).append_failure_message("zoom %s" % zoom).is_true()
		shown_at[zoom] = ["sh_tea_1", "sh_market_1", "sh_tackle_1"].filter(func(id): return (labels[id] as Label).visible).size()
	# Zooming in parts them: the three by home get their names back.
	assert_int(int(shown_at[15.0])).is_greater(int(shown_at[12.2]))

## q(72) / 不知火舞 on C30: the whole name and who is in, never cut; a selected outpost's label always shows.
func test_an_outpost_label_is_whole_and_shows_when_selected() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.set_places(P0Outposts.all().map(func(o): return P0Outposts.place_entry(o, 3 if str(o.role) == "tea" else 0)))
	_look(m, Vector2(m.home_lat, m.home_lng), 14.0, 0.0)
	var tea: Label = _labels(m)["sh_tea_1"]
	assert_str(tea.text).is_equal("Lotus Tea House · 3 online")
	assert_int(tea.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	var font := tea.get_theme_font("font")
	assert_float(tea.size.x).is_greater_equal(font.get_string_size(tea.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x)
	assert_str(_labels(m)["sh_market_1"].text).is_equal("Xuhui Market Square")
	# Selected, a folded label comes back (the city overview folds all but one by home).
	_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)
	var folded: Array = _labels(m).keys().filter(func(id): return not (_labels(m)[id] as Label).visible)
	assert_bool(folded.is_empty()).is_false()
	city.selected = city.entries.filter(func(e): return str(e.id) == str(folded[0]))[0]
	_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)
	assert_bool((_labels(m)[str(folded[0])] as Label).visible).is_true()
	city.selected = {}

## 不知火舞 on C30: outpost pins draw in front of the player's own 3D avatar (no depth test), under a selected pin.
func test_outpost_pins_draw_over_the_avatar() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)
	var city: CityMapView = m.city_map
	var tea: Sprite3D = city.markers["sh_tea_1"].sprite
	assert_bool(tea.no_depth_test).is_true()
	assert_int(tea.render_priority).is_equal(CityMapView.PLACE_PRIORITY)
	city._set_marker_front("sh_tea_1", true)
	assert_int(tea.render_priority).is_equal(2)
	city._set_marker_front("sh_tea_1", false)
	assert_int(tea.render_priority).is_equal(CityMapView.PLACE_PRIORITY)

## 不知火舞 on C30: My Farm's label gives way to an outpost label it touches; it is back when they part.
func test_my_farm_label_gives_way_to_an_outpost_label() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var fm: FarmMarkers = m.farm_markers
	var city: CityMapView = m.city_map
	var home := Vector2(m.home_lat, m.home_lng)
	var outposts: Array = P0Outposts.all().map(func(o): return P0Outposts.place_entry(o))
	# An outpost right at home: its label sits where My Farm's does.
	var here := P0Outposts.place_entry(P0Outposts.by_role("tea"))
	here.merge({"id": "test_here", "lat": home.x, "lng": home.y}, true)
	city.set_places(outposts + [here])
	_look(m, home, 15.0, 0.0)
	assert_bool((_labels(m)["test_here"] as Label).visible).is_true()
	assert_bool(fm.self_label_yields).is_true()
	assert_bool(fm._buttons["self"].visible).is_false()
	fm.sync(m.cam, m.anchor_lat, m.anchor_lng, Rect2(0, 0, 360, 800))   # the next frame's sync keeps it down
	assert_bool(fm._buttons["self"].visible).is_false()
	city.set_places(outposts)   # gone: My Farm says its name again
	_look(m, home, 15.0, 0.0)
	assert_bool(fm.self_label_yields).is_false()
	assert_bool(fm._buttons["self"].visible).is_true()
