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
##   do.` Shown in quotes with the keeper's name: `"…" — Finn`.

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

## As shown: `"Rainbow Trout bite in the rain. Bring worms." — Finn`.
static func quoted(text: String, keeper: String) -> String:
	return "\"%s\" — %s" % [text, keeper]
