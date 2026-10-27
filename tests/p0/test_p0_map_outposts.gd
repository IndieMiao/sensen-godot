extends GdUnitTestSuite
## int6 C30 (李元芳): at the city overview the outpost pins were packed away — behind ponds, landmarks and the
## player's own avatar — so the Travel Post could only be found by zooming in. q(72): P0 does not aggregate; every
## outpost keeps one pin at every zoom, `Oak Tea House · 3 online` (just the name with no one in). The packing
## order is the selected pin, a pin wearing a map marker (q(48)), outposts, then the rest (蒙恬 on C30), and a tap
## on an outpost pin drawn over the player's avatar opens the outpost (SGODOT-224).

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Map := preload("res://scenes/p0/p0_map.gd")
const NEAREST_POND := "pond_san_francisco_03"   # Fern Pond, the beginner pond (P0City.beginner_pond(), SGODOT-270)

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

## SGODOT-269 (用户 via 263-6; 不知火舞) and q(137) ⑤: space pins give way — no two discs nearer than 36 px, none on an
## avatar's body — except the ones always in: the selected pin, a marked one and the pin of where the player is. They
## pack by a fixed rank (beginner pond, ponds, market, tea house, post, tackle shop, silhouette), so one gives way only
## to a higher-ranked pin or the avatar; zooming in parts them and they come back. Fresh here (no incumbents).
func _look_fresh(m: Node, at: Vector2, zoom: float) -> Array:
	(m.city_map as CityMapView)._shown_last.clear()
	(m.city_map as CityMapView)._hidden_until.clear()
	return _look(m, at, zoom, 0.0)

## The space pins on the map now: id -> its disc as drawn in the city view (over its point, scaled by its selection).
static func _discs(city: CityMapView) -> Dictionary:
	var out := {}
	for mk in city.displayed:
		if not mk.has("dest"): continue
		var k := (mk.node as Control).scale.x
		out[str(mk.entry.id)] = Rect2((mk.anchor as Vector2) - Vector2(20.0, 40.0) * k, Vector2(40.0, 40.0) * k)
	return out

## Whether the pin `id` is one of those always in (the selected pin, a marked one, where the player is).
static func _kept(m: Node, id: String) -> bool:
	var city: CityMapView = m.city_map
	if str(city.selected.get("id", "")) == id: return true
	var found: Array = city.entries.filter(func(e): return str(e.get("id", "")) == id)
	return not found.is_empty() and (city._marker_of(found[0]) != "" or bool(m._kept_pin(found[0])))

## No space pin that gives way covers an avatar's body, and no two discs shown are nearer than 36 px centre to centre
## unless both are always in (q(137) ⑤; fresh, no incumbents).
func _assert_clear(m: Node, why: String) -> void:
	var city: CityMapView = m.city_map
	var discs := _discs(city)
	var bodies: Array = city._player_blockers(true)
	var ids: Array = discs.keys()
	for i in ids.size():
		if _kept(m, ids[i]): continue
		assert_bool(bodies.any(func(b): return (b as Rect2).intersects(discs[ids[i]]))).append_failure_message(
			"%s: %s on an avatar" % [why, ids[i]]).is_false()
		for j in ids.size():
			if j == i: continue
			var apart := (discs[ids[i]] as Rect2).get_center().distance_to((discs[ids[j]] as Rect2).get_center())
			assert_float(apart).append_failure_message("%s: %s by %s" % [why, ids[i], ids[j]]) \
				.is_greater_equal(CityMapView.DEST_NEAR - 0.01)

func test_space_pins_never_cover_one_another_or_the_avatar() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var mid := Vector2.ZERO
	for o in P0Outposts.all(): mid += Vector2(float(o.lat), float(o.lng))
	mid /= 4.0
	for at in [mid, Vector2(m.home_lat, m.home_lng)]:
		for zoom in [11.5, 12.2, 13.0, 13.8, 14.5, 15.5]:
			_look_fresh(m, at, zoom)
			_assert_clear(m, "z%.1f" % zoom)

