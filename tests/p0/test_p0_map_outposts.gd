extends GdUnitTestSuite
## int6 C30 (李元芳): at the city overview the outpost pins were packed away — behind ponds, landmarks and the
## player's own avatar — so the Travel Post could only be found by zooming in. q(72): P0 does not aggregate; every
## outpost keeps one pin at every zoom, `Lotus Tea House · 3 online` (just the name with no one in). The packing
## order is the selected pin, a pin wearing a map marker (q(48)), outposts, then the rest (蒙恬 on C30), and a tap
## on an outpost pin drawn over the player's avatar opens the outpost (SGODOT-224).

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const NEAREST_POND := "pond_shanghai_05"   # Reed Pond (p0_map.gd)

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	# The player starts at home: a pond or outpost world attached by another suite leaves P0Runtime.here there, and
	# away from home the avatar stands at that place (SGODOT-234 A2).
	P0Runtime.ensure().here = {"space": "home", "place": ""}

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

## q(72) / C30: at city level every outpost keeps its pin, never packed away behind ponds, landmarks or the avatar.
## Asserted on screen (奕星 on 234 A2), not in the packing margin: around the four outposts, each one inside the city
## view is displayed, and z11.5 holds all four. (P0 has no city-overview flight; the opening view is the home set.)
func test_every_outpost_on_screen_keeps_its_pin_at_city_level() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	assert_int(_outposts().size()).is_equal(4)
	var city: CityMapView = m.city_map
	var mid := Vector2.ZERO
	for o in P0Outposts.all(): mid += Vector2(float(o.lat), float(o.lng))
	mid /= 4.0
	for zoom in [11.5, 12.2, 13.0]:
		var shown := _look(m, mid, zoom, 0.0)
		var view := Rect2(city.global_position, city.size)
		var on_screen: Array = P0Outposts.all().filter(func(o):
			var p = m.geo_to_screen(float(o.lat), float(o.lng))
			return p != null and view.has_point(p)).map(func(o): return str(o.id))
		if zoom == 11.5: assert_array(on_screen).append_failure_message("z11.5 holds all four").contains_exactly_in_any_order(_outposts())
		assert_array(shown).append_failure_message("zoom %s" % zoom).contains(on_screen)

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
	assert_array(_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)).contains([NEAREST_POND, "sh_tackle_1"])   # on screen
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

func _labels(m: Node) -> Dictionary:   # outpost id -> its pin (MapDestination: its name under the disc), on screen
	var out := {}
	for mk in (m.city_map as CityMapView).displayed:
		if mk.entry.kind == "place": out[str(mk.entry.id)] = mk.get("dest", mk.label)
	return out

static func _dest_label_rect(marker: Dictionary) -> Rect2:   # a MapDestination's name, in the city view, as drawn
	var pin: UiMapDestination = marker.dest
	if not pin.name_shown: return Rect2()
	var box: Control = pin._label_box
	var k: Vector2 = (marker.node as Control).scale   # a selected pin is drawn scaled about its point (SGODOT-261)
	return Rect2((marker.anchor as Vector2) + (pin.position + box.position) * k, box.size * k)

static func _shown(pin: Control) -> bool:   # whether the pin says its name
	return (pin as UiMapDestination).name_shown if pin is UiMapDestination else pin.visible

