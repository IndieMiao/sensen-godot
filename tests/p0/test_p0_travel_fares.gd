extends GdUnitTestSuite
## q(256) / q(257) (SGODOT-367, 不知火舞 on 367 ec5f2daa): the fare to a city from view.travel.fares — the trip tier's,
## half (rounded up) on a return, free for Trip 1 (the 3 nearest cities) and where the player already is with a pass —
## and MAP-5's rows: Distance, Energy and Coins (the fare, what the player has after the label; or Cost · Free), Fish
## here, Visit, a running pass's Day Pass; Fly always lit, short of the fare its tap says so (q(318): coins first, the
## fare with the 40 the wallet keeps).

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

## q(318) (the user's bot 740 / 741): what Fly's tap says short of the fare — the fare, never a difference; the coins
## with the 40 the wallet keeps after the trip, first when both are short.
func test_the_gap_says_coins_first_with_the_40_floor() -> void:
	var f := {energy = 30, coins = 120}
	assert_dict(P0Travel.fare_gap(_view({}, {}, SF, 160, 142), f)).is_empty()   # 160 − 120 = 40: the floor kept
	assert_dict(P0Travel.fare_gap(_view({}, {}, SF, 150, 142), f)).is_equal({text = "Need 120 coins · keep 40 after the trip", short = "coins"})
	assert_dict(P0Travel.fare_gap(_view({}, {}, SF, 230, 19), f)).is_equal({text = "Need 30 Energy", short = "energy"})
	assert_dict(P0Travel.fare_gap(_view({}, {}, SF, 230, 30), f)).is_empty()   # the Energy has no floor
	assert_str(str(P0Travel.fare_gap(_view({}, {}, SF, 150, 19), f).text)).is_equal("Need 120 coins · keep 40 after the trip")   # both: coins
	assert_str(P0Travel.short_text("not_enough_coins", 60)).is_equal("Need 60 coins · keep 40 after the trip")
	assert_str(P0Travel.short_text("not_enough_energy", 15)).is_equal("Need 15 Energy")

func test_map_5_first_visit_rows() -> void:
	var spec := P0Map.travel_card(_view(), LA, {utc_offset_min = -420}, 14)
	assert_str(str(spec.title)).is_equal("Los Angeles")
	var re := RegEx.create_from_string("^United States · \\d\\d:\\d\\d local · 14 online$")
	assert_object(re.search(str(spec.subtitle))).is_not_null()
	var trip := int(P0Travel.trip(_view(), LA).trip)
	var e := int(FARES.energy[trip - 1])
	var c := int(FARES.coins[trip - 1])
	assert_array((spec.facts as Array).map(func(f): return str(f[0]))).is_equal(["Distance", "Energy · You have 142", "Coins · You have 230", "Fish here", "Visit"])
	assert_str(str(spec.facts[1][1])).is_equal(str(e))   # the fare only (q(318)): no `→ N left`
	assert_str(str(spec.facts[2][1])).is_equal(str(c))
	assert_object(spec.facts[1][2]).is_same(P0Logic.icon("energy"))   # v3 (bot 746): their glyphs ahead of the labels
	assert_object(spec.facts[2][2]).is_same(P0Logic.icon("coin"))
	assert_int((spec.facts[0] as Array).size()).is_equal(2)   # no other row has one
	assert_str(str(spec.facts[4][1])).is_equal("First visit · stamp + 10 Energy")
	assert_str(str(spec.primary)).is_equal("Fly")
	assert_bool(spec.has("blocked")).is_false()
	assert_str(str(spec.footer)).is_equal("Return home is always free")

