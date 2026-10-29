extends GdUnitTestSuite
## q(256) / q(257) (SGODOT-367, 不知火舞 on 367 ec5f2daa): the fare to a city from view.travel.fares — the trip tier's,
## half (rounded up) on a return, free for Trip 1 (the 3 nearest cities) and where the player already is with a pass —
## and MAP-5's rows: Distance, Energy and Coins left once paid (or Cost · Free), Fish here, Visit, a running pass's Day
## Pass; short of it, Fly reads the gap (coins first: fare + the 40 floor − the wallet).

const P0Travel := preload("res://modules/p0/p0_travel.gd")
const P0Map := preload("res://scenes/p0/p0_map.gd")
const SF := "gn-5391959"
const LA := "gn-5368361"
const TOKYO := "gn-1850147"
const SALINAS := "gn-5391295"
const FARES := {energy = [0, 10, 20, 30, 40, 50, 60], coins = [0, 20, 60, 120, 200, 300, 500]}

static func _view(visits := {}, passes := {}, here := SF, coins := 230, energy := 142) -> Dictionary:
	return {now = 1_000_000_000.0, coins = coins, energy = {value = energy, max = 210},
		travel = {home = SF, here = here, passes = passes, visits = visits, stamps = [], fares = FARES,
			fallback = {near3 = [SALINAS], near10 = [SALINAS]}, explorer = 0}}

func test_a_first_visit_pays_its_trip_tiers_fare() -> void:
	var trip := int(P0Travel.trip(_view(), LA).trip)
	var f := P0Travel.fare(_view(), LA)
	assert_int(int(f.energy)).is_equal(int(FARES.energy[trip - 1]))
	assert_int(int(f.coins)).is_equal(int(FARES.coins[trip - 1]))
	assert_bool(f.revisit).is_false()
	assert_bool(f.free).is_false()

func test_a_return_pays_half_rounded_up() -> void:
	var v := _view({TOKYO: {n = 1}})
	var trip := int(P0Travel.trip(v, TOKYO).trip)
	var f := P0Travel.fare(v, TOKYO)
	assert_int(int(f.energy)).is_equal(ceili(int(FARES.energy[trip - 1]) / 2.0))
	assert_int(int(f.coins)).is_equal(ceili(int(FARES.coins[trip - 1]) / 2.0))
	assert_bool(f.revisit).is_true()

func test_trip_1_home_and_already_there_are_free() -> void:
	assert_int(int(P0Travel.trip(_view(), SALINAS).trip)).is_equal(1)   # one of the 3 nearest
	assert_bool(P0Travel.fare(_view(), SALINAS).free).is_true()
	assert_bool(P0Travel.fare(_view(), SF).free).is_true()
	var there := _view({LA: {n = 1}}, {LA: {kind = "day", from = 1.0, until = 1_000_000_000.0 + 7 * 3_600_000.0}}, LA)
	assert_bool(P0Travel.fare(there, LA).free).is_true()
	# a server from before sends no table: free
	var old := _view()
	old.travel.erase("fares")
	assert_bool(P0Travel.fare(old, TOKYO).free).is_true()

func test_the_gap_says_coins_first_with_the_40_floor() -> void:
	var f := {energy = 30, coins = 120}
	assert_dict(P0Travel.fare_gap(_view({}, {}, SF, 160, 142), f)).is_empty()   # 160 − 120 = 40: the floor kept
	assert_str(str(P0Travel.fare_gap(_view({}, {}, SF, 150, 142), f).text)).is_equal("Need 10 more coins")
	assert_str(str(P0Travel.fare_gap(_view({}, {}, SF, 230, 19), f).text)).is_equal("Need 11 more Energy")
	assert_str(str(P0Travel.fare_gap(_view({}, {}, SF, 150, 19), f).text)).is_equal("Need 10 more coins")   # both: coins

func test_map_5_first_visit_rows() -> void:
	var spec := P0Map.travel_card(_view(), LA, {utc_offset_min = -420}, 14)
	assert_str(str(spec.title)).is_equal("Los Angeles")
	var re := RegEx.create_from_string("^United States · \\d\\d:\\d\\d local · 14 online$")
	assert_object(re.search(str(spec.subtitle))).is_not_null()
	var trip := int(P0Travel.trip(_view(), LA).trip)
	var e := int(FARES.energy[trip - 1])
	var c := int(FARES.coins[trip - 1])
	assert_array((spec.facts as Array).map(func(f): return str(f[0]))).is_equal(["Distance", "Energy", "Coins", "Fish here", "Visit"])
	assert_str(str(spec.facts[1][1])).is_equal("%d → %d left" % [e, 142 - e])
	assert_str(str(spec.facts[2][1])).is_equal("%d → %d left" % [c, 230 - c])
	assert_str(str(spec.facts[4][1])).is_equal("First visit · stamp + 10 Energy")
	assert_str(str(spec.primary)).is_equal("Fly")
	assert_str(str(spec.blocked)).is_empty()
	assert_str(str(spec.footer)).is_equal("Return home is always free")

func test_map_5_return_with_a_pass_and_no_online_or_local_time() -> void:
	var v := _view({LA: {n = 1}}, {LA: {kind = "day", from = 1.0, until = 1_000_000_000.0 + 7 * 3_600_000.0}})
	var spec := P0Map.travel_card(v, LA, {}, 0)
	assert_str(str(spec.subtitle)).is_equal("United States")   # the local time before its preview, no `0 online`
	var labels: Array = (spec.facts as Array).map(func(f): return str(f[0]))
	assert_array(labels).is_equal(["Distance", "Energy", "Coins", "Fish here", "Visit", "Day Pass"])
	assert_str(str(spec.facts[4][1])).is_equal("Return visit · half price")
	assert_str(str(spec.facts[5][1])).is_equal("7h left")
	# the pass ran out: no Day Pass row
	var ended := _view({LA: {n = 1}}, {LA: {kind = "day", from = 1.0, until = 999_000_000.0}})
	assert_array((P0Map.travel_card(ended, LA, {}, 0).facts as Array).map(func(f): return str(f[0]))).not_contains(["Day Pass"])

func test_map_5_trip_1_is_one_cost_free_row() -> void:
	var spec := P0Map.travel_card(_view(), SALINAS, {}, 0)
	assert_array((spec.facts as Array).map(func(f): return str(f[0]))).is_equal(["Distance", "Cost", "Fish here", "Visit"])
	assert_str(str(spec.facts[1][1])).is_equal("Free")

func test_map_5_short_of_coins_fly_reads_the_gap() -> void:
	var spec := P0Map.travel_card(_view({}, {}, SF, 50), LA, {}, 0)
	assert_str(str(spec.blocked)).starts_with("Need ")
	assert_str(str(spec.blocked)).ends_with(" more coins")
	assert_str(str(spec.gap.short)).is_equal("coins")
