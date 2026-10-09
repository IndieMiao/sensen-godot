class_name P0Logic
extends RefCounted
## P0 client rules that only read the server view (plan v2 §10.2.2 main action states,
## §10.3.3 quick bar fill, §3.7 countdown format, §9.5.3 Today line; M2: §6.6.1 Cast states,
## §7.2.4 heat ring, §7.17.1 eating). Pure and static: tested headless.

const ICON_DIR := "res://assets/p0/icons/%s.svg"

static var _content: Dictionary = {}

## The bundled content table (shared with the server) for display-only lookups the view doesn't carry.
static func content() -> Dictionary:
	if _content.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/p0_content.json"))
		if parsed is Dictionary: _content = parsed
	return _content

## FISH-5 line 1 for a level gate: "Fishing Lv2 · 3 XP to go" one level up, else "Fishing Lv4 needed · about 30 casts"
## (Common catches at today's level; the estimate ignores first-catch bonuses).
static func level_gate_line(view: Dictionary, need_level: int) -> String:
	var sk: Dictionary = view.get("skills", {}).get("fishing", {})
	var level := int(sk.get("level", 1))
	var xp := int(sk.get("xp", 0))
	var th: Array = content().get("skills", {}).get("fishing", [])
	var need_xp := int(th[need_level - 1]) if need_level - 1 < th.size() else int(sk.get("next", xp))
	var to_go := maxi(0, need_xp - xp)
	if need_level <= level + 1: return "Fishing Lv%d · %d XP to go" % [need_level, to_go]
	var per_cast := int(content().get("fishing", {}).get("catch_xp", [5])[0])
	return "Fishing Lv%d needed · about %d casts" % [need_level, ceili(float(to_go) / maxf(1.0, per_cast))]

## Fish that open at a Fishing level, by name ("Golden Koi, Catfish").
static func fish_at_level(view: Dictionary, level: int) -> Array:
	var out := []
	for d in view.get("fishing", {}).get("dex", []):
		var where = d.get("where", [])
		var inland: bool = not (where is Array) or where.has("pond") or where.has("river")
		if int(d.get("level", 1)) == level and inland: out.append(item_name(view, str(d.id)))
	return out

## What a gate fish that broke free needs (§4.8.6): `Fishing Lv4 needed · You: Lv3 · 30 XP to go` for a level gate,
## `Reed Rod · Fishing Lv3 · 80 coins` for a rod gate (the next rod that lands it).
static func break_free_need(view: Dictionary, ev: Dictionary) -> String:
	if ev.has("need_level"):
		var need := int(ev.need_level)
		var sk: Dictionary = view.get("skills", {}).get("fishing", {})
		var th: Array = content().get("skills", {}).get("fishing", [])
		var need_xp := int(th[need - 1]) if need - 1 < th.size() and need >= 1 else int(sk.get("next", 0))
		return "Fishing Lv%d needed · You: Lv%d · %d XP to go" % [need, int(sk.get("level", 1)), maxi(0, need_xp - int(sk.get("xp", 0)))]
	var rod := rod_for(view, int(ev.get("rarity", 2)))
	return "" if rod.is_empty() else "%s · Fishing Lv%d · %d coins" % [str(rod.name), int(rod.level), int(rod.price)]

## The Energy a failed catch gave back, as it really came back (q(55)): inside the daily protection
## `Energy refunded (8 left today)`, else `+3 Energy back`.
static func refund_line(view: Dictionary, ev: Dictionary) -> String:
	var refund := int(ev.get("refund", 3))
	if ev.has("protected_left") and refund >= int(view.get("fishing", {}).get("cast_energy", 5)):
		return "Energy refunded (%d left today)" % int(ev.protected_left)
	return "+%d Energy back" % refund

## The cheapest rod that holds a rarity, for the "Too heavy for your rod" card.
static func rod_for(view: Dictionary, rarity: int) -> Dictionary:
	for r in view.get("gear", {}).get("rods", []):
		if int(r.get("reach", 0)) >= rarity and not r.get("owned", false): return r
	return {}

# ---------------------------------------------------------------- gate card (§4.8.7, q(49), SKILL-2 482:169)
## Fishing XP a cast brings at the pond recommended for a level (§4.4.2 grid, fails and break-frees included):
## Pond to Lv3, River from Lv4 (the pond card's recommendation; P0 has no coast). Copied from the plan, not read from
## content: it only sizes the gate card's "about N casts" hint — move it into content when the fishing table changes.
const CAST_XP := [2.7, 3.8, 4.9, 5.1, 6.7, 6.7, 5.2, 3.8, 3.2, 2.1]
const GATE_SKILL_ICONS := {"farming": "hoe", "fishing": "rod", "cooking": "pot"}
## Crop names that read the same in the plural ("harvest 30 corn").
const _SAME_PLURAL := ["chamomile", "corn", "lettuce", "chili"]

## The four things on the gate card (§4.8.7): what is locked, which level, how far, what crossing it does. One sheet
## spec for UiInfoSheet (SKILL-2 482:169): the title with the lock, `Locked` (or the rarity), the lead line
## `Farming Lv2 unlocks Carrot and Herb`, a NeedTile `Farming XP 32/50` with `18 XP to go · harvest 9 radishes`
## beside it, the level-up gift row, and at most one guiding button (Show my plots / Cookbook / Skills; none for
## Fishing). gate:
##   {skill, level}           a skill gate; `unlocks` (names) or `after` (a verb phrase, "keeps Golden Koi on the
##                            hook") finish the lead line; unlocks default to the crops / fish of that level
##   {rod: <gear.rods row>}   a rod gate (Fish-dex silhouette, q(57)): coins at the Tackle Shop
##   {homestead: level}       a Homestead gate (Bag Upgrade I, Clay Bank)
## plus what (title), icon (item id), sub (state line, e.g. "Rare"), guide ({label, go} or {} for none).
static func gate_spec(view: Dictionary, gate: Dictionary) -> Dictionary:
	var spec := {id = "gate", title = str(gate.get("what", "")), badge = &"locked",
		rarity_text = str(gate.get("sub", "Locked")), icon = icon(str(gate.get("icon", ""))) if str(gate.get("icon", "")) != "" else null,
		facts = [], buttons = []}
	var guide: Dictionary = {}
	if gate.has("rod"):
		var rod: Dictionary = gate.rod
		var price := int(rod.get("price", 0))
		var rod_lv := int(rod.get("level", 1))
		var short := skill_xp_to_go(view, "fishing", rod_lv)
		spec.lead = "%s lands up to %s fish" % [str(rod.get("name", "")), rarity_name(view, int(rod.get("reach", 1)))]
		var note := "%d coins at Tackle Shop" % price
		if short > 0: note += " · Fishing Lv%d first" % rod_lv
		spec.need = {name = "Coins", have = mini(int(view.get("coins", 0)), price), need = price, icon = icon("coin"), note = note}
	elif gate.has("homestead"):
		var lv := int(gate.homestead)
		var have := int(view.get("homestead", {}).get("level", 1))
		spec.lead = ("Homestead Lv%d %s" % [lv, str(gate.get("after", ""))]).strip_edges()
		var left := maxi(0, lv - have)
		spec.need = {name = "Homestead", have = have, need = lv, icon = icon("home"),
			note = "%d level%s to go" % [left, "" if left == 1 else "s"]}
		guide = {label = "Skills", go = "skills"}
	else:
		var skill := str(gate.get("skill", "farming"))
		var lv := int(gate.get("level", 2))
		var after := str(gate.get("after", ""))
		if after == "":
			var names: Array = gate.get("unlocks", skill_unlocks(view, skill, lv))
			after = ("unlocks " + and_list(names)) if not names.is_empty() else ""
		spec.lead = ("%s Lv%d %s" % [skill.capitalize(), lv, after]).strip_edges()
		var th: Array = content().get("skills", {}).get(skill, [])
		var need_xp := int(th[lv - 1]) if lv >= 1 and lv - 1 < th.size() else 0
		var xp := int(view.get("skills", {}).get(skill, {}).get("xp", 0))
		var to_go := int(gate.get("xp_to_go", maxi(0, need_xp - xp)))
		var act := gate_action(view, skill, to_go)
		spec.need = {name = "%s XP" % skill.capitalize(), have = maxi(0, need_xp - to_go), need = need_xp,
			icon = icon(str(GATE_SKILL_ICONS.get(skill, "field"))),
			note = ("%d XP to go" % to_go) + ((" · " + act) if act != "" else "")}
		spec.info_row = level_gift_row(view, skill, lv)
		guide = {"farming": {label = "Show my plots", go = "plots"}, "cooking": {label = "Cookbook", go = "cookbook"}}.get(skill, {})
	if gate.has("guide"): guide = gate.guide
	if not guide.is_empty(): spec.buttons = [{id = &"guide", label = str(guide.label), kind = &"nav", chevron = false, payload = {go = str(guide.go)}}]
	return spec

