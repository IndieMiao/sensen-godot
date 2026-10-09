extends GdUnitTestSuite
## MAP-1 (§10.6.1, SGODOT-234 A1; 不知火舞 on 234): on the map P0's two-row HUD and Bag replace the map's own chrome —
## no city title, filters, place list, compass, Map / Farm / Me dock or + / −; the recenter key sits right over Bag,
## 12 apart, and keeps the zoom. The place chip names where the player is and takes them back there. Pin cards: the
## homestead's says Go home · Free, ponds and outposts Go, the place the player is at Back to <name> (q(80)).

const P0_MAP := "res://scenes/p0/p0_map.tscn"

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

func test_the_maps_own_chrome_gives_way_to_the_hud_and_bag() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	var city: CityMapView = m.city_map
	assert_bool(city.host_chrome).is_true()
	for n in [city.city_button, city.subtitle, city.dock, city.get_node("MapLandmarkList"), city.get_node("MapFilters"),
			city.get_node("MapNorth"), city.get_node("MapZoom_plus"), city.get_node("MapZoom_minus")]:
		assert_bool((n as CanvasItem).visible).append_failure_message(str(n.name)).is_false()
	assert_bool(city.recenter.visible).is_true()
	# MapLocateButton 1793:103795: 44, styled like Close, the i-locate glyph in its own colours.
	assert_object(city.recenter.icon).is_same(P0Logic.icon("locate"))
	assert_str(str(city.recenter.theme_type_variation)).is_equal(str(UiTokens.BUTTON_CLOSE_ROUND))
	assert_that(city.recenter.size).is_equal(Vector2(44, 44))
	# Right-aligned over Bag, 12 from the edge and 12 above the bar's row (Bag 24 + 68 from the bottom).
	var bag_top := city.size.y - UiTokens.SIZE_QUICK_BAR_BOTTOM - UiTokens.SIZE_QUICK_BAR_H
	assert_float(city.recenter.position.x + city.recenter.size.x).is_equal_approx(city.size.x - 12.0, 0.5)
	assert_float(city.recenter.position.y + city.recenter.size.y).is_equal_approx(bag_top - 12.0, 0.5)
	assert_float(city.content_bottom()).is_equal_approx(bag_top, 0.5)
	assert_str(m.own_farm_name).is_equal("Homestead")

func test_recenter_brings_the_camera_home_and_keeps_the_zoom() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	m.center_lat = m.home_lat + 0.02
	m.center_lng = m.home_lng + 0.02
	m.zoom = 13.3
	m._city_action("recenter")
	await _landed(m)   # it flies (SGODOT-267)
	assert_float(m.center_lat).is_equal_approx(m.home_lat, 1e-6)
	assert_float(m.center_lng).is_equal_approx(m.home_lng, 1e-6)
	assert_float(m.zoom).is_equal_approx(13.3, 1e-6)

