extends GdUnitTestSuite
## SGODOT-311 / 303: the player's home set comes from view.home (the city picked, its outposts and beginner pond frozen
## with it), not the written city's tables. A save at home in San Francisco reads exactly what it did; a home in a
## generated city (Tokyo here, as the server's generator gives it) names its own market, sends Show on map to its own
## pins and fishes its own beginner pond.

const P0Outposts := preload("res://modules/p0/p0_outposts.gd")
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const P0Guide := preload("res://modules/p0/p0_guide.gd")
const TOKYO := "gn-1850147"
const SF := "gn-5391959"

## Tokyo as the server's generator gives it (cityPlaces, trimmed): its Travel Post 1, Market Square 1, a tea house and a
## tackle shop by its beginner pond.
const CITY := {
	"ponds": ["gn-1850147~pond0"], "outposts": ["gn-1850147~post0", "gn-1850147~market0", "gn-1850147~tea0", "gn-1850147~tackle0"],
	"residents": 4, "fish": [],
	"detail": {
		"ponds": [
			{"id": "gn-1850147~pond0", "name": "Willow Pond", "site": "pond", "beginner": true, "lat": 35.682835, "lng": 139.718115,
				"template_id": "crescent", "decoration_seed": 3674092014}],
		"outposts": [
			{"id": "gn-1850147~post0", "role": "post", "name": "Tokyo Travel Post", "lat": 35.690732, "lng": 139.69817,
				"category": "Travel post · Coffee", "keeper": {"role": "Post Clerk", "name": "Tom", "look": "post_temperate_0"},
				"residents": ["res_pip", "res_sam"], "art": "post_office", "anchors": "res://assets/p0/outposts/post.anchors.json", "capacity": 12},
			{"id": "gn-1850147~market0", "role": "market", "name": "Shibuya Market Square", "lat": 35.684175, "lng": 139.712805,
				"category": "Market square · Requests", "keeper": {"role": "Market Keeper", "name": "Elsa", "look": "market_temperate_1"},
				"residents": ["res_nadia"], "art": "fruit_shop", "anchors": "res://assets/p0/outposts/market.anchors.json", "capacity": 30},
			{"id": "gn-1850147~tea0", "role": "tea", "name": "Maple Tea House", "lat": 35.70, "lng": 139.72,
				"category": "Tea house · Hot tea", "keeper": {"role": "Tea Host", "name": "Hana", "look": "tea_temperate_0"},
				"residents": [], "art": "coffee_shop", "anchors": "res://assets/p0/outposts/tea.anchors.json", "capacity": 12},
			{"id": "gn-1850147~tackle0", "role": "tackle", "name": "Willow Tackle Shop", "lat": 35.6840, "lng": 139.7170,
				"category": "Tackle shop · Bait", "keeper": {"role": "Tackle Keeper", "name": "Ren", "look": "tackle_temperate_0"},
				"residents": [], "art": "farm_tools_store", "anchors": "res://assets/p0/outposts/tackle.anchors.json", "capacity": 12,
				"nearest": {"name": "Willow Pond", "site": "pond"}}]},
	"preview": {"cluster": "gn-1850147", "name": "Tokyo"},
}

## A save whose home is Tokyo (view.home, SGODOT-303).
static func _tokyo_home() -> Dictionary:
	return {"travel": {"home": TOKYO, "here": TOKYO}, "home": {"city": TOKYO, "name": "Tokyo", "pending": false,
		"farm": {"lat": 35.6801, "lng": 139.7102},
		"set": {"market": "gn-1850147~market0", "tea": "gn-1850147~tea0", "tackle": "gn-1850147~tackle0",
			"post": "gn-1850147~post0", "pond": "gn-1850147~pond0"}}}

func before_test() -> void:
	P0CityPlaces.accept(TOKYO, CITY)