## The gate on a Fish-dex silhouette (q(57)): the Fishing level first, then the rod; {} when nothing holds the fish
## back (it just hasn't bitten yet).
static func fish_gate(view: Dictionary, fish_id: String) -> Dictionary:
	var d: Dictionary = {}
	for f in content().get("fish", []):
		if str(f.get("id", "")) == fish_id: d = f
	if d.is_empty(): return {}
	var r := int(d.get("rarity", 1))
	var name := item_name(view, fish_id)
	var base := {what = name, icon = fish_id, sub = "%s · Locked" % rarity_name(view, r)}
	if int(d.get("level", 1)) > int(view.get("skills", {}).get("fishing", {}).get("level", 1)):
		return base.merged({skill = "fishing", level = int(d.level), after = "keeps %s on the hook" % name})
	if r > int(view.get("fishing", {}).get("rod_reach", 4)):
		var rod := rod_for(view, r)
		if not rod.is_empty(): return base.merged({rod = rod})
	return {}

static func dex_caught(view: Dictionary, fish_id: String) -> bool:
	for f in view.get("fishing", {}).get("dex", []):
		if str(f.get("id", "")) == fish_id: return int(f.get("caught", 0)) > 0
	return false

## XP share for a skill level against a content level (§4.2.1, server rules.ts xpPercent): 100 within one level,
## then xp_multiplier (75 / 50 / 25), -1 once outleveled.
static func xp_percent(player_level: int, content_level: int) -> int:
	var d := player_level - content_level
	if d <= 1: return 100
	for row in content().get("xp_multiplier", []):
		if int(row[0]) == d: return int(row[1])
	return -1

## A Fish-dex cell's card (FISH-6, P0): name, rarity, `Caught ×3 · Pond · River` and what it gives now (`Full XP`,
## `XP 50% · Reduced`, `No XP · outleveled`), or `Not caught yet · Pond · River`. No buttons.
static func fish_card_spec(view: Dictionary, fish_id: String) -> Dictionary:
	var d: Dictionary = {}
	for f in view.get("fishing", {}).get("dex", []):
		if str(f.get("id", "")) == fish_id: d = f
	var where := " · ".join((d.get("where", []) as Array).map(func(w): return str(w).capitalize()))
	var n := int(d.get("caught", 0))
	var spec := {id = fish_id, title = item_name(view, fish_id), icon = icon(fish_id if n > 0 else "fish_unknown"),
		rarity_text = rarity_name(view, int(d.get("rarity", 1))), buttons = []}
	if n == 0:
		spec.facts = ["Not caught yet" + ((" · " + where) if where != "" else "")]
		return spec
	var pct := xp_percent(int(view.get("skills", {}).get("fishing", {}).get("level", 1)), int(d.get("level", 1)))
	var xp := "Full XP" if pct >= 100 else ("No XP · outleveled" if pct < 0 else "XP %d%% · Reduced" % pct)
	spec.facts = ["Caught ×%d" % n + ((" · " + where) if where != "" else ""), xp]
	return spec

## XP still needed for a skill level (0 once reached).
static func skill_xp_to_go(view: Dictionary, skill: String, level: int) -> int:
	var th: Array = content().get("skills", {}).get(skill, [])
	if level < 1 or level - 1 >= th.size(): return 0
	return maxi(0, int(th[level - 1]) - int(view.get("skills", {}).get(skill, {}).get("xp", 0)))

## The action amount beside the XP (§4.8.7 "还差多少"): Farming `harvest N <crop>` with the highest-XP crop the
## player can sow at full XP; Fishing `about N casts` at the recommended pond; Cooking `about N new dishes` (first
## cooks, biggest first) or `about N Fine dishes` once no new page is cookable. "" when it can't be worked out.
static func gate_action(view: Dictionary, skill: String, xp_to_go: int) -> String:
	if xp_to_go <= 0: return ""
	var lv := int(view.get("skills", {}).get(skill, {}).get("level", 1))
	match skill:
		"farming":
			var best := {}
			for c in content().get("crops", []):
				if int(c.get("gate", 1)) > lv or lv - int(c.get("level", 1)) > 1: continue   # can't sow / not full XP
				if best.is_empty() or int(c.get("xp", 0)) > int(best.get("xp", 0)): best = c   # ties: the first (Radish)
			if best.is_empty() or int(best.get("xp", 0)) <= 0: return ""
			var n := ceili(float(xp_to_go) / float(best.xp))
			return "harvest %d %s" % [n, crop_plural(str(best.name), n)]
		"fishing":
			var per: float = CAST_XP[clampi(lv, 1, CAST_XP.size()) - 1]
			var n := ceili(float(xp_to_go) / per)
			return "about %d cast%s" % [n, "" if n == 1 else "s"]
		"cooking":
			var tiers: Dictionary = content().get("cooking", {}).get("tiers", {})
			var firsts: Array = []
			for p in view.get("cooking", {}).get("cookbook", []):
				var t: Dictionary = tiers.get(str(int(p.get("rarity", 1))), {})
				if bool(p.get("p0", false)) and not bool(p.get("cooked", false)) and p.get("lock") == null and int(t.get("level", 1)) <= lv:
					firsts.append(int(t.get("first_xp", 0)))
			firsts.sort()
			firsts.reverse()
			var left := xp_to_go
			var n := 0
			for x in firsts:
				if left <= 0: break
				left -= x
				n += 1
			if n > 0 and left <= 0: return "about %d new dish%s" % [n, "" if n == 1 else "es"]
			var fine := int(tiers.get("2", {}).get("xp", 0))
			if n == 0 and fine > 0:
				var m := ceili(float(xp_to_go) / float(fine))
				return "about %d Fine dish%s" % [m, "" if m == 1 else "es"]
			return ""
	return ""

## What a skill level brings, for the gate card's lead line: the crops sown from that Farming level, the fish
## landed from that Fishing level. Cooking unlocks are the caller's words.
static func skill_unlocks(view: Dictionary, skill: String, level: int) -> Array:
	var out: Array = []
	match skill:
		"farming":
			# Main ingredients before seasonings, as §4.8.7 reads them (Carrot and Herb, Potato and Chamomile).
			var crops: Array = content().get("crops", []).filter(func(c): return int(c.get("gate", 1)) == level)
			for main in [true, false]:
				for c in crops:
					if (str(c.get("ingr", ["F"])[0]) == "F") == main: out.append(str(c.name))
		"fishing":   # this season's waters: ponds and rivers (no coast in P0)
			for f in content().get("fish", []):
				var where: Array = f.get("where", ["pond"])
				if int(f.get("level", 1)) == level and (where.has("pond") or where.has("river")): out.append(item_name(view, str(f.id)))
	return out

## The level-up gift of a skill level as the gate card's info row ("Carrot Seeds ×5" / "Level-up gift" / "At Lv2"),
## or {} when that level brings none. Recipes are not counted items: the first other item names the row.
static func level_gift_row(view: Dictionary, skill: String, level: int) -> Dictionary:
	var gifts: Array = content().get("level_gifts", {}).get("%s:%d" % [skill, level], [])
	var items := gifts.filter(func(g): return not str(g[0]).begins_with("recipe:"))
	if items.is_empty(): return {}
	var more := gifts.size() - 1
	return {title = item_name(view, str(items[0][0])), qty = "×%d" % int(items[0][1]),
		lines = ["Level-up gift" + ((" · +%d more" % more) if more > 0 else ""), "At Lv%d" % level]}

## "Carrot", "Carrot and Herb", "Potato, Chamomile and Compost".
static func and_list(names: Array) -> String:
	if names.size() <= 1: return "" if names.is_empty() else str(names[0])
	return ", ".join(names.slice(0, names.size() - 1).map(func(n): return str(n))) + " and " + str(names[-1])

## A crop name in an action amount: "1 radish", "9 radishes", "14 carrots", "30 tomatoes", "12 chamomile".
static func crop_plural(name: String, n: int) -> String:
	var w := name.to_lower()
	if n == 1 or w in _SAME_PLURAL: return w
	if w.ends_with("sh") or w.ends_with("ch") or w.ends_with("s") or w.ends_with("x") or w.ends_with("o"): return w + "es"
	if w.ends_with("y") and not (w.length() > 1 and w[-2] in "aeiou"): return w.substr(0, w.length() - 1) + "ies"
	return w + "s"

## Items that share an existing icon until they get their own (SGODOT-228 content).
const ICON_ALIAS := {"fert_compost": "compost", "tool_row_hoe": "hoe", "bag_upgrade_1": "bag", "postcard_shanghai": "postcard", "wild_herb": "crop_herb", "drink_hot_tea": "dish_fruit_tea", "drink_coffee": "dish_fruit_tea"}

static func icon(id: String) -> Texture2D:
	var path := ICON_DIR % str(ICON_ALIAS.get(id, id))
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

## Plots one Sow action covers with the equipped hoe (Starter Hoe 1, Row Hoe 3; §9.11.2).
static func sow_count(view: Dictionary) -> int:
	for h in view.get("gear", {}).get("hoes", []):
		if h.get("equipped", false): return maxi(1, int(h.get("sow", 1)))
	return 1

## The plots a Row Hoe sows from the bed in front: that bed, then tilled beds next to it in the same row, the
## walking direction first (dir +1 / −1 along the row), up to sow_count. Plot ids run row by row, `columns` a row.
static func row_plots(view: Dictionary, front: Dictionary, columns: int, dir: int) -> Array:
	var out: Array = []
	if front.is_empty() or str(front.get("state", "")) != "tilled": return out
	out.append(front)
	var most := sow_count(view)
	var by_id := {}
	for p in view.get("plots", []): by_id[int(p.get("id", -1))] = p
	var id := int(front.get("id", -1))
	var row := id / columns
	for side in [dir if dir != 0 else 1, -(dir if dir != 0 else 1)]:
		var next: int = id + side
		while out.size() < most and next >= 0 and next / columns == row and by_id.has(next) and str(by_id[next].get("state", "")) == "tilled":
			out.append(by_id[next])
			next += side
	return out

