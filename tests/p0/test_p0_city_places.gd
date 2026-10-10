extends GdUnitTestSuite
## SGODOT-280 / 275 (李元芳 round 3): another city's ponds and outposts on the map, from the server's generator
## (GET /v1/p0/city/:cluster), entered like the home city's; the first visit's "3 things to do here" (MAP-7-FREE).

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const P0Outposts := preload("res://modules/p0/p0_outposts.gd")
const P0Ponds := preload("res://modules/p0/p0_ponds.gd")
const PondCard := preload("res://modules/p0/p0_pond_card.gd")
const TOKYO := "gn-1850147"
const SF := "gn-5391959"

## Tokyo as the server's generator gives it (cityPlaces, trimmed to two of each).
const CITY := {
	"ponds": ["gn-1850147~pond0", "gn-1850147~pond1"], "outposts": ["gn-1850147~post0", "gn-1850147~market0"],
	"residents": 9, "fish": [{"fish": "fish_grass_carp", "level": 3}, {"fish": "fish_smelt", "level": 1}],
	"detail": {
		"ponds": [
			{"id": "gn-1850147~pond0", "name": "Willow Pond", "site": "pond", "beginner": true, "lat": 35.682835, "lng": 139.718115,
				"template_id": "crescent", "decoration_seed": 3674092014},
			{"id": "gn-1850147~pond1", "name": "Reed Creek", "site": "river", "beginner": false, "lat": 35.67426, "lng": 139.671401,
				"template_id": "gourd", "decoration_seed": 1035405354}],
		"outposts": [
			{"id": "gn-1850147~post0", "role": "post", "name": "Tokyo Travel Post", "lat": 35.690732, "lng": 139.69817,
				"category": "Travel post · Coffee", "keeper": {"role": "Post Clerk", "name": "Tom", "look": "post_temperate_0"},
				"residents": ["res_pip", "res_sam"], "art": "post_office", "anchors": "res://assets/p0/outposts/post.anchors.json", "capacity": 12},
			{"id": "gn-1850147~market0", "role": "market", "name": "Tokyo Market Square", "lat": 35.684175, "lng": 139.712805,
				"category": "Market square · Requests", "keeper": {"role": "Market Keeper", "name": "Elsa", "look": "market_temperate_1"},
				"residents": ["res_nadia", "res_theo"], "art": "fruit_shop", "anchors": "res://assets/p0/outposts/market.anchors.json", "capacity": 30}]},
	"preview": {"cluster": "gn-1850147", "name": "Tokyo"},
}

func before_test() -> void:
	P0CityPlaces.clear()
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	P0CityPlaces.clear()
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

func test_a_city_read_registers_its_ponds_and_outposts_by_their_ids() -> void:
	P0CityPlaces.accept(TOKYO, CITY)
	# a generated pond is a pond the scene, the loading cover and the card read like Fern Pond
	var pond := P0Ponds.location("gn-1850147~pond0")
	assert_str(str(pond.get("name", ""))).is_equal("Willow Pond")
	assert_dict(SystemPonds.site(pond)).is_not_empty()
	assert_object(SystemPonds.blueprint(pond)).is_not_null()
	var card := PondCard.info({}, "gn-1850147~pond0", 1.2)
	assert_str(str(card.get("subtitle", ""))).is_equal("Beginner")
	# a generated outpost takes the room of its art (walls, seats, anchors) and keeps its own name, keeper and point
	var o := P0Outposts.find("gn-1850147~market0")
	assert_str(str(o.name)).is_equal("Tokyo Market Square")
	assert_str(str(o.keeper.name)).is_equal("Elsa")
	assert_str(str(o.cluster)).is_equal(TOKYO)
	assert_array(o.bounds).is_equal(P0Outposts.by_role("market").bounds)
	assert_str(str(P0CityPlaces.beginner_pond(TOKYO).id)).is_equal("gn-1850147~pond0")
	assert_str(str(P0CityPlaces.first_outpost(TOKYO).id)).is_equal("gn-1850147~market0")
	# an id of a city not read yet is unknown; home ids are untouched
	assert_dict(P0Outposts.find("gn-1816670~tea0")).is_empty()
	assert_str(str(P0Outposts.by_role("market").id)).is_equal("sh_market_1")