## 不知火舞 on C30: outpost labels never overlap; the one nearest home keeps its label, the others fold only their
## label (the pin stays) and come back once zooming in parts them.
func test_outpost_labels_never_overlap_and_the_nearest_home_keeps_its_label() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	# Outposts among themselves: after the tutorial, so Reed Pond wears no marker that packs before them.
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(-1)
	var home := Vector2(m.home_lat, m.home_lng)
	var by_home: Array = P0Outposts.all().duplicate()
	by_home.sort_custom(func(a, b): return city._home_distance(a) < city._home_distance(b))
	var shown_at := {}
	for zoom in [11.5, 12.3, 13.3, 13.8]:   # phone geometry (P0Map._map_logical_height); 13.8 the opening view
		_look(m, home, zoom, 0.0)
		var labels := _labels(m)
		# Every pin on screen stays (the far Travel Post leaves the screen from z13.3 on).
		assert_array(labels.keys()).append_failure_message("zoom %s" % zoom).contains(["sh_tea_1", "sh_market_1", "sh_tackle_1"])
		var rects: Array = city._place_labels
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				assert_bool((rects[i] as Rect2).intersects(rects[j])).append_failure_message("zoom %s" % zoom).is_false()
		assert_int(rects.size()).is_equal(labels.values().filter(func(l): return _shown(l)).size())
		assert_bool(_shown(labels[str(by_home[0].id)])).append_failure_message("zoom %s" % zoom).is_true()
		shown_at[zoom] = ["sh_tea_1", "sh_market_1", "sh_tackle_1"].filter(func(id): return _shown(labels[id])).size()
	# Zooming in parts them: the three by home get their names back.
	assert_int(int(shown_at[13.8])).is_greater(int(shown_at[11.5]))
	rt.session.view = saved

## q(72) / 不知火舞 on C30: the whole name and who is in, never cut; a selected outpost's label always shows.
func test_an_outpost_label_is_whole_and_shows_when_selected() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.set_places(P0Outposts.all().map(func(o): return P0Outposts.place_entry(o, 3 if str(o.role) == "tea" else 0)))
	_look(m, Vector2(m.home_lat, m.home_lng), 14.0, 0.0)
	var tea: UiMapDestination = _labels(m)["sh_tea_1"]
	assert_str(tea.text).is_equal("Lotus Tea House · 3 online")
	assert_float(tea.label_size().x).is_greater_equal(UiMapDestination.label_size_for(tea.text).x)   # the whole name
	assert_str(_labels(m)["sh_market_1"].text).is_equal("Xuhui Market Square")
	# Selected, a folded label comes back (the city overview folds all but one by home).
	_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)
	var folded: Array = _labels(m).keys().filter(func(id): return not _shown(_labels(m)[id]))
	assert_bool(folded.is_empty()).is_false()
	city.selected = city.entries.filter(func(e): return str(e.id) == str(folded[0]))[0]
	_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)
	assert_bool(_shown(_labels(m)[str(folded[0])])).is_true()
	city.selected = {}

## 不知火舞 on C30 / 234: outpost and pond pins draw in front of the player's own 3D avatar — MapDestination is 2D over
## the map — with a selected pin in front of the others.
func test_outpost_pins_draw_over_the_avatar() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)
	var city: CityMapView = m.city_map
	var tea: Dictionary = city.markers["sh_tea_1"]
	assert_bool(tea.has("sprite")).is_false()
	assert_object(tea.dest).is_instanceof(UiMapDestination)
	assert_bool((tea.node as Node).is_ancestor_of(tea.dest)).is_true()
	city._set_marker_front("sh_tea_1", true)
	var top := 0
	for mk in city.markers.values(): top = maxi(top, (mk.node as Node).get_index())
	assert_int((tea.node as Node).get_index()).is_equal(top)   # in front of the other pins
	city._set_marker_front("sh_tea_1", false)

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
	assert_bool(_shown(_labels(m)["test_here"])).is_true()
	assert_bool(fm.self_label_yields).is_true()
	assert_bool(fm._buttons["self"].visible).is_false()
	fm.sync(m.cam, m.anchor_lat, m.anchor_lng, Rect2(0, 0, 360, 800))   # the next frame's sync keeps it down
	assert_bool(fm._buttons["self"].visible).is_false()
	city.set_places(outposts)   # gone: My Farm says its name again
	_look(m, home, 15.0, 0.0)
	assert_bool(fm.self_label_yields).is_false()
	assert_bool(fm._buttons["self"].visible).is_true()

## The stall board of a view: Pond Catch taken with `have` of its 2 fish caught, or handed in (-1: not on the board).
func _board(have: int, status := "accepted") -> Dictionary:
	var reqs: Array = [] if have < 0 else [{"id": P0Guide.TUTORIAL, "have": have, "qty": 2, "status": status}]
	return {"stall": {"board": {"requests": reqs}}, "req_done": [P0Guide.TUTORIAL] if have < 0 else []}