## Main action button for the plot in front of the player (Farming).
## Returns {icon, verb, sub, enabled, amber, cmd, need}. Facilities never appear here (§10.2.2).
## `row`: plots a Row Hoe would sow (row_plots); the selected item decides the verb (k(4)): seeds sow, Compost fertilizes.
static func main_action(view: Dictionary, plot: Dictionary, seed_id: String, row: Array = []) -> Dictionary:
	var a := {"icon": "sow", "verb": "Sow", "sub": "Walk to a plot", "enabled": false, "amber": false, "cmd": {}, "need": 0}
	if plot.is_empty():
		if seed_id == "": a.sub = "Pick a seed"
		return a
	var plot_id := int(plot.get("id", -1))
	if seed_id.begins_with("fert_"):
		var ripe := str(plot.get("state", "")) == "ready"
		if str(plot.get("state", "")) in ["sown", "growing"] and not ripe and not plot.get("fert", false):
			return {"icon": "compost", "verb": "Fertilize", "sub": "Free", "enabled": true, "amber": false,
				"cmd": {"type": "fertilize", "plot": plot_id, "item": seed_id}, "need": 0}
		if str(plot.get("state", "")) == "tilled":
			a.sub = "Pick a seed"
			return a
	match str(plot.get("state", "")):
		"wild":
			return {"icon": "hoe", "verb": "Till", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "till", "plot": plot_id}, "need": 0}
		"tilled":
			# A pinned slot stays on the bar at 0 (LOCK-05) and P0Ui deselects it; a 0 seed is no seed here too, so the
			# key never sends a sow the server turns down (PR #12 review, 李白 q(44) ③). The verb change stops a held row.
			if seed_id == "" or bag_count(view, seed_id) <= 0:
				a.sub = "Pick a seed"
				return a
			var cost := int(crop_for_seed(view, seed_id).get("energy", 2))
			var have := int(view.get("energy", {}).get("value", 0))
			# Row Hoe: as many of the row's plots as the seeds allow, then trimmed to what Energy covers (§5.3).
			var plots: Array = row if row.size() > 1 and int(row[0].get("id", -1)) == plot_id else [plot]
			var n := clampi(mini(plots.size(), bag_count(view, seed_id)), 1, plots.size())
			if have < cost:
				return {"icon": "sow", "verb": "Sow ×%d" % n, "sub": "Need %d Energy" % (cost * n), "enabled": true, "amber": true,
					"cmd": {"type": "energy_card"}, "need": cost * n}
			n = mini(n, have / cost)
			var cmd := {"type": "sow", "plot": plot_id, "seed": seed_id}
			if n > 1: cmd = {"type": "sow", "plots": plots.slice(0, n).map(func(p): return int(p.get("id", -1))), "seed": seed_id}
			return {"icon": "sow", "verb": "Sow ×%d" % n, "sub": "%d Energy" % (cost * n), "enabled": true, "amber": false,
				"cmd": cmd, "need": cost * n}
		"sown":
			return {"icon": "water", "verb": "Water", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "water", "plot": plot_id}, "need": 0}
		"growing":
			return {"icon": "clock", "verb": "Growing", "sub": "Ready in " + duration(float(plot.get("ready_in", 0))), "enabled": false, "amber": false, "cmd": {}, "need": 0}
		"ready":
			return {"icon": "hoe", "verb": "Harvest", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "harvest", "plot": plot_id}, "need": 0}
	return a

## Five candidates for the current action — Farming: seeds, Fishing: bait — kept order: previously shown → most plentiful (§10.3.3).
## Pinned ids always stay on the bar, also at 0 left (LOCK-05, §10.3.3 归零); ids the player dragged off the bar
## (`removed`) are not refilled until pinned again (§10.3.4 "从栏上移除，物品仍在背包").
## What each action's quick bar holds (§10.3.2): Farming seeds and fertiliser, Fishing bait. Anything in the pool
## stays where it was put or pinned; the bar fills its free end only with the first family (seeds / bait).
const BAR_POOL := {"farm": ["seed_", "fert_"], "fish": ["bait_"]}

## The action whose bar takes this item ("farm" / "fish"), or "" when no bar does.
static func bar_action_of(id: String) -> String:
	for mode in BAR_POOL:
		for prefix in BAR_POOL[mode]:
			if id.begins_with(prefix): return mode
	return ""

static func quick_bar(view: Dictionary, previous: Array, mode := "farm", pinned: Array = [], removed: Array = []) -> Array:
	var prefix := "bait_" if mode == "fish" else "seed_"
	var counts := {}
	for s in view.get("bag", {}).get("slots", []):
		var id := str(s.get("id", ""))
		if bar_action_of(id) == mode: counts[id] = int(counts.get(id, 0)) + int(s.get("qty", 0))
	var bar: Array = []
	for id in previous:
		if bar.size() >= 5: break
		# A slot emptied by dragging its item off stays empty in place, not refilled (LOCK-05 v1.10, BAR-DRAG-4).
		if str(id) == "": bar.append("")
		elif not bar.has(id) and (pinned.has(id) or (counts.has(id) and not removed.has(id))): bar.append(id)
	for id in pinned:
		if bar.has(id): continue
		var hole := bar.find("")   # pinning again (Undo, a drop from the Bag) takes the first gap
		if hole >= 0: bar[hole] = id
		elif bar.size() < 5: bar.append(id)
	var rest: Array = counts.keys().filter(func(id): return str(id).begins_with(prefix) and not bar.has(id) and not removed.has(id))
	rest.sort_custom(func(a, b): return counts[a] > counts[b] if counts[a] != counts[b] else str(a) < str(b))
	for id in rest:
		if bar.size() < 5: bar.append(id)
	while not bar.is_empty() and str(bar.back()) == "": bar.pop_back()   # a gap at the end is just the end
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
		if int(r.have) >= int(r.qty): return "%s · Deliver at the Stall" % str(r.title)
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

## Energy Card facts (§3.7.2 / §3.7.3, LOCK-09): one card for short and zero; only facts, tiles only guide.
## Away from home (the pond, later the mine) Cook and Rest are greyed with `At home` (q(6)).
static func energy_card(view: Dictionary, need: int, verb: String, at_home := true) -> Dictionary:
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
	var subtitle := "Recover or do something free" if have <= 0 else "%s needs %d Energy · you have %d" % [verb, need, have]
	var cook := {"icon": "pot", "label": "Cook", "fact": "%d fish in creel" % fish if fish > 0 else "No fish to cook", "guide": "Show kitchen", "go": "stove", "on": fish > 0}
	# LOCK-09: Rest guides to the bench by the farmhouse (SGODOT-224 3fb574b0, q(30)). Near full it says the real
	# gain, like the bench card (rest_state.button `Rest · +25 Energy`).
	var rest_tile := {"icon": "rest", "label": "Rest", "fact": "Available", "guide": "Show bench", "go": "bench", "on": true}
	var rs := rest_state(view)
	if str(rs.button).begins_with("Rest · "): rest_tile.fact = str(rs.button).trim_prefix("Rest · ")
	if rest_left <= 0:
		rest_tile.fact = "Rested today"   # the reset time is on the bench card (李白, 225)
		rest_tile.on = false
	elif rest.has("away_ready_in"):   # q(41): Rest opens after 2 h away from the farm (SGODOT-228)
		var away = rest.get("away_ready_in")
		if away == null:
			rest_tile.fact = "After %dh away" % int(rest.get("away_h", 2))
			rest_tile.on = false
		elif float(away) > 0.0:
			rest_tile.fact = "Ready in %s" % duration(float(away))
			rest_tile.on = false
	if rest_tile.on and str(rs.get("state", "")) == "full":   # nothing to gain: no "+0 Energy" tile (亚瑟 on #37)
		rest_tile.fact = "Energy full"
		rest_tile.on = false
	if not at_home:
		for t in [cook, rest_tile]:
			t.fact = "At home"
			t.on = false
	return {
		"title": "Energy %d/%d%s" % [have, mx, tick],
		"have": have, "max": mx, "regen": "" if next_in == null else "+1 in %s" % duration(float(next_in)),
		"zero": have <= 0,
		"subtitle": subtitle, "fact": subtitle,
		"wait": "Wait · Full in %s" % duration(full_ms) if next_in != null else "Wait · Full now",
		"tiles": [
			{"icon": "dish_grilled_fish", "label": "Eat", "fact": "%d dish%s in bag" % [dishes, "" if dishes == 1 else "es"] if dishes > 0 else "No dishes in bag", "guide": "Open bag", "go": "bag", "on": dishes > 0},
			cook,
			_tea_tile(view),
			rest_tile,
		],
	}

