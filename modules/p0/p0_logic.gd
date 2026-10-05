class_name P0Logic
extends RefCounted
## P0 client rules that only read the server view (plan v2 §10.2.2 main action states,
## §10.3.3 quick bar fill, §3.7 countdown format, §9.5.3 Today line; M2: §6.6.1 Cast states,
## §7.2.4 heat ring, §7.17.1 eating). Pure and static: tested headless.

const RARITY_COLORS := [Color("9db89a"), Color("5fa85a"), Color("6fa8dc"), Color("e3b341")]

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

## Five candidates for the current action — Farming: seeds, Fishing: bait — kept order: previously shown → most plentiful (§10.3.3).
static func quick_bar(view: Dictionary, previous: Array, mode := "farm") -> Array:
	var prefix := "bait_" if mode == "fish" else "seed_"
	var counts := {}
	for s in view.get("bag", {}).get("slots", []):
		var id := str(s.get("id", ""))
		if id.begins_with(prefix): counts[id] = int(counts.get(id, 0)) + int(s.get("qty", 0))
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
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if str(r.get("status", "")) != "accepted": continue
		if int(r.have) >= int(r.qty): return "%s · Deliver to Bao" % str(r.title)
		return "%s · %s %d/%d" % [str(r.title), item_name(view, str(r.item)), int(r.have), int(r.qty)]
	if ready != "": return "%s ready to harvest" % plural(item_name(view, ready))
	var stove = view.get("cooking", {}).get("stove", null)
	if stove is Dictionary:
		var dish := item_name(view, str(stove.dish)) if stove.get("dish", null) != null else "Your dish"
		if float(stove.get("ready_in", 0)) <= 0.0: return "%s ready at the stove" % dish
		return "%s · %s left at the stove" % [dish, duration(float(stove.ready_in))]
	var fish := 0
	for st in view.get("bag", {}).get("slots", []):
		if str(st.get("id", "")).begins_with("fish_") and item(view, str(st.id)).get("cook", true): fish += int(st.get("qty", 0))
	if fish > 0: return "%d fish · the stove is free" % fish
	if best_crop != "": return "%s ready in %s" % [plural(item_name(view, best_crop)), duration(best_ms)]
	if any_sown: return "Water what you sowed"
	return "Sow your first plot"

static func plural(name: String) -> String:
	if name.ends_with("ss") or name.ends_with("sh") or name.ends_with("ch") or name.ends_with("x") or name.ends_with("o"): return name + "es"
	if name.ends_with("s"): return name
	if name.ends_with("y"): return name.substr(0, name.length() - 1) + "ies"
	return name + "s"

## Energy Card facts (§3.7.2 / §3.7.3): one card for short and zero; only facts, tiles only guide.
static func energy_card(view: Dictionary, need: int, verb: String) -> Dictionary:
	var e: Dictionary = view.get("energy", {})
	var have := int(e.get("value", 0))
	var mx := int(e.get("max", 200))
	var next_in = e.get("next_in", null)
	var regen := float(e.get("regen_ms", 240000))
	var tick := "" if next_in == null else " · +1 in %s" % duration(float(next_in))
	var full_ms := 0.0 if next_in == null else float(next_in) + float(maxi(0, mx - have - 1)) * regen
	var dishes := 0
	var fish := 0
	for st in view.get("bag", {}).get("slots", []):
		var id := str(st.get("id", ""))
		if id.begins_with("dish_"): dishes += int(st.get("qty", 0))
		if id.begins_with("fish_") and item(view, id).get("cook", true): fish += int(st.get("qty", 0))
	var rest: Dictionary = view.get("rest", {})
	var rest_left := int(rest.get("limit", 1)) - int(rest.get("used", 0))
	return {
		"title": "Energy %d/%d%s" % [have, mx, tick],
		"zero": have <= 0,
		"subtitle": "Recover or do something free" if have <= 0 else "%s needs %d Energy · you have %d" % [verb, need, have],
		"wait": "Wait · Full in %s" % duration(full_ms) if next_in != null else "Wait · Full now",
		"tiles": [
			{"icon": "eat", "label": "Eat", "fact": "%d dish%s in bag" % [dishes, "" if dishes == 1 else "es"] if dishes > 0 else "No dishes in bag", "guide": "Open bag", "go": "bag", "on": dishes > 0},
			{"icon": "pot", "label": "Cook", "fact": "%d fish in creel" % fish if fish > 0 else "No fish to cook", "guide": "Show kitchen", "go": "stove", "on": fish > 0},
			{"icon": "dish_fruit_tea", "label": "Tea", "fact": "Tea House opens later", "guide": "", "go": "", "on": false},
			{"icon": "rest", "label": "Rest", "fact": "Available" if rest_left > 0 else "Rested today · %s" % duration(float(rest.get("resets_in", 0))), "guide": "Show home", "go": "home", "on": rest_left > 0},
		],
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
	var stove = v.get("cooking", {}).get("stove", null)
	if stove is Dictionary:
		stove["elapsed"] = float(stove.get("elapsed", 0)) + elapsed_ms
		stove["ready_in"] = maxf(0.0, float(stove.get("ready_in", 0)) - elapsed_ms)
	var cast = v.get("fishing", {}).get("cast", null)
	if cast is Dictionary: cast["bite_in"] = maxf(0.0, float(cast.get("bite_in", 0)) - elapsed_ms)
	return v

# ---------------------------------------------------------------- M2: fishing, cooking, eating
static func item(view: Dictionary, id: String) -> Dictionary:
	return view.get("items", {}).get(id, {})

static func rarity_name(view: Dictionary, rarity: int) -> String:
	var names: Array = view.get("rarity_names", ["Common", "Fine", "Rare", "Legendary"])
	return str(names[clampi(rarity - 1, 0, names.size() - 1)])

static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity - 1, 0, 3)]