## 蒙恬 on #83: the first session's map (minutes 5–9: the chip → the map → Reed Pond) opens at the city level with
## nothing selected; while the tutorial Pond Catch is taken and short of its fish, Reed Pond wears the Request !
## (q(48); untaken it marks no pond, q(103)) and shows beside the Tackle Shop 200 m away, over the player's avatar, its label whole and clear of My
## Farm's (不知火舞 on #83). With the fish caught (off to the stall) or the request handed in, it packs as a pond again.
func test_the_beginner_pond_shows_at_the_city_level_until_pond_catch_is_handed_in() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var fm: FarmMarkers = m.farm_markers
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(0, "open")
	assert_dict(m.city_pin_markers()).is_empty()   # not taken yet: its ! is the stall's (q(103))
	rt.session.view = _board(0)
	assert_dict(m.city_pin_markers()).is_equal({NEAREST_POND: "request"})
	rt.session.view = _board(1)
	assert_dict(m.city_pin_markers()).is_equal({NEAREST_POND: "request"})
	assert_dict(city.selected).is_empty()
	# On screen (phone geometry): around home at the city level, and the opening view the first session gets.
	assert_array(_look(m, Vector2(m.home_lat, m.home_lng), 12.2, 0.0)).contains([NEAREST_POND, "sh_tackle_1"])
	m.frame_home_set()
	assert_array(m.framed.map(func(it): return str(it.get("id", "self")))).contains([NEAREST_POND, "sh_tackle_1"])
	m._sync_farm_markers()
	city._update_markers()
	# A MapDestination (SGODOT-234 A2): 2D over the map, so over the player's avatar.
	var reed: UiMapDestination = city.markers[NEAREST_POND].dest
	# Its name is written whole: the first session finds its way by it.
	assert_bool(reed.name_shown).is_true()
	assert_str(reed.text).is_equal(city._label_text(city.markers[NEAREST_POND].entry))
	assert_float(reed.label_size().x).is_greater_equal(UiMapDestination.label_size_for(reed.text).x)
	# My Farm's label never sits on it, measured as drawn — scaled about its pivot by the zoom boost (1.21 at z12.2), the
	# 5 px 不知火舞 saw past its unscaled rect on the overview. Home at z12.2 and the opening view, both on screen.
	for zoom in [12.2, m.zoom]:
		var at := Vector2(m.home_lat, m.home_lng) if zoom == 12.2 else Vector2(m.center_lat, m.center_lng)
		_look(m, at, zoom, 0.0)
		var label: Button = fm._buttons["self"]
		var b := fm._pin_zoom_boost()
		assert_float(b).is_greater(1.0)
		var steady := Rect2(label.position + label.pivot_offset * (1.0 - b), label.size * b)   # how it draws at rest
		var own: Rect2 = fm.self_label_rect()
		assert_bool(own.encloses(steady)).is_true()
		own.position += fm.global_position - city.global_position
		var reed_label := _dest_label_rect(city.markers[NEAREST_POND])
		assert_bool(label.visible and own.intersects(reed_label)).append_failure_message("z%.1f" % zoom).is_false()
	# Both fish in the bag (the target is now the stall), or handed in: no marker, a pond like any other.
	for gone in [_board(2), _board(-1)]:
		rt.session.view = gone
		assert_dict(m.city_pin_markers()).is_empty()
		var home := Vector2(m.home_lat, m.home_lng)
		assert_array(_look(m, home, 12.2, 0.0)).not_contains([NEAREST_POND])   # 200 m from the Tackle Shop: it gives way
		# Drawn like any pond when it shows again: a MapDestination over the avatar, its name whole (LOCK-24).
		assert_bool(city._over_avatar(city.markers[NEAREST_POND].entry)).is_true()
		assert_bool(city._whole_label(city.markers[NEAREST_POND].entry)).is_true()
	rt.session.view = saved