## Tea on the Energy card (BAR-3 / E-11, §3.4.4): three cups a day shared by tea and coffee, from view.drinks
## (SGODOT-228); copy 李白 (225). Facts only: the tile guides to the Tea House on the map. Without the server's
## drinks the tile stays greyed with no line (安其拉 on #11: no placeholder state).
static func _tea_tile(view: Dictionary) -> Dictionary:
	var tea := {"icon": "dish_fruit_tea", "label": "Tea", "fact": "", "guide": "", "go": "", "on": false}
	var drinks: Dictionary = view.get("drinks", {})
	if drinks.is_empty(): return tea
	tea.guide = "Show on map"
	tea.go = "outpost:tea"
	tea.on = true
	if int(drinks.get("left", 0)) <= 0:
		tea.fact = "%d/%d today" % [int(drinks.get("used", 0)), int(drinks.get("limit", 3))]
		tea.on = false
	elif bool(drinks.get("full", false)):
		tea.fact = "Energy full"
		tea.on = false
	elif drinks.get("need", null) != null and int(drinks.need) > int(view.get("coins", 0)):
		# drinks.need is the whole sum a cup asks (price + the 40-coin floor), so the gap is need − coins
		tea.fact = "Need %d more coins" % (int(drinks.need) - int(view.get("coins", 0)))
		tea.on = false
	else:
		tea.fact = "%d/%d today · %d coins" % [int(drinks.get("used", 0)), int(drinks.get("limit", 3)), int(drinks.get("price", 0))]
	return tea

## Inbox parcels as read-only lines until the stage 4 Inbox (SGODOT-234): `Radish ×3 · 22h left`, soonest to expire
## first (奕星 on #11, LOCK-14). The view already sorts them by expiry; left is projected between replies.
static func parcel_lines(view: Dictionary) -> Array:
	var parcels: Array = view.get("inbox", {}).get("parcels", []).duplicate()
	parcels.sort_custom(func(a, b) -> bool: return float(a.get("left", 0)) < float(b.get("left", 0)))
	return parcels.map(func(p) -> String:
		var left := float(p.get("left", 0))
		var when := ("%dh left" % ceili(left / 3600000.0)) if left >= 3600000.0 else ("%dm left" % maxi(1, ceili(left / 60000.0)))
		return "%s ×%d · %s" % [item_name(view, str(p.get("id", ""))), int(p.get("qty", 1)), when])

## Energy panel under the HUD chip (LOCK-09 Kind=Panel): max, today's use as count tiles, the blessing.
static func energy_panel(view: Dictionary) -> Dictionary:
	var e: Dictionary = view.get("energy", {})
	var m: Dictionary = view.get("meals", {})
	var r: Dictionary = view.get("rest", {})
	var out := {
		"max": int(e.get("max", 200)), "level": "",
		"uses": [
			{"name": "Meals", "have": int(m.get("used", 0)), "need": int(m.get("cap", 200)), "icon": "dish_veggie_plate"},
			{"name": "Rest", "have": int(r.get("used", 0)), "need": int(r.get("limit", 1)), "icon": "rest"},
		],
		"blessing": {},
	}
	var b = view.get("blessing", null)
	if b is Dictionary:
		var days := ceili(float(b.get("left", 0)) / 86400000.0)
		out.blessing = {"title": "Newcomer Blessing · %d day%s left" % [days, "" if days == 1 else "s"],
			"detail": "Energy returns %s× faster · Meals %d a day" % [str(snappedf(float(b.get("regen_mult", 1.5)), 0.1)), int(m.get("cap", 300))]}
	return out

## Level progress of a skill track, 0..1 (the HUD avatar ring).
static func skill_progress(s: Dictionary) -> float:
	if s.is_empty() or s.get("next", null) == null: return 1.0
	return clampf(float(int(s.xp) - int(s.floor)) / maxf(1.0, float(int(s.next) - int(s.floor))), 0.0, 1.0)