func test_map_5_return_with_a_pass_and_no_online_or_local_time() -> void:
	var v := _view({LA: {n = 1}}, {LA: {kind = "day", from = 1.0, until = 1_000_000_000.0 + 7 * 3_600_000.0}})
	var spec := P0Map.travel_card(v, LA, {}, 0)
	assert_str(str(spec.subtitle)).is_equal("United States")   # the local time before its preview, no `0 online`
	var labels: Array = (spec.facts as Array).map(func(f): return str(f[0]))
	assert_array(labels).is_equal(["Distance", "Energy · You have 142", "Coins · You have 230", "Fish here", "Visit", "Day Pass"])
	assert_str(str(spec.facts[4][1])).is_equal("Return visit · half price")
	assert_str(str(spec.facts[5][1])).is_equal("7h left")
	# the pass ran out: no Day Pass row
	var ended := _view({LA: {n = 1}}, {LA: {kind = "day", from = 1.0, until = 999_000_000.0}})
	assert_array((P0Map.travel_card(ended, LA, {}, 0).facts as Array).map(func(f): return str(f[0]))).not_contains(["Day Pass"])

func test_map_5_trip_1_is_one_cost_free_row() -> void:
	var spec := P0Map.travel_card(_view(), SALINAS, {}, 0)
	assert_array((spec.facts as Array).map(func(f): return str(f[0]))).is_equal(["Distance", "Cost", "Fish here", "Visit"])
	assert_str(str(spec.facts[1][1])).is_equal("Free")
	# a return there: no `Return visit · half price` (half of nothing, 不知火舞 on #642); a running pass still says its hours
	var back := _view({SALINAS: {n = 1}}, {SALINAS: {kind = "day", from = 1.0, until = 1_000_000_000.0 + 7 * 3_600_000.0}})
	assert_array((P0Map.travel_card(back, SALINAS, {}, 0).facts as Array).map(func(f): return str(f[0]))).is_equal(["Distance", "Cost", "Fish here", "Day Pass"])

## q(318) (李元芳 0.3.8: a return to Los Angeles with 60 coins read `60 → 0 left` beside a grey `Need 40 more coins`;
## the user's bot 740 / 741): short of the fare or not, the card says the same — the fare on the right, what the player
## has after the label — and Fly stays lit, no gap on it.
func test_map_5_short_or_not_says_the_fare_and_what_the_player_has() -> void:
	var trip := int(P0Travel.trip(_view(), LA).trip)
	var half := ceili(int(FARES.coins[trip - 1]) / 2.0)
	var back := {LA: {n = 1}}
	var day_pass := {LA: {kind = "day", from = 1.0, until = 1_000_000_000.0 + 23 * 3_600_000.0}}
	for coins in [half, half + 20, half + 40]:
		var spec := P0Map.travel_card(_view(back, day_pass, SF, coins), LA, {}, 0)
		assert_array([spec.facts[1].slice(0, 2), spec.facts[2].slice(0, 2)]).is_equal([["Energy · You have 142", str(ceili(int(FARES.energy[trip - 1]) / 2.0))],
			["Coins · You have %d" % coins, str(half)]])
		assert_str(str(spec.primary)).is_equal("Fly")
		assert_bool(spec.has("blocked")).is_false()
	var tired := P0Map.travel_card(_view({}, {}, SF, 230, 10), LA, {}, 0)
	assert_array(tired.facts[1].slice(0, 2)).is_equal(["Energy · You have 10", str(FARES.energy[trip - 1])])
	assert_bool(tired.has("blocked")).is_false()

## q(257) ① (FARE-BOARD 9:133836): the board's rows say each tier's first-visit fare on two lines, Trip 1 `Free`.
func test_the_fare_board_says_the_real_fares() -> void:
	var rows := P0Travel.fares(_view())
	assert_int(rows.size()).is_equal(7)
	assert_str(str(rows[0].fare)).is_equal("Free")
	assert_bool(rows[0].free).is_true()
	assert_str(str(rows[3].fare)).is_equal("30 Energy\n120 coins")
	assert_str(str(rows[6].fare)).is_equal("60 Energy\n500 coins")
	assert_bool(rows[3].free).is_false()
	assert_str(str(P0Travel.fares()[3].fare)).is_equal("Free")   # a server without fares
	var d: UiDrawer = load("res://scenes/p0/panels/p0_fare_board_drawer.gd").new(rows)
	add_child(auto_free(d))
	assert_str((d.find_child("Footnote", true, false) as Label).text).is_equal("Return trips are half price · Going home is always free")
	assert_str((d.find_child("Trip4", true, false).find_child("Fare", true, false) as Label).text).is_equal("30 Energy\n120 coins")