func test_the_camera_city_reads_its_places_and_pins_them() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var asked: Array = []
	rt.session.transport = func(_m: int, path: String, _b: Dictionary, cmd: Dictionary):
		if str(cmd.get("type", "")) == "city": asked.append(path)
	m._switch_city(load("res://modules/p0/p0_clusters.gd").region(TOKYO))
	assert_array(asked).is_equal(["/p0/city/gn-1850147"])
	P0CityPlaces.accept(TOKYO, CITY)
	m._show_city_places(P0CityPlaces.city(TOKYO), TOKYO)
	var ids: Array = m.city_map.extra_places.map(func(e): return str(e.id))
	assert_array(ids).contains(["gn-1850147~post0", "gn-1850147~market0"])
	assert_array(ids).contains(["sh_tea_1"])   # home's stay
	m._switch_city(load("res://modules/p0/p0_clusters.gd").region(SF))   # home: never read, hand-written
	assert_int(asked.size()).is_equal(1)

func test_a_first_visit_lands_on_three_things_to_do() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	P0CityPlaces.accept(TOKYO, CITY)
	m.open_arrival_card(TOKYO)
	assert_str(rt.ui.modal_kind).is_equal("arrival_card")
	var texts: Array = rt.ui.root.find_children("*", "Label", true, false).filter(func(l): return (l as Label).is_visible_in_tree()).map(func(l): return (l as Label).text)
	for t in ["Tokyo", "Trip 6 · Intercontinental", "Choose your first local activity.", "Local pond", "Pond Crucian for every level", "Outpost",
			"Temperate seeds and local requests", "Tokyo stamp", "New", "View it in your Passport"]:
		assert_array(texts).override_failure_message("missing " + t).contains([t])
	var link := rt.ui.root.find_child("Link_Show_local_pond", true, false)
	assert_str(str(link.get("label"))).is_equal("Show local pond")   # a NavigationRow (its text is the Button's)
	var primary := rt.ui.root.find_child("Primary", true, false)
	assert_str(str(primary.get("label"))).is_equal("Visit the outpost")
	assert_object(rt.ui.root.find_child("Handle", true, false)).is_not_null()   # the sheet's grip (不知火舞 on #248)
	rt.ui.close_modal()

## The arrival card's Visit the outpost goes to the market square nearest where the player landed (不知火舞 on #248).
func test_visit_the_outpost_is_the_nearest_market_square() -> void:
	var two: Dictionary = CITY.duplicate(true)
	two.detail.outposts.append({"id": "gn-1850147~market2", "role": "market", "name": "Oak Market Square", "lat": 35.7453, "lng": 139.7130,
		"category": "Market square · Requests", "keeper": {"role": "Market Keeper", "name": "Ivy", "look": "market_temperate_0"},
		"residents": [], "art": "fruit_shop", "anchors": "res://assets/p0/outposts/market.anchors.json", "capacity": 30})
	P0CityPlaces.accept(TOKYO, two)
	assert_str(str(P0CityPlaces.nearest_outpost(TOKYO, Vector2(35.745, 139.713)).id)).is_equal("gn-1850147~market2")
	assert_str(str(P0CityPlaces.nearest_outpost(TOKYO, Vector2(35.684, 139.712)).id)).is_equal("gn-1850147~market0")

## PASS-1 (不知火舞 on #256): a city row that opens its page ends in ›; the home row has none and takes no tap.
func test_the_passports_city_rows_open_their_pages_and_say_so() -> void:
	var rt := P0Runtime.ensure()
	await get_tree().process_frame
	rt.ui.close_modal()
	var saved: Dictionary = rt.ui.view
	var v := saved.duplicate(true)
	v["travel"] = {"home": SF, "here": SF, "today": "2026-10-10", "passes": {}, "stamps": [],
		"visits": {TOKYO: {"n": 2, "first_at": 1.0, "deliveries": 0}}}
	rt.ui.view = v
	rt.ui.open_passport()
	assert_str(rt.ui.modal_kind).is_equal("passport")
	var tokyo := rt.ui.root.find_child("Row_Tokyo", true, false)
	assert_object(tokyo).is_instanceof(Button)
	assert_object(tokyo.find_child("Chevron", false, false)).is_not_null()
	var home := rt.ui.root.find_child("Row_San_Francisco", true, false)
	assert_bool(home is Button).is_false()
	(tokyo as Button).pressed.emit()
	assert_str(rt.ui.modal_kind).is_equal("city_page")
	var texts: Array = rt.ui.root.find_children("*", "Label", true, false).filter(func(l): return (l as Label).is_visible_in_tree()).map(func(l): return (l as Label).text)
	assert_array(texts).contains(["2/10"])   # Local: Visits 2/10
	rt.ui.close_modal()
	rt.ui.view = saved

