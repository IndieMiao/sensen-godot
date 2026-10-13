extends GdUnitTestSuite
## q(119) (李白, 283): the Bite Board's section titles and the keeper's line from today's best fish.

const Board := preload("res://modules/p0/p0_bite_board.gd")
const RIVER := ["fish_crucian", "fish_carp", "fish_mullet", "fish_perch", "fish_bass", "fish_trout", "fish_catfish", "fish_eel", "fish_sturgeon", "fish_arctic_char", "fish_salmon"]

func test_titles_add_forecast_from_lv3() -> void:
	assert_array(Board.titles(2)).is_equal(["Ponds", "Regional fish"])
	assert_array(Board.titles(3)).is_equal(["Ponds", "Regional fish", "Forecast"])

func test_q119_samples() -> void:
	# Lv2 on a rainy day: Trout (rain ×2) beats Carp (rain ×1.5); Bass (dawn/dusk ×2) ties Trout but the weather match wins
	assert_str(Board.line(RIVER, "rain", 2, {})).is_equal("Rainbow Trout bite in the rain. Bring worms.")
	assert_str(Board.line(["fish_seabass", "fish_mackerel", "fish_mullet"], "wind", 5, {})).is_equal("Sea Bass bite at dawn and dusk in the wind. Bring worms.")
	assert_str(Board.line(["fish_eel", "fish_crucian"], "rain", 9, {})).is_equal("River Eels only bite at night in the rain. Bring worms.")
	# an uncaught regional fish: named Regional fish (Arctic Char, dawn/dusk ×2, Lv3)
	assert_str(Board.line(["fish_arctic_char", "fish_crucian", "fish_perch"], "sun", 3, {})).is_equal("Regional fish bite at dawn and dusk. Bring worms.")

func test_regional_name_once_caught_and_the_lure_from_lv5() -> void:
	assert_str(Board.line(["fish_arctic_char", "fish_crucian"], "sun", 5, {"fish_arctic_char": 1})).is_equal("Arctic Char bite at dawn and dusk. Try a Spinner Lure.")
	assert_str(Board.line(["fish_arctic_char"], "sun", 4, {})).is_equal("Regional fish bite at dawn and dusk. Bring worms.")

func test_only_landable_fish_and_the_quiet_day() -> void:
	assert_str(Board.line(["fish_eel"], "rain", 8, {})).is_equal(Board.QUIET)   # River Eel needs Lv9
	assert_str(Board.line([], "sun", 10, {})).is_equal("Quiet day. Any pond will do.")
	assert_str(Board.line(["fish_crucian"], "sun", 1, {})).is_equal("Pond Crucians bite. Bring worms.")   # no factor: just bite

func test_ties_go_to_weather_then_level_then_id() -> void:
	# sunny Lv4: Koi (sun ×1.5) beats everything at 1.0; with Bass's ×2 dawn/dusk it is Bass (2.0 > 1.5)
	assert_str(str(Board.pick(["fish_koi", "fish_crucian"], "sun", 4).fish.id)).is_equal("fish_koi")
	assert_str(str(Board.pick(["fish_koi", "fish_bass"], "sun", 4).fish.id)).is_equal("fish_bass")
	# Trout (rain ×2) and Bass (dawn/dusk ×2) tie at 2 in the rain: the weather match wins
	assert_str(str(Board.pick(["fish_bass", "fish_trout"], "rain", 4).fish.id)).is_equal("fish_trout")

func test_quoted_with_the_keeper() -> void:
	assert_str(Board.quoted("Rainbow Trout bite in the rain. Bring worms.", "Finn")).is_equal("“Rainbow Trout bite in the rain. Bring worms.” —\u00a0Finn")

const FERN := {"name": "Fern Pond", "site": "pond", "template": "Pond", "time": "Dusk", "weather": "rain",
	"fish": ["fish_crucian", "fish_carp", "fish_perch", "fish_bass", "fish_koi", "fish_catfish", "fish_arctic_char", "fish_sturgeon", "fish_eel"],
	"forecast": [{"day": "Sun", "weather": "rain"}, {"day": "Mon", "weather": "wind"}, {"day": "Tue", "weather": "sun"}]}

func test_condition_line_and_tags() -> void:
	assert_array(Board.conditions(FERN)).is_equal([["dawn_dusk", "Dusk"], ["rain", "Rain"]])
	assert_str(Board.tags(Board.FishWorld._fish("fish_catfish"))).is_equal("Night ×2 · Rain ×1.5")
	assert_str(Board.tags(Board.FishWorld._fish("fish_eel"))).is_equal("Night only · Rain ×2")
	assert_str(Board.tags(Board.FishWorld._fish("fish_seabass"))).is_equal("Dawn & dusk ×2 · Windy ×1.5")
	assert_str(Board.tags(Board.FishWorld._fish("fish_crucian"))).is_equal("")