## The user's pile (263-6): around home at the city level the outposts by home, Reed Pond and the avatar no longer
## sit on one another — and each outpost comes back once zooming in parts it from them.
func test_the_outposts_by_home_give_way_at_the_city_level_and_come_back_closer() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var by_home := ["sh_tea_1", "sh_market_1", "sh_tackle_1"]
	var city_level := _look_fresh(m, Vector2(m.home_lat, m.home_lng), 12.2)
	_assert_clear(m, "z12.2")
	assert_int(by_home.filter(func(id): return city_level.has(id)).size()).is_less(by_home.size())   # some give way
	for id in by_home:   # closer in, around each, it is there
		var o := P0Outposts.find(id)
		assert_array(_look_fresh(m, Vector2(float(o.lat), float(o.lng)), 16.0)).append_failure_message(id).contains([id])
		_assert_clear(m, "%s at z16" % id)

## The selected pin is never packed away (the Show on map target: Reed Pond, 200 m from the Tackle Shop); a pin it
## would cover gives way to it.
func test_the_selected_pond_shows_and_the_pins_it_touches_give_way() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var reed: Dictionary = city.entries.filter(func(e): return str(e.id) == NEAREST_POND)[0]
	city.selected = reed   # what select() leaves for the packing (select() also prewarms the pond scene)
	assert_array(_look_fresh(m, Vector2(m.home_lat, m.home_lng), 12.2)).contains([NEAREST_POND])
	_assert_clear(m, "Reed Pond selected")
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

## q(137) ①–③: the pin says the short name, the people in are its top-right count (none at 0); a tackle shop says no
## name (it is always its pond's), and the card keeps the whole name and Online now.
func test_an_outpost_pin_says_who_is_in() -> void:
	var tea := P0Outposts.by_role("tea")
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	assert_str(city._dest_text(P0Outposts.place_entry(tea, 3))).is_equal("Oak")   # Oak Tea House (SGODOT-270)
	assert_str(city._dest_text(P0Outposts.place_entry(P0Outposts.by_role("tackle"), 0))).is_equal("")
	assert_str(city._dest_text(P0Outposts.place_entry(P0Outposts.by_role("post"), 0))).is_equal("Union Square")
	assert_str(city._dest_text(P0Outposts.place_entry(P0Outposts.by_role("market"), 0))).is_equal("Mission")
	m._online = {str(tea.id): 3}
	m._set_outpost_places()
	_look_fresh(m, Vector2(float(tea.lat), float(tea.lng)), 16.0)
	var pin: UiMapDestination = city.markers[str(tea.id)].dest
	assert_int(pin.online).is_equal(3)
	assert_bool(pin._count.visible).is_true()
	assert_str(pin.text).is_equal("Oak")
	var card: Dictionary = m.place_card(P0Outposts.place_entry(tea, 3))
	assert_str(card.title).is_equal(str(tea.name))
	assert_array(card.facts).contains([["Online now", "3"]])
	m._online = {}
	m._set_outpost_places()
	_look_fresh(m, Vector2(float(tea.lat), float(tea.lng)), 16.0)
	assert_bool(pin._count.visible).is_false()

## q(137) ①: the short name drops the type word; a name that is only one stays whole.
func test_a_short_name_is_the_place_without_its_type() -> void:
	for pair in [["Willow Pond", "Willow"], ["Reed Creek", "Reed"], ["Elm Cove", "Elm"], ["Maple Market Square", "Maple"],
			["Oak Tea House", "Oak"], ["Tundra Trading Post", "Tundra"], ["Union Square Travel Post", "Union Square"],
			["Mission Tackle Shop", "Mission"], ["Barbary Card Room", "Barbary"], ["Homestead", "Homestead"], ["Pond", "Pond"]]:
		assert_str(P0Map.short_name(pair[0])).is_equal(pair[1])