func test_san_francisco_reads_its_own_tables_as_before() -> void:
	for v in [{}, {"travel": {"home": SF}}]:   # an older server (no view.home), and a San Francisco save
		assert_str(P0Outposts.home_id(v, "market")).is_equal("sh_market_1")
		assert_str(str(P0Outposts.home(v, "tea").name)).is_equal(str(P0Outposts.by_role("tea").name))
		assert_str(P0Guide.home_pond(v)).is_equal(P0Guide.BEGINNER_POND)
		assert_bool(P0Travel.home_is_written(v)).is_true()
		assert_str(P0Travel.home_name(v)).is_equal("San Francisco")
	var sf := {"travel": {"home": SF}, "home": {"city": SF, "name": "San Francisco",
		"set": {"market": "sh_market_1", "tea": "sh_tea_1", "tackle": "sh_tackle_1", "post": "sh_post_1", "pond": P0Guide.BEGINNER_POND}}}
	assert_str(P0Outposts.home_id(sf, "tackle")).is_equal("sh_tackle_1")

func test_a_generated_home_names_its_own_set() -> void:
	var v := _tokyo_home()
	assert_bool(P0Travel.home_is_written(v)).is_false()
	assert_str(P0Travel.home_name(v)).is_equal("Tokyo")
	assert_that(P0Travel.home_farm(v)).is_equal(Vector2(35.6801, 139.7102))
	assert_str(P0Outposts.home_id(v, "market")).is_equal("gn-1850147~market0")
	assert_str(str(P0Outposts.home(v, "market").name)).is_equal("Shibuya Market Square")
	assert_str(str(P0Outposts.home(v, "tackle").name)).is_equal("Willow Tackle Shop")
	assert_str(P0Guide.home_pond(v)).is_equal("gn-1850147~pond0")

func test_the_market_board_hands_in_at_the_home_market() -> void:
	var v := _tokyo_home()
	v["boards"] = {"stall": {"slots": []}, "market": {"slots": [{"id": "req_dusk", "title": "Dusk Haul", "kind": "fish",
		"rarity": 2, "items": [], "have": 4, "qty": 4, "ready": true, "status": "accepted"}]}}
	var rows := P0Logic.today_rows(v)
	assert_that([rows[0].line, rows[0].go]).is_equal(["Dusk Haul · Deliver at Shibuya Market Square", "outpost:gn-1850147~market0"])
	var d := P0Board.detail(v, "market", "req_dusk")
	assert_str(str(d.effect)).ends_with("to any Tokyo market.")

func test_a_stamp_run_goes_to_its_outpost_by_id_and_fish_to_the_home_pond() -> void:
	var v := _tokyo_home()
	assert_str(P0Board._go(v, {"visit": {"place": "gn-1850147~tea0"}}, "")).is_equal("outpost:gn-1850147~tea0")
	assert_str(P0Board._go(v, {"kind": "fish"}, "fish_crucian")).is_equal("pond:gn-1850147~pond0")

func test_the_first_session_row_names_the_home_beginner_pond() -> void:
	var v := _tokyo_home()
	assert_str(P0Guide._place_name(v, P0Guide.home_pond(v))).is_equal("Willow Pond")

func test_the_tea_host_names_the_city_the_player_is_in() -> void:
	var v := _tokyo_home()
	assert_str(P0Logic._here_name(v)).is_equal("Tokyo")
	v.travel.here = SF
	assert_str(P0Logic._here_name(v)).is_equal("San Francisco")

func test_the_place_chip_names_the_generated_home() -> void:
	var v := _tokyo_home()
	var farm := {city = "San Francisco", space = "Homestead", kind = UiHud.PlaceKind.HOME, day_pass = ""}
	assert_dict(P0Travel.place(v, farm, "home")).is_equal({city = "Tokyo", space = "Homestead", kind = UiHud.PlaceKind.HOME, day_pass = ""})
	assert_dict(P0Travel.place({"travel": {"home": SF}}, farm, "home")).is_equal(farm)   # San Francisco's own chip, as before