## q(257) ⑥: the silhouette card's Fare row under Trip: the first-visit fare, Trip 1 `Free`.
func test_the_silhouette_card_says_the_fare() -> void:
	var spec := P0Map.city_card(_view(), LA, {})
	var trip := int(P0Travel.trip(_view(), LA).trip)
	assert_str(str(spec.facts[2][0])).is_equal("Fare")
	assert_str(str(spec.facts[2][1])).is_equal("%d Energy · %d coins" % [int(FARES.energy[trip - 1]), int(FARES.coins[trip - 1])])
	assert_str(str(P0Map.city_card(_view(), SALINAS, {}).facts[2][1])).is_equal("Free")

## q(257) ⑤: a return's welcome says what its pass has left.
func test_welcome_back_says_the_pass_left() -> void:
	var v := _view({LA: {n = 2}}, {LA: {kind = "day", from = 1.0, until = 1_000_000_000.0 + 24 * 3_600_000.0}}, LA)
	assert_str(P0Map.welcome_back(v, LA)).is_equal("Welcome back · Day Pass 24h")
	v.travel.passes[LA].until = 1_000_000_000.0 + 7 * 3_600_000.0
	assert_str(P0Map.welcome_back(v, LA)).is_equal("Welcome back · Day Pass 7h")
	assert_str(P0Map.welcome_back(_view(), LA)).is_equal("Welcome back")

## 周瑜 on #569: Trip 1 checks no wallet floor (the server's fareOf: only a fare over 0 does) — a wallet of 30 flies free.
func test_trip_1_flies_with_a_wallet_under_the_floor() -> void:
	var v := _view({}, {}, SF, 30, 0)
	assert_dict(P0Travel.fare_gap(v, P0Travel.fare(v, SALINAS))).is_empty()
	assert_bool(P0Map.travel_card(v, SALINAS, {}, 0).has("blocked")).is_false()

## 周瑜 on #569: the view's clock moves on between reads — a Day Pass's time left runs down with it.
func test_projecting_the_view_moves_its_clock_on() -> void:
	var v := _view({LA: {n = 1}}, {LA: {kind = "day", from = 1.0, until = 1_000_000_000.0 + 90_000.0}}, LA)
	var later: Dictionary = P0Logic.project(v, 1000.0)
	assert_float(float(later.now)).is_equal(1_000_001_000.0)
	assert_float(P0Travel.pass_left_ms(later, LA)).is_equal(89_000.0)

## Kind=need-energy keeps a fitted button's own padding and inset under its amber (周瑜 on #569).
func test_need_energy_keeps_fit_and_inset() -> void:
	var b := UiCommandButton.new("Fly")
	b.fit_text = true
	b.visual_inset_x = 6.0
	add_child(auto_free(b))
	b.reason = "Fly · Need 30 Energy"
	b.need_energy = true
	var box := b.get_theme_stylebox(&"normal")
	assert_float(box.content_margin_left).is_less_equal(4.0)
	if box is UiStyleBox:
		assert_float((box as UiStyleBox).inset.x).is_equal(6.0)
		assert_that((box as UiStyleBox).bg_color).is_equal(UiTokens.COLOR_WARNING_TINT)
	assert_that(b.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_WARNING)

## The Fare Board's bounds as whole sentences (SGODOT-385: a translation can order them), the English as it was.
func test_the_bounds_read_as_before() -> void:
	var lines: Array = P0Travel.fares().map(func(f): return str(f.line))
	assert_str(lines[0]).is_equal("Up to 30 km, or the 3 nearest cities")
	assert_str(lines[1]).is_equal("Up to 100 km, or the 10 nearest cities")
	assert_str(lines[2]).is_equal("Up to 500 km")
	assert_str(lines[-1]).is_equal("Over 10,000 km")
