extends GdUnitTestSuite
## The Bite Board drawer and the pond card's P1 rows (SGODOT-283; 不知火舞 e61cda10 ②③, 1e21c014, 2370cb2a, f74fafae;
## Figma BITE-BOARD-V2 2255:32861, -LV2 2255:33188, POND-CARD-WX-V2 2255:143053).

const Board := preload("res://modules/p0/p0_bite_board.gd")
const PondCard := preload("res://modules/p0/p0_pond_card.gd")
const Drawer := preload("res://scenes/p0/panels/p0_bite_board_drawer.gd")
const FERN := "pond_san_francisco_03"
const CLOVER := "pond_san_francisco_02"
const DAYS := [{"day": "Sun", "weather": "rain"}, {"day": "Mon", "weather": "wind"}, {"day": "Tue", "weather": "sun"}]

## San Francisco's six ponds as the view gives them: every one at `time`, in `weather`, with its fish.
func _places(time := "Dusk", weather := "rain") -> Dictionary:
	var c := P0Logic.content()
	var out := {}
	for id in c.fishing.places:
		var site := str(c.fishing.places[id].site)
		out[id] = {"name": c.fishing.places[id].name, "site": site, "template": str(c.fishing.sites[site].template), "time": time,
			"weather": weather, "forecast": DAYS, "fish": P0Logic.pond_fish({}, id)}
	return out

func _view(level: int, caught := {}, time := "Dusk", weather := "rain", traps := []) -> Dictionary:
	return {"skills": {"fishing": {"level": level}}, "fishing": {"places": _places(time, weather), "caught": caught,
		"dex": caught.keys().map(func(id): return {"id": id, "caught": caught[id]}), "trap": {"traps": traps, "slots": 1}}}

func _model(level: int, caught := {}) -> Dictionary:
	return Board.model(_view(level, caught), P0Outposts.by_role("tackle"))

# ---------------------------------------------------------------- the board's model (2255:32861 / 2255:33188)
func test_board_lv5_matches_the_frames() -> void:
	var m := _model(5, {"fish_arctic_char": 1})
	assert_str(str(m.title)).is_equal("Bite Board · Mission Tackle Shop")
	assert_array(m.conditions).is_equal([["dawn_dusk", "Dusk"], ["rain", "Rain"]])
	assert_str(str(m.line)).is_equal("“Catfish bite at night in the rain. Bring worms.” —\u00a0Finn")
	assert_array(m.titles).is_equal(["Ponds", "Regional fish", "Forecast"])
	var by_id := {}
	for r in m.ponds: by_id[str(r.id)] = r
	assert_str(str(by_id[FERN].line)).is_equal("Catfish · Night ×2 · Rain ×1.5")
	assert_str(str(by_id["pond_san_francisco_06"].line)).is_equal("Catfish · Night ×2 · Rain ×1.5")   # Blossom: ×3 over the Trout's ×2
	assert_that([by_id[CLOVER].fish, by_id[CLOVER].fish_name, by_id[CLOVER].tags]).is_equal(["fish_seabass", "Sea Bass", " · Dawn & dusk ×2"])
	assert_str(str(by_id[CLOVER].sub)).starts_with("Coast · ")
	# nearest first from this shop (the player is in it): Fern 0.2 km, Blossom 1.6 km …
	var kms: Array = m.ponds.map(func(r): return float(r.km))
	var sorted := kms.duplicate()
	sorted.sort()
	assert_array(kms).is_equal(sorted)
	assert_that([m.ponds[0].id, m.ponds[0].sub]).is_equal([FERN, "Pond · 0.2 km"])
	assert_array(m.regional.map(func(r): return [r.name, r.sub])).is_equal([["Arctic Char", ""], ["?", "Fishing Lv8"]])
	assert_array(m.forecast.map(func(d): return [d.day, d.icon, d.word, d.fish])).is_equal([
		["Sun", "rain", "Rain", ["Rainbow Trout", "Catfish"]], ["Mon", "windy", "Windy", ["Mackerel", "Sea Bass"]], ["Tue", "clear", "Clear", ["Golden Koi"]]])