## An outpost pin drawn over the player's avatar takes the tap (蒙恬 on C30): it is selected, not the avatar. Since 269
## only the pins always in stay on an avatar: at the Oak Tea House the avatar stands beside its pin (where the player
## is), and a tap on that pin selects it.
func test_a_tap_on_an_outpost_over_the_avatar_opens_the_outpost() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.here
	rt.here = {"space": "outpost", "place": "sh_tea_1"}
	m._sync_here()
	var tea_at := P0Outposts.find("sh_tea_1")
	_look_fresh(m, Vector2(float(tea_at.lat), float(tea_at.lng)), 12.2)
	var city: CityMapView = m.city_map
	var shown: Array = city.displayed.filter(func(mk): return str(mk.entry.id) == "sh_tea_1")
	assert_array(shown).is_not_empty()   # where the player is: kept beside the avatar
	var tea: Dictionary = shown[0]
	var screen: Vector2 = (tea.anchor as Vector2) + Vector2(0, -20) + city.global_position   # on its artwork
	assert_bool(city.activate_place_at(screen)).is_true()
	assert_str(str(city.selected.get("id", ""))).is_equal("sh_tea_1")
	assert_bool(city.activate_place_at(Vector2(4, 4))).is_false()   # nowhere near an outpost
	city.selected = {}
	rt.here = saved
	m._sync_here()

func _labels(m: Node) -> Dictionary:   # outpost id -> its pin (MapDestination: its name under the disc), on screen
	var out := {}
	for mk in (m.city_map as CityMapView).displayed:
		if mk.entry.kind == "place" or mk.has("dest"): out[str(mk.entry.id)] = mk.get("dest", mk.label)
	return out

static func _dest_label_rect(marker: Dictionary) -> Rect2:   # a MapDestination's name, in the city view, as drawn
	var pin: UiMapDestination = marker.dest
	if not pin.name_shown: return Rect2()
	var box: Control = pin._label_box
	var k: Vector2 = (marker.node as Control).scale   # a selected pin is drawn scaled about its point (SGODOT-261)
	return Rect2((marker.anchor as Vector2) + (pin.position + box.position) * k, box.size * k)

static func _shown(pin: Control) -> bool:   # whether the pin says its name
	return (pin as UiMapDestination).name_shown if pin is UiMapDestination else pin.visible

## 不知火舞 on C30: outpost labels never overlap; the others fold only their label (the pin stays) and come back once
## zooming in parts them. 269: a name keeps clear of the avatar's body as of the pins (under, then over, then folded).
func test_outpost_labels_never_overlap_and_keep_clear_of_the_avatar() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	# Outposts among themselves: after the tutorial, so Reed Pond wears no marker that packs before them.
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(-1)
	var home := Vector2(m.home_lat, m.home_lng)
	var shown_at := {}
	for zoom in [11.5, 12.3, 13.3, 13.8, 15.0]:   # phone geometry (P0Map._map_logical_height); 13.8 the opening view
		_look_fresh(m, home, zoom)
		var labels := _labels(m)
		var rects: Array = city._place_labels
		var bodies: Array = city._player_blockers(true)
		for i in rects.size():
			assert_bool(bodies.any(func(b): return (b as Rect2).intersects(rects[i]))).append_failure_message("zoom %s" % zoom).is_false()
			for j in range(i + 1, rects.size()):
				assert_bool((rects[i] as Rect2).intersects(rects[j])).append_failure_message("zoom %s" % zoom).is_false()
		# q(137) ⑤: no name shown covers the disc of a pin packed before it (a higher rank)
		var order: Array = city.displayed.filter(func(mk): return mk.has("dest"))
		for i in order.size():
			if not (order[i].dest as UiMapDestination).name_shown: continue
			var name_rect := _dest_label_rect(order[i])
			for j in i:
				var disc := Rect2((order[j].anchor as Vector2) - Vector2(20.0, 40.0), Vector2(40.0, 40.0))
				assert_bool(name_rect.intersects(disc)).append_failure_message("zoom %s: %s's name on %s" % [zoom,
					order[i].entry.id, order[j].entry.id]).is_false()
		assert_int(rects.size()).is_equal(labels.values().filter(func(l): return _shown(l)).size())
		shown_at[zoom] = labels.values().filter(func(l): return _shown(l)).size()
	# Closer in, around each of the three by home, its pin is there and its name with it — the tackle shop's pin without
	# one (q(137) ②).
	for id in ["sh_tea_1", "sh_market_1", "sh_tackle_1"]:
		var o := P0Outposts.find(id)
		_look_fresh(m, Vector2(float(o.lat), float(o.lng)), 16.0)
		assert_bool(_labels(m).has(id)).append_failure_message(id).is_true()
		assert_bool(_shown(_labels(m)[id])).append_failure_message(id).is_equal(id != "sh_tackle_1")
	rt.session.view = saved