## q(80): the homestead's and the outposts' cards are P0PlaceSheet. At home the avatar is the homestead's mark: its card
## reads Back to Homestead, no Distance. Away, the farm wears a Homestead pin whose card says Go home · Free with
## Distance, and the avatar's card is the place the player is at. Online now shows only with someone in (q(72)).
func test_place_cards_follow_q80() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.here
	var city: CityMapView = m.city_map
	rt.here = {"space": "home", "place": ""}
	m._sync_here()
	assert_bool(city.entries.any(func(e): return str(e.get("id", "")) == "home")).is_false()   # no Homestead pin
	m._own_pin_pressed()
	assert_str(rt.ui.modal_kind).is_equal("place_card")
	assert_str(_primary(rt)).is_equal("Back to Homestead")
	assert_array(_facts(rt)).is_empty()
	m.p0_frame(rt.session.view, 0.0)
	assert_bool(city.recenter.visible).is_false()   # the recenter key gives way to the sheet (不知火舞 on 234 A2)
	await _close(rt)
	m.p0_frame(rt.session.view, 0.0)
	assert_bool(city.recenter.visible).is_true()
	var tea := P0Outposts.by_role("tea")
	rt.here = {"space": "outpost", "place": str(tea.id)}
	m._sync_here()
	var home: Array = city.entries.filter(func(e): return str(e.get("id", "")) == "home")
	assert_int(home.size()).is_equal(1)
	city.select(home[0])
	assert_bool(city.info.visible).is_false()   # the sheet is the card: no city info panel under it
	assert_str(_primary(rt)).is_equal("Go home · Free")
	assert_array(_facts(rt)).is_equal(["Distance"])
	await _close(rt)
	assert_dict(city.selected).is_empty()   # closing the card clears the pin
	m._own_pin_pressed()
	assert_str(_primary(rt)).is_equal("Back to Lotus Tea House")
	await _close(rt)
	var tackle := P0Outposts.by_role("tackle")
	city.select(P0Outposts.place_entry(tackle))
	assert_str(_primary(rt)).is_equal("Go")
	assert_array(_facts(rt)).is_equal(["Distance"])   # nobody in: no Online now row
	await _close(rt)
	m._online = {str(tackle.id): 3}
	var spec: Dictionary = m.place_card(P0Outposts.place_entry(tackle, 3))
	assert_str(str(spec.title)).is_equal("Xuhui Tackle Shop")
	assert_str(str(spec.subtitle)).is_equal("Tackle shop · Rods and bait")
	assert_array(spec.facts[1]).is_equal(["Online now", "3"])
	m._online = {}
	rt.here = saved
	m._sync_here()

## 不知火舞 on 234: the avatar stands where the player is (the place chip): at home on the homestead, at an outpost left
## of its pin with no name of its own; recenter and the opening view go to it.
func test_the_avatar_stands_where_the_player_is() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.here
	var fm: FarmMarkers = m.farm_markers
	var tea := P0Outposts.by_role("tea")
	rt.here = {"space": "outpost", "place": str(tea.id)}
	m._sync_here()
	assert_that(fm.anchor_of("self")).is_equal(Vector2(float(tea.lat), float(tea.lng)))
	assert_that(fm.anchor_shift.get("self")).is_equal(m.AVATAR_BESIDE)
	assert_bool(fm.self_label_off).is_true()
	var item: Dictionary = m.home_set_items()[0]
	assert_float(float(item.lat)).is_equal_approx(float(tea.lat), 1e-5)   # a Vector2 point
	m._city_action("recenter")
	await _landed(m)
	assert_float(m.center_lat).is_equal_approx(float(tea.lat), 1e-6)
	assert_float(m.center_lng).is_equal_approx(float(tea.lng), 1e-6)
	rt.here = {"space": "pond", "place": "pond_shanghai_05"}
	m._sync_here()
	var reed := SystemPonds.location("pond_shanghai_05").merged({"kind": "pond"})
	assert_str(m._pin_tag(reed)).is_equal("Beginner pond")   # no distance at the pond the player is at (q(80))
	rt.here = {"space": "mine", "place": ""}   # the mine is the homestead
	m._sync_here()
	assert_that(fm.anchor_of("self")).is_equal(fm.points.self.center)
	assert_bool(fm.anchor_shift.has("self")).is_false()
	assert_bool(fm.self_label_off).is_false()
	rt.here = saved
	m._sync_here()

static func _primary(rt: P0Runtime) -> String:
	return str((rt.ui._modal.find_child("Primary", true, false) as UiCommandButton).label)

static func _facts(rt: P0Runtime) -> Array:
	return rt.ui._modal.find_children("*", "UiFactRow", true, false).map(func(f): return str((f as UiFactRow).label))

func _close(rt: P0Runtime) -> void:
	rt.ui.close_modal()
	await get_tree().process_frame

## The place chip on the map goes back to where the player is; from a world it goes to the map.
class FakeWorld extends Node:
	var surface := "map"
	var space := ""
	var routes: Array = []
	func p0_surface() -> String: return surface
	func p0_return(route: String) -> void: routes.append(route)

func test_the_place_chip_on_the_map_goes_back_where_the_player_is() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var w: FakeWorld = auto_free(FakeWorld.new())
	rt.world = w
	rt.return_to = "pond:pond_shanghai_05"
	rt._on_place_pressed()
	assert_array(w.routes).is_equal(["pond:pond_shanghai_05"])

