extends RefCounted
## The Tackle Shop's Bite Board (SGODOT-283; plan §6.9.3, 李白 q(119), 不知火舞's weather screens on 283): the section
## titles and the keeper's line built from today's best fish. Pure and static: tested headless. The board's layout
## comes with 安其拉's frames; this is its copy.
##   The fish: from every pond of the city the fish the player can land (its Fishing level), the one with the highest
##   factor today, factor = its time factor (any time today) × today's weather factor in that city; ties go to the one
##   whose weather matches, then the higher level, then the fish id. An uncaught regional fish may be picked but is
##   written `Regional fish`.
##   The line: `<fish> bite[ at dawn and dusk| at night][ in the rain| in the wind| in the sun]. <bait>` — the time part
##   only for a fish with a time factor (`only bite at …` for the *_only ones), the weather part only when today's
##   weather is its own; plural names for River Eel / Snakehead / Pond Crucian (fish.plural); `Try a Spinner Lure.` for a
##   regional fish once the lure is open (Fishing Lv5), else `Bring worms.`; nothing to pick: `Quiet day. Any pond will
##   do.` Shown in curly quotes with the keeper's name: `“…” — Finn`.

const FishWorld := preload("res://modules/p0/p0_fish_world.gd")
const TITLES := ["Ponds", "Regional fish", "Forecast"]
const FORECAST_LEVEL := 3
const LURE_LEVEL := 5
const QUIET := "Quiet day. Any pond will do."
const TIME_WORDS := {"dawn_dusk": "at dawn and dusk", "night": "at night"}
const WEATHER_WORDS := {"rain": "in the rain", "wind": "in the wind", "sun": "in the sun"}

## The board's section titles at this Fishing level (Forecast from Lv3, as the pond card's Forecast row).
static func titles(level: int) -> Array:
	return TITLES if level >= FORECAST_LEVEL else TITLES.slice(0, 2)

## Today's pick: {fish (content row), factor, weather_match} from the fish the city's ponds give that the player can
## land, or {} when there are none. `weather` is today's in that city; `regional` the city's 2 regional fish.
static func pick(fish_ids: Array, weather: String, level: int) -> Dictionary:
	var best := {}
	for id in fish_ids:
		var f := FishWorld._fish(str(id))
		if f.is_empty() or int(f.get("level", 1)) > level: continue
		var t = f.get("time", null)
		var time_f := 1.0
		if t is Dictionary:
			for k in t: time_f = maxf(time_f, float(t[k]))
		var w := float(f.get("weather", {}).get(weather, 1.0))
		var cand := {"fish": f, "factor": time_f * w, "weather_match": w > 1.0}
		if best.is_empty() or _better(cand, best): best = cand
	return best

static func _better(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a.factor), float(b.factor)): return float(a.factor) > float(b.factor)
	if bool(a.weather_match) != bool(b.weather_match): return bool(a.weather_match)
	var la := int(a.fish.get("level", 1)); var lb := int(b.fish.get("level", 1))
	if la != lb: return la > lb
	return str(a.fish.get("id", "")) < str(b.fish.get("id", ""))

## The keeper's line, unquoted: `Rainbow Trout bite in the rain. Bring worms.`
static func line(fish_ids: Array, weather: String, level: int, caught: Dictionary) -> String:
	var p := pick(fish_ids, weather, level)
	if p.is_empty(): return QUIET
	var f: Dictionary = p.fish
	var regional := bool(f.get("regional", false))
	var name := "Regional fish" if regional and int(caught.get(str(f.id), 0)) <= 0 else str(f.get("plural", f.get("name", f.id)))
	var parts := PackedStringArray([name])
	var t = f.get("time", null)
	if t is String:   # night_only / dawn_dusk_only
		parts.append("only bite " + str(TIME_WORDS.get(str(t).trim_suffix("_only"), "")))
	else:
		parts.append("bite")
		if t is Dictionary and not t.is_empty():
			var key := ""
			var top := 0.0
			for k in t:
				if float(t[k]) > top: top = float(t[k]); key = str(k)
			parts.append(str(TIME_WORDS.get(key, "")))
	if bool(p.weather_match): parts.append(str(WEATHER_WORDS.get(weather, "")))
	var bait := "Try a Spinner Lure." if regional and level >= LURE_LEVEL else "Bring worms."
	return " ".join(parts) + ". " + bait

## As shown, in curly quotes (the frames' 2255:32861): `“Rainbow Trout bite in the rain. Bring worms.” — Finn`.
static func quoted(text: String, keeper: String) -> String:
	return "“%s” — %s" % [text, keeper]

# ---------------------------------------------------------------- the conditions on the cards (283 e61cda10 / 1e21c014)
const WEATHER_WORD := {"sun": "Clear", "rain": "Rain", "wind": "Windy"}
const WEATHER_ICON := {"sun": "clear", "rain": "rain", "wind": "windy"}
const TIME_ICON := {"Dawn": "dawn_dusk", "Dusk": "dawn_dusk", "Day": "day", "Night": "night"}
const TIME_TAG := {"dawn_dusk": "Dawn & dusk", "night": "Night"}

## The condition line's parts, now: [[icon, word], [icon, word]] — `Dusk · Rain` with their icons.
static func conditions(place: Dictionary) -> Array:
	var time := str(place.get("time", ""))
	var weather := str(place.get("weather", ""))
	if time == "" or weather == "": return []
	return [[str(TIME_ICON.get(time, "day")), time], [str(WEATHER_ICON.get(weather, "clear")), str(WEATHER_WORD.get(weather, weather))]]