## q(137) ①④: the short name, never more than one line of 96 px; a selected pin shows even where it would give way
## (269), its name hidden — the card says it whole.
func test_an_outpost_name_is_short_and_hides_when_selected() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.set_places(P0Outposts.all().map(func(o): return P0Outposts.place_entry(o, 3 if str(o.role) == "tea" else 0)))
	for id in ["sh_tea_1", "sh_market_1"]:   # each where it shows: around itself, closer in
		var o := P0Outposts.find(id)
		_look_fresh(m, Vector2(float(o.lat), float(o.lng)), 16.0)
		var pin: UiMapDestination = _labels(m)[id]
		assert_str(pin.text).is_equal(P0Map.short_name(str(o.name)))
		assert_float(pin.label_size().x).is_equal(UiMapDestination.label_size_for(pin.text, false).x)
		assert_float(pin.label_size().x).is_less_equal(UiMapDestination.SHORT_MAX_W)
	# At the city level the one by home gives way (to the avatar, a pin or a higher-ranked one); selected, it shows,
	# without its name.
	var home := Vector2(m.home_lat, m.home_lng)
	var city_level := _look_fresh(m, home, 12.2)
	var gone: Array = ["sh_tea_1", "sh_market_1", "sh_tackle_1"].filter(func(id): return not city_level.has(id))
	assert_bool(gone.is_empty()).is_false()
	city.selected = city.entries.filter(func(e): return str(e.id) == str(gone[0]))[0]
	assert_array(_look_fresh(m, home, 12.2)).contains([str(gone[0])])
	assert_bool(_shown(_labels(m)[str(gone[0])])).is_false()
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

## 不知火舞 on C30: My Farm's label gives way to an outpost label it touches; it is back when they part. Since 269 an
## outpost's name keeps clear of the avatar's body and name, so only a pin always in — here a selected one right at
## home — puts its name there.
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
	_look_fresh(m, home, 15.0)
	assert_bool(_labels(m).has("test_here")).is_false()   # not selected: it gives way to the avatar
	assert_bool(fm.self_label_yields).is_false()
	city.selected = city.entries.filter(func(e): return str(e.id) == "test_here")[0]
	_look_fresh(m, home, 15.0)
	assert_bool(_shown(_labels(m)["test_here"])).is_true()
	assert_bool(fm.self_label_yields).is_true()
	assert_bool(fm._buttons["self"].visible).is_false()
	fm.sync(m.cam, m.anchor_lat, m.anchor_lng, Rect2(0, 0, 360, 800))   # the next frame's sync keeps it down
	assert_bool(fm._buttons["self"].visible).is_false()
	city.selected = {}
	city.set_places(outposts)   # gone: My Farm says its name again
	_look_fresh(m, home, 15.0)
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
	# On screen (phone geometry): around home at the city level, and the opening view the first session gets; the
	# Tackle Shop 200 m away gives way to it where they touch (269: 不知火舞 keeps it so, the pin is a zoom away).
	assert_array(_look_fresh(m, Vector2(m.home_lat, m.home_lng), 12.2)).contains([NEAREST_POND])
	_assert_clear(m, "z12.2")
	m.frame_home_set()
	assert_array(m.framed.map(func(it): return str(it.get("id", "self")))).contains([NEAREST_POND, "sh_tackle_1"])
	m._sync_farm_markers()
	city._update_markers()
	# A MapDestination (SGODOT-234 A2): 2D over the map, so over the player's avatar.
	var reed: UiMapDestination = city.markers[NEAREST_POND].dest
	# Its short name shows (q(137)): the first session finds its way by it.
	assert_bool(reed.name_shown).is_true()
	assert_str(reed.text).is_equal("Fern")
	assert_float(reed.label_size().x).is_equal(UiMapDestination.label_size_for(reed.text, false).x)
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
	# Both fish in the bag (the target is now the stall), or handed in: no marker, the beginner pond by its rank — the
	# Tackle Shop 200 m away, ranked last but the silhouettes, gives way to it where they touch (q(137) ⑤).
	for gone in [_board(2), _board(-1)]:
		rt.session.view = gone
		assert_dict(m.city_pin_markers()).is_empty()
		var tackle := P0Outposts.find("sh_tackle_1")
		_look_fresh(m, Vector2(float(tackle.lat), float(tackle.lng)), 12.2)
		assert_int(city._dest_rank(city.markers[NEAREST_POND].entry)).is_less(city._dest_rank(P0Outposts.place_entry(tackle)))
		_assert_clear(m, "no marker")   # no longer always in: it gives way to the avatar by home, the shop to it
		assert_bool(city._over_avatar(city.markers[NEAREST_POND].entry)).is_true()
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
	assert_str((card.find_child("Primary", true, false) as UiCommandButton).label).is_equal("Back to Fern Pond")
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
	# the card room (SGODOT-351): i-cards, its short name (不知火舞 351 0c2082b7: `Barbary`), packed with the tackle shop
	var casino: Dictionary = m._destination_style(P0Outposts.place_entry(P0Outposts.by_role("casino")))
	assert_object(casino.icon).is_same(P0Outposts.cards_icon())
	assert_str(str(casino.label)).is_equal("Barbary")
	assert_int(int(casino.rank)).is_equal(int(m.PIN_RANK.tackle))
	assert_bool(bool(casino.get("plate", false))).is_false()