## Where each world sends the place chip back to: the farm, its farmhouse and the mine are the homestead.
class SpaceWorld extends Object:
	var space := ""
	var place := ""
	var outpost := {}
	func p0_space() -> String: return space
	func p0_place() -> String: return place

func test_the_route_back_from_each_world() -> void:
	var w := SpaceWorld.new()
	for c in [["home", "", {}, "farm"], ["mine", "", {}, "farm"], ["pond", "pond_shanghai_05", {}, "pond:pond_shanghai_05"],
			["outpost", "", {"id": "sh_tea_1"}, "outpost:sh_tea_1"], ["pond", "", {}, "farm"], ["outpost", "", {}, "farm"]]:
		w.space = c[0]
		w.place = c[1]
		w.outpost = c[2]
		assert_str(P0Runtime.route_of(w)).append_failure_message(str(c)).is_equal(c[3])
	w.free()

## 李元芳 int8: the dev entry outpost:<id> pushes the outpost onto the empty p0_boot; leaving it goes to the map
## instead of a blank screen. Over the farm root (the first session's farmhouse) or the map it just pops.
func test_a_room_on_the_empty_boot_leaves_for_the_map() -> void:
	assert_bool(P0Runtime.room_leaves_for_map(1, false)).is_true()    # outpost on the empty p0_boot
	assert_bool(P0Runtime.room_leaves_for_map(1, true)).is_false()    # farmhouse on the farm root, or a room on the map
	assert_bool(P0Runtime.room_leaves_for_map(2, false)).is_false()   # farmhouse on a farm on the boot

## 不知火舞 on 234 / A2: opening the map frames the home set in z13.5–16, labels included, in the safe frame — the own
## avatar and the marked pins (the first session's Reed Pond) always, then each role's outpost nearest home, nearest
## the avatar first, while z13.5 holds them all.
func _board(have: int) -> Dictionary:
	var reqs: Array = [] if have < 0 else [{"id": P0Guide.TUTORIAL, "have": have, "qty": 2}]
	return {"stall": {"board": {"requests": reqs}}}

func test_the_opening_view_frames_the_home_set() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var safe: Rect2 = m.frame_safe_rect()
	var id_of := func(it): return str(it.get("id", "self"))
	for phase in [[0, "first"], [-1, "after"]]:
		rt.session.view = _board(int(phase[0]))
		m.frame_home_set()
		var framed: Array = m.framed
		var z: float = m.zoom
		var at := Vector2(m.center_lat, m.center_lng)
		var ids: Array = framed.map(id_of)
		assert_bool(ids.has("self")).is_true()
		assert_bool(ids.has("pond_shanghai_05")).is_equal(phase[1] == "first")   # the marked pin always goes in
		assert_float(m.zoom).append_failure_message(phase[1]).is_between(13.5, 16.0)
		var box: Rect2 = m._frame_box(framed)
		assert_bool(safe.grow(0.5).encloses(box)).append_failure_message("%s: %s in %s at z%.1f" % [phase[1], box, safe, m.zoom]).is_true()
		# The home set goes in nearest the avatar first and stops at the first that z13.5 cannot hold with the rest.
		var must: int = m.frame_must().size()
		var optional: Array = m.frame_optional()
		var n := framed.size() - must
		assert_array(framed.slice(must).map(id_of)).is_equal(optional.slice(0, n).map(id_of))
		if n < optional.size(): assert_dict(m._fit(framed + [optional[n]], safe)).is_empty()   # (moves the camera)
		if phase[1] == "first":   # the first session (不知火舞 on 234 A2): the far Travel Post stays offscreen
			assert_bool(ids.has("sh_post_1")).is_false()
			assert_array(ids).contains(["sh_tea_1", "sh_market_1", "sh_tackle_1"])
		# The smallest such view: a tenth closer, the set no longer fits wherever it is centred.
		var fits_closer := false
		if z + 0.1 <= 16.0:
			m._look(at, z + 0.1)
			for k in 3:
				var b: Rect2 = m._frame_box(framed)
				m._pan_by(safe.get_center() - b.get_center())
			fits_closer = safe.encloses(m._frame_box(framed))
		assert_bool(fits_closer).append_failure_message(phase[1]).is_false()
	# A MapDestination is framed with a name row under it and over it (刘邦 on #111): either side stays in the frame.
	var tea := P0Outposts.place_entry(P0Outposts.by_role("tea"))
	var fp: Rect2 = m._frame_footprint(tea)
	var name_h := UiMapDestination.label_size_for(m.city_map._label_text(tea)).y
	assert_float(fp.position.y).is_equal_approx(-UiMapDestination.DISC - UiMapDestination.above_gap_for(false) - name_h, 0.01)
	assert_float(fp.end.y).is_equal_approx(UiMapDestination.LABEL_GAP + name_h, 0.01)
	rt.session.view = saved

