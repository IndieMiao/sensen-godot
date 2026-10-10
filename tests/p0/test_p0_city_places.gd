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
	for t in ["Tokyo", "Nearby", "Choose your first local activity.", "Local pond", "Pond Crucian for every level", "Outpost",
			"Temperate seeds and local requests", "Tokyo stamp", "New", "View it in your Passport"]:
		assert_array(texts).override_failure_message("missing " + t).contains([t])
	var link := rt.ui.root.find_child("Link_Show_local_pond", true, false)
	assert_str(str(link.get("label"))).is_equal("Show local pond")   # a NavigationRow (its text is the Button's)
	var primary := rt.ui.root.find_child("Primary", true, false)
	assert_str(str(primary.get("label"))).is_equal("Visit the outpost")
	assert_object(rt.ui.root.find_child("Handle", true, false)).is_not_null()   # the sheet's grip (不知火舞 on #248)
	rt.ui.close_modal()

## The arrival card's Visit the outpost goes to the market square nearest where the player landed (Nearby, 不知火舞 on #248).
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
