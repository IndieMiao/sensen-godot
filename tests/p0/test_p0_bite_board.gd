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
	assert_str(Board.quoted("Rainbow Trout bite in the rain. Bring worms.", "Finn")).is_equal("\"Rainbow Trout bite in the rain. Bring worms.\" — Finn")
