class_name P0Logic
extends RefCounted
## P0 milestone-1 client rules that only read the server view (plan v2 §10.2.2 main action states,
## §10.3.3 quick bar fill, §3.7 countdown format, §9.5.3 Today line). Pure and static: tested headless.

const ICON_DIR := "res://assets/p0/icons/%s.svg"

static func icon(id: String) -> Texture2D:
	var path := ICON_DIR % id
	return load(path) if ResourceLoader.exists(path) else load(ICON_DIR % "field")

## "m:ss" under an hour, "1h 12m" from one hour (state-icons rule: durations, never clock times).
static func duration(ms: float) -> String:
	var total := maxi(0, ceili(ms / 1000.0))
	if total < 3600:
		return "%d:%02d" % [total / 60, total % 60]
	var minutes := total / 60
	return "%dh %dm" % [minutes / 60, minutes % 60]

static func crop(view: Dictionary, crop_id: String) -> Dictionary:
	for c in view.get("crops", []):
		if str(c.get("id", "")) == crop_id: return c
	return {}

static func crop_for_seed(view: Dictionary, seed_id: String) -> Dictionary:
	for c in view.get("crops", []):
		if str(c.get("seed", "")) == seed_id: return c
	return {}

static func item_name(view: Dictionary, id: String) -> String:
	return str(view.get("names", {}).get(id, id))

static func bag_count(view: Dictionary, id: String) -> int:
	var n := 0
	for s in view.get("bag", {}).get("slots", []):
		if str(s.get("id", "")) == id: n += int(s.get("qty", 0))
	return n

## Main action button for the plot in front of the player (Farming).
## Returns {icon, verb, sub, enabled, amber, cmd, need}. Facilities never appear here (§10.2.2).
static func main_action(view: Dictionary, plot: Dictionary, seed_id: String) -> Dictionary:
	var a := {"icon": "sow", "verb": "Sow", "sub": "Walk to a plot", "enabled": false, "amber": false, "cmd": {}, "need": 0}
	if plot.is_empty():
		if seed_id == "": a.sub = "Pick a seed"
		return a
	var plot_id := int(plot.get("id", -1))
	match str(plot.get("state", "")):
		"wild":
			return {"icon": "hoe", "verb": "Till", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "till", "plot": plot_id}, "need": 0}
		"tilled":
			if seed_id == "":
				a.sub = "Pick a seed"
				return a
			var cost := int(crop_for_seed(view, seed_id).get("energy", 2))
			var have := int(view.get("energy", {}).get("value", 0))
			if have < cost:
				return {"icon": "sow", "verb": "Sow ×1", "sub": "Need %d Energy" % cost, "enabled": true, "amber": true,
					"cmd": {"type": "energy_card"}, "need": cost}
			return {"icon": "sow", "verb": "Sow ×1", "sub": "%d Energy" % cost, "enabled": true, "amber": false,
				"cmd": {"type": "sow", "plot": plot_id, "seed": seed_id}, "need": cost}
		"sown":
			return {"icon": "water", "verb": "Water", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "water", "plot": plot_id}, "need": 0}
		"growing":
			return {"icon": "clock", "verb": "Growing", "sub": "Ready in " + duration(float(plot.get("ready_in", 0))), "enabled": false, "amber": false, "cmd": {}, "need": 0}
		"ready":
			return {"icon": "hoe", "verb": "Harvest", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "harvest", "plot": plot_id}, "need": 0}
	return a

## Five Farming candidates (seeds) — kept order: previously shown → most plentiful (§10.3.3).
static func quick_bar(view: Dictionary, previous: Array) -> Array:
	var counts := {}
	for s in view.get("bag", {}).get("slots", []):
		var id := str(s.get("id", ""))
		if id.begins_with("seed_"): counts[id] = int(counts.get(id, 0)) + int(s.get("qty", 0))
	var bar: Array = []
	for id in previous:
		if counts.has(id) and bar.size() < 5: bar.append(id)
	var rest: Array = counts.keys().filter(func(id): return not bar.has(id))
	rest.sort_custom(func(a, b): return counts[a] > counts[b] if counts[a] != counts[b] else str(a) < str(b))
	for id in rest:
		if bar.size() < 5: bar.append(id)
	return bar

## Today chip: the nearest ready crop, else what to do first (§9.5.3; facts only).
static func today_line(view: Dictionary) -> String:
	var best_ms := INF
	var best_crop := ""
	var ready := ""
	var any_sown := false
	for p in view.get("plots", []):
		var st := str(p.get("state", ""))
		if st == "ready": ready = str(p.get("crop", ""))
		if st == "growing":
			any_sown = true
			if float(p.get("ready_in", INF)) < best_ms:
				best_ms = float(p.get("ready_in", INF))
				best_crop = str(p.get("crop", ""))
		if st == "sown": any_sown = true
	if ready != "": return "%s ready to harvest" % plural(item_name(view, ready))
	if best_crop != "": return "%s ready in %s" % [plural(item_name(view, best_crop)), duration(best_ms)]
	if any_sown: return "Water what you sowed"
	return "Sow your first plot"

static func plural(name: String) -> String:
	if name.ends_with("ss") or name.ends_with("sh") or name.ends_with("ch") or name.ends_with("x") or name.ends_with("o"): return name + "es"
	if name.ends_with("s"): return name
	if name.ends_with("y"): return name.substr(0, name.length() - 1) + "ies"
	return name + "s"

## Energy Card facts (§3.7.2): what, have, gap + when; tiles only guide.
static func energy_card(view: Dictionary, need: int, verb: String) -> Dictionary:
	var e: Dictionary = view.get("energy", {})
	var have := int(e.get("value", 0))
	var gap := maxi(0, need - have)
	var next_in = e.get("next_in", null)
	var when := ""
	if gap > 0 and next_in != null:
		when = "+1 in %s" % duration(float(next_in))
	var rest: Dictionary = view.get("rest", {})
	var rest_left := int(rest.get("limit", 1)) - int(rest.get("used", 0))
	return {
		"title": "%s · %d Energy needed" % [verb, need],
		"have": "You have %d" % have,
		"gap": ("Need %d more · %s" % [gap, when]) if when != "" else ("Need %d more" % gap),
		"rest": "Rest · %d/1 today" % maxi(0, rest_left) if rest_left > 0 else "Rest · used today · resets in %s" % duration(float(rest.get("resets_in", 0))),
		"rest_available": rest_left > 0,
	}

## Locally advance a view by elapsed ms (energy ticks and crop timers) between server refreshes.
static func project(view: Dictionary, elapsed_ms: float) -> Dictionary:
	if elapsed_ms <= 0: return view
	var v := view.duplicate(true)
	var e: Dictionary = v.get("energy", {})
	var next_in = e.get("next_in", null)
	if next_in != null:
		var remaining := float(next_in) - elapsed_ms
		var regen := float(e.get("regen_ms", 240000))
		var value := int(e.get("value", 0))
		var maxv := int(e.get("max", 200))
		while remaining <= 0 and value < maxv:
			value += 1
			remaining += regen
		e["value"] = value
		e["next_in"] = null if value >= maxv else remaining
	for p in v.get("plots", []):
		if str(p.get("state", "")) == "growing" and p.get("ready_in", null) != null:
			p["ready_in"] = maxf(0.0, float(p["ready_in"]) - elapsed_ms)
			if float(p["ready_in"]) <= 0.0: p["state"] = "ready"
	return v