## The P0Runtime singleton the map brought up goes with the suite (P0Runtime.free_instance_for_tests).
func after() -> void:
	P0Runtime.free_instance_for_tests()

## 李元芳 int10: Android Back on the map closes P0's layers one per press — Bag, Today, the Inbox, a pond card under its
## fish list, an outpost's card — and only with none left is it the map's own (LOCK-06). #92 brought P0's HUD and Bag
## to the map without this; int9's map had neither.
func test_back_on_the_map_closes_p0_layers_one_at_a_time() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var ui: P0Ui = rt.ui
	var saved: Dictionary = rt.session.view
	var v := _bag_view()
	rt.session.view = v
	ui.set_view(v)
	assert_str(ui.space).is_equal("map")
	assert_bool(m.is_back_navigation_locked()).is_false()   # nothing open: the map's own Back
	for layer in ["bag", "today", "inbox"]:
		match layer:
			"bag": ui.open_bag()
			"today": ui.open_today()
			"inbox": ui.open_inbox()
		assert_bool(ui.has_modal()).append_failure_message(layer).is_true()
		assert_bool(m.is_back_navigation_locked()).append_failure_message(layer).is_true()
		assert_bool(ui.has_modal()).append_failure_message(layer).is_false()
		await get_tree().process_frame
	# Two layers on the map: a pond card and its Details › fish list (#95). Back: the list, then the card, then the
	# map's own. (The map's quick bar is Bag alone, so no slot can be lifted or dragged here.)
	m.p0_dev(PackedStringArray(["pondfish", "pond_shanghai_05"]))
	await get_tree().process_frame
	assert_str(ui.modal_kind).is_equal("pond_fish")
	assert_bool(m.is_back_navigation_locked()).is_true()
	await get_tree().process_frame
	assert_str(ui.modal_kind).is_equal("pond_card")
	assert_bool(m.is_back_navigation_locked()).is_true()
	await get_tree().process_frame
	assert_bool(ui.has_modal()).is_false()
	assert_bool(m.is_back_navigation_locked()).is_false()
	# An outpost's card (#100): one Back.
	m.city_map.select(P0Outposts.place_entry(P0Outposts.by_role("tea")))
	assert_str(ui.modal_kind).is_equal("place_card")
	assert_bool(m.is_back_navigation_locked()).is_true()
	assert_bool(ui.has_modal()).is_false()
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()
	rt.session.view = saved

func _bag_view() -> Dictionary:
	return {"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000}, "coins": 40, "skills": {},
		"items": {"seed_herb": {"kind": "seed"}}, "names": {"seed_herb": "Herb Seeds"},
		"bag": {"capacity": 25, "free": 24, "slots": [{"id": "seed_herb", "qty": 5}]}, "plots": [],
		"inbox": {"limit": 8, "badge": 0, "waiting": 0, "claim_slots": 0, "parcels": [], "updates": []}}

func _landed(m: Node) -> void:   # the map's own flight (SGODOT-267) has landed, at most 2 s
	var until := Time.get_ticks_msec() + 2000
	while m._flight != null and m._flight.is_running() and Time.get_ticks_msec() < until: await get_tree().process_frame