## From Fishing Lv8 the pond card says Biting now (不知火舞 on 283): the fish in the pool now, best factor first, at most 2
## named, ` · +N more` for the rest, no factors; an uncaught regional fish is `?`.
func test_biting_now_lists_the_pool_now_best_first() -> void:
	assert_str(Board.biting_now(FERN, 9, {"fish_arctic_char": 1})).is_equal("Arctic Char, Largemouth Bass · +%d more" % (_landable_now(FERN, 9) - 2))
	assert_bool(Board.biting_now(FERN, 9, {}).begins_with("?, Largemouth Bass")).is_true()   # an uncaught regional
	assert_str(Board.biting_now({}, 9, {})).is_equal("")

func _landable_now(place: Dictionary, level: int) -> int:
	var part := Board.part_now(place)
	return (place.fish as Array).filter(func(id):
		var f: Dictionary = preload("res://modules/p0/p0_fish_world.gd")._fish(str(id))
		return not f.is_empty() and int(f.get("level", 1)) <= level and preload("res://modules/p0/p0_fish_world.gd").bites_at(f, part)).size()

func test_biting_more_now_best_two_and_plus_n() -> void:
	# Dusk in the rain at Lv9: Bass dusk 2, Trout no (not in a Pond), Carp rain 1.5, Char (regional) dusk 2, Catfish rain 1.5,
	# Eel night only (out); Koi sun only (out)
	assert_str(Board.biting_more(FERN, 9, {"fish_arctic_char": 1})).is_equal("Arctic Char ×2 · Largemouth Bass ×2 · +2")
	assert_str(Board.biting_more(FERN, 9, {})).is_equal("? ×2 · Largemouth Bass ×2 · +2")
	assert_str(Board.biting_more(FERN.merged({"time": "Day", "weather": "wind"}, true), 1, {})).is_equal("")

func test_forecast_from_lv3() -> void:
	assert_array(Board.forecast(FERN, 2)).is_empty()
	assert_array(Board.forecast(FERN, 3)).is_equal([["Sun", "rain"], ["Mon", "windy"], ["Tue", "clear"]])

func test_board_pond_row() -> void:
	var r := Board.pond_row("pond_san_francisco_03", FERN, "0.8 km", 9, {})
	# Catfish night 2 × rain 1.5 = 3 beats the Eel's rain 2 (2370cb2a: Blossom / Fern at Lv5 are Catfish too)
	assert_that([r.name, r.sub, r.fish, r.line]).is_equal(["Fern Pond", "Pond · 0.8 km", "fish_catfish", "Catfish · Night ×2 · Rain ×1.5"])
	# Lv2 in the rain: Largemouth Bass dawn & dusk 2 over the Carp's rain 1.5; the Bass's weather is not today's
	var lv2 := Board.pond_row("pond_san_francisco_03", FERN, "0.8 km", 2, {})
	assert_str(lv2.line).is_equal("Largemouth Bass · Dawn & dusk ×2")
	var lv1 := Board.pond_row("pond_san_francisco_03", FERN.merged({"weather": "sun"}, true), "0.8 km", 1, {})
	assert_that([lv1.fish, lv1.line]).is_equal(["", ""])   # nothing over ×1 today at Lv1: two lines, no badge

func test_details_lines_and_the_45_percent() -> void:
	var eel := Board.FishWorld._fish("fish_eel")
	assert_str(Board.details_line(eel, false)).is_equal("Fishing Lv9 · Night only · Rain ×2")
	assert_str(Board.details_line(eel, true)).is_equal("Night only · Rain ×2")
	assert_str(Board.details_line(Board.FishWorld._fish("fish_mullet"), true)).is_equal("")
	assert_str(Board.details_line(Board.FishWorld._fish("fish_sturgeon"), false)).is_equal("Fishing Lv7")
	assert_str(Board.details_line(Board.FishWorld._fish("fish_salmon"), false)).is_equal("Fishing Lv8 · Regional")
	assert_bool(Board.dim_now(eel, FERN)).is_true()
	assert_bool(Board.dim_now(eel, FERN.merged({"time": "Night"}, true))).is_false()

func test_the_time_words_only_for_a_raising_window() -> void:
	# a window under ×1 never reads as "bite at night"; an unknown window adds no words (苏烈 on #262)
	assert_str(Board.line(["fish_crucian"], "sun", 1, {})).is_equal("Pond Crucians bite. Bring worms.")
	var shy := {"id": "fish_test_shy", "name": "Shy Fish", "level": 1, "time": {"night": 0.5, "noon": 3.0}}
	var c: Dictionary = P0Logic.content()
	(c.fish as Array).append(shy)
	var got := Board.line(["fish_test_shy"], "sun", 1, {})
	(c.fish as Array).erase(shy)
	assert_str(got).is_equal("Shy Fish bite. Bring worms.")