## Once the server sends map_markers (蒙恬, SGODOT-232 U6), the pins pack by them, not by the client's tutorial mark.
func test_the_pin_markers_follow_the_servers_map_markers_once_it_sends_them() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var v := _board(0)
	v["map_markers"] = [{"place": "sh_market_1", "kind": "deliver"}, {"place": "sh_market_1", "kind": "new"}]
	rt.session.view = v
	assert_dict(m.city_pin_markers()).is_equal({"sh_market_1": "deliverable"})   # its first mark; no tutorial !
	rt.session.view = saved

## q(80): the card of the pond the player is at drops Distance and reads Back to <pond>; another pond's reads Go.
func test_the_pond_card_reads_back_to_at_the_pond_the_player_is_at() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.here
	rt.here = {"space": "pond", "place": NEAREST_POND}
	m.p0_dev(PackedStringArray(["pondcard", NEAREST_POND]))
	var card: Control = rt.ui._modal
	assert_str(rt.ui.modal_kind).is_equal("pond_card")
	assert_str((card.find_child("Primary", true, false) as UiCommandButton).label).is_equal("Back to Reed Pond")
	assert_array(card.find_children("*", "UiFactRow", true, false).map(func(f): return str((f as UiFactRow).label))).not_contains(["Distance"])
	rt.ui.close_modal()
	await get_tree().process_frame
	rt.here = {"space": "home", "place": ""}
	m.p0_dev(PackedStringArray(["pondcard", NEAREST_POND]))
	card = rt.ui._modal
	assert_str((card.find_child("Primary", true, false) as UiCommandButton).label).is_equal("Go")
	assert_array(card.find_children("*", "UiFactRow", true, false).map(func(f): return str((f as UiFactRow).label))).contains(["Distance"])
	rt.ui.close_modal()
	await get_tree().process_frame
	rt.here = saved
	_drain_shore()

## Back and a tap outside on the fish list go back to the pond card like its × (哪吒 on #95; the layered way back of
## #37 / #87), the pin still selected; from the card they close it and clear the selection.
func test_back_on_the_fish_list_goes_back_to_the_pond_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var city: CityMapView = m.city_map
	var details := func():   # the card's own Details ›, as a tap
		(rt.ui._modal.find_child("Details", true, false) as Button).pressed.emit()
		await get_tree().process_frame
	m.p0_dev(PackedStringArray(["pondcard", NEAREST_POND]))
	await details.call()
	assert_str(rt.ui.modal_kind).is_equal("pond_fish")
	assert_bool(rt.ui.close_top_layer()).is_true()   # Android Back
	await get_tree().process_frame
	assert_str(rt.ui.modal_kind).is_equal("pond_card")
	assert_str(str(city.selected.get("id", ""))).is_equal(NEAREST_POND)
	await details.call()
	rt.ui.back_modal()   # a tap outside
	await get_tree().process_frame
	assert_str(rt.ui.modal_kind).is_equal("pond_card")
	assert_str(str(city.selected.get("id", ""))).is_equal(NEAREST_POND)
	assert_bool(rt.ui.close_top_layer()).is_true()   # Back from the card closes it
	await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_false()
	assert_dict(city.selected).is_empty()
	_drain_shore()

## Selecting a pond pin prewarms its bank on a worker thread (WaterShore.prewarm): a test that opens a pond card waits
## for it, else the detached bank counts as an orphan and the thread is still running when the engine shuts down.
static func _drain_shore() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

## MapDestination 1795:103793 (不知火舞 on 234): outposts by role — tea pot, tackle rod, market board, post travel —,
## ponds, and the Homestead pin with its name on a plate; landmarks and POIs keep the city view's own pins.
func test_destination_pins_wear_their_icons() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var icons := {"tea": "pot", "tackle": "rod", "market": "board", "post": "travel"}
	for role in icons:
		var style: Dictionary = m._destination_style(P0Outposts.place_entry(P0Outposts.by_role(role)))
		assert_object(style.icon).append_failure_message(role).is_same(P0Logic.icon(icons[role]))
		assert_bool(bool(style.get("plate", false))).is_false()
	assert_object(m._destination_style({"kind": "pond", "id": NEAREST_POND}).icon).is_same(P0Logic.icon("pond"))
	var home: Dictionary = m._destination_style(m.home_entry())
	assert_object(home.icon).is_same(P0Logic.icon("home"))
	assert_bool(bool(home.plate)).is_true()
	assert_dict(m._destination_style({"kind": "landmark", "id": "x"})).is_empty()
	assert_dict(m._destination_style({"kind": "poi", "id": "x"})).is_empty()

