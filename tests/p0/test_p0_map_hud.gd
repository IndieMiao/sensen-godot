extends GdUnitTestSuite
## MAP-1 (§10.6.1, SGODOT-234 A1; 不知火舞 on 234): on the map P0's two-row HUD and Bag replace the map's own chrome —
## no city title, filters, place list, compass, Map / Farm / Me dock or + / −; the recenter key sits right over Bag,
## 12 apart, and keeps the zoom. The place chip names where the player is and takes them back there. Pin cards: the
## player's own pin says Go home · Free, ponds and outposts Go. The own pin reads Homestead.

const P0_MAP := "res://scenes/p0/p0_map.tscn"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())

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
	assert_float(m.center_lat).is_equal_approx(m.home_lat, 1e-6)
	assert_float(m.center_lng).is_equal_approx(m.home_lng, 1e-6)
	assert_float(m.zoom).is_equal_approx(13.3, 1e-6)

func test_pin_cards_say_go_home_and_go() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	m._own_pin_pressed()
	assert_str(str(city.selected.get("id", ""))).is_equal("player:self")
	assert_str(city.info_action.text).is_equal("Go home · Free")
	assert_str(city.info_title.text).is_equal("Homestead")
	m._own_pin_pressed()   # a second tap closes it
	assert_dict(city.selected).is_empty()
	# A pond's card (an id outside the catalog, so selecting it prewarms no pond scene).
	var pond: Dictionary = (city.entries.filter(func(e): return str(e.get("kind", "")) == "pond")[0] as Dictionary).duplicate()
	pond.id = "test_pond"
	city.select(pond)
	assert_str(city.info_action.text).is_equal("Go")
	city.select(P0Outposts.place_entry(P0Outposts.by_role("tea")))
	assert_str(city.info_action.text).is_equal("Go")
	city.clear_selection()

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

## 不知火舞 on 234: opening the map frames the home set — the own avatar, each role's outpost nearest home and the
## marked pins (the first session's Reed Pond), labels included — in the safe frame, as close as z12–16 allows.
func _board(have: int) -> Dictionary:
	var reqs: Array = [] if have < 0 else [{"id": P0Guide.TUTORIAL, "have": have, "qty": 2}]
	return {"stall": {"board": {"requests": reqs}}}

func test_the_opening_view_frames_the_home_set() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var zooms := {}
	for phase in [[0, "first"], [-1, "after"]]:
		rt.session.view = _board(int(phase[0]))
		m.frame_home_set()
		var items: Array = m.home_set_items()
		var ids: Array = items.map(func(it): return str(it.get("id", "self")))
		assert_array(ids).contains(["self", "sh_tea_1", "sh_market_1", "sh_tackle_1", "sh_post_1"])
		assert_bool(ids.has("pond_shanghai_05")).is_equal(phase[1] == "first")   # Reed Pond while it wears the !
		assert_float(m.zoom).is_between(12.0, 16.0)
		var safe: Rect2 = m.frame_safe_rect()
		var box: Rect2 = m._frame_box(items)
		assert_bool(safe.grow(0.5).encloses(box)).append_failure_message("%s: %s in %s at z%.1f" % [phase[1], box, safe, m.zoom]).is_true()
		zooms[phase[1]] = m.zoom
		# The smallest such view: a tenth closer, the set no longer fits wherever it is centred.
		var fits_closer := false
		var z: float = m.zoom
		if z + 0.1 <= 16.0:
			m._look(Vector2(m.center_lat, m.center_lng), z + 0.1)
			for k in 3:
				var b: Rect2 = m._frame_box(items)
				m._pan_by(safe.get_center() - b.get_center())
			fits_closer = safe.encloses(m._frame_box(items))
		assert_bool(fits_closer).append_failure_message(phase[1]).is_false()
	rt.session.view = saved
