extends GdUnitTestSuite
## The P0 home city (SGODOT-270, q(106)): every place chip, the map's region, the beginner pond and the homestead's map
## point come from content.profile and fishing.places through P0City, so moving the whole server is a data change.

const P0City := preload("res://modules/p0/p0_city.gd")
const P0Map := preload("res://scenes/p0/p0_map.gd")

func test_the_city_comes_from_the_content() -> void:
	var profile: Dictionary = P0Logic.content().profile
	assert_str(P0City.city_name()).is_equal(str(profile.city))
	assert_str(P0City.region()).is_equal(str(profile.region))
	assert_str(P0City.short_name()).is_equal(str(profile.get("city_short", profile.city)))
	assert_that(P0City.farm_at()).is_equal(Vector2(float(profile.farm_at[0]), float(profile.farm_at[1])))
	assert_str(P0City.chip("Homestead")).is_equal("%s · Homestead" % profile.get("chip_city", profile.city))
	assert_str(P0City.chip("Homestead", true)).is_equal("%s · Homestead" % P0City.short_name())

## The beginner pond is fishing.places' beginner one (周瑜 on 270: one source with the server's markers), and every
## place that names it reads it.
func test_the_beginner_pond_is_the_places_beginner_one() -> void:
	var places: Dictionary = P0Logic.content().fishing.places
	var beginner := places.keys().filter(func(id): return bool(places[id].get("beginner", false)))
	assert_int(beginner.size()).is_equal(1)
	assert_str(P0City.beginner_pond()).is_equal(str(beginner[0]))
	assert_str(P0Guide.BEGINNER_POND).is_equal(P0City.beginner_pond())
	assert_str(P0Map.NEAREST_POND).is_equal(P0City.beginner_pond())

## No P0 script spells the city out any more: the chips, the keepers' answers and the boards read P0City.
func test_no_p0_script_spells_the_city_out() -> void:
	var city := P0City.city_name()
	for path in ["res://modules/p0/p0_runtime.gd", "res://scenes/p0/p0_farm.gd", "res://scenes/p0/p0_mine.gd",
			"res://scenes/p0/p0_ui.gd", "res://scenes/p0/panels/p0_loading_layer.gd", "res://scenes/p0/rooms/p0_room.gd",
			"res://modules/p0/p0_board.gd", "res://modules/p0/p0_logic.gd", "res://scenes/p0/p0_map.gd",
			"res://modules/p0/p0_guide.gd", "res://modules/p0/p0_pin_reason.gd"]:
		var lines: Array = Array(FileAccess.get_file_as_string(path).split("\n")).filter(func(l): return not str(l).strip_edges().begins_with("#"))
		var code := "\n".join(PackedStringArray(lines))
		assert_bool(code.contains("\"%s" % city) or code.contains("%s ·" % city)).override_failure_message("%s spells %s" % [path, city]).is_false()
		assert_bool(code.contains("\"%s\"" % P0City.beginner_pond())).override_failure_message("%s names the beginner pond" % path).is_false()

## The loading cover says where the player is going in the same words as the chip there.
func test_the_loading_cover_names_the_city() -> void:
	assert_str(P0LoadingLayer.destination("res://scenes/p0/p0_farm.tscn", {})).is_equal(P0City.chip("Homestead"))
	assert_str(P0LoadingLayer.destination("res://scenes/p0/p0_mine.tscn", {"floor": 2})).is_equal(P0City.chip("Mine · Floor 2"))

## With profile.chip_city set (李白 5965ec02: SF on every chip), the homestead, a room and the loading cover all write it.
func test_every_chip_writes_chip_city_when_the_content_sets_it() -> void:
	var profile: Dictionary = P0Logic.content().profile
	var had = profile.get("chip_city", null)
	profile["chip_city"] = "XY"
	assert_str(P0City.chip("Homestead")).is_equal("XY · Homestead")
	assert_str(P0LoadingLayer.destination("res://scenes/p0/p0_farm.tscn", {})).is_equal("XY · Homestead")
	assert_str(P0LoadingLayer.destination("res://scenes/p0/p0_outpost.tscn", {"outpost_id": "sh_tea_1"})) \
		.is_equal("XY · " + str(P0Outposts.find("sh_tea_1").name))
	var room := FileAccess.get_file_as_string("res://scenes/p0/rooms/p0_room.gd")
	assert_bool(room.contains("set_place(P0City.chip_for(place_name")).is_true()   # the rooms' chip goes through P0City too
	assert_str(P0City.chip_for("Homestead", "")).is_equal("XY · Homestead")   # a home place: chip()
	# another city's place (a generated id, SGODOT-280) names its own city
	assert_str(P0City.chip_for("Tokyo Market Square", "gn-1850147~market0")).is_equal("Tokyo · Tokyo Market Square")
	assert_bool(room.contains('" · " + place_name')).is_false()
	if had == null: profile.erase("chip_city")
	else: profile["chip_city"] = had