## SGODOT-261 (用户 via 奕星): a selected MapDestination grows with the jelly every pin plays (it used to keep its size,
## Figma 1802:118612); Today's Show pulse still scales only its disc. test_p0_map_space_pins plays them frame by frame.
func test_a_selected_destination_grows_and_a_pulse_scales_its_disc() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look(m, Vector2(m.home_lat, m.home_lng), 14.0, 0.0)
	var city: CityMapView = m.city_map
	var tea: Dictionary = city.markers["sh_tea_1"]
	if tea.get("pop_tween") is Tween: (tea.pop_tween as Tween).kill()
	tea.pop = 1.0   # settled in (it may still be popping in)
	tea.focus = CityMapView.FOCUS_SCALE
	tea.pulse = false   # the selection jelly (_animate_focus)
	city.selected = tea.entry
	city._apply_marker_scale(tea)
	assert_float((tea.node as Control).scale.x).is_equal_approx(CityMapView.FOCUS_SCALE, 1e-6)   # the whole pin
	assert_float((tea.dest as UiMapDestination).focus).is_equal_approx(1.0, 1e-6)
	city.selected = {}
	tea.focus = 1.18
	tea.pulse = true   # Show on map (pulse_pin)
	city._apply_marker_scale(tea)
	assert_float((tea.dest as UiMapDestination).focus).is_equal_approx(1.18, 1e-6)
	assert_float((tea.node as Control).scale.x).is_equal_approx(1.0, 1e-6)   # the name keeps its size
	tea.focus = 1.0
	tea.pulse = false
	city._apply_marker_scale(tea)

## A selected pin's name stays over its neighbours' discs, pins packed after it was selected included.
func test_the_selected_pin_draws_over_pins_made_after_it() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.selected = city.entries.filter(func(e): return str(e.get("id", "")) == "sh_market_1")[0]
	_look(m, Vector2(m.home_lat, m.home_lng), 15.5, 0.0)   # closer: more pins come in, after the selection
	var top := 0
	for mk in city.markers.values(): top = maxi(top, (mk.node as Node).get_index())
	assert_int((city.markers["sh_market_1"].node as Node).get_index()).is_equal(top)
	city.selected = {}

## 不知火舞 on 234 A2: the selected pin's name always shows and the names it touches fold — a marked pin's too — until
## the card closes; every pin stays.
func test_a_selected_name_folds_the_names_it_touches() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(0)   # Reed Pond wears the !
	var city: CityMapView = m.city_map
	var reed := SystemPonds.location(NEAREST_POND)
	var at := Vector2(float(reed.lat), float(reed.lng))
	var home: Dictionary = m.home_entry().merged({"lat": at.x - 0.0002, "lng": at.y}, true)   # 22 m south of it
	city.set_places(P0Outposts.all().map(func(o): return P0Outposts.place_entry(o)) + [home])
	_look(m, at, 15.0, 0.0)
	var reed_pin: UiMapDestination = city.markers[NEAREST_POND].dest
	var home_pin: UiMapDestination = city.markers["home"].dest
	assert_bool(reed_pin.name_shown).is_true()    # nothing selected: the marked pin packs first
	assert_bool(home_pin.name_shown).is_false()
	city.selected = city.entries.filter(func(e): return str(e.get("id", "")) == "home")[0]
	_look(m, at, 15.0, 0.0)
	assert_bool(home_pin.name_shown).is_true()
	# The marked one's name, touched under its disc, goes over it (不知火舞 on 234 A2: under, then over, then folded).
	assert_bool(reed_pin.name_shown and reed_pin.label_above).is_true()
	assert_float(reed_pin.above_gap).is_equal(UiMapDestination.above_gap_for(true))   # clear of its ! (刘邦 on #111)
	assert_bool(_dest_label_rect(city.markers[NEAREST_POND]).intersects(_dest_label_rect(city.markers["home"]))).is_false()
	assert_array(city.displayed.map(func(mk): return str(mk.entry.id))).contains([NEAREST_POND, "home"])
	city.selected = {}
	_look(m, at, 15.0, 0.0)
	assert_bool(reed_pin.name_shown).is_true()
	m._set_outpost_places()
	rt.session.view = saved