## 李元芳 0.2.0 (286 5d27bd93): the map read the city first (its camera city), then the silhouette card asked while
## that read was out — the card's callback was dropped and it stayed at "–". Every asker hears the one answer.
func test_a_card_asking_while_the_maps_read_is_out_still_fills_in() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var asked: Array = []
	rt.session.transport = func(_m: int, path: String, _b: Dictionary, cmd: Dictionary):
		if str(cmd.get("type", "")) == "city": asked.append(path)
	m._switch_city(load("res://modules/p0/p0_clusters.gd").region(TOKYO))   # the map's read goes out
	m.open_city_card(TOKYO)   # the card asks while it is out
	assert_array(asked).is_equal(["/p0/city/gn-1850147"])   # one read, not two
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	var counts := func() -> Array:
		var rows: Array = rt.ui.root.find_children("*", "UiItemRow", true, false).filter(func(r): return (r as Control).is_visible_in_tree())
		return rows.map(func(r): return str(r.quantity))
	assert_array(counts.call()).is_equal(["–", "–", "–"])
	var city: Dictionary = CITY.duplicate(true)
	city.preview = {"cluster": TOKYO, "trip": 6, "km": 8278, "trip_name": "Intercontinental", "utc_offset_min": 540,
		"counts": {"ponds": 2, "outposts": 2, "residents": 9}}
	P0CityPlaces.accept(TOKYO, city)   # the answer
	await get_tree().process_frame   # the card is rebuilt; the old one leaves at the end of the frame
	assert_str(rt.ui.modal_kind).is_equal("city_card")
	assert_array(counts.call()).is_equal(["2", "2", "9"])
	assert_array(m.city_map.extra_places.map(func(e): return str(e.id))).contains(["gn-1850147~market0"])   # the map's too
	# the refilled card's Travel details › works the first time (李元芳, 279 fd340f21: it went to the card closed for it)
	(rt.ui.root.find_child("Link_Travel_details", true, false) as Button).pressed.emit()
	assert_str(rt.ui.modal_kind).is_equal("travel_card")
	rt.ui.close_modal()

## A cross-city request's Show on map (苏烈, SGODOT-284): `outpost:gn-…~market0` of a city not read yet reads it, pins
## it, then flies there; the same from another scene through after_leave.
func test_show_on_map_reads_another_city_then_flies_to_its_pin() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var asked: Array = []
	rt.session.transport = func(_m: int, path: String, _b: Dictionary, cmd: Dictionary):
		if str(cmd.get("type", "")) == "city": asked.append(path)
	assert_dict(m.place_for("outpost:gn-1850147~market0")).is_empty()   # not read: no pin known
	m.show_place("outpost:gn-1850147~market0")
	assert_array(asked).is_equal(["/p0/city/gn-1850147"])
	P0CityPlaces.accept(TOKYO, CITY)   # the answer: pinned, then the flight
	assert_array(m.city_map.extra_places.map(func(e): return str(e.id))).contains(["gn-1850147~market0"])
	assert_float(float(m.place_for("outpost:gn-1850147~market0").lat)).is_equal_approx(35.684175, 0.000001)
	assert_str(str(m.place_for("pond:gn-1850147~pond0").name)).is_equal("Willow Pond")
	m.show_place("outpost:gn-1850147~market0")   # read: no second request
	assert_int(asked.size()).is_equal(1)
	# from another scene: after_leave carries it to the map, which accepts the unread target
	P0CityPlaces.clear()
	rt.after_leave = "show:outpost:gn-1850147~post0"
	assert_bool(m._take_after_leave()).is_true()