## The card room's pin is in only while view.blackjack says the table is open to this player (q(238): Homestead Lv2,
## the guide over), no grey card before (不知火舞 351 8aa69403); it comes in as soon as the table opens.
func test_the_card_room_pin_shows_once_its_table_is_open() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var ids := func() -> Array: return m.city_map.extra_places.map(func(e): return str(e.get("id", "")))
	var v: Dictionary = rt.session.view.duplicate(true)
	v["blackjack"] = {"open": false}
	rt.session.view = v
	m.p0_frame(v, 1.0 / 30.0)
	assert_array(ids.call()).not_contains(["sf_card_room_1"])
	assert_array(ids.call()).contains(["sh_tea_1"])
	v = v.duplicate(true)
	v["blackjack"] = {"open": true}
	rt.session.view = v
	m.p0_frame(v, 1.0 / 30.0)
	assert_array(ids.call()).contains(["sf_card_room_1"])

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

## q(137) ④⑤: the selected pin shows with its name hidden (its card says it whole); a marked pin is always in, its name
## under its disc; a pin they touch gives way. Every pin stays on its point. q(146): between always-in pins the higher
## goes first — the selected disc on the marked pin's name hides that name (its disc stays) until it is deselected.
func test_a_selected_pin_hides_its_name_and_a_marked_one_keeps_its() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(0)   # Fern Pond wears the !
	var city: CityMapView = m.city_map
	var reed := SystemPonds.location(NEAREST_POND)
	var at := Vector2(float(reed.lat), float(reed.lng))
	var home: Dictionary = m.home_entry().merged({"lat": at.x - 0.0002, "lng": at.y}, true)   # 22 m south of it
	city.set_places(P0Outposts.all().map(func(o): return P0Outposts.place_entry(o)) + [home])
	_look_fresh(m, at, 15.0)
	var reed_pin: UiMapDestination = city.markers[NEAREST_POND].dest
	assert_bool(reed_pin.name_shown).is_true()    # nothing selected: the marked pin packs first
	assert_array(city.displayed.map(func(mk): return str(mk.entry.id))).not_contains(["home"])   # under 36 px: it gives way
	city.selected = city.entries.filter(func(e): return str(e.get("id", "")) == "home")[0]
	_look_fresh(m, at, 15.0)
	var home_pin: UiMapDestination = city.markers["home"].dest
	assert_array(city.displayed.map(func(mk): return str(mk.entry.id))).contains([NEAREST_POND, "home"])
	assert_bool(home_pin.name_shown).is_false()   # selected: the card says Homestead
	assert_bool(reed_pin.name_shown).is_false()   # q(146): under the selected (higher) disc, the marked name hides
	assert_bool(reed_pin.label_above).is_false()  # under its disc only (q(137) ①), never moved above instead
	city.selected = {}
	_look_fresh(m, at, 15.0)
	assert_bool(reed_pin.name_shown).is_true()
	m._set_outpost_places()
	rt.session.view = saved