## The P0Runtime singleton the map brought up goes with the suite (P0Runtime.free_instance_for_tests).
func after() -> void:
	P0Runtime.free_instance_for_tests()

## int9 (韩信): a selected outpost by the left edge kept its name partly off screen. A MapDestination's name now slides
## in to LABEL_EDGE from the screen's sides, its disc staying over the point; the hit rect follows the name.
func test_a_name_by_the_edge_stays_on_screen() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var tackle := P0Outposts.place_entry(P0Outposts.by_role("tackle"), 3)
	var at := Vector2(float(tackle.lat), float(tackle.lng))
	_look(m, at, 15.0, 0.0)
	var p: Vector2 = m.geo_to_screen(at.x, at.y)
	m._pan_by(Vector2(18.0 - p.x, 0.0))   # the pin 18 px from the left edge
	m._update_cameras()
	m._sync_farm_markers()
	city.selected = city.entries.filter(func(e): return str(e.get("id", "")) == "sh_tackle_1")[0]
	city._update_markers()
	var mk: Dictionary = city.markers["sh_tackle_1"]
	if mk.get("pop_tween") is Tween: (mk.pop_tween as Tween).kill()
	mk.pop = 1.0
	mk.focus = CityMapView.FOCUS_SCALE   # at its selected size (SGODOT-261): the drawn name is the scaled one
	city._apply_marker_scale(mk)
	var name_rect := _dest_label_rect(mk)
	var on_screen := Rect2(name_rect.position + city.global_position, name_rect.size)   # in the screen's coordinates
	assert_float(on_screen.position.x).is_greater_equal(CityMapView.LABEL_EDGE - 0.5)
	assert_float(on_screen.end.x).is_less_equal(360.0 - CityMapView.LABEL_EDGE + 0.5)
	var pin: UiMapDestination = mk.dest
	var disc_centre: Vector2 = (mk.anchor as Vector2) + pin.position + pin._pin.position + Vector2(20, 20)
	assert_float(disc_centre.x).is_equal_approx((mk.anchor as Vector2).x, 0.5)   # the disc stays on its point
	assert_bool((mk.hit as Array).any(func(r): return (r as Rect2).is_equal_approx(name_rect))).is_true()
	# Its disc packed in the margin off the screen: no name either (no name without its pin).
	var q: Vector2 = m.geo_to_screen(at.x, at.y)
	m._pan_by(Vector2(-30.0 - q.x, 0.0))   # its whole disc off the screen's left edge
	m._update_cameras()
	m._sync_farm_markers()
	city._update_markers()
	assert_float((city.markers["sh_tackle_1"].anchor as Vector2).x + city.global_position.x).is_less(0.0)
	city.selected = {}   # (a selected pin is packed first wherever it is)
	city._update_markers()
	assert_bool((city.markers["sh_tackle_1"].dest as UiMapDestination).name_shown).is_false()   # no name without its disc
	city.selected = {}

## 不知火舞 on 234 A2: a name touching another tries over its disc before folding, in C30's order (no outpost has a
## privilege). In the first session's opening view the market's name, under its disc against the tea house's, goes over.
func test_a_name_goes_over_its_disc_before_it_folds() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(0)
	m.frame_home_set()
	m._sync_farm_markers()
	var city: CityMapView = m.city_map
	city._update_markers()
	var market: UiMapDestination = city.markers["sh_market_1"].dest
	assert_bool(market.name_shown).is_true()
	assert_bool(market.label_above).is_true()
	var rects: Array = city._place_labels
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_bool((rects[i] as Rect2).intersects(rects[j])).is_false()   # still no two names on each other
	rt.session.view = saved