## Dish label with its quality star: "Grilled Crucian ★" (Good) / "★★" (Perfect).
static func dish_label(view: Dictionary, id: String) -> String:
	var info := item(view, id)
	var q := int(info.get("quality", 0))
	return str(info.get("name", item_name(view, id))) + ("" if q == 0 else " " + "★".repeat(q))

## Main action at the pond (§6.6.1): Cast pre-pays 5; creel full / short energy say why.
static func fish_action(view: Dictionary, bait: String, site := "pond") -> Dictionary:
	var f: Dictionary = view.get("fishing", {})
	var cost := int(f.get("cast_energy", 5))
	var a := {"icon": "rod", "verb": "Cast", "sub": "%d Energy" % cost, "enabled": true, "amber": false,
		"cmd": {"type": "cast", "bait": bait if bait != "" else null, "site": site}, "need": cost}
	if f.get("cast", null) != null:
		return {"icon": "bobber", "verb": "Fishing…", "sub": "Line in the water", "enabled": false, "amber": false, "cmd": {}, "need": 0}
	if int(view.get("bag", {}).get("free", 1)) < 1:
		return {"icon": "creel", "verb": "Creel full", "sub": "Sell or cook first", "enabled": false, "amber": true, "cmd": {}, "need": 0}
	if int(view.get("energy", {}).get("value", 0)) < cost:
		a.sub = "Need %d Energy" % cost
		a.amber = true
		a.cmd = {"type": "energy_card"}
	return a

## "Creel 7 · 6 free" — the bag is the creel (§6.6.3).
static func creel_line(view: Dictionary) -> String:
	var fish := 0
	for s in view.get("bag", {}).get("slots", []):
		if str(s.get("id", "")).begins_with("fish_"): fish += int(s.get("qty", 0))
	return "Creel %d · %d free" % [fish, int(view.get("bag", {}).get("free", 0))]

static func protection_line(view: Dictionary) -> String:
	var left = view.get("fishing", {}).get("protection_left", null)
	return "" if left == null else "Catch protection %d left today" % int(left)

static func meal_line(view: Dictionary) -> String:
	var m: Dictionary = view.get("meals", {})
	return "Meals today %d/%d · resets in %s" % [int(m.get("used", 0)), int(m.get("cap", 200)), duration(float(m.get("resets_in", 0)))]

## Eat button for one dish (§7.17.1): full → disabled; clipped → ask; same page → half / none.
static func eat_button(view: Dictionary, id: String) -> Dictionary:
	var e: Dictionary = view.get("energy", {})
	var have := int(e.get("value", 0))
	var mx := int(e.get("max", 200))
	var info := item(view, id)
	var value := int(info.get("meal", 0))
	var full := int(info.get("full", value))
	var m: Dictionary = view.get("meals", {})
	var left := maxi(0, int(m.get("cap", 200)) - int(m.get("used", 0)))
	if have >= mx: return {"text": "Energy full · eat later", "enabled": false, "confirm": ""}
	if left <= 0: return {"text": "Full belly · Meals reset in " + duration(float(m.get("resets_in", 0))), "enabled": true, "confirm": "", "gain": 0}
	var counted := mini(value, left)
	var gain := mini(counted, mx - have)
	if value == 0: return {"text": "Same dish · no Energy today", "enabled": true, "confirm": "", "gain": 0}
	var text := "Eat · +%d Energy" % value
	if value < full: text = "Same dish again · +%d (half)" % value
	var confirm := ""
	if gain < value: confirm = "Only +%d of %d · Eat anyway?" % [gain, value]
	return {"text": text, "enabled": true, "confirm": confirm, "gain": gain}