## q(137) ⑤: a name that would cover a higher-ranked disc or name hides and its pin stays; a pin shown last pass holds
## until 4 px more overlap, so a pan on the edge does not flicker; the order is the rank, whatever the id says.
func test_names_give_way_before_pins_by_rank_and_hold_by_4_px() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(-1)   # no marks
	var city: CityMapView = m.city_map
	var at := Vector2(m.home_lat + 0.03, m.home_lng + 0.03)   # clear of home and the outposts
	var tea := P0Outposts.place_entry(P0Outposts.by_role("tea"))
	var market := P0Outposts.place_entry(P0Outposts.by_role("market"))
	_look_fresh(m, at, 15.0)
	# The market (rank 3) left of the tea house (rank 4), the tea house's id first: 30 px apart they cannot both show
	var p0 = m.geo_to_screen(at.x, at.y)
	var p1 = m.geo_to_screen(at.x, at.y + 0.0001)
	var per := 0.0001 / maxf(0.001, absf((p1 as Vector2).x - (p0 as Vector2).x))   # degrees of longitude per view px
	var place := func(e: Dictionary, dx: float) -> Dictionary: return e.merged({"lat": at.x, "lng": at.y + dx * per}, true)
	city.set_places([place.call(market, 0.0), place.call(tea, 30.0)])
	var shown := _look_fresh(m, at, 15.0)
	assert_array(shown).contains([str(market.id)]).not_contains([str(tea.id)])
	# 38 px apart both show; the tea house's name, under its disc, does not cover the market's — both say theirs
	city.set_places([place.call(market, 0.0), place.call(tea, 38.0)])
	shown = _look_fresh(m, at, 15.0)
	assert_array(shown).contains([str(market.id), str(tea.id)])
	# shown last pass at 38, it holds down to 32 px (4 px more), fresh it would not at 34
	city.set_places([place.call(market, 0.0), place.call(tea, 34.0)])
	assert_array(_look(m, at, 15.0, 0.0)).contains([str(tea.id)])
	assert_array(_look_fresh(m, at, 15.0)).not_contains([str(tea.id)])
	m._set_outpost_places()
	rt.session.view = saved

## q(141): of the pins on screen with one short name only the highest-ranked says it; the always-in kinds keep theirs.
func test_one_name_on_screen_is_said_once() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(-1)   # no marks
	var city: CityMapView = m.city_map
	var at := Vector2(m.home_lat + 0.03, m.home_lng + 0.03)   # clear of home and the outposts
	_look_fresh(m, at, 15.0)
	var p0 = m.geo_to_screen(at.x, at.y)
	var p1 = m.geo_to_screen(at.x, at.y + 0.0001)
	var per := 0.0001 / maxf(0.001, absf((p1 as Vector2).x - (p0 as Vector2).x))   # degrees of longitude per view px
	var market := P0Outposts.place_entry(P0Outposts.by_role("market")).merged({"name": "Echo Market Square", "lat": at.x,
		"lng": at.y - 60.0 * per}, true)
	var tea := P0Outposts.place_entry(P0Outposts.by_role("tea")).merged({"name": "Echo Tea House", "lat": at.x,
		"lng": at.y + 60.0 * per}, true)
	m._dest_styles.clear()
	city.set_places([market, tea])
	_look_fresh(m, at, 15.0)
	var market_pin: UiMapDestination = city.markers[str(market.id)].dest
	var tea_pin: UiMapDestination = city.markers[str(tea.id)].dest
	assert_array(city.displayed.map(func(mk): return str(mk.entry.id))).contains([str(market.id), str(tea.id)])
	assert_bool(market_pin.name_shown).is_true()   # the market ranks above the tea house: it says Echo
	assert_str(market_pin.text).is_equal("Echo")
	assert_bool(tea_pin.name_shown).is_false()     # the tea house only its icon
	# both always in (marked): both say it
	city.set_places([market.merged({"marker": "request"}, true), tea.merged({"marker": "new"}, true)])
	_look_fresh(m, at, 15.0)
	assert_bool((city.markers[str(market.id)].dest as UiMapDestination).name_shown).is_true()
	assert_bool((city.markers[str(tea.id)].dest as UiMapDestination).name_shown).is_true()
	# the market off screen: the tea house says its name
	city.set_places([market.merged({"lng": at.y - 400.0 * per}, true), tea])
	_look_fresh(m, at, 15.0)
	assert_bool((city.markers[str(tea.id)].dest as UiMapDestination).name_shown).is_true()
	m._dest_styles.clear()
	m._set_outpost_places()
	rt.session.view = saved

