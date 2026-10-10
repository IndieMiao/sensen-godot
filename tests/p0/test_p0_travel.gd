extends GdUnitTestSuite
## SGODOT-275: P0Travel reads view.travel in the shape the cross-city plan froze (275 comments 0fc0bc5e, v1.1).

const P0Travel := preload("res://modules/p0/p0_travel.gd")
const SF := "gn-5391959"
const TOKYO := "gn-1850147"
const HOUR := 3600000.0

func _view(travel: Dictionary, now := 1_000_000_000.0) -> Dictionary:
	return {"now": now, "travel": travel}

func test_a_view_without_travel_is_at_home_in_san_francisco() -> void:
	var v := {"now": 1.0}
	assert_str(P0Travel.home(v)).is_equal(SF)
	assert_str(P0Travel.here(v)).is_equal(SF)
	assert_bool(P0Travel.away(v)).is_false()
	assert_bool(P0Travel.covers(v, SF)).is_true()
	assert_bool(P0Travel.covers(v, TOKYO)).is_false()
	assert_str(P0Travel.fog(v, SF)).is_equal("explored")
	assert_str(P0Travel.fog(v, TOKYO)).is_equal("unexplored")

func test_a_running_day_pass_covers_its_city_and_shows_on_the_chip() -> void:
	var now := 1_000_000_000.0
	var v := _view({home = SF, here = TOKYO, passes = {TOKYO: {kind = "day", from = now - HOUR, until = now + 22.5 * HOUR}},
		visits = {TOKYO: {n = 1}}, stamps = [{cluster = TOKYO, kind = "landmark"}]}, now)
	assert_bool(P0Travel.away(v)).is_true()
	assert_bool(P0Travel.covers(v, TOKYO)).is_true()
	assert_str(P0Travel.fog(v, TOKYO)).is_equal("explored")
	assert_int(P0Travel.visits(v, TOKYO)).is_equal(1)
	assert_str(P0Travel.pass_text(v, TOKYO)).is_equal("23h")
	var chip := P0Travel.place(v, {city = "San Francisco", space = "Homestead", kind = UiHud.PlaceKind.HOME, day_pass = ""})
	# q(108): the free version's chip shows no Day Pass — Tokyo · Arrived
	assert_dict(chip).is_equal({city = "Tokyo", space = "Arrived", kind = UiHud.PlaceKind.FOREIGN, day_pass = ""})
	v.travel.passes[TOKYO].until = now + 47 * 60000.0
	assert_str(P0Travel.pass_text(v, TOKYO)).is_equal("47m")

func test_an_expired_pass_covers_nothing_and_the_home_chip_is_untouched() -> void:
	var now := 1_000_000_000.0
	var v := _view({home = SF, here = TOKYO, passes = {TOKYO: {kind = "day", from = now - 25 * HOUR, until = now - HOUR}},
		visits = {TOKYO: {n = 1}}}, now)
	assert_bool(P0Travel.covers(v, TOKYO)).is_false()
	assert_str(P0Travel.pass_text(v, TOKYO)).is_empty()
	assert_str(P0Travel.fog(v, TOKYO)).is_equal("explored")   # once visited, stays explored
	var home := _view({home = SF, here = SF})
	var info := {city = "San Francisco", space = "Homestead", kind = UiHud.PlaceKind.HOME, day_pass = ""}
	assert_dict(P0Travel.place(home, info)).is_equal(info)

func test_the_browse_tier_matches_the_server_rule() -> void:
	var v := _view({home = SF, here = SF})
	assert_int(int(P0Travel.trip(v, TOKYO).trip)).is_equal(6)
	assert_int(int(P0Travel.trip(v, SF).trip)).is_equal(1)

func test_the_travel_card_lines() -> void:
	assert_str(P0Travel.grouped(1758)).is_equal("1,758")
	assert_str(P0Travel.grouped(12)).is_equal("12")
	assert_str(P0Travel.grouped(1234567)).is_equal("1,234,567")
	assert_str(P0Travel.trip_line({km = 8815, trip = 6, name = "Intercontinental"})).is_equal("8,815 km · Trip 6 · Intercontinental")
	assert_str(P0Travel.trip_line({km = 0, trip = 1, name = "Local"})).is_equal("Your home city")
	assert_array([1, 3, 4, 5, 6, 7].map(func(t): return P0Travel.flight_s(t))).is_equal([3.0, 3.0, 4.0, 4.0, 5.0, 5.0])

func test_a_space_of_the_arrived_city_keeps_its_own_name() -> void:
	var v := _view({home = SF, here = TOKYO})
	var chip := P0Travel.place(v, {city = "Tokyo", space = "Fern Pond", kind = UiHud.PlaceKind.HOME, day_pass = ""})
	assert_str(str(chip.space)).is_equal("Fern Pond")
	assert_int(int(chip.kind)).is_equal(UiHud.PlaceKind.FOREIGN)