## 不知火舞 on #279: Show on map to another city whose read fails says so — Didn't go through · try again — never silently
## nothing; the next Show reads again.
func test_show_on_map_says_when_the_citys_read_fails() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var asked: Array = []
	rt.session.transport = func(_m: int, path: String, _b: Dictionary, cmd: Dictionary):
		if str(cmd.get("type", "")) == "city": asked.append(path)
	m.show_place("outpost:gn-1850147~market0")
	m.open_city_card(TOKYO)   # a second asker without a failed callback: stays quiet
	P0CityPlaces.fail(TOKYO)   # the read did not come back
	assert_str(rt.ui.sys_text()).is_equal("Didn't go through · try again")
	assert_bool(P0CityPlaces.has_city(TOKYO)).is_false()
	m.show_place("outpost:gn-1850147~market0")   # tries again
	assert_int(asked.size()).is_equal(2)
	# left the map while the read was out (a world over it): no banner there (不知火舞 on #282)
	var other := Node.new()
	add_child(auto_free(other))
	rt.world = other
	rt.ui.show_sys(UiSysBanner.Kind.CMD_FAIL, "earlier", 30.0)
	P0CityPlaces.fail(TOKYO)
	assert_str(rt.ui.sys_text()).is_equal("earlier")
	rt.world = m
	rt.ui.close_modal()

## MAP-2 (2107:32861, pin 2107:33077, 不知火舞 on #281 / #287): a place of a city the fog covers is its silhouette — a
## 32 px surface disc with a border edge, the 18 px glyph in color/secondary, no name, the whole pin (glyph and mark too)
## at 55 %; it takes the tap (its silhouette card) and turns full colour once the city is explored.
func test_a_fogged_citys_places_are_silhouettes_until_explored() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = {"home": SF, "here": SF, "passes": {}, "visits": {}, "stamps": [], "fallback": {"near3": [], "near10": []}, "explorer": 0}
	rt.session.view = v
	P0CityPlaces.accept(TOKYO, CITY)
	var tokyo_market := P0Outposts.place_entry(P0Outposts.find("gn-1850147~market0"))
	var home_market := P0Outposts.place_entry(P0Outposts.by_role("market"))
	assert_bool(bool(m._destination_style(tokyo_market).get("silhouette", false))).is_true()
	assert_bool(bool(m._destination_style({"kind": "pond", "id": "gn-1850147~pond0"}).get("silhouette", false))).is_true()
	assert_bool(bool(m._destination_style(home_market).get("silhouette", false))).is_false()   # home: full colour, P0's pin
	var pin := UiMapDestination.new(P0Logic.icon("board"), "Tokyo Market Square")
	add_child(auto_free(pin))
	pin.silhouette = true
	assert_vector(pin._disc.size).is_equal(Vector2(32, 32))   # 2107:33077: a 32 px surface disc, 1 px border edge
	var box := pin._disc.get_theme_stylebox("panel") as UiStyleBox
	assert_that(box.bg_color).is_equal(UiTokens.COLOR_SURFACE)
	assert_that(box.border_color).is_equal(UiTokens.COLOR_BORDER)
	assert_vector(pin._disc.position + pin._disc.size * 0.5).is_equal(Vector2.ONE * UiMapDestination.DISC * 0.5)   # same point
	assert_bool(pin._label_box.visible).is_false()
	assert_float(pin.modulate.a).is_equal_approx(0.55, 0.001)
	await get_tree().process_frame
	assert_vector(pin._icon.size).is_equal(Vector2(18, 18))
	assert_object(pin._icon.material).is_not_null()
	# the glyph's ink keeps the incoming alpha (the node's modulate in it): written over, it stayed at 100 % (#287)
	var ink: String = ((pin._icon.material as ShaderMaterial).shader as Shader).code
	assert_str(ink).contains("COLOR.a")
	pin.mark = "request"   # a mark sits on the smaller disc's corner (蒙恬 on #287)
	assert_vector(pin._badge.position).is_equal(UiMapDestination._MARK_AT + Vector2(4, 4))
	pin.silhouette = false   # explored: the pin as ever
	assert_vector(pin._badge.position).is_equal(UiMapDestination._MARK_AT)
	assert_vector(pin._disc.size).is_equal(Vector2(40, 40))
	assert_object(pin._icon.material).is_null()
	assert_float(pin.modulate.a).is_equal(1.0)
	# exploring the city drops its silhouettes (the style cache follows the visits)
	rt.session.view.travel.visits = {TOKYO: {"n": 1}}
	assert_bool(bool(m._destination_style(tokyo_market).get("silhouette", false))).is_false()
	assert_bool(m._travel_first(tokyo_market)).is_true()   # still no pass here: a tap opens its card
	rt.ui.close_modal()
	rt.session.view = saved