## 周瑜 on #306: an always-in pin's name never gives way, so a lower-ranked disc that would sit on it hides.
func test_no_disc_sits_on_an_always_in_name() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(-1)
	var city: CityMapView = m.city_map
	var at := Vector2(m.home_lat + 0.03, m.home_lng + 0.03)
	_look_fresh(m, at, 15.0)
	var p0 = m.geo_to_screen(at.x, at.y)
	var p1 = m.geo_to_screen(at.x - 0.0001, at.y)
	var per := 0.0001 / maxf(0.001, absf((p1 as Vector2).y - (p0 as Vector2).y))   # degrees of latitude per view px
	# the tea house marked (always in) and the market 40 px under it: its disc would sit on the tea house's name
	var tea := P0Outposts.place_entry(P0Outposts.by_role("tea")).merged({"lat": at.x, "lng": at.y, "marker": "request"}, true)
	var market := P0Outposts.place_entry(P0Outposts.by_role("market")).merged({"lat": at.x - 40.0 * per, "lng": at.y}, true)
	city.set_places([tea, market])
	var shown := _look_fresh(m, at, 15.0)
	assert_array(shown).contains([str(tea.id)]).not_contains([str(market.id)])
	assert_bool((city.markers[str(tea.id)].dest as UiMapDestination).name_shown).is_true()
	# unmarked, the tea house (rank 4) gives way to the market (rank 3) by the 36 px rule instead: 40 px apart both show
	city.set_places([tea.merged({"marker": ""}, true), market])
	shown = _look_fresh(m, at, 15.0)
	assert_array(shown).contains([str(tea.id), str(market.id)])
	m._set_outpost_places()
	rt.session.view = saved

## 不知火舞 on #306: a pin's name draws over every disc (a lower-ranked disc beside it never covers it); the view's own
## controls (keys, credit line) draw over the names.
func test_names_draw_over_discs_and_the_keys_over_names() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	_look_fresh(m, Vector2(m.home_lat, m.home_lng), 14.0)
	var pins: Array = city.displayed.filter(func(mk): return mk.has("dest"))
	assert_array(pins).is_not_empty()
	for mk in pins:
		var pin: UiMapDestination = mk.dest
		assert_int(pin._label_box.z_index).is_equal(UiMapDestination.NAME_Z)
		assert_int(pin._disc.z_index).is_equal(0)
		assert_int((mk.node as Control).z_index).is_equal(0)
	for n in [city.recenter, city.home_key, city.get_node("MapCredits")]:
		assert_int((n as Control).z_index).is_greater(UiMapDestination.NAME_Z)

## The P0Runtime singleton the map brought up goes with the suite (P0Runtime.free_instance_for_tests).
func after() -> void:
	P0Runtime.free_instance_for_tests()

## int9 (韩信): an outpost by the left edge kept its name partly off screen. A MapDestination's name slides in to
## LABEL_EDGE from the screen's sides, its disc staying over the point; the hit rect follows the name.
func test_a_name_by_the_edge_stays_on_screen() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var tea := P0Outposts.place_entry(P0Outposts.by_role("tea"), 3)
	var at := Vector2(float(tea.lat), float(tea.lng))
	_look(m, at, 15.0, 0.0)
	var p: Vector2 = m.geo_to_screen(at.x, at.y)
	m._pan_by(Vector2(18.0 - p.x, 0.0))   # the pin 18 px from the left edge
	m._update_cameras()
	m._sync_farm_markers()
	city._shown_last.clear()
	city._update_markers()
	var mk: Dictionary = city.markers["sh_tea_1"]
	if mk.get("pop_tween") is Tween: (mk.pop_tween as Tween).kill()
	mk.pop = 1.0
	city._apply_marker_scale(mk)
	assert_bool((mk.dest as UiMapDestination).name_shown).is_true()
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
	if city.markers.has("sh_tea_1") and city.displayed.has(city.markers["sh_tea_1"]):
		assert_float((city.markers["sh_tea_1"].anchor as Vector2).x + city.global_position.x).is_less(0.0)
		assert_bool((city.markers["sh_tea_1"].dest as UiMapDestination).name_shown).is_false()   # no name without its disc