## A fish's condition tags (Details, the Bite Board's fish line): `Night ×2 · Rain ×1.5`, `Night only`; "" for an
## all-day, any-weather fish. `weather` set: only that weather's tag (the board writes today's only when it matches).
static func tags(f: Dictionary, weather := "") -> String:
	var out := PackedStringArray()
	var t = f.get("time", null)
	if t is String: out.append("%s only" % str(TIME_TAG.get(str(t).trim_suffix("_only"), "")))
	elif t is Dictionary:
		for k in ["dawn_dusk", "night"]:
			if t.has(k): out.append("%s ×%s" % [TIME_TAG[k], _num(float(t[k]))])
	var w: Dictionary = f.get("weather", {})
	for k in ["sun", "rain", "wind"]:
		if w.has(k) and (weather == "" or weather == k): out.append("%s ×%s" % [WEATHER_WORD[k], _num(float(w[k]))])
	return " · ".join(out)

## The daypart a place's time word stands for (Dawn / Dusk → dawn_dusk).
static func part_now(place: Dictionary) -> String:
	return str({"Dawn": "dawn_dusk", "Dusk": "dawn_dusk", "Night": "night"}.get(str(place.get("time", "")), "day"))

static func _num(x: float) -> String: return str(int(x)) if is_equal_approx(x, roundf(x)) else str(x)

## Biting more (the pond card, now): the landable fish whose factor now (time now × today's weather) is over 1, best
## first, at most 2 named and `+N` for the rest; an uncaught regional fish is `?`. "" when none (the row hides).
static func biting_more(place: Dictionary, level: int, caught: Dictionary) -> String:
	var part := part_now(place)
	var weather := str(place.get("weather", ""))
	var rows: Array = []
	for id in place.get("fish", []):
		var f := FishWorld._fish(str(id))
		if f.is_empty() or int(f.get("level", 1)) > level or not FishWorld.bites_at(f, part): continue
		var t = f.get("time", null)
		var k := float(t.get(part, 1.0)) if t is Dictionary and part != "day" else 1.0
		k *= float(f.get("weather", {}).get(weather, 1.0))
		if k <= 1.0: continue
		rows.append({"f": f, "k": k})
	if rows.is_empty(): return ""
	rows.sort_custom(func(a, b): return float(a.k) > float(b.k) if not is_equal_approx(float(a.k), float(b.k)) else str(a.f.id) < str(b.f.id))
	var names := PackedStringArray()
	for r in rows.slice(0, 2):
		var hide := bool(r.f.get("regional", false)) and int(caught.get(str(r.f.id), 0)) <= 0
		names.append("%s ×%s" % ["?" if hide else str(r.f.get("name", r.f.id)), _num(float(r.k))])
	var text := " · ".join(names)
	if rows.size() > 2: text += " · +%d" % (rows.size() - 2)
	return text

## The Forecast fact (Lv3+): [[day, weather icon]] × 3, from the view's place.forecast; [] below Lv3.
static func forecast(place: Dictionary, level: int) -> Array:
	if level < FORECAST_LEVEL: return []
	return (place.get("forecast", []) as Array).map(func(d): return [str(d.get("day", "")), str(WEATHER_ICON.get(str(d.get("weather", "")), "clear"))])

## A Bite Board pond row: {id, name, sub `River · 1.6 km`, fish (id or ""), line `Catfish · Night ×2 · Rain ×1.5`}; the
## fish is the landable one with the highest factor today over 1 (any time today × today's weather; Biting more's rule,
## 1e21c014 ③), its time tag always and its weather tag only when today's weather is its own (2370cb2a); none: no fish
## line and no badge (8d12967e: Clover at Lv2).
static func pond_row(id: String, place: Dictionary, km_text: String, level: int, caught: Dictionary) -> Dictionary:
	var weather := str(place.get("weather", ""))
	var p := pick(place.get("fish", []), weather, level)
	var row := {"id": id, "name": str(place.get("name", id)), "sub": "%s · %s" % [str(place.get("template", "Pond")), km_text],
		"template": str(place.get("site", "pond")), "fish": "", "line": ""}
	if p.is_empty() or float(p.factor) <= 1.0: return row
	var f: Dictionary = p.fish
	var hide := bool(f.get("regional", false)) and int(caught.get(str(f.id), 0)) <= 0
	var tag := tags(f, weather if bool(p.weather_match) else "-")
	row.fish = str(f.id)
	row.line = ("?" if hide else str(f.get("name", f.id))) + (" · " + tag if tag != "" else "")
	return row

## Details' second line (C): caught — the tags only ("" for a fish with none); not caught — `Fishing Lv9 · Night only ·
## Rain ×2`; an uncaught regional fish `Fishing Lv8 · Regional`. dim: outside its time window now (45 %).
static func details_line(f: Dictionary, caught: bool) -> String:
	var lv := "Fishing Lv%d" % int(f.get("level", 1))
	if not caught and bool(f.get("regional", false)): return lv + " · Regional"
	var t := tags(f)
	if caught: return t
	return lv + (" · " + t if t != "" else "")

static func dim_now(f: Dictionary, place: Dictionary) -> bool:
	var part := part_now(place)
	return not FishWorld.bites_at(f, part)