func test_board_lv2_has_no_forecast_and_clover_no_fish() -> void:
	var m := _model(2)
	assert_array(m.titles).is_equal(["Ponds", "Regional fish"])
	assert_array(m.forecast).is_empty()
	assert_str(str(m.line)).is_equal("“Rainbow Trout bite in the rain. Bring worms.” —\u00a0Finn")
	var by_id := {}
	for r in m.ponds: by_id[str(r.id)] = r
	assert_str(str(by_id[FERN].line)).is_equal("Largemouth Bass · Dawn & dusk ×2")   # 2370cb2a
	assert_str(str(by_id["pond_san_francisco_06"].line)).is_equal("Rainbow Trout · Rain ×2")
	assert_that([by_id[CLOVER].fish, by_id[CLOVER].line]).is_equal(["", ""])   # nothing over ×1 for Lv2: no fish line, no badge
	assert_array(m.regional.map(func(r): return [r.name, r.sub])).is_equal([["?", "Fishing Lv3"], ["?", "Fishing Lv8"]])

func test_forecast_fish_are_landable_and_weather_ranked() -> void:
	var fish: Array = P0Logic.pond_fish({}, "pond_san_francisco_06")
	# Lv9 in the rain: River Eel (Lv9) and Atlantic Salmon (Lv8, regional) both rain ×2 over the Trout's (Lv2): the level
	# breaks the tie; the salmon not caught yet is `?`
	assert_array(Board.forecast_fish(fish, "rain", 9, {})).is_equal(["River Eel", "?"])
	assert_array(Board.forecast_fish(fish, "rain", 9, {"fish_salmon": 1})).is_equal(["River Eel", "Atlantic Salmon"])
	assert_array(Board.forecast_fish(fish, "rain", 3, {})).is_equal(["Rainbow Trout", "Common Carp"])
	assert_array(Board.forecast_fish(["fish_arctic_char"], "sun", 9, {})).is_empty()   # no weather factor: not a forecast fish

# ---------------------------------------------------------------- the drawer
func test_drawer_rows_badges_and_sections() -> void:
	var d: UiDrawer = auto_free(Drawer.new(_view(2), P0Outposts.by_role("tackle")))
	add_child(d)
	await await_idle_frame()
	var ponds: Array = d.get("pond_rows")
	assert_int(ponds.size()).is_equal(6)
	var clover := d.find_child("Pond_" + CLOVER, true, false)
	assert_bool((clover.find_child("Thumb", true, false) as UiPondThumb).badge_shown()).is_false()
	assert_object(clover.find_child("Fish", true, false)).is_null()
	var fern := d.find_child("Pond_" + FERN, true, false)
	assert_bool((fern.find_child("Thumb", true, false) as UiPondThumb).badge_shown()).is_true()
	assert_str((fern.find_child("FishName", true, false) as Label).text).is_equal("Largemouth Bass")
	assert_str((fern.find_child("Tags", true, false) as Label).text).is_equal(" · Dawn & dusk ×2")
	assert_object(d.find_child("Forecast", true, false)).is_null()   # Lv2
	assert_object(d.find_child("Section_Regional_fish", true, false)).is_not_null()
	var line := d.find_child("KeeperLine", true, false) as Label
	assert_int(line.max_lines_visible).is_equal(2)
	var hit := []
	d.connect(&"pond_pressed", func(id: String): hit.append(id))
	(fern as Button).pressed.emit()
	assert_array(hit).is_equal([FERN])