## One Cookbook row's facts: rarity, energy, time, ingredients with what the bag has.
static func page_line(view: Dictionary, page: Dictionary) -> String:
	var tiers: Dictionary = view.get("cooking", {}).get("tiers", {})
	var t: Dictionary = tiers.get(str(int(page.get("rarity", 1))), {})
	return "%s · +%d Energy · %ds" % [rarity_name(view, int(page.get("rarity", 1))), int(t.get("energy", 20)), int(t.get("ms", 5000)) / 1000]

static func ingredient_label(view: Dictionary, token: String) -> String:
	if token == "?": return "?"
	var tags := {"W": "fish", "F": "vegetable", "O": "fruit", "S": "seasoning"}
	if token.length() == 2 and tags.has(token[0]) and token[1].is_valid_int():
		if token[0] == "S": return "Any seasoning"
		return "Any %s %s" % [rarity_name(view, int(token[1])), tags[token[0]]]
	return item_name(view, token)

## Client-side preview of the server's heat judgement (§7.2.4): first tap in the ring's lifetime, gold ± 150 ms.
static func heat_hit(heat: Dictionary, tap_ms: float, tolerance := 150.0) -> bool:
	var at := float(heat.get("at", 0))
	var spin := float(heat.get("spin", 1600))
	var gold := float(heat.get("gold", 0.3))
	var width := float(heat.get("width", 0.3))
	return tap_ms >= at + gold * spin - tolerance and tap_ms <= at + (gold + width) * spin + tolerance

