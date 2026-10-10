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

## 不知火舞 69310899: a regional fish not yet caught is `?` over `Fishing Lv3 · Regional`; a fish without its own icon
## falls back to the fish silhouette, not the sprout.
func test_an_uncaught_regional_fish_keeps_its_name_back() -> void:
	var rows: Array = P0PondCard.fish_rows({}, "pond_san_francisco_03")
	var char_row: Dictionary = rows.filter(func(r): return r.id == "fish_arctic_char")[0]
	assert_str(str(char_row.name)).is_equal("?")
	assert_str(P0PondCard.locked_line(char_row)).is_equal("Fishing Lv3 · Regional")
	var koi: Dictionary = rows.filter(func(r): return r.id == "fish_koi")[0]
	assert_str(str(koi.name)).is_equal("Golden Koi")
	assert_str(P0PondCard.locked_line(koi)).is_equal("Fishing Lv4")
	var caught := {"fishing": {"dex": [{"id": "fish_arctic_char", "caught": 1}]}}
	assert_str(str(P0PondCard.fish_rows(caught, "pond_san_francisco_03").filter(func(r): return r.id == "fish_arctic_char")[0].name)).is_equal("Arctic Char")

func test_a_fish_without_art_shows_the_silhouette() -> void:
	assert_str(P0Logic.icon("fish_not_drawn_yet").resource_path).ends_with("fish_sil.svg")
	# P1's fish, gear and conditions have their art (不知火舞 accepted on 283): 12 fish, Carbon Rod, Spinner Lure, Fish
	# Trap, and the time-of-day / weather icons
	for id in ["fish_catfish", "fish_seabass", "fish_sturgeon", "fish_eel", "fish_tilapia", "fish_smelt", "fish_grass_carp",
			"fish_arctic_char", "fish_snakehead", "fish_pike", "fish_barramundi", "fish_salmon", "rod_carbon", "bait_lure",
			"trap_fish", "dawn_dusk", "day", "night", "clear", "rain", "windy"]:
		assert_str(P0Logic.icon(id).resource_path).override_failure_message(id).is_equal("res://assets/p0/icons/%s.svg" % id)
	assert_str(P0Logic.icon("fish_carp").resource_path).ends_with("fish_carp.svg")
	assert_str(P0Logic.icon("nothing_here").resource_path).ends_with("field.svg")