func test_drawer_lv5_forecast_cards_and_height_cap() -> void:
	var d: UiDrawer = auto_free(Drawer.new(_view(5), P0Outposts.by_role("tackle")))
	add_child(d)
	for i in 4: await await_idle_frame()
	var days := d.find_child("Forecast", true, false)
	assert_int(days.get_child_count()).is_equal(3)
	assert_float(d.height).is_less_equal(Drawer.MAX_HEIGHT)
	assert_float(d.height).is_equal(Drawer.MAX_HEIGHT)   # six ponds and the forecast: over 560, it scrolls

# ---------------------------------------------------------------- the pond card (2255:143053)
func test_pond_card_rows_in_order() -> void:
	var clover := PondCard.info(_view(5), CLOVER, 2.4)
	assert_str(str(clover.thumb)).is_equal("coast")
	assert_array(clover.conditions).is_equal([["dawn_dusk", "Dusk"], ["rain", "Rain"]])
	assert_array(clover.facts).is_equal([["Distance", "2.4 km"], ["Recommended", "Lv6+"], ["Biting more", "Sea Bass ×2"],
		["Forecast", [["Sun", "rain"], ["Mon", "windy"], ["Tue", "clear"]]]])
	# Lv2: nothing over ×1 now at Clover and no Forecast yet; a trap there is the last row (POND-CARD-TRAP 2162:138260)
	var lv2 := PondCard.info(_view(2, {}, "Dusk", "rain", [{"place": CLOVER, "fish": 2, "keep": 3}]), CLOVER, 2.4)
	assert_array(lv2.facts).is_equal([["Distance", "2.4 km"], ["Recommended", "Lv6+"], ["Your trap", "2/3"]])
	# Lv8: the one line becomes Biting now — the pool now, best first, no factors (不知火舞 on 283), never both
	var lv8: Array = PondCard.info(_view(8), CLOVER, 2.4).facts
	var labels := lv8.map(func(f): return str(f[0]))
	assert_bool(labels.has("Biting now") and not labels.has("Biting more")).is_true()
	assert_str(str(lv8[labels.find("Biting now")][1])).is_equal("?, Sea Bass · +3 more")   # the uncaught regional smelt first

func test_details_lines_and_the_45_percent() -> void:
	var rows := PondCard.fish_rows(_view(5, {"fish_catfish": 1}, "Dusk", "rain"), "pond_san_francisco_06")
	var by_id := {}
	for r in rows: by_id[str(r.id)] = r
	assert_that([by_id.fish_catfish.line, by_id.fish_catfish.dim]).is_equal(["Night ×2 · Rain ×1.5", false])
	assert_that([by_id.fish_eel.name, by_id.fish_eel.line, by_id.fish_eel.dim]).is_equal(["River Eel", "Fishing Lv9 · Night only · Rain ×2", true])
	assert_that([by_id.fish_salmon.name, by_id.fish_salmon.line]).is_equal(["?", "Fishing Lv8 · Regional"])
	var night := PondCard.fish_rows(_view(5, {}, "Night", "rain"), "pond_san_francisco_06")
	assert_bool(night.filter(func(r): return r.id == "fish_eel")[0].dim).is_false()

func test_sheet_rows_draw_the_icons() -> void:
	var cond: HBoxContainer = auto_free(P0PlaceSheet.conditions_row([["dawn_dusk", "Dusk"], ["windy", "Windy"]]))
	assert_array(cond.get_children().filter(func(c): return c is Label).map(func(c): return c.text)).is_equal(["Dusk", "·", "Windy"])
	assert_int(cond.get_children().filter(func(c): return c is TextureRect).size()).is_equal(2)
	var fc: MarginContainer = auto_free(P0PlaceSheet.forecast_row("Forecast", [["Sat", "rain"], ["Sun", "windy"], ["Mon", "clear"]]))
	var days := fc.find_child("Days", true, false)
	assert_array(days.get_children().filter(func(c): return c is Label).map(func(c): return c.text)).is_equal(["Sat", "·", "Sun", "·", "Mon"])
	assert_int(days.get_children().filter(func(c): return c is TextureRect).size()).is_equal(3)