## Which known Cookbook page these ingredients make (§7.2.3: specific pages before tag pages, fewest
## wildcards first). Unknown pages hide their ingredients, so experiments still discover them.
static func match_known(view: Dictionary, items: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_wild := 99
	for page in view.get("cooking", {}).get("cookbook", []):
		if not page.get("known", false): continue
		var tokens: Array = page.get("in", [])
		if tokens.size() != items.size(): continue
		var wild := tokens.filter(func(t): return str(t).length() == 2).size()
		if wild < best_wild and _fits(view, tokens, items, 0, []):
			best = page
			best_wild = wild
	return best

static func _fits(view: Dictionary, tokens: Array, items: Array, i: int, used: Array) -> bool:
	if i == tokens.size(): return true
	for j in items.size():
		if used.has(j) or not _token_matches(view, str(tokens[i]), str(items[j])): continue
		if _fits(view, tokens, items, i + 1, used + [j]): return true
	return false

static func _token_matches(view: Dictionary, token: String, id: String) -> bool:
	if token.length() == 2 and "WFOS".contains(token[0]) and token[1].is_valid_int():
		var info := item(view, id)
		return str(info.get("family", "")) == token[0] and int(info.get("rarity", 0)) == int(token[1])
	return token == id

## What a new level opens, in one line (§4.5 / §6.7.2 / §7.2.3).
static func unlock_line(view: Dictionary, skill: String, level: int) -> String:
	var names: Array = []
	match skill:
		"fishing":
			for f in view.get("fishing", {}).get("dex", []):
				if int(f.get("level", 0)) == level: names.append(item_name(view, str(f.id)))
			if not names.is_empty(): return "Now you can land " + ", ".join(names)
		"farming":
			for c in view.get("crops", []):
				if int(c.get("level", 0)) == level: names.append(plural(item_name(view, str(c.id))))
			if not names.is_empty(): return "New seeds at Bao's Stall: " + ", ".join(names)
		"cooking":
			if level == 4: return "A 3rd pot slot · three-family dishes"
	return ""

## §3.4.8 one-time rewards, said at the moment that earned them.
static func reward_line(id: String, energy: int) -> String:
	var rarity := ["", "Common", "Fine", "Rare", "Legendary"]
	if id.begins_with("first_fish_"): return "First %s fish! +%d Energy" % [rarity[int(id.substr(11))], energy]
	if id.begins_with("first_dish_"): return "First %s dish! +%d Energy" % [rarity[int(id.substr(11))], energy]
	if id.begins_with("cookbook_"): return "Home Cook · %s recipes · +%d Energy" % [id.substr(9), energy]
	if id.begins_with("fishdex_"): return "Fish-dex %s kinds · +%d Energy" % [id.substr(8), energy]
	return "+%d Energy" % energy

## "Newcomer Blessing · 5 days left" (§3.4.6), or "" once it has ended.
static func blessing_line(view: Dictionary) -> String:
	var b = view.get("blessing", null)
	if not b is Dictionary: return ""
	var days := ceili(float(b.get("left", 0)) / 86400000.0)
	return "Newcomer Blessing · %d day%s left · faster Energy, Meals %d" % [days, "" if days == 1 else "s", int(view.get("meals", {}).get("cap", 300))]

## "Next: Lv3 · Potato, Chamomile seeds" — what the next level of a track opens (§4.5 / §6.7.2 / §7.2.3).
static func next_line(view: Dictionary, skill: String, level: int) -> String:
	if level > 10: return "Top level"
	var parts: Array = []
	match skill:
		"farming":
			for c in view.get("crops", []):
				if int(c.get("level", 0)) == level: parts.append(item_name(view, str(c.id)))
			if not parts.is_empty(): return "Next: Lv%d · %s seeds" % [level, ", ".join(parts)]
		"fishing":
			for f in view.get("fishing", {}).get("dex", []):
				if int(f.get("level", 0)) == level: parts.append(item_name(view, str(f.id)))
			if level == 2: parts.append("Worm Bait")
			if level == 3: parts.append("Reed Rod")
			if not parts.is_empty(): return "Next: Lv%d · %s" % [level, ", ".join(parts)]
		"cooking":
			if level == 4: return "Next: Lv4 · 3rd ingredient slot"
	return "Next: Lv%d · more XP from every new page" % level if skill == "cooking" else "Next: Lv%d" % level

## Today panel (§14.5): up to 3 lines — doable now first, then the shortest countdown, then the skill
## closest to its next level. Facts only; never "spend your Energy".
static func today_lines(view: Dictionary) -> Array:
	var now_lines: Array = []
	var timed: Array = []    # [ms, text]
	var farmed := (view.get("firsts", []) as Array).any(func(f): return str(f).begins_with("harvest:")) \
		or (view.get("plots", []) as Array).any(func(p): return str(p.get("state", "")) in ["sown", "growing", "ready"])
	if not farmed: now_lines.append("Sow your first plot")
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if str(r.get("status", "")) == "open":
			now_lines.append("%s · %d %s · Stall Board" % [str(r.title), int(r.qty), item_name(view, str(r.item))])
			continue
		if str(r.get("status", "")) != "accepted": continue
		if int(r.have) >= int(r.qty): now_lines.append("%s · Deliver to Bao" % str(r.title))
		else: now_lines.append("%s · %s %d/%d" % [str(r.title), item_name(view, str(r.item)), int(r.have), int(r.qty)])
	var ready := {}
	var sown := 0
	for p in view.get("plots", []):
		var st := str(p.get("state", ""))
		if st == "ready": ready[str(p.crop)] = int(ready.get(str(p.crop), 0)) + 1
		elif st == "sown": sown += 1
		elif st == "growing": timed.append([float(p.get("ready_in", 0)), "%s ready in %s" % [plural(item_name(view, str(p.crop))), duration(float(p.get("ready_in", 0)))]])
	for c in ready: now_lines.append("Harvest %d %s" % [int(ready[c]), plural(item_name(view, str(c))) if int(ready[c]) > 1 else item_name(view, str(c))])
	if sown > 0: now_lines.append("Water %d sown plot%s · Free" % [sown, "" if sown == 1 else "s"])
	var stove = view.get("cooking", {}).get("stove", null)
	if stove is Dictionary:
		var dish := item_name(view, str(stove.dish)) if stove.get("dish", null) != null else "Your dish"
		if float(stove.get("ready_in", 0)) <= 0.0: now_lines.append("%s ready at the stove" % dish)
		else: timed.append([float(stove.ready_in), "%s · %s left at the stove" % [dish, duration(float(stove.ready_in))]])
	else:
		var fish := 0
		for st in view.get("bag", {}).get("slots", []):
			if str(st.get("id", "")).begins_with("fish_") and item(view, str(st.id)).get("cook", true): fish += int(st.get("qty", 0))
		if fish > 0: now_lines.append("%d fish · the stove is free" % fish)
	timed.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var lines: Array = now_lines.duplicate()
	for t in timed:
		if lines.size() < 3 and not lines.has(t[1]): lines.append(t[1])
	var best := ""
	var best_gap := 1 << 30
	for key in ["farming", "fishing", "cooking"]:
		var sk: Dictionary = view.get("skills", {}).get(key, {})
		if sk.get("next", null) == null: continue
		var gap := int(sk.next) - int(sk.get("xp", 0))
		if gap < best_gap:
			best_gap = gap
			best = "%s Lv%d in %d XP" % [key.capitalize(), int(sk.get("level", 1)) + 1, gap]
	if lines.size() < 3 and best != "": lines.append(best)
	if lines.is_empty(): lines.append("Sow your first plot")
	return lines.slice(0, 3)
