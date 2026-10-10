extends GdUnitTestSuite
## SGODOT-283: the client's copy of the server's fishing_world.ts gives the same answers — the frozen vectors of
## server/test/p0/p1_fishing.test.ts — and the pond card reads its fish from the view or that copy.

const FishWorld := preload("res://modules/p0/p0_fish_world.gd")
const P0PondCard := preload("res://modules/p0/p0_pond_card.gd")
const SF := "gn-5391959"

func _ids(tiers: Array) -> Array:
	return tiers.map(func(t): var a: Array = t.map(func(p): return str(p.fish.id)); a.sort(); return a)

func test_hash_and_weather_match_the_servers_vectors() -> void:
	assert_str("%.8f" % FishWorld.hash01("gensen-p1:weather:gn-5391959:2026-10-10")).is_equal("0.14122267")
	assert_str(FishWorld.weather_on(SF, "2026-10-10")).is_equal("sun")
	assert_str(FishWorld.weather_on("gn-1796236", "2026-10-11")).is_equal("sun")

func test_regional_fish_match_the_servers() -> void:
	assert_array(FishWorld.regional_fish(SF)).is_equal(["fish_arctic_char", "fish_salmon"])
	assert_array(FishWorld.regional_fish("gn-1796236")).is_equal(["fish_grass_carp", "fish_snakehead"])
	assert_array(FishWorld.regional_fish("gn-1850147")).is_equal(["fish_grass_carp", "fish_smelt"])   # Tokyo: hashed

func test_river_on_a_rainy_night_matches_the_servers_pool() -> void:
	assert_array(_ids(FishWorld.pool("River", SF, "night", "rain"))).is_equal([
		["fish_carp", "fish_crucian", "fish_mullet"], ["fish_arctic_char", "fish_bass", "fish_perch", "fish_trout"],
		["fish_catfish"], ["fish_eel", "fish_salmon", "fish_sturgeon"]])

func test_weights_global_regional_time_weather() -> void:
	var w := {}
	for t in FishWorld.pool("River", SF, "dawn_dusk", "rain", 2.0):
		for p in t: w[str(p.fish.id)] = float(p.weight)
	assert_float(w.fish_crucian).is_equal(1.0)
	assert_float(w.fish_carp).is_equal(1.5)
	assert_float(w.fish_bass).is_equal(2.0)
	assert_float(w.fish_salmon).is_equal(16.0)   # regional 2 × lure 2 × dawn 2 × rain 2

func test_the_pond_card_lists_the_views_fish_else_works_them_out() -> void:
	var view := {"fishing": {"places": {"pond_san_francisco_02": {"fish": ["fish_mullet", "fish_mackerel"]}}}, "skills": {}}
	var rows: Array = P0PondCard.fish_rows(view, "pond_san_francisco_02")
	assert_array(rows.map(func(r): return r.id)).contains_exactly(["fish_mullet", "fish_mackerel"])
	var fern: Array = P0PondCard.fish_rows({}, "pond_san_francisco_03").map(func(r): return r.id)
	assert_array(fern).contains(["fish_crucian", "fish_koi", "fish_catfish", "fish_arctic_char"])
	assert_array(fern).not_contains(["fish_trout", "fish_tilapia", "fish_smelt"])

func test_now_line() -> void:
	assert_str(FishWorld.now_line({"daypart": "night", "weather": "rain"})).is_equal("Night · Rain")
	assert_str(FishWorld.now_line({})).is_equal("")