## HUD data for UiHud.apply (SGODOT-222, LOCK-06). ctx: next_cost (Energy the next action needs),
## place (UiHud place dictionary), unread (overrides the Inbox count). Until the stage 4 Inbox (SGODOT-234) can show
## expiry records, the bell counts the waiting parcels only (奕星 on #11, option B): what the bell's sheet lists.
static func hud_state(view: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var e: Dictionary = view.get("energy", {})
	var have := int(e.get("value", 0))
	var mx := int(e.get("max", 200))
	var nx = e.get("next_in", null)
	var regen := "Full"
	if have > mx: regen = "Bonus +%d" % (have - mx)
	elif nx != null: regen = "+1 in " + duration(float(nx))
	var sk: Dictionary = view.get("skills", {})
	var rows := today_rows(view)
	var out := {
		"energy": have, "energy_max": mx, "regen": regen, "next_cost": int(ctx.get("next_cost", 0)),
		"skills": {"farming": skill_progress(sk.get("farming", {})), "fishing": skill_progress(sk.get("fishing", {}))},
		"coins": int(view.get("coins", 0)), "unread": int(ctx.get("unread", P0Inbox.badge(view))), "buff": {},
		"today": today_chip_line(rows),
		"today_key": today_chip_key(rows),
	}
	if ctx.has("place"): out["place"] = ctx.place
	return out

## Location chip data from a scene's "City · Space" text (P0 is always the home city).
static func place_info(text: String, space_override := "") -> Dictionary:
	var parts := text.split(" · ", false, 1)
	var space := parts[1] if parts.size() > 1 else ""
	if space_override != "": space = space_override
	return {"city": parts[0] if parts.size() > 0 else "", "space": space, "kind": UiHud.PlaceKind.HOME, "day_pass": ""}

## Where a material comes from, for the NeedSource line under a tapped NEED-TILE (LOCK-10): one line, and a
## camera-only Show target ("" hides Show). Never a jump (LOCK-08).
static func need_source(view: Dictionary, id: String) -> Dictionary:
	var label := item_name(view, id)
	if id.begins_with("seed_"): return {"text": "%s · Homestead Stall" % label, "go": "stall"}
	if id.begins_with("crop_"): return {"text": "%s · Grow it on your plots" % label, "go": "plots"}
	if id.begins_with("fish_"): return {"text": "%s · Ponds on the map" % label, "go": ""}
	if id.begins_with("dish_"): return {"text": "%s · Cook it at the stove" % label, "go": "stove"}
	var material := P0MaterialLogic.material_source(view, id)   # spots and mine floors (SGODOT-231 B2-06)
	if not material.is_empty(): return material
	return {"text": label, "go": ""}

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
	for parcel in v.get("inbox", {}).get("parcels", []):
		parcel["left"] = maxf(0.0, float(parcel.get("left", 0)) - elapsed_ms)
	return v

## LOCK-14 / q(87): one InboxNotice card (BAG-5-2) for the rewards of one server reply that did not fit the bag, {} when
## there is nothing to say: {title, item, quantity, line} for UiInboxNotice. The card speaks of the first parcel: its
## name and ×N, `Sent to Inbox` and `Expires in 24h`, or `Inbox full · waiting` and `Claim a parcel first` when it is
## waiting for a place (its 24 h start once it is in, §10.4.8); the reply's other parcels (stacks split included) are
## `+N more · ` before the third line. A resident's gift meal is said by the resident bar instead (SGODOT-225), so gift
## parcels are left out here.
static func parcel_notice(view: Dictionary, events: Array) -> Dictionary:
	var parcels := events.filter(func(e): return str(e.get("kind", "")) == "parcel" and not bool(e.get("gift", false)))
	if parcels.is_empty(): return {}
	var first: Dictionary = parcels[0]
	var waiting := bool(first.get("waiting", false))
	var more := ("+%d more · " % (parcels.size() - 1)) if parcels.size() > 1 else ""
	return {title = "Inbox full · waiting" if waiting else "Sent to Inbox", item = item_name(view, str(first.get("id", ""))),
		quantity = "×%d" % int(first.get("qty", 1)), line = more + ("Claim a parcel first" if waiting else "Expires in 24h")}

## q(88): a resident's gift meal that did not fit the bag (`gift_meal` with to: parcel; §3.4.5) on the same card: the dish
## ×1 and `From Pip · Expires in 9h 12m`, counting down to 04:00 as the Inbox's Parcels row does (the parcel's
## expires_in), or `Inbox full · waiting` / `From Pip · Claim a parcel first` while it waits for a place. {} for a meal
## that went into the bag. Without that parcel in the reply (the server sends it with the meal) the time comes from the
## Inbox's own row; with neither, no time is written rather than a wrong one (刘邦 on #118).
static func gift_meal_notice(view: Dictionary, ev: Dictionary, events: Array) -> Dictionary:
	if str(ev.get("to", "")) != "parcel": return {}
	var dish := str(ev.get("dish", ""))
	var who := str(content().get("residents", {}).get(str(ev.get("resident", "")), {}).get("name", ""))
	var found := events.filter(func(e): return str(e.get("kind", "")) == "parcel" and bool(e.get("gift", false)) and str(e.get("id", "")) == dish)
	var parcel: Dictionary = found[0] if not found.is_empty() else {}
	var waiting := bool(parcel.get("waiting", false))
	var left := float(parcel.get("expires_in", -1))
	if parcel.is_empty():
		var rows := P0Inbox.parcels(view).filter(func(p): return p.get("gift", null) != null and str(p.get("id", "")) == dish)
		left = float(rows[0].get("left", -1)) if not rows.is_empty() else -1.0
	var expiry := ("Expires in " + P0Inbox.left_text(left).trim_suffix(" left")) if left > 0.0 else ""
	var tail := "Claim a parcel first" if waiting else expiry
	var from := "From %s" % who if who != "" else ""
	return {title = "Inbox full · waiting" if waiting else "Sent to Inbox", item = item_name(view, dish), quantity = "×1",
		line = " · ".join(PackedStringArray([from, tail].filter(func(t): return t != "")))}

# ---------------------------------------------------------------- M2: fishing, cooking, eating
static func item(view: Dictionary, id: String) -> Dictionary:
	return view.get("items", {}).get(id, {})

static func rarity_name(view: Dictionary, rarity: int) -> String:
	var names: Array = view.get("rarity_names", ["Common", "Fine", "Rare", "Legendary"])
	return str(names[clampi(rarity - 1, 0, names.size() - 1)])

## Dish label with its quality star: "Grilled Crucian ★" (Good) / "★★" (Perfect).
## COOK-4 for a pot that came out a Mystery Dish (SGODOT-232 S5): with the Newcomer Blessing's refund there is no
## dish at all (李白 2026-10-08), so the card says so and offers no Eat.
static func mystery_card(ev: Dictionary) -> Dictionary:
	if bool(ev.get("none", false)):
		return {title = "No dish this time", sub = "Ingredients back (%d left today)" % int(ev.get("trial_left", 0)), eat = false}
	return {title = "Mystery Dish", sub = "Hmm… not a dish. Try another mix.", eat = true}

static func dish_label(view: Dictionary, id: String) -> String:
	var info := item(view, id)
	var q := int(info.get("quality", 0))
	return str(info.get("name", item_name(view, id))) + ("" if q == 0 else " " + "★".repeat(q))

## Main action at the pond (§6.6.1): Cast pre-pays 5; creel full / short energy say why.
static func fish_action(view: Dictionary, bait: String, site := "pond") -> Dictionary:
	# Bait is optional (不知火舞 on PR #12): a pinned bait at 0 stays on the bar, and the cast just goes without it.
	if bait != "" and bag_count(view, bait) <= 0: bait = ""
	var f: Dictionary = view.get("fishing", {})
	var cost := int(f.get("cast_energy", 5))
	var a := {"icon": "rod", "verb": "Cast", "sub": "%d Energy" % cost, "enabled": true, "amber": false,
		"cmd": {"type": "cast", "bait": bait if bait != "" else null, "site": site}, "need": cost}
	if f.get("cast", null) != null:
		return {"icon": "bobber", "verb": "Fishing…", "sub": "Line in the water", "enabled": false, "amber": false, "cmd": {}, "need": 0}
	if int(view.get("bag", {}).get("free", 1)) < 1:
		# FISH-4: the key is greyed with the short reason (plan §10.2.2 `Cast · Creel full`); pressing it or the creel
		# badge says the long one in the Error toast with Open bag › (q(83): no pills above the switch).
		return {"icon": "rod", "verb": "Cast", "sub": "Creel full", "enabled": false, "amber": false,
			"cmd": {}, "need": 0, "creel_full": true}

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
			if not names.is_empty(): return "New seeds at the Homestead Stall: " + ", ".join(names)
		"cooking":
			if level == 4: return "A 3rd pot slot · three-family dishes"
	return ""

## Cooking conveniences by key (§7.2.2 / §4.6.3): the names the level banner and SKILL-1 use.
const CONVENIENCE_NAMES := {"cook_again": "Cook Again", "clue_double": "Double Clue", "hearty_mishap": "Hearty Mishap",
	"steady_hand_1": "Steady Hand I", "queue_two": "Queue ×2", "quick_fire": "Quick Fire"}
const LEVEL_TIP := "Levels unlock gear, fish and seeds. Basics never lock."
## Levels that change the day say so on the banner's Tip instead of the next level (§4.8.3, q(69)).
const DAY_CHANGES := {"cooking:4": "Today changes: 3-ingredient dishes", "farming:6": "Today changes: no more watering"}

## The MomentBanner for a skill level-up (§4.8.3 / §4.8.6; ev = the server's {skill, level, energy, gifts}). Fields as
## the accepted FARM-LV2 (1368:91797), content and timing as §4.8.6 (不知火舞 233, 10-08):
##   subtitle  `New for you · Potato, Chamomile, Compost` (what the level opens, q(69)); Fishing `Fine fish now stay on the hook`;
##             Cooking Lv4 `Three-ingredient dishes now possible`
##   rewards   pills: the Energy and the level-up gift's items (`+50 Energy` · `+3 Worm Bait` · `+3 Wild Herb`; SKILL-3
##             482:65; Cooking levels give no Energy)
##   detail    recipe cards only (`New recipe: Herb Grilled Fish`), else nothing
##   tip       the next level (`Next Lv4 · Tomato, Chili, Row Hoe · 150 XP`, its new things this season); the account's
##             first level-up teaches instead, a level that changes the day says `Today changes: …` (q(69))
##   time      the account's first ≤ 3 s, later ones 1.5 s; `Use bait` when the first one gave bait
static func level_banner(view: Dictionary, ev: Dictionary, first := false) -> Dictionary:
	var skill := str(ev.get("skill", "farming"))
	var lv := int(ev.get("level", 2))
	var title := "%s Lv %d" % [skill.capitalize(), lv]
	var rewards: Array = []
	if int(ev.get("energy", 0)) > 0:
		rewards.append({text = "+%d Energy" % int(ev.energy), tone = UiFloatText.Tone.ENERGY_GAIN})
	var recipes: Array = []
	var bait := ""
	for g in ev.get("gifts", []):
		var id := str(g[0])
		if id.begins_with("recipe:"): recipes.append(item_name(view, id.substr(7)))
		else:
			rewards.append({text = "+%d %s" % [int(g[1]), item_name(view, id)], tone = UiFloatText.Tone.ITEM, icon = icon(id)})
			if id.begins_with("bait_") and bait == "": bait = id
	var opens := level_unlocks(view, skill, lv)
	var subtitle := ("New for you · " + ", ".join(opens)) if not opens.is_empty() else ""
	if skill == "fishing": subtitle = fishing_unlock_line(view, lv)
	if skill == "cooking" and lv == 4:
		title += " · 3rd slot"
		subtitle = "Three-ingredient dishes now possible"
	var detail := ("New recipe: " + ", ".join(recipes)) if not recipes.is_empty() else ""
	# Tip: the next level, except the account's first (the teaching line) and a level that changes the day (q(69)).
	var tip := LEVEL_TIP if first else str(DAY_CHANGES.get("%s:%d" % [skill, lv], next_level_line(view, skill, lv)))
	return {kind = "level_up", level = str(lv), title = title, subtitle = subtitle, rewards = rewards, detail = detail,
		tip = tip, action = "Use bait" if first and bait != "" else "", action_id = "use_bait" if first and bait != "" else "",
		seconds = 3.0 if first else 1.5}

## What a skill level opens this season: Farming — the crops of that gate (main ingredients first), then other stall
## goods and tools (Compost, Row Hoe); Fishing — the fish of that level; Cooking — the conveniences of that level.
static func level_unlocks(view: Dictionary, skill: String, level: int) -> Array:
	var out: Array = []
	match skill:
		"farming":
			# The crops, main ones first (`Potato, Chamomile`), then other stall goods and tools (`Compost`) — q(69).
			out = skill_unlocks(view, "farming", level)
			for o in view.get("stall", {}).get("buy", []):
				var id := str(o.get("id", ""))
				if id.begins_with("seed_") or str(o.get("skill", "farming")) != "farming" or int(o.get("gate", 1)) != level: continue
				out.append(item_name(view, id))
			var hoe: Dictionary = content().get("tools", {}).get("row_hoe", {})
			if int(hoe.get("gate", 0)) == level: out.append(item_name(view, str(hoe.get("id", ""))))
		"fishing":
			# The fish, then gear and goods the level opens (Worm Bait at Lv2, the Reed Rod at Lv3).
			out = skill_unlocks(view, "fishing", level)
			for o in view.get("stall", {}).get("buy", []):
				if str(o.get("skill", "")) == "fishing" and int(o.get("gate", 1)) == level: out.append(item_name(view, str(o.get("id", ""))))
			for r in content().get("fishing", {}).get("rods", []):
				if int(r.get("level", 1)) == level and int(r.get("price", 0)) > 0: out.append(str(r.get("name", "")))
		"cooking":
			var conv: Dictionary = content().get("cooking", {}).get("conveniences", {})
			for k in conv:
				if int(conv[k]) == level: out.append(str(CONVENIENCE_NAMES.get(k, k)))
			if level == 4: out.push_front("third ingredient slot")   # SKILL-1 482:167
	return out

## `Fine fish now stay on the hook` when a level opens a whole rarity, else the fish by name (`Golden Koi now stays
## on the hook`); "" when no fish opens at that level.
static func fishing_unlock_line(view: Dictionary, level: int) -> String:
	var fish: Array = content().get("fish", []).filter(func(f): return int(f.get("level", 1)) == level)
	if fish.is_empty(): return ""
	var rarities := {}
	for f in fish: rarities[int(f.get("rarity", 1))] = true
	if fish.size() >= 3 and rarities.size() == 1:
		return "%s fish now stay on the hook" % rarity_name(view, int(rarities.keys()[0]))
	var names: Array = fish.map(func(f): return item_name(view, str(f.id)))
	return "%s now %s on the hook" % [and_list(names), "stays" if names.size() == 1 else "stay"]

## `Next Lv4 · Tomato, Chili, Row Hoe · 150 XP`, or `Next Lv5 · 200 XP` when that level brings nothing this season.
static func next_level_line(view: Dictionary, skill: String, level: int) -> String:
	var th: Array = content().get("skills", {}).get(skill, [])
	if level >= th.size(): return ""
	var to_go := maxi(0, int(th[level]) - int(view.get("skills", {}).get(skill, {}).get("xp", th[level - 1])))
	var opens := level_unlocks(view, skill, level + 1)
	return "Next Lv%d%s · %d XP" % [level + 1, (" · " + ", ".join(opens)) if not opens.is_empty() else "", to_go]

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

## The Today chip names the row with the focus, the first still to do (q(58)): a ticked guide row (Deliver after the
## Pond Catch is handed in) stays in the panel with its ✓ but no longer heads the chip. "" when nothing is left to do.
static func today_chip_line(rows: Array) -> String:
	for r in rows:
		if str(r.get("state", "")) != "done": return str(r.line)
	return ""

## Which row the chip names, independent of its countdown text: the chip pulses when this changes (不知火舞 on 232),
## not when "Radishes ready in 3h 48m" ticks to 3h 47m.
static func today_chip_key(rows: Array) -> String:
	for r in rows:
		if str(r.get("state", "")) != "done": return "%s|%s" % [str(r.get("go", "")), str(r.get("icon", ""))]
	return ""

## Today panel (§14.5): up to 3 lines — doable now first, then the shortest countdown, then the skill
## closest to its next level. Facts only; never "spend your Energy".
static func today_lines(view: Dictionary) -> Array:
	return today_rows(view).map(func(r): return r.line)

## Today rows (§14.5, LOCK-06 TodayRow): {line, icon, go, state, tail}. Now-lines first, then countdowns, then
## the nearest skill level; at most 3. `go` is a camera-only Show target ("" hides Show, LOCK-08).
## The first-session guide's rows lead (P0Guide.lead_rows, §14.2 / q(58)): the tutorial request and the first dish replace
## their generic rows; only the first row still to do has the focus.
static func today_rows(view: Dictionary) -> Array:
	var now_rows: Array = []
	var timed: Array = []    # [ms, row]
	var lead := P0Guide.lead_rows(view)
	var guided_stove := lead.any(func(r): return str(r.go) == "stove" and str(r.state) != "done")
	var farmed := (view.get("firsts", []) as Array).any(func(f): return str(f).begins_with("harvest:")) \
		or (view.get("plots", []) as Array).any(func(p): return str(p.get("state", "")) in ["sown", "growing", "ready"])
	if not farmed: now_rows.append(_first_sow_row(view))
	now_rows.append_array(lead)
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if str(r.get("id", "")) == P0Guide.TUTORIAL: continue   # the guide's Catch / Deliver row
		if str(r.get("status", "")) == "open":
			now_rows.append(_row("%s · %d %s · Stall Board" % [str(r.title), int(r.qty), item_name(view, str(r.item))], "board", "stall"))
			continue
		if str(r.get("status", "")) != "accepted": continue
		if int(r.have) >= int(r.qty): now_rows.append(_row("%s · Deliver at the Stall" % str(r.title), "board", "stall"))
		else: now_rows.append(_row("%s · %s %d/%d" % [str(r.title), item_name(view, str(r.item)), int(r.have), int(r.qty)], str(r.item), ""))
	var ready := {}
	var sown := 0
	for p in view.get("plots", []):
		var st := str(p.get("state", ""))
		if st == "ready": ready[str(p.crop)] = int(ready.get(str(p.crop), 0)) + 1
		elif st == "sown": sown += 1
		elif st == "growing": timed.append([float(p.get("ready_in", 0)), _row("%s ready in %s" % [plural(item_name(view, str(p.crop))), duration(float(p.get("ready_in", 0)))], str(p.crop), "plots")])
	# One harvest row (q(69)): `Harvest 20 Radishes` for one crop, `Harvest 30 crops` for several; the level it brings
	# follows it as an info row (`Farming Lv 2 with this harvest`, no button — §14.5's exception: it goes with its source).
	var level := P0Guide.harvest_level(view)
	if ready.size() == 1:
		var c: String = ready.keys()[0]
		now_rows.append(_row("Harvest %d %s" % [int(ready[c]), plural(item_name(view, c)) if int(ready[c]) > 1 else item_name(view, c)], c, "plots"))
	elif ready.size() > 1:
		var n := 0
		for c in ready: n += int(ready[c])
		now_rows.append(_row("Harvest %d crops" % n, str(ready.keys()[0]), "plots"))
	if not ready.is_empty() and bool(level.get("now", false)):
		now_rows.append(_row("Farming Lv %d with this harvest" % int(level.level), "hoe", ""))
	if sown > 0: now_rows.append(_row("Water %d sown plot%s · Free" % [sown, "" if sown == 1 else "s"], "water", "plots"))
	var stove = view.get("cooking", {}).get("stove", null)
	if stove is Dictionary:
		var dish := item_name(view, str(stove.dish)) if stove.get("dish", null) != null else "Your dish"
		var dish_icon := str(stove.dish) if stove.get("dish", null) != null else "pot"
		if float(stove.get("ready_in", 0)) <= 0.0: now_rows.append(_row("%s ready at the stove" % dish, dish_icon, "stove"))
		else: timed.append([float(stove.ready_in), _row("%s · %s left at the stove" % [dish, duration(float(stove.ready_in))], dish_icon, "stove")])
	else:
		var fish := 0
		for st in view.get("bag", {}).get("slots", []):
			if str(st.get("id", "")).begins_with("fish_") and item(view, str(st.id)).get("cook", true): fish += int(st.get("qty", 0))
		if fish > 0 and not guided_stove: now_rows.append(_row("%d fish · the stove is free" % fish, "pot", "stove"))
	timed.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var rows: Array = now_rows.duplicate()
	for t in timed:
		if rows.size() < 3 and not rows.any(func(r): return r.line == t[1].line): rows.append(t[1])
	# Not harvested yet, the growing crops bring the level: the info row follows the soonest crop's row (q(69), the old
	# tail on that row read as that crop's own level, §14.2 end).
	if not level.is_empty() and not bool(level.now) and not P0Guide.first_phase(view):
		var at := -1
		for i in rows.size():
			if str(rows[i].go) == "plots" and at < 0: at = i
		if at >= 0: rows.insert(at + 1, _row("Farming Lv %d at your first harvest" % int(level.level), "hoe", ""))
	var best := ""
	var best_gap := 1 << 30
	for key in ["farming", "fishing", "cooking"]:
		var sk: Dictionary = view.get("skills", {}).get(key, {})
		if sk.get("next", null) == null: continue
		if key == "farming" and not level.is_empty(): continue   # already said by the harvest's info row
		var gap := int(sk.next) - int(sk.get("xp", 0))
		if gap < best_gap:
			best_gap = gap
			best = "%s Lv %d · %d XP to go" % [key.capitalize(), int(sk.get("level", 1)) + 1, gap]   # q(69)
	if rows.size() < 3 and best != "": rows.append(_row(best, "xp", ""))
	if rows.is_empty(): rows.append(_first_sow_row(view))
	return P0Guide.focus_first(rows.slice(0, 3))

static func _row(line: String, icon_id: String, go: String) -> Dictionary:
	return {"line": line, "icon": icon_id, "go": go, "state": "default", "tail": "", "focus": false}

## "Sow your first plot", short of Energy when sowing a radish costs more than the player has (TodayRow Short).
static func _first_sow_row(view: Dictionary) -> Dictionary:
	var r := _row("Sow your first plot", "seed_radish", "plots")
	var e: Dictionary = view.get("energy", {})
	var cost := int(crop_for_seed(view, "seed_radish").get("energy", 2))
	if int(e.get("value", 0)) < cost:
		r.state = "short"
		r.tail = "needs %d Energy" % cost + ("" if e.get("next_in", null) == null else " · +1 in %s" % duration(float(e.next_in)))
	return r

## Resident dialogue bar data (LOCK-18, SGODOT-225 UiResidentBar) from view.residents facts + the content table:
## {id, portrait, name, role, stage, have, need, next, line, gift_reason, request_label, request_reason, request_cmd,
##  meal, meal_note, lesson}. An empty reason means the button works; otherwise the button is grey with that reason.
static func resident_bar(view: Dictionary, id: String) -> Dictionary:
	var def: Dictionary = content().get("residents", {}).get(id, {})
	var r: Dictionary = view.get("residents", {}).get(id, {})
	if def.is_empty() or r.is_empty(): return {}
	var lines: Dictionary = def.get("lines", {})
	var stage := str(r.get("stage", "Stranger"))
	var line := str(lines.get(stage, lines.get("Familiar", lines.get("Stranger", ""))))
	var gift_reason := ""
	if r.get("gift_today", false): gift_reason = "Gift already given today"
	elif not _has_dish(view): gift_reason = "No dishes in your bag"
	var label := "Request"
	var reason := ""
	var cmd := {}
	var req = r.get("request", null)
	match str(r.get("request_state", "none")):
		"open":
			cmd = {"type": "accept", "request": str(req.id)}
		"accepted":
			label = "Deliver"
			if req.get("ready", false): cmd = {"type": "deliver", "request": str(req.id)}
			else: reason = _request_gap(req)
		"wait":
			reason = "Next request in " + duration(float(r.get("next_in", 0)))
		"stage":
			reason = "Next request at " + str(r.get("need_stage", ""))
		_:
			reason = "No more requests"
	var meal := str(r.get("meal", "none"))
	var note := ""
	return {
		"id": id, "portrait": str(def.get("portrait", "")), "name": str(def.get("name", "")), "role": str(def.get("role", "")),
		"stage": stage, "stage_index": affinity_stage_index(stage), "have": int(r.get("affinity", 0)),
		"need": int(r.get("next_at", r.get("affinity", 0))) if r.get("next_at", null) != null else int(r.get("affinity", 0)),
		"next": str(r.get("next_stage", "")) if r.get("next_stage", null) != null else "",
		"line": line, "gift_reason": gift_reason,
		"request_label": label, "request_reason": reason, "request_cmd": cmd,
		"meal": meal == "given" and not gift_meal(view, id).is_empty(), "meal_note": note, "lesson": false,
	}

## The affinity stage's place in content affinity.stages (Stranger 0 … Kindred 4; 0 for a name it does not know): the
## stage label's tone follows it (用户 on 225 验收, 不知火舞's palette).
static func affinity_stage_index(stage: String) -> int:
	var stages: Array = content().get("affinity", {}).get("stages", [])
	for i in stages.size():
		if str((stages[i] as Array)[0]) == stage: return i
	return 0

## Where today's gift meal from resident `id` is (§3.4.5): {at: "bag", item} for the stack they gave (it carries
## `from`), {at: "inbox", item} for the parcel it became with the bag full; {} once it is eaten, passed on or gone.
static func gift_meal(view: Dictionary, id: String) -> Dictionary:
	for s in view.get("bag", {}).get("slots", []):
		if str(s.get("from", "")) == id: return {"at": "bag", "item": str(s.get("id", ""))}
	for p in view.get("inbox", {}).get("parcels", []):
		if str(p.get("key", "")).begins_with("gift_meal:%s:" % id): return {"at": "inbox", "item": str(p.get("id", ""))}
	return {}

## A resident's line after a gift (Mystery Dish only so far, q(33)); "" keeps the stage line.
static func resident_reply(id: String, verdict: String) -> String:
	if verdict != "not_a_fan": return ""
	var def: Dictionary = content().get("residents", {}).get(id, {})
	return str(def.get("lines", {}).get("mystery", content().get("affinity", {}).get("mystery_line", "")))

static func _has_dish(view: Dictionary) -> bool:
	for s in view.get("bag", {}).get("slots", []):
		if str(s.get("id", "")).begins_with("dish_"): return true
	return false

## What an accepted request still needs, written on the button (LOCK-10: gaps on buttons).
static func _request_gap(req: Dictionary) -> String:
	var left := maxi(0, int(req.get("qty", 0)) - int(req.get("have", 0)))
	match str(req.get("kind", "")):
		"sow": return "Plant %d more plot%s" % [left, "" if left == 1 else "s"]
		"dish": return "Need %d more dish%s" % [left, "" if left == 1 else "es"]
		"fish":
			var rarity := int(req.get("rarity", 0)) if req.get("rarity", null) != null else 0
			var names: Array = content().get("rarity_names", [])
			var what := (str(names[rarity - 1]) + " fish") if rarity > 0 and rarity <= names.size() else "fish"
			return "Need %d more %s" % [left, what]
	return "Need %d more" % left

# ---------------------------------------------------------------- outpost keepers (SGODOT-224, LOCK-15 / 16)
## Keeper greeting card copy (李白 SGODOT-228 b7d8b665 D, P0 version) from the server's facts in view.keepers[role]
## (SGODOT-228: state codes and numbers, no names). Names and places are data (后裔's p0_outposts.json): the caller
## passes them in ctx {keeper, place}; the tackle answer also takes ctx.nearest {name, site} (the closest pond).
## Returns {line, greet, counter, trade, question, answer} — line is "Pours the tea · Lotus Tea House" when ctx.place is
## given; `greet` is the greeting card's line, `counter` the keeper bar's over the counter drawer (附录 B 掌柜问候 · P0's
## counter lines: the greeting card's question never sits on the counter, 不知火舞 #56).
const _KEEPER_COPY := {
	"tea": {"does": "Pours the tea", "trade": "order tea", "question": "Any news in town?"},
	"post": {"does": "Runs the post", "trade": "get a coffee", "question": "Who needs help today?"},
	"tackle": {"does": "Minds the tackle", "trade": "see the rods", "question": "Where are they biting?"},
	"market": {"does": "Keeps the stall", "trade": "open the stall", "question": "What's fresh today?"},
}
const _CUPS_OUT := "That's three cups today. Come back tomorrow."

static func keeper_lines(view: Dictionary, role: String, ctx := {}) -> Dictionary:
	var copy: Dictionary = _KEEPER_COPY.get(role, {})
	var k: Dictionary = view.get("keepers", {}).get(role, {})
	var greet := ""
	var counter := ""
	var answer := ""
	match role:
		"tea":
			match str(k.get("greet", "")):
				"cups_out": greet = _CUPS_OUT
				"full": greet = "You look rested. Tea's here when you need it."
				_: greet = "Sit a minute. Hot tea, %d Energy a cup." % int(view.get("drinks", {}).get("energy", 30))
			answer = "Quiet day."
			if k.get("online", null) != null: answer += " %d %s around Shanghai right now." % [int(k.online), "person" if int(k.online) == 1 else "people"]
		"post":
			var pip := resident_name(str(k.get("request_by", ""))) if k.get("request_by", null) != null else ""
			match str(k.get("greet", "")):
				"cups_out": greet = _CUPS_OUT
				"request": greet = "Coffee's fresh. %s's been asking for a hand." % pip
				_: greet = "Coffee's fresh. %d %s left today." % [int(k.get("cups_left", 0)), "cup" if int(k.get("cups_left", 0)) == 1 else "cups"]
			if pip != "": answer = "%s has a request for you." % pip
			elif int(k.get("board_open", 0)) > 0: answer = _board_count(int(k.board_open))
			else: answer = "All quiet." + ("" if k.get("refill_in", null) == null else " The Market Board refills in %s." % duration(float(k.refill_in)))
		"tackle":
			if str(k.get("greet", "")) == "reed_rod":
				var rod := _rod_offer(view, "rod_reed")
				greet = "Reed Rod's in. %d coins, lands up to %s." % [int(rod.get("price", 80)), rarity_name(view, int(rod.get("reach", 3)))]
			else:
				greet = "Worms are %d coins. %d left today." % [int(_shop_price(view, "tackle", "bait_worm", 2)), int(k.get("worms_left", 0))]
			var near: Dictionary = ctx.get("nearest", {})
			if not near.is_empty():
				var nxt = k.get("next_fish", {}).get(str(near.get("site", "pond")), null)
				answer = "%s is closest. " % str(near.name)
				answer += ("%s need Fishing Lv%d." % [item_name(view, str(nxt.id)), int(nxt.level)]) if nxt is Dictionary else "You can land everything there."
		"market":
			if str(k.get("greet", "")) == "row_hoe":
				# 李白 q(46): Mei's P0 greeting is the Row Hoe (the stall's only gear), not the sweet-potato line.
				var hoe: Dictionary = content().get("tools", {}).get("row_hoe", {})
				greet = "Morning! Row Hoes just came in — sows %s plots at once, Farming Lv%d. Anything I can get you?" % [
					_count_word(int(hoe.get("sow", 3))), int(hoe.get("gate", 4))]
				counter = "Row Hoe's %d coins. Farming Lv%d to use." % [_shop_price(view, "market", "tool_row_hoe", int(hoe.get("price", 240))),
					int(hoe.get("gate", 4))]
			else:
				greet = _board_count(int(k.get("board_open", 0)))
			var titles: Array = k.get("board_templates", []).map(func(t): return str(content().get("requests", {}).get("templates", {}).get(str(t), {}).get("title", "")))
			titles = titles.filter(func(t): return t != "")
			if not titles.is_empty(): answer = "Fresh off the board: %s." % " and ".join(PackedStringArray(titles))
			else: answer = "Board's empty." + ("" if k.get("refill_in", null) == null else " Next request in %s." % duration(float(k.refill_in)))
	var place := str(ctx.get("place", ""))
	return {
		"line": ("%s · %s" % [str(copy.get("does", "")), place]) if place != "" else str(copy.get("does", "")),
		"greet": greet, "counter": counter if counter != "" else greet, "trade": "Trade · " + str(copy.get("trade", "")),
		"question": str(copy.get("question", "")), "answer": answer, "leave": "Just passing by",
	}

## Small counts in keeper speech ("sows three plots"), digits from ten up.
static func _count_word(n: int) -> String:
	var words := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
	return words[n] if n >= 0 and n < words.size() else str(n)

static func _board_count(n: int) -> String:
	return "The Market Board has %d %s today." % [n, "request" if n == 1 else "requests"]

## A resident's name from its id (`res_pip` → Pip); "" for an unknown id.
static func resident_name(id: String) -> String:
	return str(content().get("residents", {}).get(id, {}).get("name", ""))

static func _shop_price(view: Dictionary, role: String, id: String, fallback: int) -> int:
	for o in view.get("shops", {}).get(role, {}).get("buy", []):
		if str(o.get("id", "")) == id: return int(o.get("price", fallback))
	return fallback

static func _rod_offer(view: Dictionary, id: String) -> Dictionary:
	for r in view.get("gear", {}).get("rods", []):
		if str(r.get("id", "")) == id: return r.merged({"price": _shop_price(view, "tackle", id, int(r.get("price", 0)))})
	return {}

# ---------------------------------------------------------------- rest bench (FARM-7, q(30) / q(41), SGODOT-224)
## The bench's state from view.rest {used, limit, resets_in, amount, away_h, away_ready_in} and Energy (FARM-7-2 482:52;
## q(70): `wait` is the strip's fact while it can't be used yet, "in 1h 12m" or "after 2h away"):
## state "ready" / "away" (2 h away from home first, q(41)) / "used" / "full"; the badge (STATE-ICONS: Available,
## Countdown with the time left, Used today); the near card copy; the sheet's lines and its one button.
## Near-full Rest says the real gain (WP4-D10 ②: "Rest · +25 Energy"). away_ready_in null = never left home.
static func rest_state(view: Dictionary) -> Dictionary:
	var r: Dictionary = view.get("rest", {})
	var e: Dictionary = view.get("energy", {})
	var amount := int(r.get("amount", 60))
	var gain := mini(amount, maxi(0, int(e.get("max", 200)) - int(e.get("value", 0))))
	var used := int(r.get("used", 0)) >= int(r.get("limit", 1))
	var away = r.get("away_ready_in", 0)
	var out := {
		"state": "ready", "badge": "available", "caption": "",
		"card": "Rest · +%d Energy · once a day" % amount,
		"sheet_state": "Available", "effect": "Restores up to %d Energy" % amount,
		"fact": "Uses left", "fact_value": "%d today" % maxi(0, int(r.get("limit", 1)) - int(r.get("used", 0))),
		"button": ("Rest · +%d Energy" % gain) if gain < amount else "Rest", "reason": "", "can_rest": true,
		"close": "Not now", "note": "",
	}
	if used:
		out.merge({"state": "used", "badge": "used_today", "sheet_state": "Used today", "effect": "",
			"fact": "Uses", "fact_value": "%d/%d" % [int(r.get("used", 0)), int(r.get("limit", 1))], "button": "", "can_rest": false,
			"close": "Close", "note": "Available again at the next home-day reset."}, true)
	elif away == null or float(away) > 0.0:
		# q(41) / q(70): Rest opens 2 h after leaving the homestead. A new account that never left has no leave time
		# (away_ready_in null): no countdown at all, just "after 2h away"; after the first leave the time to go.
		var left := "" if away == null else duration(float(away))
		var back := "Rest · back after %dh away" % int(r.get("away_h", 2))
		out.merge({"state": "away", "badge": "countdown", "caption": left, "effect": "",
			"sheet_state": back if away == null else "%s · %s to go" % [back, left],
			"wait": "after %dh away" % int(r.get("away_h", 2)) if away == null else "in " + left,
			"reason": "Not yet", "can_rest": false, "close": "Close"}, true)
	elif gain <= 0:
		out.merge({"state": "full", "reason": "Energy full", "can_rest": false}, true)
	return out

## HOME-1 (Figma 482:152, §8.6.1, LOCK-10) from view.homestead facts: title, the look line, NEED-TILEs in order
## materials → coins → skills, what changes, and the button (the first gap is written on it). P0 stops at Lv3.
## {title, look, tiles: [{id, name, have, need, icon}], changes: [{icon, text, note}], label, reason, footer, max}
static func home_panel(view: Dictionary, at_home := true) -> Dictionary:
	var h: Dictionary = view.get("homestead", {})
	var level := int(h.get("level", 1))
	var next = h.get("next", null)
	var out := {"title": "Homestead Lv%d" % level, "look": "", "tiles": [], "changes": [], "label": "Upgrade",
		"reason": "", "tap": "", "footer": "Upgrading is free of Energy · fills Energy to the new max", "max": next == null}
	if next == null:
		out.reason = "Highest level for now"
		return out
	out.title = "Homestead Lv%d → Lv%d" % [level, int(next.level)]
	var unlocks: Array = next.get("unlocks", [])
	if unlocks.has("fence"): out.look = "Lv%d look · Full fence" % int(next.level)
	for m in next.get("materials", []):
		out.tiles.append({"id": str(m.id), "name": str(m.name), "have": int(m.have), "need": int(m.need), "icon": str(m.id)})
	out.tiles.append({"id": "coins", "name": "Coins", "have": int(next.coins.have), "need": int(next.coins.need), "icon": "coin"})
	out.tiles.append({"id": "skills", "name": "Skills", "have": int(next.skills.have), "need": int(next.skills.need), "icon": "star"})
	var energy: Dictionary = view.get("energy", {})
	out.changes.append({"icon": "energy", "text": "Max Energy %d · Meals %d a day" % [int(next.energy), int(next.meals)],
		"note": "now %d" % int(energy.get("max", 0))})
	var board_now := int(h.get("unlocks", {}).get("board_slots", 2))
	for u in unlocks:
		match str(u):
			"spice_rack": out.changes.append({"icon": "kitchen", "text": "Spice Rack", "note": "seasonings off your bag"})
			"clay_bank": out.changes.append({"icon": "clay", "text": "Clay Bank", "note": "Clay next to the Reed Bank"})
			"warming_cabinet": out.changes.append({"icon": "kitchen", "text": "Warming Cabinet", "note": "keeps 6 dishes by the stove"})
			"bag_upgrade_1":
				out.changes.append({"icon": "bag", "text": "Bag Upgrade I for sale · 150 coins",
					"note": "Bag %d → %d" % [int(view.get("bag", {}).get("capacity", 25)), int(view.get("bag", {}).get("capacity", 25)) + 5]})
			"board_slot_3": out.changes.append({"icon": "board", "text": "Stall Board · 3rd slot", "note": "now %d" % board_now})
	# The first gap in tile order goes on the button (LOCK-10). Away from home (HOME-1 from the Profile farm card,
	# §10.6.2) the button is grey with `At home`, as the Energy card's Cook / Rest tiles (q(6)); a tap says
	# `Upgrade at home · Going home is free` and sends nothing. Going home is the place chip / the map, not a button
	# here (k(1), q(83); 不知火舞 and 李白, 2026-10-09).
	if not at_home:
		out.reason = "At home"
		out.tap = "Upgrade at home · Going home is free"
		return out
	for t in out.tiles:
		if int(t.have) >= int(t.need): continue
		var short := int(t.need) - int(t.have)
		match str(t.id):
			"coins": out.reason = "Need %d more coins" % short
			"skills": out.reason = "Skills total %d needed · now %d" % [int(t.need), int(t.have)]
			_: out.reason = "Need %d more %s" % [short, str(t.name)]
		break
	return out

## The one-line source for a HOME-1 tile (NeedSource, guide only): coins, skill levels, or a material's places, the
## same line as the workbench (P0MaterialLogic.material_source, Li Bai q(65)).
static func home_source(view: Dictionary, id: String) -> Dictionary:
	var sk: Dictionary = view.get("skills", {})
	match id:
		"coins": return {"text": "Coins · sell crops and fish at the Homestead Stall", "go": "stall"}
		"skills":
			return {"text": "Farming %d + Fishing %d · Cooking not counted" % [int(sk.get("farming", {}).get("level", 1)),
				int(sk.get("fishing", {}).get("level", 1))], "go": ""}
	return need_source(view, id)

## PLAQUE-READ (Figma 1510:97745): the Upgrade Plaque's lines, one per Homestead upgrade, "Lv2" / "Oct 5" in the
## device's time zone. Empty until the first upgrade (the plaque appears in the yard with its first line).
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

static func plaque_lines(view: Dictionary, bias_min := 999999) -> Array:
	var bias := bias_min if bias_min != 999999 else int(Time.get_time_zone_from_system().get("bias", 0))
	var out: Array = []
	for p in view.get("homestead", {}).get("plaque", []):
		var d := Time.get_datetime_dict_from_unix_time(int(float(p.get("at", 0)) / 1000.0) + bias * 60)
		out.append({"label": "Lv%d" % int(p.get("level", 1)), "value": "%s %d" % [MONTHS[int(d.month) - 1], int(d.day)]})
	return out

## HOME-2 MomentBanner (Figma 482:154 / 1228:108620) from the server's homestead event: level disc, title,
## what changed (Energy refilled to the new max) and one line of consequences.
static func home_moment(view: Dictionary, ev: Dictionary) -> Dictionary:
	var level := int(ev.get("level", 1))
	var max_e := int(view.get("energy", {}).get("max", 0))
	var lines: Array = []
	for u in ev.get("unlocks", []):
		match str(u):
			"spice_rack": lines.append("Spice Rack · seasonings off your bag")
			"clay_bank": lines.append("Clay Bank opened")   # gathering spot (SGODOT-231, q(45))
			"warming_cabinet": lines.append("Warming Cabinet")
			"bag_upgrade_1": lines.append("Bag Upgrade I for sale · 150 coins")
	return {"level": str(level), "title": "Homestead Lv %d" % level, "subtitle": "Max Energy %d · Energy full" % max_e,
		"detail": "\n".join(lines)}