## q(137) ①⑤: a name sits only under its disc — no second place over it (234 A2's) — and hides where it would cover a
## higher-ranked disc or name. In the first session's opening view no two names lie on each other and none is over its
## disc.
func test_a_name_sits_under_its_disc_or_hides() -> void:
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
	for mk in city.displayed:
		if mk.has("dest"): assert_bool((mk.dest as UiMapDestination).label_above).append_failure_message(str(mk.entry.id)).is_false()
	var rects: Array = city._place_labels
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_bool((rects[i] as Rect2).intersects(rects[j])).is_false()   # still no two names on each other
	rt.session.view = saved

## 不知火舞 on 269: a space pin gives way to the avatar's body (its 70 × 130 tap target and its name while shown), not to
## the margin a POI's tall artwork keeps over and beside it; POIs keep that margin.
func test_a_space_pin_gives_way_to_the_body_and_a_poi_to_its_margin() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look_fresh(m, Vector2(m.home_lat, m.home_lng), 14.0)
	var fm: FarmMarkers = m.farm_markers
	var body: Rect2 = fm.blocker_rects(true)[0]
	var poi: Rect2 = fm.blocker_rects()[0]
	var target: Control = fm._avatar_targets["self"]
	var label: Control = fm._buttons["self"]
	assert_bool(label.visible).is_true()
	assert_that(body).is_equal(Rect2(target.position, target.size).merge(Rect2(label.position, label.size)))
	assert_bool(poi.encloses(body) and poi.size.x > body.size.x and poi.size.y > body.size.y).is_true()
	label.visible = false   # away from home the name is off: then it does not count
	assert_that(fm.blocker_rects(true)[0]).is_equal(Rect2(target.position, target.size))
	label.visible = true

## 不知火舞 on 269: the opening view zooms in only where that shows more of the pins it holds untouched, the avatar and
## the marked pins kept in the frame. The first session's (Reed Pond's ! and the avatar spanning the frame) cannot part
## the Tackle Shop from Reed Pond, so it stays as _fit chose it rather than zooming in for nothing.
func test_the_opening_view_zooms_in_only_to_show_more_pins() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	rt.session.view = _board(0)
	var safe: Rect2 = m.frame_safe_rect()
	m.frame_home_set()
	var chosen: Array = m.framed
	var fit: Dictionary = m._fit(chosen, safe)
	m.frame_home_set()
	assert_float(m.zoom).is_equal_approx(float(fit.z), 0.001)   # nothing to gain: the view _fit chose
	# Two pins touching at a wide view holding them, the avatar alone to keep: a closer view parts them and is taken.
	rt.session.view = _board(-1)
	var home := Vector2(m.home_lat, m.home_lng)
	var a := P0Outposts.place_entry(P0Outposts.by_role("tea")).merged({"lat": home.x, "lng": home.y + 0.003}, true)
	var b := P0Outposts.place_entry(P0Outposts.by_role("market")).merged({"lat": home.x, "lng": home.y + 0.0043}, true)
	var items: Array = [{lat = home.x, lng = home.y, self_pin = true, shift = Vector2.ZERO}, a, b]   # 125 m apart
	var view := {"at": Vector2(home.x, home.y + 0.0021), "z": 13.5}
	m._look(view.at, 13.5)
	assert_int(m._pins_shown(items, safe)).is_equal(1)   # they touch there
	var parted: Dictionary = m._part_pins(items, view, safe)
	assert_float(float(parted.z)).is_greater(13.5)
	m._look(parted.at, float(parted.z))
	assert_int(m._pins_shown(items, safe)).is_equal(2)
	assert_bool(safe.encloses(m._frame_box(m.frame_must()))).is_true()   # the avatar still in the frame
	rt.session.view = saved
