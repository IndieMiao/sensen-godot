class_name P0Logic
extends RefCounted
## P0 client rules that only read the server view (plan v2 §10.2.2 main action states,
## §10.3.3 quick bar fill, §3.7 countdown format, §9.5.3 Today line; M2: §6.6.1 Cast states,
## §7.2.4 heat ring, §7.17.1 eating). Pure and static: tested headless.

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const P0FishWorld := preload("res://modules/p0/p0_fish_world.gd")   # a pond's fish, time of day and weather (SGODOT-283)
const P0Trap := preload("res://modules/p0/p0_trap.gd")   # Fish Trap (SGODOT-283)
const ICON_DIR := "res://assets/p0/icons/%s.svg"
const PinReason := preload("res://modules/p0/p0_pin_reason.gd")   # the taken requests and the pins they mark (q(104))
const GearLogic := preload("res://modules/p0/p0_gear_logic.gd")

static var _content: Dictionary = {}
## Problems found merging the content fragments (tests read it; the server refuses to start on the same ones).
static var content_errors: Array = []

const CONTENT_DIR := "res://assets/p0/content/"

## The bundled content table (shared with the server) for display-only lookups the view doesn't carry, with the
## content fragments merged in (SGODOT-275, see merge_content).
static func content() -> Dictionary:
	if _content.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/p0_content.json"))
		if parsed is Dictionary:
			_content = parsed
			content_errors = merge_content_dir(_content, CONTENT_DIR)
	return _content

## Content fragments (SGODOT-275, 亚瑟's cross-city plan §6), as the server's mergeContentDir: assets/p0/content/
## <line>_<topic>.json, shaped like the main table, merged in name order. Objects merge key by key, arrays of objects
## with an `id` append by id; a key, an id or a scalar already there is not applied and comes back as an error naming
## the file and the path. Keys starting with `_` are skipped. Returns the errors (empty when all merged).
static func merge_content_dir(base: Dictionary, dir: String) -> Array:
	var errors: Array = []
	if not DirAccess.dir_exists_absolute(dir): return errors
	var files: Array = []
	for f in DirAccess.get_files_at(dir):   # an exported pack may list a file under its .remap name
		var name := str(f).trim_suffix(".remap")
		if name.ends_with(".json") and not files.has(name): files.append(name)
	files.sort()
	for f in files:
		var add = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if add is Dictionary: errors.append_array(merge_content(base, add, f))
		else: errors.append("p0 content: %s: not a JSON object" % f)
	return errors

static func merge_content(base: Dictionary, add: Dictionary, file: String, at := "") -> Array:
	var errors: Array = []
	for k in add:
		if at == "" and str(k).begins_with("_"): continue
		var where := str(k) if at == "" else "%s.%s" % [at, k]
		if not base.has(k):
			base[k] = add[k]
			continue
		var have = base[k]
		var v = add[k]
		if have is Dictionary and v is Dictionary:
			errors.append_array(merge_content(have, v, file, where))
		elif have is Array and v is Array and _all_with_id(have) and _all_with_id(v):
			var ids := {}
			for e in have: ids[str(e.id)] = true
			for e in v:
				if ids.has(str(e.id)): errors.append("p0 content: %s: %s already has id %s" % [file, where, e.id])
				else:
					ids[str(e.id)] = true
					have.append(e)
		else:
			errors.append("p0 content: %s: %s is already set (fragments add, they never change an entry)" % [file, where])
	return errors

static func _all_with_id(list: Array) -> bool:
	return list.all(func(e): return e is Dictionary and e.has("id"))

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

## The float of a gate fish breaking free again, after its card (§6.1.1), the refund as it came back with no + (q(50)):
## a level gate in the card's word and whose level it is — `Too strong · Fishing Lv8 · 3 Energy back`, `Too strong ·
## Fishing Lv4 · Energy refunded (8 left today)` (q(278); it read `Got away · Lv8`; 不知火舞 386 1c3d0416: no +) —
## a rod gate as before, `Got away · Reed Rod · 3 Energy back`.
static func break_free_float(view: Dictionary, ev: Dictionary) -> String:
	var refund := refund_line(view, ev).trim_prefix("+")
	if ev.has("need_level"): return "Too strong · Fishing Lv%d · %s" % [int(ev.need_level), refund]
	var rod := rod_for(view, int(ev.get("rarity", 2)))
	return "Got away · %s · %s" % [str(rod.name) if not rod.is_empty() else "rod too light", refund]

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
## q(58): crop names that keep their form in the plural, or take another; every plural reads it (Today, the chip, the
## waiting line, harvest amounts; 李白 q(98): `Lettuces ready in` was written where Lettuce stays Lettuce). The materials
## are mass nouns, the same in the plural: `7 Clay`, `Need 3 more Timber` — not `7 Claies` (不知火舞 on the Stall Board,
## 奕星 11-04); Reeds and Grapes are plurals already (李白 on b1: `harvest 9 grapeses`).
const PLURALS := {"Lettuce": "Lettuce", "Chamomile": "Chamomile", "Corn": "Corn", "Chili": "Chilies",
	"Cress": "Cress", "Pea Shoots": "Pea Shoots", "Baby Spinach": "Baby Spinach", "Bok Choy": "Bok Choy", "Grapes": "Grapes",
	"Timber": "Timber", "Stone": "Stone", "Clay": "Clay", "Flax": "Flax", "Hardwood": "Hardwood", "Coal": "Coal",
	"Rock Salt": "Rock Salt", "Copper Ore": "Copper Ore", "Iron Ore": "Iron Ore", "Quartz": "Quartz"}

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
		spec.lead = ("Home Lv%d %s" % [lv, str(gate.get("after", ""))]).strip_edges()
		var left := maxi(0, lv - have)
		spec.need = {name = "Home", have = have, need = lv, icon = icon("home"),
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

## The Fishing level a fish request still waits for (q(104)): of the fish it takes — the named ones, else every P0 fish
## of its rarity that a pond or river holds — the lowest level, when the player is below it; 0 once one can be landed
## (the server's landable, #185). A taken request then marks no pond and its button reads `Fishing Lv4 needed`.
## Every fish id a pond can give (SGODOT-283): the view's list for that pond (fishing.places[id].fish), else worked out
## from its template and the home city (P0FishWorld). place "" = all the ponds the content knows.
static func pond_fish(view: Dictionary, place: String) -> Array:
	var c := content()
	var places: Dictionary = c.get("fishing", {}).get("places", {})
	var seen := {}
	for id in places:
		if place != "" and id != place: continue
		var v: Dictionary = view.get("fishing", {}).get("places", {}).get(id, {})
		var ids: Array = v.get("fish", []) if v.has("fish") else P0FishWorld.ever_fish(
			str(c.get("fishing", {}).get("sites", {}).get(str(places[id].get("site", "pond")), {}).get("template", "Pond")),
			P0Clusters.cluster_of_region(P0City.region())).map(func(f): return str(f.id))
		for f in ids: seen[str(f)] = true
	if seen.is_empty() and place.find("~") > 0:   # a generated pond of another city (SGODOT-280): its site there
		var g: Dictionary = load("res://modules/p0/p0_city_places.gd").pond(place)
		if not g.is_empty():
			var v: Dictionary = view.get("fishing", {}).get("places", {}).get(place, {})
			var ids: Array = v.get("fish", []) if v.has("fish") else P0FishWorld.ever_fish(
				str(c.get("fishing", {}).get("sites", {}).get(str(g.get("site", "pond")), {}).get("template", "Pond")),
				str(g.cluster)).map(func(f): return str(f.id))
			for f in ids: seen[str(f)] = true
	return seen.keys()

static func fish_level_short(view: Dictionary, items: Array, rarity) -> int:
	return int(fish_level_gate(view, items, rarity).get("level", 0))

## The fish that holds such a request back (fish_level_short): {id, level} of the lowest-level fish it takes, when the
## player's Fishing is below it, else {}. Today's request row opens its gate card (the Fish-dex silhouette's, q(104)).
static func fish_level_gate(view: Dictionary, items: Array, rarity) -> Dictionary:
	var c := content()
	var held := {}   # every fish some pond gives (SGODOT-283: by habitat and the city's regional fish, not a list per site)
	for id in pond_fish(view, ""): held[str(id)] = true
	var lowest := {}
	for f in c.get("fish", []):
		var id := str(f.get("id", ""))
		if not held.has(id): continue
		if not items.is_empty():
			if not items.has(id): continue
		elif rarity == null or int(f.get("rarity", 0)) != int(rarity): continue
		var lv := int(f.get("level", 1))
		if lowest.is_empty() or lv < int(lowest.level): lowest = {"id": id, "level": lv}
	if lowest.is_empty() or int(lowest.level) <= int(view.get("skills", {}).get("fishing", {}).get("level", 1)): return {}
	return lowest

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
			# Main ingredients before seasonings, as §4.8.7 reads them (Carrot and Herb, Potato and Chamomile). P1 (李白
			# on #214, §5.2.3 / §4.5): the regional crops are one item, `Regional seeds`, at their level (Lv5 opens buying
			# them; which one sells at home depends on the city); a perennial is named by what is bought and planted,
			# its sapling (`Apple Sapling`, `Grapevine Cutting`).
			var crops: Array = content().get("crops", []).filter(func(c): return int(c.get("gate", 1)) == level)
			var regional := false
			for main in [true, false]:
				for c in crops:
					if bool(c.get("regional", false)):
						regional = true
						continue
					if (str(c.get("ingr", ["F"])[0]) == "F") != main: continue
					out.append(str(c.get("seed_name", c.name)) if c.get("perennial", null) != null else str(c.name))
			if regional: out.append(REGIONAL_SEEDS)
		"fishing":
			# This season's waters only (the fishing sites the content has: Pond, River and Coast from P1), and the
			# regional fish as one item, `Regional fish`, at the level the first of them can be landed (李白 on #214, §14
			# minutes 28–30: `Next Lv3 · Reed Rod, Regional fish`): which two a city has depends on the city.
			var sites: Array = content().get("fishing", {}).get("sites", {}).keys()
			var fished := func(f): return (f.get("where", ["pond"]) as Array).any(func(w): return sites.has(w))
			for f in content().get("fish", []):
				if fished.call(f) and not bool(f.get("regional", false)) and int(f.get("level", 1)) == level:
					out.append(item_name(view, str(f.id)))
			if level == regional_fish_level(): out.append(REGIONAL_FISH)
	return out

const REGIONAL_FISH := "Regional fish"
const REGIONAL_SEEDS := "Regional seeds"

## The level `Regional fish` is written at: the first level past Lv1 that opens a regional fish (Lv3: Grass Carp and
## Arctic Char; §14's `Next Lv3 · Reed Rod, Regional fish`). Lv1 ones (Tilapia, Smelt) are there from the start, which
## no milestone row names. 0 with no such fish in the content.
static func regional_fish_level() -> int:
	var lowest := 0
	for f in content().get("fish", []):
		var lv := int(f.get("level", 1))
		if bool(f.get("regional", false)) and lv >= 2: lowest = lv if lowest == 0 else mini(lowest, lv)
	return lowest

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
	if n == 1: return w
	for k in PLURALS:
		if str(k).to_lower() == w: return str(PLURALS[k]).to_lower()
	if w.ends_with("sh") or w.ends_with("ch") or w.ends_with("s") or w.ends_with("x") or w.ends_with("o"): return w + "es"
	if w.ends_with("y") and not (w.length() > 1 and w[-2] in "aeiou"): return w.substr(0, w.length() - 1) + "ies"
	return w + "s"

## Items that share an existing icon until they get their own (SGODOT-228 content).
## SGODOT-282: P1 pages without an icon of their own yet borrow the nearest P0 dish by main ingredient and style
## (never the field sprout, int6 C7). Remove each line once 安其拉's icon lands (the first six landed: 283 / 0d45e4a1).
const DISH_STANDIN := {
	"dish_cabbage_stew": "dish_veggie_plate", "dish_travel_biscuits": "dish_carrot_cake", "dish_tilapia_wraps": "dish_pan_fried_fish",
	"dish_crispy_smelt": "dish_salt_grilled_fish", "dish_cucumber_salad": "dish_radish_salad", "dish_apple_tea": "dish_fruit_tea",
	"dish_corn_cake": "dish_carrot_cake", "dish_grass_carp_soup": "dish_fish_soup", "dish_char_chowder": "dish_fisher_stew",
	"dish_catfish_stew": "dish_fisher_stew", "dish_sea_bass_salt": "dish_salt_grilled_fish", "dish_chili_snakehead": "dish_herb_grilled_fish",
	"dish_grilled_pike": "dish_herb_baked_perch", "dish_pineapple_barra": "dish_pan_fried_fish", "dish_strawberry_tart": "dish_carrot_cake",
	"dish_melon_platter": "dish_fruit_tea", "dish_orchard_tea": "dish_fruit_tea", "dish_steamed_sturgeon": "dish_smoked_trout",
	"dish_eel_skewers": "dish_mullet_skewers", "dish_herb_salmon": "dish_herb_baked_perch", "dish_pineapple_fish": "dish_bass_tomato_stew",
	"dish_sweet_potato_cakes": "dish_carrot_cake", "dish_pumpkin_chowder": "dish_fisher_stew", "dish_beet_fish_soup": "dish_fish_soup"}

const ICON_ALIAS := {"fert_compost": "compost", "facility_compost_bin": "compost", "tool_row_hoe": "hoe", "bag_upgrade_1": "bag", "bag_upgrade_2": "bag", "bag_upgrade_3": "bag", "bag_upgrade_4": "bag", "postcard_san_francisco": "postcard", "postcard_shanghai": "postcard", "wild_herb": "crop_herb", "drink_hot_tea": "dish_fruit_tea", "drink_coffee": "dish_fruit_tea"}

## A line as the player will read it: P0's table's Chinese under 中文 (Localization.use_p0), else the English as it is
## (#649 第二批 ⑨: what a width is measured on, never the English a label is given).
static func shown(text: String) -> String: return String(TranslationServer.translate(text))

## `text`'s width in a UiKit style's font and size (the theme the panels draw with): the cuts that keep a line to a
## width measure with it.
static func text_width(text: String, style: StringName = UiTokens.STYLE_C11_B) -> float:
	var th := UiKit.theme()
	return th.get_font(&"font", style).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, th.get_font_size(&"font_size", style)).x

static func icon(id: String) -> Texture2D:
	id = base_id(id)   # a dish's quality (`dish_x@good`) has the dish's own art; the stars say the quality (286 5d27bd93)
	if id.begins_with("weapon_") or id.begins_with("potion_"):
		if ResourceLoader.exists(ICON_DIR % id): return load(ICON_DIR % id)
		id = "heart" if id.begins_with("potion_") else "sword_wooden" if id == "weapon_wooden_sword" else "sword"
	if id.begins_with("postcard_"): id = "postcard"   # every city's postcard (SGODOT-296) has the one postcard art for now
	var path := ICON_DIR % str(ICON_ALIAS.get(id, DISH_STANDIN.get(id, id)))
	if ResourceLoader.exists(path): return load(path)
	# a fish without its own art yet (P1's twelve, SGODOT-283) shows the fish silhouette, not the sprout (不知火舞 69310899)
	return load(ICON_DIR % ("fish_sil" if id.begins_with("fish_") else "field"))

## "m:ss" under an hour, "1h 12m" from one hour (state-icons rule: durations, never clock times). For the timers that
## tick in front of the player (q(97) ①): the stove and cooking (`Cooking 0:42`, `The stove is busy · 0:22 left`),
## the badge capsules (`0:22`) and Energy regen (`+1 in 2:41`, `+2 in 7:41`). A duration inside a sentence is span().
static func duration(ms: float) -> String:
	var total := maxi(0, ceili(ms / 1000.0))
	if total < 3600:
		return "%d:%02d" % [total / 60, total % 60]
	var minutes := total / 60
	return "%dh %dm" % [minutes / 60, minutes % 60]

## A duration inside a sentence (q(97) ②): whole minutes rounded up, at least `1m`, then `42m` under an hour, `2h` on
## the hour, `9h 12m` otherwise — never `60m`. `Available again in`, `… to go`, `Ready in`, `Resets in`,
## `Meals reset in`, `Next request in`, `Expires in`; the Inbox's `42m left` is the same (P0Inbox.left_text).
static func span(ms: float) -> String:
	var minutes := maxi(1, ceili(ms / 60000.0))
	if minutes < 60: return "%dm" % minutes
	if minutes % 60 == 0: return "%dh" % (minutes / 60)
	return "%dh %dm" % [minutes / 60, minutes % 60]

## The main key's second line for a growing plot (≤ 80 px, q(44); 不知火舞 on 241): `Ready in 48h` with one unit, just
## `19h 58m` with two (`Ready in 19h 58m` is about 101 px and ran off the round key). q(249): last 5:00 ticks as Today.
static func key_ready(ms: float) -> String:
	var t := _crop_countdown(ms)
	return t if t.contains(" ") else "Ready in " + t

static func crop(view: Dictionary, crop_id: String) -> Dictionary:
	for c in view.get("crops", []):
		if str(c.get("id", "")) == crop_id: return c
	var fast := fast_crop(view, crop_id)
	if str(fast.get("id", "")) == crop_id and not fast.is_empty(): return fast
	var q := quick_seed(view, crop_id)
	return q if not q.is_empty() and str(q.get("id", "")) == crop_id else {}

static func crop_for_seed(view: Dictionary, seed_id: String) -> Dictionary:
	for c in view.get("crops", []):
		if str(c.get("seed", "")) == seed_id: return c
	var fast := fast_crop(view, seed_id)
	if str(fast.get("seed", "")) == seed_id and not fast.is_empty(): return fast
	var q := quick_seed(view, seed_id)
	return q if not q.is_empty() and str(q.get("seed", "")) == seed_id else {}

## A teaching seed (q(217): Quick Radish Seeds) by its plot crop or its seed — view.quick_seeds' {id, seed, energy, grow_s,
## harvest}; {} for any other id. Never one of view.crops: lists of crops (unlocks, Next, requests) never show it.
static func quick_seed(view: Dictionary, id: String) -> Dictionary:
	if id == "": return {}
	for q in view.get("quick_seeds", []):
		if str(q.get("id", "")) == id or str(q.get("seed", "")) == id: return q
	return {}

## Separate from normal crops and the guide-only Quick Radish: no recipe / request / notification membership.
static func fast_crop(view: Dictionary, id: String) -> Dictionary:
	if id == "": return {}
	for c in view.get("fast_crops", []):
		if str(c.get("id", "")) == id or str(c.get("seed", "")) == id: return c
	return {}

## What a plot's crop is harvested as: a Quick Radish is a Radish (q(217)); any other crop itself.
static func harvest_of(view: Dictionary, crop_id: String) -> String:
	var q := quick_seed(view, crop_id)
	return str(q.get("harvest", crop_id)) if not q.is_empty() and str(q.get("id", "")) == crop_id else crop_id

## q(247)/q(249): Today and the Growing key share this rule for every crop, including orchard trees.
static func ripe_in(_view: Dictionary, _crop_id: String, ms: float) -> String:
	return _crop_countdown(ms)

static func _crop_countdown(ms: float) -> String:
	return duration(ms) if ms <= 300_000.0 else span(ms)

## Gift Clues (Fishing Lv7, q(167)): the residents met who like this dish, in content order — view.gift_clues
## {dish: [{resident, verdict}]}, null before Lv7. Names, [] when none.
static func liked_by(view: Dictionary, item_id: String) -> Array:
	var residents: Dictionary = content().get("residents", {})
	return clue_residents(view, item_id).map(func(r): return str(residents.get(r, {}).get("name", r)))

## The ids of the residents met who love or like this dish (view.gift_clues; [] before Fishing Lv7).
static func clue_residents(view: Dictionary, item_id: String) -> Array:
	var clues = view.get("gift_clues", null)
	if not clues is Dictionary: return []
	return ((clues as Dictionary).get(item_id, []) as Array).map(func(c): return str(c.get("resident", "")))

## A resident who likes by rarity alone (`Fine+` Hana, `Rare+` Mira and Tomo), not by a dish's style.
static func likes_by_rarity(resident: String) -> bool:
	return str(content().get("residents", {}).get(resident, {}).get("likes", "")).ends_with("+")

## The bag cell's ♥: a resident met likes this dish's style (Pip's Dessert, Old Kai's Grilled). A liking by rarity alone
## (Hana's `Fine+`) marks no cell — any Fine dish would wear it — only the card's `Liked by …` and the gift drawer's mark
## (不知火舞 on 283, q(167)).
static func style_liked(view: Dictionary, item_id: String) -> bool:
	return clue_residents(view, item_id).any(func(r): return not likes_by_rarity(r))

## The gift drawer's green mark: this dish is one this resident loves or likes (in their gift_clues), whatever it adds —
## a Perfect dish they do not care for gives +2 on white (不知火舞 on 283, q(167)).
static func gift_hit(view: Dictionary, resident: String, item_id: String) -> bool:
	return clue_residents(view, item_id).has(resident)

## The dish card's line: `Liked by Hana · Old Kai`, at most two names, then ` · +1 more` (302 b308ee14); "" when none.
static func liked_by_line(view: Dictionary, item_id: String) -> String:
	var names := liked_by(view, item_id)
	if names.is_empty(): return ""
	var line := "Liked by " + " · ".join(PackedStringArray(names.slice(0, 2)))
	return line + (" · +%d more" % (names.size() - 2) if names.size() > 2 else "")

static func item_name(view: Dictionary, id: String) -> String:
	var names: Dictionary = view.get("names", {})
	if not names.has(id) and id.begins_with("weapon_"): return str(GearLogic.weapon(id).get("name", id))
	if not names.has(id) and id.begins_with("potion_"): return str(GearLogic.potion(id).get("name", id))
	var fast := fast_crop(view, id)
	if not names.has(id) and not fast.is_empty(): return str(fast.get("seed_name" if id == str(fast.get("seed")) else "name", id))
	if not names.has(id) and P0Decor.is_decor(id): return P0Decor.name_of(id)   # Decorate's pieces (SGODOT-284)
	if not names.has(id) and id.begins_with("postcard_gn-"):   # a city's postcard the view has not named (SGODOT-296)
		var cl := P0Clusters.get_cluster(id.trim_prefix("postcard_"))
		if not cl.is_empty(): return "%s Postcard" % str(cl.get("name", ""))
	if names.has(id) or base_id(id) == id: return str(names.get(id, id))
	# A dish stack with its quality (`dish_x@good`, §7.2.5): the dish's name, never the raw id; the quality shows as stars
	# beside it (the item card's state line, dish_label) — 李元芳 on 286 5d27bd93.
	return str(names.get(base_id(id), item(view, id).get("name", base_id(id))))

## An item id without a dish's quality suffix: `dish_x@good` → `dish_x` (other ids as they are).
static func base_id(id: String) -> String:
	var at := id.find("@")
	return id.left(at) if at > 0 else id

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
## walking direction first (dir +1 / −1 along the row), up to sow_count, along the garden grid's row (P0Garden).
static func row_plots(view: Dictionary, front: Dictionary, columns: int, dir: int) -> Array:
	var out: Array = []
	if front.is_empty() or str(front.get("state", "")) != "tilled": return out
	out.append(front)
	var most := sow_count(view)
	var by_id := {}
	for p in view.get("plots", []): by_id[int(p.get("id", -1))] = p
	# Along the row on the garden grid (content.garden.plots: ids go in opening order, not along the rows — SGODOT-355
	# b1), up to a bed the view does not have. `columns` is P0's row length, kept for callers.
	var at := P0Garden.grid_of(int(front.get("id", -1)))
	for side in [dir if dir != 0 else 1, -(dir if dir != 0 else 1)]:
		var g := at + Vector2i(side, 0)
		var next := P0Garden.id_of(P0Garden.PLOT_ORIGIN + g * 2)
		while out.size() < most and next >= 0 and by_id.has(next) and str(by_id[next].get("state", "")) == "tilled":
			out.append(by_id[next])
			g += Vector2i(side, 0)
			next = P0Garden.id_of(P0Garden.PLOT_ORIGIN + g * 2)
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
	var tree := bool(plot.get("tree", false))
	# P1 trees (q(118), 不知火舞 on 241): Orchard Feed feeds a picked tree, regrowing, not fed yet; any other tree goes by
	# its state (ripe: Pick, its first ripening or fed: Growing — 哪吒 on #252); no tree underfoot greys the key with
	# `No tree here`.
	if seed_id == "fert_orchard" and not tree:
		return {"icon": "compost", "verb": "Fertilize", "sub": "No tree here", "enabled": false, "amber": false, "cmd": {}, "need": 0,
			"toast": "No tree here"}
	if seed_id == "fert_orchard" and str(plot.get("state", "")) == "growing" and int(plot.get("picks", 0)) > 0 and not plot.get("fert", false):
		return {"icon": "compost", "verb": "Fertilize", "sub": "Free", "enabled": true, "amber": false,
			"cmd": {"type": "fertilize", "plot": plot_id, "item": seed_id}, "need": 0}
	if tree: return _tree_action(view, plot)
	if bool(crop_for_seed(view, seed_id).get("perennial", false)) and str(plot.get("state", "")) in ["tilled", "wild"]:
		if plot.get("greenhouse", false):   # q(118) ②: no trees under glass (李白: `Outside only`, ≤ 80 px)
			return {"icon": "sow", "verb": "Plant", "sub": "Outside only", "enabled": false, "amber": false, "cmd": {}, "need": 0,
				"toast": "No trees in the greenhouse"}
		return _plant_action(view, plot_id, seed_id)
	if seed_id.begins_with("fert_"):
		var ripe := str(plot.get("state", "")) == "ready"
		# a Quick Radish takes no Compost (q(217) ①): the key goes by the plot's state, no word about it
		var quick := not quick_seed(view, str(plot.get("crop", ""))).is_empty() or not fast_crop(view, str(plot.get("crop", ""))).is_empty()
		if str(plot.get("state", "")) in ["sown", "growing"] and not ripe and not plot.get("fert", false) and not quick:
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
			# SGODOT-355 b1 (v4 2.5): annuals stand on at most the level's Plots; a full field greys the key with the count
			var room := fields_room(view)
			if room == 0: return fields_full_action(view)
			# Row Hoe: as many of the row's plots as the seeds allow, then trimmed to what Energy covers (§5.3) and to the
			# Plots left.
			var plots: Array = row if row.size() > 1 and int(row[0].get("id", -1)) == plot_id else [plot]
			var n := clampi(mini(plots.size(), bag_count(view, seed_id)), 1, plots.size())
			if room > 0: n = mini(n, room)
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
			var sub := key_ready(float(plot.get("ready_in", 0)))
			return {"icon": "clock", "verb": "Growing", "sub": sub, "enabled": false, "amber": false, "cmd": {}, "need": 0}
		"ready":
			# Harvest All (Farming Lv9, q(118) ④): the ripe annuals of the garden row underfoot, this one first.
			var whole := harvest_row(view, plot)
			if whole.size() > 1:
				return {"icon": "hoe", "verb": "Harvest ×%d" % whole.size(), "sub": "Free", "enabled": true, "amber": false,
					"cmd": {"type": "harvest", "plot": plot_id, "plots": whole}, "need": 0}
			return {"icon": "hoe", "verb": "Harvest", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "harvest", "plot": plot_id}, "need": 0}
	return a

## Plots an annual may still take (view.garden.fields: the level's Plots less the annuals standing, SGODOT-355 b1); -1
## when the view does not say.
static func fields_room(view: Dictionary) -> int:
	var f = view.get("garden", {}).get("fields", null)
	if not (f is Dictionary): return -1
	return maxi(0, int(f.get("cap", 0)) - int(f.get("used", 0)))

## The Sow key on a full field (不知火舞 on the grid, as q(130)'s capped facilities): the grey key only counts, `Plots 8/8`;
## the tap's Info toast says what the next Homestead level adds, `Plots 8/8 · Homestead Lv2 adds 2`; at the top both
## only count, `Plots 41/41`.
static func fields_full_action(view: Dictionary) -> Dictionary:
	var f: Dictionary = view.get("garden", {}).get("fields", {})
	var label := "Plots %d/%d" % [int(f.get("used", 0)), int(f.get("cap", 0))]
	var toast := label
	var level := int(view.get("homestead", {}).get("level", 1))
	var ladder: Array = content().get("homestead", {}).get("plots", [])
	var now := -1
	var next := -1
	for step in ladder:
		if int(step[0]) <= level: now = int(step[1])
		elif int(step[0]) == level + 1: next = int(step[1])
	if now >= 0 and next > now: toast += " · Home Lv%d adds %d" % [level + 1, next - now]
	return {"icon": "sow", "verb": "Sow", "sub": label, "enabled": false, "amber": false, "cmd": {}, "need": 0, "toast": toast,
		"toast_break": true}   # too long for a line, it breaks at its « · » (不知火舞 on #624)

## Harvest All's row (q(118) ④): from Farming Lv9 (content farming.conveniences), the plot in front and every other ripe
## annual on its garden row (trees are picked one by one); [] below that level.
static func harvest_row(view: Dictionary, front: Dictionary) -> Array:
	var at = content().get("farming", {}).get("conveniences", {}).get("harvest_all", null)
	if at == null or int(view.get("skills", {}).get("farming", {}).get("level", 1)) < int(at): return []
	var id := int(front.get("id", -1))
	var row_y := P0Garden.grid_of(id).y
	var out := [id]
	for p in view.get("plots", []):
		var pid := int(p.get("id", -1))
		if pid == id or pid < 0 or pid >= P0Garden.plot_count(view) or P0Garden.grid_of(pid).y != row_y: continue
		if str(p.get("state", "")) == "ready" and not bool(p.get("tree", false)) and p.get("facility", null) == null: out.append(pid)
	# Near to far from the plot in front (q(123)): a bag that fills stops the server at the first that does not fit, so
	# what the player gets is what is nearest; equally near on both sides, the left one first.
	var x := P0Garden.grid_of(id).x
	var rest := out.slice(1)
	rest.sort_custom(func(a, b):
		var da := absi(P0Garden.grid_of(a).x - x)
		var db := absi(P0Garden.grid_of(b).x - x)
		return da < db or (da == db and P0Garden.grid_of(a).x < P0Garden.grid_of(b).x))
	return [id] + rest

## A sapling at an empty plot, tilled or wild (q(118) ①): `Plant` / `6 Energy`, one tree a press (never repeated while
## held, `once`); the orchard full greys it with `Orchard 5/5` and the whole reason as the toast (q(44) 80 px).
static func _plant_action(view: Dictionary, plot_id: int, seed_id: String) -> Dictionary:
	if bag_count(view, seed_id) <= 0:
		return {"icon": "sow", "verb": "Sow", "sub": "Pick a seed", "enabled": false, "amber": false, "cmd": {}, "need": 0}
	var cost := int(crop_for_seed(view, seed_id).get("energy", 6))
	var o: Dictionary = view.get("orchard", {})
	var used := int(o.get("used", 0))
	var cap := int(o.get("cap", 0))
	if used >= cap:
		var nxt = o.get("homestead_next", null)
		return {"icon": "sow", "verb": "Plant", "sub": "Orchard %d/%d" % [used, cap], "enabled": false, "amber": false, "cmd": {},
			"need": 0, "toast": "Orchard %d/%d" % [used, cap] + (" · Home Lv%d adds 1" % int(nxt) if nxt != null else "")}
	if int(view.get("energy", {}).get("value", 0)) < cost:
		return {"icon": "sow", "verb": "Plant", "sub": "Need %d Energy" % cost, "enabled": true, "amber": true,
			"cmd": {"type": "energy_card"}, "need": cost}
	return {"icon": "sow", "verb": "Plant", "sub": "%d Energy" % cost, "enabled": true, "amber": false, "once": true,
		"cmd": {"type": "sow", "plot": plot_id, "seed": seed_id}, "need": cost}

## A tree in front: ripe, `Pick` / `2 Energy` (a tree per press, §5.6); growing, how long until it is.
static func _tree_action(view: Dictionary, plot: Dictionary) -> Dictionary:
	var plot_id := int(plot.get("id", -1))
	if str(plot.get("state", "")) != "ready":
		return {"icon": "clock", "verb": "Growing", "sub": key_ready(float(plot.get("ready_in", 0))), "enabled": false, "amber": false, "cmd": {}, "need": 0}
	var cost := 2
	for c in view.get("crops", []): if str(c.get("id", "")) == str(plot.get("crop", "")): cost = int(c.get("pick_energy", 2))
	if int(view.get("energy", {}).get("value", 0)) < cost:
		return {"icon": "hoe", "verb": "Pick", "sub": "Need %d Energy" % cost, "enabled": true, "amber": true,
			"cmd": {"type": "energy_card"}, "need": cost}
	return {"icon": "hoe", "verb": "Pick", "sub": "%d Energy" % cost, "enabled": true, "amber": false,
		"cmd": {"type": "harvest", "plot": plot_id}, "need": cost}

## Five candidates for the current action — Farming: seeds, Fishing: bait — kept order: previously shown → most plentiful (§10.3.3).
## Pinned ids always stay on the bar, also at 0 left (LOCK-05, §10.3.3 归零); ids the player dragged off the bar
## (`removed`) are not refilled until pinned again (§10.3.4 "从栏上移除，物品仍在背包").
## What each action's quick bar holds (§10.3.2): Farming seeds and fertiliser, Fishing bait. Anything in the pool
## stays where it was put or pinned; the bar fills its free end only with the first family (seeds / bait).
const BAR_POOL := {"farm": ["seed_", "fert_"], "fish": ["bait_", "trap_"], "combat": ["potion_"]}

## The action whose bar takes this item ("farm" / "fish"), or "" when no bar does.
static func bar_action_of(id: String) -> String:
	if id.begins_with("potion_") and not GearLogic.potion_actions_enabled: return ""
	for mode in BAR_POOL:
		for prefix in BAR_POOL[mode]:
			if id.begins_with(prefix): return mode
	return ""

static func quick_bar(view: Dictionary, previous: Array, mode := "farm", pinned: Array = [], removed: Array = []) -> Array:
	if mode == "combat" and not GearLogic.potion_actions_enabled: return []
	var prefix := "potion_" if mode == "combat" else "bait_" if mode == "fish" else "seed_"
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
	# the free end fills with the first family, and on Fishing with the Fish Trap too (the pond's design shows it, §6.8)
	var fill := func(id): return str(id).begins_with(prefix) or (mode == "fish" and str(id).begins_with("trap_"))
	var rest: Array = counts.keys().filter(func(id): return fill.call(id) and not bar.has(id) and not removed.has(id))
	# a teaching seed first (q(217) ②: Quick Radish Seeds ×2 on the first slot, then Radish ×20, Lettuce ×10)
	var teach := func(id): return 0 if quick_seed(view, str(id)).is_empty() else 1
	rest.sort_custom(func(a, b):
		if teach.call(a) != teach.call(b): return teach.call(a) > teach.call(b)
		return counts[a] > counts[b] if counts[a] != counts[b] else str(a) < str(b))
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
		if st != "growing" and not fast_crop(view, str(p.get("crop", ""))).is_empty(): continue
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
	if fish > 0: return "Cook with %d fish" % fish
	if best_crop != "": return "%s ready in %s" % [plural(item_name(view, best_crop)), ripe_in(view, best_crop, best_ms)]
	if any_sown: return "Water what you sowed"
	return "Sow your first plot"

static func plural(name: String) -> String:
	if PLURALS.has(name): return str(PLURALS[name])
	if name.ends_with("ss") or name.ends_with("sh") or name.ends_with("ch") or name.ends_with("x") or name.ends_with("o"): return name + "es"
	if name.ends_with("s"): return name
	# a consonant's y only (Strawberry → Strawberries); a vowel's takes an s (Day → Days), as crop_plural
	if name.ends_with("y") and not (name.length() > 1 and name[-2].to_lower() in "aeiou"): return name.substr(0, name.length() - 1) + "ies"
	return name + "s"

## A name that is the same in the plural (Lettuce, Chamomile, Corn): `when lettuce is ready`, not `are` (q(98)).
static func uncountable(name: String) -> bool: return str(PLURALS.get(name, "")) == name

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
		"wait": "Wait · Full in %s" % span(full_ms) if next_in != null else "Wait · Full now",
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
		"buffs": buff_rings(view),
		"today_dots": today_dots(rows),
		"today_key": today_chip_key(rows),
	}
	if ctx.has("place"): out["place"] = ctx.place
	return out

## The priest's buffs (q(300); 不知火舞's spec v1.1): fish first, then farm — their names, their HUD icons.
const BUFF_ORDER := ["fish", "farm"]
const BUFF_NAMES := {"fish": "Twin Catch", "farm": "Swift Growth"}
const BUFF_ICONS := {"fish": "fish", "farm": "field"}

## The HUD's buff rings from view.buffs [{id, left ms}] (projected each frame): fish left of farm, each its icon, the
## time left `18:20` and the share of the full time (content buffs.minutes) its arc shows. None on: [].
static func buff_rings(view: Dictionary) -> Array:
	var full := float(content().get("buffs", {}).get("minutes", 20)) * 60000.0
	var left := buffs_left(view)
	var out: Array = []
	for id in BUFF_ORDER:
		if not left.has(id): continue
		out.append({"id": id, "icon": icon(BUFF_ICONS[id]), "remaining": duration(left[id]),
			"progress": clampf(left[id] / full, 0.0, 1.0)})
	return out

## view.buffs as {id: ms left}, the ones still on.
static func buffs_left(view: Dictionary) -> Dictionary:
	var out := {}
	for b in view.get("buffs", []):
		if b is Dictionary and float(b.get("left", 0)) > 0.0: out[str(b.get("id", ""))] = float(b.left)
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
	if id.begins_with("seed_"): return {"text": "%s · Home Stall" % label, "go": "stall"}
	if id.begins_with("crop_"): return {"text": "%s · Grow it on your plots" % label, "go": "plots"}
	if id.begins_with("fish_"): return {"text": "%s · Ponds on the map" % label, "go": ""}
	if id.begins_with("dish_"): return {"text": "%s · Cook it at the stove" % label, "go": "stove"}
	var material := P0MaterialLogic.material_source(view, id)   # spots and mine floors (SGODOT-231 B2-06)
	if not material.is_empty(): return material
	return {"text": label, "go": ""}

## A view and everything in it made read-only (SGODOT-260 Q3: P0Session.view, whose parts current() shares).
static func freeze(x) -> void:
	if x is Dictionary:
		if x.is_read_only(): return
		for k in x: freeze(x[k])
		x.make_read_only()
	elif x is Array:
		if x.is_read_only(): return
		for i in x: freeze(i)
		x.make_read_only()

## Locally advance a view by elapsed ms (energy ticks and crop timers) between server refreshes.
## SGODOT-260 Q3: only the parts that age are copied (energy, plots, the guide row, the stoves, the cast and traps, the
## inbox parcels, Rest, the residents' next requests, the keepers' and boards' refills); everything else is the server
## view's own, shared — callers read the result, never write into it.
static func project(view: Dictionary, elapsed_ms: float) -> Dictionary:
	if elapsed_ms <= 0: return view
	var v := view.duplicate(false)
	# the server's clock moves on too: a Day Pass's countdown on the chip and its running out (q(257) ⑤, SGODOT-367)
	if v.has("now"): v["now"] = float(v.now) + elapsed_ms
	var owned: Array = []   # the dictionaries this projection copied (each copied once, then written in place)
	# d[key] as a shallow copy of its own, the server view's dictionary left as it was
	var own := func(d: Dictionary, key: String) -> Dictionary:
		var sub: Dictionary = d[key]
		if owned.any(func(o): return is_same(o, sub)): return sub
		sub = sub.duplicate()
		owned.append(sub)
		d[key] = sub
		return sub
	var e = v.get("energy", null)
	var mine = v.get("mine", null)
	var mine_at = mine.get("at", null) if mine is Dictionary else null
	if mine_at is Dictionary and mine_at.get("potion_ready_in", null) != null:
		own.call(own.call(v, "mine"), "at")["potion_ready_in"] = maxf(0.0, float(mine_at.potion_ready_in) - elapsed_ms)
	var next_in = e.get("next_in", null) if e is Dictionary else null
	if next_in != null:
		e = own.call(v, "energy")
		var remaining := float(next_in) - elapsed_ms
		var regen := float(e.get("regen_ms", 240000))
		var value := int(e.get("value", 0))
		var maxv := int(e.get("max", 200))
		while remaining <= 0 and value < maxv:
			value += 1
			remaining += regen
		e["value"] = value
		e["next_in"] = null if value >= maxv else remaining
	if v.get("plots") is Array:
		var plots: Array = []
		for p in v.plots:
			if p is Dictionary and str(p.get("state", "")) == "growing" and p.get("ready_in", null) != null:
				p = p.duplicate()
				p["ready_in"] = maxf(0.0, float(p["ready_in"]) - elapsed_ms)
				if float(p["ready_in"]) <= 0.0: p["state"] = "ready"
			plots.append(p)
		v["plots"] = plots
	# the priest's buffs (q(300), SGODOT-445: view.buffs[].left, ms): counted down, gone once out — 亚瑟's HUD rings and
	# `… has worn off` read it (a buff gone from the array is a buff ended)
	if v.get("buffs") is Array and not (v.buffs as Array).is_empty():
		var bs: Array = []
		for b in v.buffs:
			var ms := float(b.get("left", 0)) - elapsed_ms
			if ms > 0.0: bs.append({"id": str(b.get("id", "")), "left": ms})
		v["buffs"] = bs
	# a city gathering spot's cooldown (v4q(4): view.gather.city_ready, ms left): counted down, gone once ready
	var g = v.get("gather", null)
	if g is Dictionary and g.get("city_ready") is Dictionary and not (g.city_ready as Dictionary).is_empty():
		var left := {}
		for id in g.city_ready:
			var ms := float(g.city_ready[id]) - elapsed_ms
			if ms > 0.0: left[id] = ms
		own.call(v, "gather")["city_ready"] = left
	# a pond's points (409 / 410: view.gather.pond.points[].ready_in, ms left) counted down the same way
	var gp = v.get("gather", {}).get("pond", null) if v.get("gather") is Dictionary else null
	if gp is Dictionary and gp.get("points") is Array and (gp.points as Array).any(func(p): return float(p.get("ready_in", 0)) > 0.0):
		var pts: Array = []
		for p in gp.points:
			var q: Dictionary = (p as Dictionary).duplicate()
			q["ready_in"] = maxf(0.0, float(q.get("ready_in", 0)) - elapsed_ms)
			pts.append(q)
		var pond_g: Dictionary = (own.call(v, "gather")["pond"] as Dictionary).duplicate()
		pond_g["points"] = pts
		own.call(v, "gather")["pond"] = pond_g
	var guide = v.get("guide", null)
	var row = guide.get("row", null) if guide is Dictionary else null
	if row is Dictionary and row.get("countdown") is String and row.get("ready_in") != null:
		row = own.call(own.call(v, "guide"), "row")
		row.ready_in = maxf(0.0, float(row.ready_in) - elapsed_ms)
	if v.get("cooking") is Dictionary:
		var cooking: Dictionary = own.call(v, "cooking")
		# Every stove ages (SGODOT-282: stoves 2 and 3 are in cooking.stoves; stove 1 is the same pot as cooking.stove,
		# which may be the same dictionary in the server view, so each pot is copied and aged once and stays shared).
		var copies: Array = []   # [the view's pot, its aged copy], by reference (a dictionary key would match by content)
		var age := func(st) -> Variant:
			if not (st is Dictionary): return st
			for pair in copies:
				if is_same(pair[0], st): return pair[1]
			var c: Dictionary = st.duplicate()
			if c.has("ms") or c.has("ready_in"):
				c["elapsed"] = float(c.get("elapsed", 0)) + elapsed_ms
				c["ready_in"] = maxf(0.0, float(c.get("ready_in", 0)) - elapsed_ms)
			copies.append([st, c])
			return c
		if cooking.get("stove") is Dictionary: cooking["stove"] = age.call(cooking.stove)
		if cooking.get("stoves") is Array: cooking["stoves"] = (cooking.stoves as Array).map(age)
	if v.get("fishing") is Dictionary:
		var fishing: Dictionary = v.fishing
		if fishing.get("cast") is Dictionary:
			var cast: Dictionary = own.call(own.call(v, "fishing"), "cast")
			cast["bite_in"] = maxf(0.0, float(cast.get("bite_in", 0)) - elapsed_ms)
		# a trap's next fish counts down (its name strip `· next in 5h 12m`, q(109) ⑦); the next read brings the fish itself
		var trap = fishing.get("trap", null)
		if trap is Dictionary and trap.get("traps") is Array:
			var traps: Array = []
			for t in trap.traps:
				if t is Dictionary and t.get("next_in", null) != null:
					t = t.duplicate()
					t["next_in"] = maxf(0.0, float(t.next_in) - elapsed_ms)
				traps.append(t)
			own.call(own.call(v, "fishing"), "trap")["traps"] = traps
	var inbox = v.get("inbox", null)
	if inbox is Dictionary and inbox.get("parcels") is Array:
		var parcels: Array = []
		for parcel in inbox.parcels:
			if parcel is Dictionary:
				parcel = parcel.duplicate()
				parcel["left"] = maxf(0.0, float(parcel.get("left", 0)) - elapsed_ms)
			parcels.append(parcel)
		own.call(v, "inbox")["parcels"] = parcels
	# SGODOT-377: Rest's day reset, a resident's next request, the keepers' and boards' refills count down between reads
	# too (the 30 s refresh moved them a minute at a time; the open bench card not at all)
	var rest = v.get("rest", null)
	if rest is Dictionary and rest.get("resets_in", null) != null:
		var r: Dictionary = own.call(v, "rest")
		r["resets_in"] = maxf(0.0, float(r.resets_in) - elapsed_ms)
	var residents = v.get("residents", null)
	if residents is Dictionary and residents.values().any(func(r): return r is Dictionary and r.get("next_in", null) != null):
		var rs: Dictionary = own.call(v, "residents")
		for id in rs.keys():
			if rs[id] is Dictionary and rs[id].get("next_in", null) != null:
				var r: Dictionary = rs[id].duplicate()
				r["next_in"] = maxf(0.0, float(r.next_in) - elapsed_ms)
				rs[id] = r
	var keepers = v.get("keepers", null)
	if keepers is Dictionary:
		for k in ["post", "market"]:
			if keepers.get(k) is Dictionary and keepers[k].get("refill_in", null) != null:
				var kd: Dictionary = own.call(own.call(v, "keepers"), k)
				kd["refill_in"] = maxf(0.0, float(kd.refill_in) - elapsed_ms)
	var boards = v.get("boards", null)
	if boards is Dictionary:
		for b in boards:
			var slots = boards[b].get("slots", null) if boards[b] is Dictionary else null
			if not (slots is Array and slots.any(func(sl): return sl is Dictionary and sl.get("refill_in", null) != null)): continue
			var aged: Array = []
			for sl in slots:
				if sl is Dictionary and sl.get("refill_in", null) != null:
					sl = sl.duplicate()
					sl["refill_in"] = maxf(0.0, float(sl.refill_in) - elapsed_ms)
				aged.append(sl)
			own.call(own.call(v, "boards"), b)["slots"] = aged
	return v

## SGODOT-377: ms until the first countdown in this server view that a read changes runs out — a resident's next request
## opens, a keeper's or board's slot refills, the 04:00 day reset (Rest's `Used today` turns back; 周瑜 on #602) — or -1
## for none.
static func next_expiry(view: Dictionary) -> float:
	var ins: Array = []
	if view.get("rest") is Dictionary and view.rest.get("resets_in", null) != null: ins.append(float(view.rest.resets_in))
	var of := func(key: String) -> Array: return view[key].values() if view.get(key) is Dictionary else []
	for r in of.call("residents"):
		if r is Dictionary and r.get("next_in", null) != null: ins.append(float(r.next_in))
	for k in of.call("keepers"):
		if k is Dictionary and k.get("refill_in", null) != null: ins.append(float(k.refill_in))
	for b in of.call("boards"):
		for sl in (b.slots if b is Dictionary and b.get("slots") is Array else []):
			if sl is Dictionary and sl.get("refill_in", null) != null: ins.append(float(sl.refill_in))
	ins = ins.filter(func(ms): return ms > 0.0)
	return ins.min() if not ins.is_empty() else -1.0

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
	var expiry := ("Expires in " + span(left)) if left > 0.0 else ""
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
		return {title = "No dish this time", sub = "Ingredients back (%s)" % refunds_left(int(ev.get("trial_left", 0))), eat = false}
	return {title = "Mystery Dish", sub = "Hmm… not a dish. Try another mix.", eat = true}

## The Newcomer Blessing's count on a failed pot's card: `8 refunds left today`, `1 refund left today` (Joey on 296:
## `8 left today` did not say what was left).
static func refunds_left(n: int) -> String:
	return "%d refund%s left today" % [n, "" if n == 1 else "s"]

static func dish_label(view: Dictionary, id: String) -> String:
	var info := item(view, id)
	var q := int(info.get("quality", 0))
	return str(info.get("name", item_name(view, id))) + ("" if q == 0 else " " + "★".repeat(q))

## Main action at the pond (§6.6.1): Cast pre-pays 5; creel full / short energy say why.
static func fish_action(view: Dictionary, bait: String, site := "pond", place := "") -> Dictionary:
	# The Fish Trap selected on the bar (SGODOT-283): the key sets it here instead of casting
	if bait == P0Trap.ID: return P0Trap.set_key(view, place if place != "" else str(view.get("fishing", {}).get("place", "")))
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
static func creel_line(view: Dictionary, flying: Array = []) -> String:
	var fish := 0
	var qty := {}
	for s in view.get("bag", {}).get("slots", []):
		if str(s.get("id", "")).begins_with("fish_"):
			fish += int(s.get("qty", 0))
			qty[str(s.id)] = int(qty.get(str(s.id), 0)) + int(s.get("qty", 0))
	var free := int(view.get("bag", {}).get("free", 0))
	# A trap's fish still flying in (TRAP-COLLECT-2: the badge counts each one as it lands): not in it yet, and a kind
	# whose whole stack came with them leaves its slot free until then.
	for f in flying:
		fish -= int(f.get("count", 0))
		if int(qty.get(str(f.get("id", "")), 0)) <= int(f.get("count", 0)): free += 1
	return "Creel %d · %d free" % [fish, free]

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
	if left <= 0: return {"text": "Full belly · Meals reset in " + span(float(m.get("resets_in", 0))), "enabled": true, "confirm": "", "gain": 0}
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
	var k := heat_k(heat)
	return tap_ms >= at + gold * spin / k - tolerance and tap_ms <= at + (gold + width) * spin / k + tolerance

## The ring drifts too (q(288), SGODOT-419): `drift` degrees a second against the needle (anticlockwise; none without it).
## The needle then meets the gold k = 1 + drift ÷ the needle's speed laps a lap, so the gold's window in time is its
## share ÷ k — the server's heatHits the same way (周瑜).
static func heat_k(heat: Dictionary) -> float:
	return maxf(0.05, 1.0 + float(heat.get("drift", 0.0)) * float(heat.get("spin", 1600)) / 360000.0)

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
			if not names.is_empty(): return "New seeds at the Home Stall: " + ", ".join(names)
		"cooking":
			if level == 4: return "A 3rd pot slot · three-family dishes"
	return ""

## Cooking conveniences by key (§7.2.2 / §4.6.3): the names the level banner and SKILL-1 use.
## P1 adds Lv7–10's (the glossary, 李元芳 on 286: SKILL-1 showed their ids); Lv10's title Chef is in TITLE_NAMES.
const CONVENIENCE_NAMES := {"cook_again": "Cook Again", "clue_double": "Double Clue", "hearty_mishap": "Hearty Mishap",
	"steady_hand_1": "Steady Hand I", "queue_two": "Queue ×2", "quick_fire": "Quick Fire",
	"steady_hand_2": "Steady Hand II", "fast_mastery": "Fast Mastery", "batch_cook": "Batch Cook", "provisions_plus": "Bigger Provisions",
	"chefs_touch": "Chef's Touch", "lucky_double": "Lucky Double"}   # Lv10's title Chef: TITLE_NAMES
const LEVEL_TIP := "Levels unlock gear, fish and seeds. Basics never lock."
## Levels that change the day say so on the banner's Tip instead of the next level (§4.8.3, q(69)); the nine of them
## (Farming 6 / 7 / 8, Fishing 4 / 5 / 6 / 8 / 9, Cooking 4) as q(176) words them, from §4.6's "the day's difference".
const DAY_CHANGES := {"cooking:4": "Today changes: 3-ingredient dishes", "farming:6": "Today changes: no more watering",
	"farming:7": "Today changes: fruit every two days", "farming:8": "Today changes: grow any climate's crops",
	"fishing:4": "Today changes: River is your water now", "fishing:5": "Today changes: traps fish for you",
	"fishing:6": "Today changes: Coast is your water now", "fishing:8": "Today changes: two traps to check",
	"fishing:9": "Today changes: eels bite at night"}
## The day-changing level's action (q(59) §1.6): [label, banner action id].
const DAY_ACTIONS := {"farming:6": ["Show Workbench", "show_workbench"]}

## The MomentBanner for a skill level-up (§4.8.3 / §4.8.6; ev = the server's {skill, level, energy, gifts}). Fields as
## the accepted FARM-LV2 (1368:91797), content and timing as §4.8.6 (不知火舞 233, 10-08):
##   subtitle  `New for you · Potato, Chamomile, Compost` (what the level opens, q(69)); Fishing `Fine fish now stay on the hook`;
##             Cooking Lv4 `Three-ingredient dishes now possible`
##   rewards   pills: the level-up gift's items (`+3 Worm Bait` · `+3 Wild Herb`; SKILL-3 482:65); a level without a gift
##             has no reward row. Skill level-ups give no Energy (q(101)); a server from before q(101) still pays it and
##             says how much, and that shows as `+50 Energy` first — never a `+0 Energy`
##   detail    recipe cards only (`New recipe: Herb Grilled Fish`), else nothing
##   tip       the next level (`Next Lv4 · Tomato, Chili, Row Hoe · 150 XP`, its new things this season); the account's
##             first level-up teaches instead, a level that changes the day says `Today changes: …` (q(69))
##   time      the account's first ≤ 3 s, later ones 1.5 s; the first Fishing level-up (Lv2) ≤ 3 s too, with `Use bait`
##             when its bait is in the bag, whichever level-up of the account it is (q(215) A: a guided account's first
##             is Cooking Lv2, which teaches; its Fishing Lv2 keeps Use bait and Tips the next level)
static func level_banner(view: Dictionary, ev: Dictionary, first := false) -> Dictionary:
	var skill := str(ev.get("skill", "farming"))
	var lv := int(ev.get("level", 2))
	var title := "%s Lv%d" % [skill.capitalize(), lv]
	var rewards: Array = []
	if int(ev.get("energy", 0)) > 0:   # only from a server before q(101): what it really paid, so the bar never moves unsaid
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
	# Fishing's banner reads like the other two, `New for you · ` and its milestone row (q(178) ⑥); a fish's one time only
	# (`(night)`) is the Tip's Today changes there (q(176)). Lv2, the first session's, keeps `Fine fish now stay on the hook`
	# (the break-free card it answers); a level with nothing new keeps its fish line.
	if skill == "fishing":
		if lv == 2 or opens.is_empty(): subtitle = fishing_unlock_line(view, lv)
		else: subtitle = "New for you · " + ", ".join(opens.map(func(o): return _without_time(str(o))))
	if skill == "cooking" and lv == 4:
		title += " · 3rd slot"
		subtitle = "Three-ingredient dishes now possible"
	var detail := ("New recipe: " + ", ".join(recipes)) if not recipes.is_empty() else ""
	# Tip: the next level, except the account's first (the teaching line) and a level that changes the day (q(69)).
	var tip := keep_units(LEVEL_TIP if first else str(DAY_CHANGES.get("%s:%d" % [skill, lv], next_level_line(view, skill, lv))))
	var first_fishing := skill == "fishing" and lv == 2
	var use_bait := first_fishing and bait != "" and bag_count(view, bait) > 0
	var action := "Use bait" if use_bait else ""
	var action_id := "use_bait" if use_bait else ""
	# Farming Lv6 changes the day with an action (q(59) §1.6): the full banner up to 3 s and `Show Workbench` (the
	# camera only, LOCK-08). Cooking Lv4's banner keeps its accepted 1.5 s (q(69)).
	var day := DAY_ACTIONS.has("%s:%d" % [skill, lv])
	if not first and day:
		var a: Array = DAY_ACTIONS["%s:%d" % [skill, lv]]
		action = str(a[0])
		action_id = str(a[1])
	return {kind = "level_up", level = str(lv), title = title, subtitle = subtitle, rewards = rewards, detail = detail,
		tip = tip, action = action, action_id = action_id, seconds = 3.0 if first or day or first_fishing else 1.5}

static var _unit_space: RegEx
## A figure stays with the word after it when the banner's Tip wraps (不知火舞 on SGODOT-345, 8b936c42: `· 140 XP` never
## leaves `XP` alone on the next line; every skill): the space after a number becomes a no-break space. The words are
## unchanged; the toasts do the same in ToastLayer.keep_units (#485).
static func keep_units(text: String) -> String:
	if _unit_space == null:
		_unit_space = RegEx.new()
		_unit_space.compile("(\\d) (?=\\p{L})")
	return _unit_space.sub(text, "$1\u00a0", true)

## What a skill level opens this season: Farming — the crops of that gate (main ingredients first), then other stall
## goods and tools (Compost, Row Hoe); Fishing — the fish of that level; Cooking — the conveniences of that level.
const FARMING_CONVENIENCE_NAMES := {"harvest_all": "Harvest All", "seed_saver": "Seed Saver"}   # §4.6.1 / glossary (Plot Marks, Sow Again … come later)
## Fishing's conveniences (content fishing.conveniences; §4.6.2, q(178) ③ / ⑤, f090617f): the 3-day Forecast, Gift Clues,
## the pond card's Biting now (q(168)), Quick Recast and the Bigger Creel (15 a slot at Lv10, fishing.creel).
const FISHING_CONVENIENCE_NAMES := {"three_day_forecast": "3-day Forecast", "gift_clue_highlight": "Gift Clues", "biting_now": "Biting now",
	"quick_recast": "Quick Recast", "creel_15": "Bigger Creel"}
## A fish that bites at one time only, as the milestone row names it (q(178) ④: `River Eel (night)`, the Lv9 night fishing).
const ONLY_AT_ROW := {"night_only": "night", "dawn_dusk_only": "dawn & dusk"}

## A milestone row's item without its `(night)` (the banner leaves the time to its Tip, q(178) ⑥).
static func _without_time(item: String) -> String:
	for w in ONLY_AT_ROW.values(): item = item.trim_suffix(" (%s)" % w)
	return item

## Titles by key (§4.6 Lv10, appendix glossary; SGODOT-275): the one place their names live (奕星). A skill's title is
## a `title_*` key among its conveniences in content, at the level it comes (farming.conveniences.title_master_gardener
## 10); the level's line names it here, and its card follows the level banner (title_card).
## Homestead Lv10's and the Explorer medals' titles (§11.9.2) are named here too, for the Titles drawer (q(180), P0Titles).
const TITLE_NAMES := {"title_master_gardener": "Master Gardener", "title_master_angler": "Master Angler", "title_chef": "Chef",
	"title_homestead_master": "Home Master", "title_wanderer": "Wanderer", "title_globetrotter": "Globetrotter"}

## A level's line for its title, after the level's other unlocks: `Chef title`, `Master Gardener title` (不知火舞 on 282).
static func title_line(id: String) -> String: return "%s title" % str(TITLE_NAMES.get(id, id))

## The titles a skill level brings: content <skill>.conveniences keys `title_*` at that level.
static func level_titles(skill: String, level: int) -> Array:
	var out: Array = []
	var conv: Dictionary = content().get(skill, {}).get("conveniences", {})
	for k in conv:
		if str(k).begins_with("title_") and int(conv[k]) == level: out.append(str(k))
	return out

## A title's card (RewardMoment Milestone through P0Ui.show_title; §4.8.3 Lv10): the title, the level it came with
## (`Farming Lv10`), `New title`, the skill's icon. Queued after that level's banner.
static func title_card(skill: String, level: int, id: String) -> Dictionary:
	return {event = str(TITLE_NAMES.get(id, id)), item_name = "%s Lv%d" % [skill.capitalize(), level], strip = "New title",
		icon = icon(str(GATE_SKILL_ICONS.get(skill, "star")))}

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
			# a level that allows another of a facility (content facilities.kinds.<kind>.cap_by_farming, §4.6.1: the Greenhouse
			# 1 at Lv8, 2 at Lv10): `2nd Greenhouse`, as q(178)'s `2nd Fish Trap` (q(179)); the first comes with its blueprint below
			for kind in content().get("facilities", {}).get("kinds", {}).values():
				for at in kind.get("cap_by_farming", []):
					if int(at[0]) == level and int(at[1]) >= 2: out.append("%s %s" % [P0KitchenLogic.ordinal(int(at[1])), str(kind.get("name", ""))])
			# P1 conveniences (content farming.conveniences: Seed Saver at Lv10, §4.6.1)
			var conv: Dictionary = content().get("farming", {}).get("conveniences", {})
			for k in conv:
				if int(conv[k]) == level and not str(k).begins_with("title_"): out.append(str(FARMING_CONVENIENCE_NAMES.get(k, k)))
			# P1 facilities a level opens at the workbench (q(59) §1.6: `New for you · Cucumber, Sprinkler`)
			for r in content().get("workbench", {}).get("recipes", []):
				var gate: Array = r.get("gate", [])
				if str(r.get("to", "")) == "field" and gate.size() == 2 and str(gate[0]) == "farming" and int(gate[1]) == level:
					out.append(str(content().get("facilities", {}).get("kinds", {}).get(str(r.get("facility", "")), {}).get("name", r.get("id", ""))))
		"fishing":
			# The fish, then gear and goods the level opens (Worm Bait at Lv2, the Reed Rod at Lv3), then `Regional fish`
			# last, as §14 writes it (`Next Lv3 · Reed Rod, Regional fish`).
			out = skill_unlocks(view, "fishing", level)
			for f in content().get("fish", []):   # a fish of one time only says when (q(178) ④: `River Eel (night)`)
				var only := str(ONLY_AT_ROW.get(str(f.get("time", "")), "")) if f.get("time", null) is String else ""
				var at := out.find(item_name(view, str(f.id)))
				if only != "" and int(f.get("level", 1)) == level and at >= 0: out[at] = "%s (%s)" % [out[at], only]
			var regional := out.has(REGIONAL_FISH)
			out.erase(REGIONAL_FISH)
			for o in view.get("stall", {}).get("buy", []):
				if str(o.get("skill", "")) == "fishing" and int(o.get("gate", 1)) == level: out.append(item_name(view, str(o.get("id", ""))))
			# and the Tackle Shop's goods the stall does not sell (the Spinner Lure at Lv5, SGODOT-283)
			var goods: Dictionary = content().get("goods", {})
			for id in content().get("tackle", {}).get("buy", []):
				var g: Dictionary = goods.get(str(id), {})
				var name := item_name(view, str(id))
				if str(g.get("skill", "")) == "fishing" and int(g.get("gate", 1)) == level and not out.has(name): out.append(name)
			for r in content().get("fishing", {}).get("rods", []):
				if int(r.get("level", 1)) == level and int(r.get("price", 0)) > 0: out.append(str(r.get("name", "")))
			# a level that adds a trap (content fishing.trap.slots, §4.6.2: Lv8 the 2nd, Lv10 the 3rd; the first is the
			# Fish Trap itself, bought at Lv5 above): `2nd Fish Trap` (q(178) ①; 286 e89ae800: Lv8 and Lv10 had no row)
			for at in content().get("fishing", {}).get("trap", {}).get("slots", []):
				if int(at[0]) == level and int(at[1]) >= 2:
					out.append("%s %s" % [P0KitchenLogic.ordinal(int(at[1])), str(goods.get("trap_fish", {}).get("name", "Fish Trap"))])
			if regional: out.append(REGIONAL_FISH)
			# then the level's conveniences, as Farming and Cooking list theirs (q(178) ③: `Lv8 · 2nd Fish Trap, Biting now`)
			var conv: Dictionary = content().get("fishing", {}).get("conveniences", {})
			for k in conv:   # a title key is the title's (q(179): its own `… title` line), not a convenience (刘邦 on #366)
				if int(conv[k]) == level and not str(k).begins_with("title_"): out.append(str(FISHING_CONVENIENCE_NAMES.get(k, k)))
		"cooking":
			var conv: Dictionary = content().get("cooking", {}).get("conveniences", {})
			for k in conv:
				if int(conv[k]) == level and not str(k).begins_with("title_"): out.append(str(CONVENIENCE_NAMES.get(k, k)))
			if level == 4: out.push_front("third ingredient slot")   # SKILL-1 482:167
	# the level's title last, in any track: `Lucky Double, Chef title`, `Seed Saver, Master Gardener title` (不知火舞 on 282)
	for t in level_titles(skill, level): out.append(title_line(t))
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

## The keys of the rows that light the Today icon's red dot (q(107)): something to do now — a request to hand in, a
## harvest, a dish at the stove, a new recipe or slot, the first session's Sow / Catch / Deliver / Cook. Never a
## countdown, an info row, a request still short, `Cook with N fish` or `Water N sown plots` (their
## `dot` is ""), nor a row ticked done or short of Energy. A key is the kind and its object, e.g. `deliver:<request>`.
static func today_dots(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var key := str(r.get("dot", ""))
		if key != "" and not str(r.get("state", "")) in ["done", "short"] and not out.has(key): out.append(key)
	return out

## The row with the focus, the first still to do (q(58)), independent of its countdown text: the Today icon pulses when
## this changes (不知火舞 on 232), not when "Radishes ready in 3h 48m" ticks to 3h 47m.
static func today_chip_key(rows: Array) -> String:
	for r in rows:
		if bool(r.get("empty", false)): return ""   # nothing taken (TODAY_EMPTY): nothing to point at, no pulse
		if str(r.get("state", "")) != "done": return "%s|%s" % [str(r.get("go", "")), str(r.get("icon", ""))]
	return ""

## Today's 6 board requests are done (view.quotas.sys_requests): no board hand-in until the reset, so no board wears a ✓
## (q(270)) and its Today row reads Limit reached.
static func sys_requests_full(view: Dictionary) -> bool:
	var sys: Dictionary = view.get("quotas", {}).get("sys_requests", {})
	return not sys.is_empty() and int(sys.get("used", 0)) >= int(sys.get("cap", 6))

## Today panel (§14.5): up to 3 lines — doable now first, then the shortest countdown, then the skill
## closest to its next level. Facts only; never "spend your Energy".
static func today_lines(view: Dictionary) -> Array:
	return today_rows(view).map(func(r): return r.line)

## Today (A 包反馈 1–3, the user 11-04; 不知火舞's spec, q(284)): tasks only — the guide's rows while it runs, then the
## requests the player has taken: hand-ins here, `Limit reached`, hand-ins in another city, then the ones still short,
## the newest taken first. No crops, stove, trap, skill, Homestead or vein rows (the field, the stove, the profile's farm
## line and the push say those). No cap: the panel shows 5 and scrolls (UiTodayPanel), requests stop at 25 (track_max).
## {line, icon, go, state, tail} rows (LOCK-06 TodayRow); `go` is a camera-only Show target ("" hides Show, LOCK-08).
## One row with nothing to do (TODAY_EMPTY, no button) when there is no task.
## `<key> · Requests 25/25` while the requests tracked are at track_max, else "" (spec ③, T4): the greyed key's reason on
## every way to take one, its own name kept ahead of it as `Fly · Need 30 Energy` (不知火舞 on #738) — a board's Track, a
## resident's Request and Accept, a keeper's Accept. Pip's own requests are not counted.
static func track_full_reason(view: Dictionary, key := "") -> String:
	var cap := int(content().get("requests", {}).get("track_max", 0))
	var n := PinReason.taken(view).size()   # the boards', the keepers' and the residents' taken, as the server's tracked()
	if cap <= 0 or n < cap: return ""
	var why := "Requests %d/%d" % [n, cap]
	return why if key == "" else "%s · %s" % [key, why]

## A track-full reason, with its key's name or without (track_full_reason).
static func is_track_full(reason: String) -> bool:
	var last := reason.get_slice(" · ", reason.get_slice_count(" · ") - 1)
	return last.begins_with("Requests ") and last.contains("/")

## The toast for a greyed key's tap: the track-full one says what to do (spec ③), any other its reason.
static func blocked_toast(reason: String) -> String:
	return TRACK_FULL_TOAST if is_track_full(reason) else reason

static func today_rows(view: Dictionary) -> Array:
	return _today_rows(view)

const TODAY_EMPTY := "No requests · Look for ! on the map"
## Red-dot keys of Pip's requests (spec ③ v3): seen once for good, not forgotten when the row leaves (P0Ui._today_unseen) —
## the Homestead one lights when it first comes (the guide over), not again at each level; a vein's once a vein.
const PIP_DOT := "pip:"
## A 包反馈 3 (spec ③): requests tracked at once stop at content requests.track_max (25); the key to take another greys with
## `Requests 25/25` as its reason (LOCK-10, the key's own name kept: Track / Request / Accept), a tap says this.
const TRACK_FULL_TOAST := "Finish or drop a request first"
const PIP_HOME_DOT := "pip:home"   # spec ①: untaken requests are found by the map's `!` (q(104))

static func _today_rows(view: Dictionary) -> Array:
	# the guide's rows while it runs; on an account it never ran, only its tutorial request (Pond Catch) — not Cook it, a
	# new recipe, the 3rd slot or the generic Sow row (spec ①: requests only)
	var lead := P0Guide.lead_rows(view)
	if not P0Guide.guide_on(view): lead = lead.filter(func(r): return bool(r.get("tutorial", false)))
	var rows: Array = lead.duplicate()
	var later: Array = []   # after Upgrade: hand-ins away, `Limit reached`
	var progress: Array = []
	# Taken requests (q(104), 李白 4ac4a4e7): the Stall Board's, the Market Board's, the keepers' and the residents'; untaken
	# ones stay on their boards. The first session shows its tutorial request alone (the guide's row).
	if not P0Guide.first_phase(view):
		var deliveries: Array = []
		var away: Array = []   # q(270) / 奕星's review ⑦: another city's hand-in can't be done here; it follows what can
		var capped_rows: Array = []   # spec ①: `Limit reached` follows every hand-in that can be done, before the short ones
		var sys: Dictionary = view.get("quotas", {}).get("sys_requests", {})
		var full := sys_requests_full(view)
		for r in PinReason.taken(view):
			# a board request once today's 6 are done (q(270), 不知火舞): `Dusk Haul · Limit reached · 9h 12m`, nothing to press;
			# another city's ends with its city as its other rows do (q(270) ⑥): `… · 9h 12m · Hayward`
			if bool(r.ready) and full and r.has("away") and not r.get("local", false):   # a keeper's local one is not of the 6 (q(272))
				var capped := "%s · Limit reached · %s" % [str(r.title), span(float(sys.get("resets_in", 0)))]
				if str(r.get("city", "")) != "": capped += " · " + str(r.city)
				capped_rows.append(_row(capped, "board", ""))
			elif bool(r.ready):
				var hand := _row("%s · %s" % [str(r.title), str(r.deliver)], "board", str(r.deliver_go), "deliver:" + str(r.id))
				# `Dusk Haul · Deliver at Shibuya Market Square · Tokyo`, `Pond Catch · Deliver to Wen · Shanghai`: broken before
				# the city as the progress rows are, nothing dropped — the place is where to go (q(276) ⑥ ⑦)
				var at := str(r.get("city", ""))
				if at != "" and str(hand.line).ends_with(" · " + at):
					hand.line = str(hand.line).trim_suffix(" · " + at)
					_city_row(hand, at)
				if r.get("local", false): hand.local_request = str(r.id)   # q(272): the row opens its card (Drop request ›)
				elif str(r.get("city", "")) != "": hand.board_request = str(r.id)   # q(270): the row opens its sheet (Drop)
				(away if bool(r.get("away", false)) else deliveries).append(hand)
			else:
				var row := _request_row(view, r)
				if r.get("local", false): row.local_request = str(r.id)
				elif str(r.get("city", "")) != "": row.board_request = str(r.id)
				row["_at"] = float(r.get("accepted_at", 0))
				row["_i"] = progress.size()   # board order breaks a tie (0: an older server or save knows no time)
				progress.append(row)
		rows = deliveries + rows
		later = away + capped_rows
	# Pip's requests (spec ③ v3, eval-B; taken by themselves, never on a board): the Homestead one — `Upgrade to
	# Homestead Lv{n}` after the hand-ins here (the first session's own Pond Catch is one of them), its gap row ahead of the
	# short ones — and the vein one after it
	var home_row := homestead_row(view)
	var pip: Array = []
	if not home_row.is_empty():
		var hr: Dictionary = home_row.row
		hr.home_request = true   # a tap off its Show opens HOME-1, this request's card
		if str(hr.dot).begins_with("homestead:") or bool(home_row.get("blocked", false)): rows.append(hr)   # q(303): no dot
		else:
			hr.dot = PIP_HOME_DOT   # lights once, the first time it is there (the guide just over), never each level
			pip.append(hr)
	var wing := wing_row(view)   # q(303) ⑨: a save past Lv8 whose wing waits on its cells, with the rows to do now
	if not wing.is_empty(): rows.append(wing)
	# Pip's order (q(284) spec ③ v3): First Dig, vein, then the Homestead gap; not sorted by request acceptance time.
	var vein := vein_row(view)
	if not vein.is_empty(): pip.push_front(vein)
	var dig := GearLogic.first_dig_row(view)
	if not dig.is_empty() and not P0Guide.guide_on(view): pip.push_front(dig)
	rows.append_array(later + pip)
	# the newest taken first (spec ①, over q(143)'s latest-on-the-third-row)
	progress.sort_custom(func(a, b): return float(a._at) > float(b._at) or float(a._at) == float(b._at) and int(a._i) < int(b._i))
	for row in progress:
		row.erase("_at")
		row.erase("_i")
	rows.append_array(progress)
	# q(215): even a ready ordinary delivery cannot displace the current guide goal. Other rows keep their order.
	if P0Guide.guide_on(view) and not lead.is_empty():
		rows = lead + rows.filter(func(r): return str(r.get("dot", "")) != str(lead[0].dot) and str(r.line) != str(lead[0].line))
	if rows.is_empty():
		var none := _row(TODAY_EMPTY, "board", "")
		none.empty = true   # grey, no button (UiTodayPanel)
		return [none]
	return P0Guide.focus_first(rows)

## v4q(9) ① (SGODOT-355; 不知火舞 / the user a+b, 11-02): `Ironvale Vein · Reach Floor 10`, Show to the nearest free iron
## vein (view.wild.near3_sites, the very one Pip's line and the server's nearestFreeVein name) — when the guide is over,
## Pip's First Dig is done (view.first_dig.done), nobody has reached its Floor 10 (view.mine.records: that vein's, and any
## other vein of the same main the client knows), one of the next three Homestead levels needs Iron Ore, and Homestead
## is below Lv7 (user a): so at Lv5 and Lv6. Then the same for quartz; one row at a time, iron first. Kept when the
## Homestead row points at that very mine too (不知火舞 on #738, 405 e8fb3ea4: Pip's request, it goes by its own ends
## only — v4q(9) ①'s dedupe retired with q(284)). Red dot `pip:vein:<id>`, once a mine; the vein's pin icon. Down
## that mine the row stays, without a button (P0Ui.show_label). {} for none.
const VEIN_MAINS := ["iron_ore", "quartz"]
const VEIN_UNTIL_LEVEL := 7
const VEIN_FLOOR := 10
static func vein_row(view: Dictionary) -> Dictionary:
	if P0Guide.guide_on(view): return {}
	var dig = view.get("first_dig", null)
	if not dig is Dictionary or not bool(dig.get("done", false)): return {}
	var lv := int(view.get("homestead", {}).get("level", 1))
	if lv >= VEIN_UNTIL_LEVEL: return {}
	var levels: Array = content().get("homestead", {}).get("levels", [])
	var sites = view.get("wild", {}).get("near3_sites", []) if view.get("wild", null) is Dictionary else []
	var records: Dictionary = view.get("mine", {}).get("records", {}) if view.get("mine", null) is Dictionary and view.mine.get("records") is Dictionary else {}
	for main in VEIN_MAINS:
		if not levels.any(func(l): return int(l.get("level", 0)) in range(lv + 1, lv + 4) \
				and (l.get("materials", []) as Array).any(func(m): return str(m[0]) == main)): continue
		var site := {}
		for x in sites if sites is Array else []:
			if x is Dictionary and str(x.get("type", "")) == "vein" and str(x.get("main", "")) == main:
				site = x
				break
		if site.is_empty() or _vein_reached(records, sites, main): continue
		var go := "mine:" + str(site.id)
		# down that mine (VG4 384:187745): the row stays, with no button (周瑜 on #711: not left to show_label)
		var down := str(view.get("mine", {}).get("at", {}).get("mine", "")) == str(site.id) if view.get("mine", null) is Dictionary and view.mine.get("at") is Dictionary else false
		# Pip's vein request (spec ③ v3, eval-B): `Ironvale Vein · Floor 4/10`, as `Pip's First Dig · Floor 1/3`
		var deepest := mini(VEIN_FLOOR, int(records.get(str(site.id), {}).get("deepest", 0)) if records.get(str(site.id)) is Dictionary else 0)
		var row := _row("%s · Floor %d/%d" % [str(site.get("name", "")), deepest, VEIN_FLOOR], "vein", "" if down else go, PIP_DOT + "vein:" + str(site.id))
		row.vein_request = str(site.id)
		return row
	return {}

## Whether a vein of this main has been gone down to Floor 10 (不知火舞: any iron vein's F10 ends the iron row, a new
## home's too): a record's own type / main (周瑜 #712: the server's, every mine the player has been down), else — a
## server before it — one of the free three's or a site the map has read (P0WildSites).
static func _vein_reached(records: Dictionary, near3: Variant, main: String) -> bool:
	for id in records:
		var rec: Dictionary = records[id]
		if int(rec.get("deepest", 0)) < VEIN_FLOOR: continue
		if rec.has("type"):
			if str(rec.get("type", "")) == "vein" and str(rec.get("main", "")) == main: return true
			continue
		var x := {}
		for n in near3 if near3 is Array else []:
			if n is Dictionary and str(n.get("id", "")) == str(id): x = n
		if x.is_empty():
			var wild = load("res://modules/p0/p0_wild_sites.gd")
			if wild.has_site(str(id)):
				var s: Dictionary = wild.site(str(id))
				x = {"type": str(s.get("type", "")), "main": s.get("mine", {}).get("main", null) if s.get("mine") is Dictionary else null}
		if str(x.get("type", "")) == "vein" and str(x.get("main", "")) == main: return true
	return false

## The order q(255) ① takes a Homestead level's materials in: Timber, Stone, Reeds, Copper Ore, Clay, Rock Salt.
const HOME_MATERIAL_ORDER := ["wood", "stone", "fiber", "copper_ore", "clay", "rock_salt"]

## v4q(1): after the guide, every level shows its first gap, skills -> travel -> materials -> coins.
## Upgrade follows deliveries and alone lights the red dot; other gaps retain q(255)'s Today ordering.
## {row, now}: `now` puts it with the rows to do now — a material its Show can gather at once, or Upgrade. {} for none.
static func homestead_row(view: Dictionary) -> Dictionary:
	if P0Guide.guide_on(view): return {}
	var h: Dictionary = view.get("homestead", {})
	var next = h.get("next", null)
	if not next is Dictionary: return {}
	if not next.get("skills", []) is Array: return {}   # incomplete/old view cannot establish the v4 gate.
	var lv := int(next.get("level", int(h.get("level", 1)) + 1))
	for key in ["farming", "fishing", "cooking"]:
		for skill in next.get("skills", []):
			if str(skill.get("skill", "")) == key and int(skill.get("have", 0)) < int(skill.get("need", 0)):
				return {row = _row("Home Lv%d · %s Lv%d needed" % [lv, key.capitalize(), int(skill.need)], str(GATE_SKILL_ICONS[key]), ""), now = false, skill = key}
	var travel = next.get("travel", null)
	if travel is Dictionary:
		for key in ["stamps", "climates"]:
			if not travel.get(key) is Dictionary: continue
			var short := maxi(0, int(travel[key].need) - int(travel[key].have))
			if short > 0:
				var noun := "stamp" if key == "stamps" else "climate"
				return {row = _row("Home Lv%d · %d %s%s to go" % [lv, short, noun, "" if short == 1 else "s"], "stamp" if key == "stamps" else "globe", "map"), now = false}
	var mats := {}
	for m in next.get("materials", []): mats[str(m.get("id", ""))] = m
	var ids: Array = HOME_MATERIAL_ORDER.filter(func(id): return mats.has(id))
	ids.append_array(mats.keys().filter(func(id): return not ids.has(id)))   # any other in the server's order
	for id in ids:
		var m: Dictionary = mats[id]
		var short := int(m.get("need", 0)) - int(m.get("have", 0))
		if short <= 0: continue
		var src := _home_material_go(view, str(id))
		return {"row": _row("Home Lv%d · %s %d to go" % [lv, str(m.get("name", item_name(view, str(id)))), short], "level_up", str(src.go)),
			"now": bool(src.now)}
	var coins: Dictionary = next.get("coins", {})
	var short_coins := int(coins.get("need", 0)) - int(coins.get("have", 0))
	if short_coins > 0:
		return {"row": _row("Home Lv%d · %d coins to go" % [lv, short_coins], "level_up", "stall"), "now": false}
	# q(303) ③: the wing's cells held, the last gap — to do now, Show into Decorate, no red dot
	if not P0Decor.next_blocked(view).is_empty():
		return {"row": _row("Home Lv%d · %s" % [lv, HOME_BLOCKED], "deco_planter", DECORATE_GO), "now": true, "blocked": true}
	return {"row": _row("Upgrade to Home Lv%d" % lv, "level_up", "sign", "homestead:%d" % lv), "now": true}

## Today's row while a save past Lv8 has the Kitchen Wing's cells held (q(303) ⑨, homestead.wing_blocked): `Kitchen
## Wing · Space taken` (the Master Farmhouse's name from Lv15), Show into Decorate, no red dot. {} when nothing holds them.
const DECORATE_GO := "decorate"
static func wing_row(view: Dictionary) -> Dictionary:
	if P0Decor.wing_blocked(view).is_empty(): return {}
	var level := int(view.get("homestead", {}).get("level", 1))
	var master := look_stage("master_farmhouse")
	var stage := master if not master.is_empty() and level >= int(master.level) else look_stage("kitchen_extension")
	return _row("%s · %s" % [str(stage.get("name", "Kitchen Wing")), HOME_BLOCKED], "deco_planter", DECORATE_GO)

## Where a Homestead material's Show goes (q(255) ②, 355 C2; 李白's v4q(4) / (5) addendum eb1d7c20) — {go, now}, now = it
## can be had there at once. A gathered material: the spot gather_spot_for picks (`gather:<id>`), now when it is ready.
## Iron Ore / Quartz: the free vein of that main (view.wild.near3_sites, from home); Copper Ore / Coal / Rock Salt: the
## free quarry (`mine:<id>`), now while the player is down it. Clay: a ready Clay Pit, else (every pit cooling) the
## quarry, else the pit. A spot cooling down still points (now false: q(255) ⑥ lists it with what is still to go); the
## city's spots not read yet (P0Runtime._read_home_places), or no such site: no target.
const GATHERED := ["wood", "stone", "fiber", "clay", "wild_herb", "hardwood", "flax"]   # the yields of world_gen gather_points
const VEIN_ORES := ["iron_ore", "quartz"]
const QUARRY_ORES := ["copper_ore", "coal", "rock_salt"]
static func _home_material_go(view: Dictionary, id: String) -> Dictionary:
	var spot := gather_spot_for(view, id) if id in GATHERED else {}
	if not spot.is_empty() and (bool(spot.ready) or id != "clay"): return {"go": "gather:" + str(spot.id), "now": bool(spot.ready)}
	var site := ""
	if id in VEIN_ORES: site = near3_site(view, "vein", id)
	elif id in QUARRY_ORES or id == "clay": site = near3_site(view, "quarry")
	if site != "":
		var at = view.get("mine", {}).get("at", null)   # null while the player is not down a mine (the server's view)
		return {"go": "mine:" + site, "now": at is Dictionary and str(at.get("mine", "")) == site}
	if not spot.is_empty(): return {"go": "gather:" + str(spot.id), "now": false}
	return {"go": "", "now": false}

## The gathering spot for `item` (eb1d7c20): in the city the player is in when it has one (another town's spots first),
## else in the home city — of the spots whose first yield is it, the nearest that can be gathered now (not in
## view.gather.city_ready) {id, ready: true}; every one cooling: the nearest {id, ready: false}. Nearest to the city's
## base point (P0Clusters; the farm when the city is not in the table), the table's order breaking a tie. {} when no
## spot of it is read.
static func gather_spot_for(view: Dictionary, item: String) -> Dictionary:
	var places = load("res://modules/p0/p0_city_places.gd")
	var home := str(load("res://modules/p0/p0_travel.gd").home(view))
	var here := str(view.get("travel", {}).get("here", ""))
	var yields := func(p: Dictionary) -> bool:
		var y: Array = p.get("yield", [])
		return not y.is_empty() and str(y[0][0]) == item
	var city := home
	var spots: Array = (places.gather(here) as Array).filter(yields) if here != "" and here != home else []
	if spots.is_empty(): spots = (places.gather(home) as Array).filter(yields)
	else: city = here
	if spots.is_empty(): return {}
	var cl := P0Clusters.get_cluster(city)
	var farm: Dictionary = view.get("home", {}).get("farm", {}) if view.get("home", {}).get("farm") is Dictionary else {}
	var base := Vector2(float(cl.lat), float(cl.lng)) if not cl.is_empty() else (Vector2(float(farm.get("lat", 0.0)), float(farm.get("lng", 0.0))) if not farm.is_empty() else Vector2.INF)
	var far := func(p: Dictionary) -> float:
		if base == Vector2.INF: return 0.0
		return pow(float(p.lat) - base.x, 2.0) + pow((float(p.lng) - base.y) * cos(deg_to_rad(base.x)), 2.0)
	var cooling: Dictionary = view.get("gather", {}).get("city_ready", {}) if view.get("gather", {}).get("city_ready") is Dictionary else {}
	var best := {}
	var any := {}
	for p in spots:
		if any.is_empty() or float(far.call(p)) < float(far.call(any)): any = p
		if int(cooling.get(str(p.id), 0)) > 0: continue
		if best.is_empty() or float(far.call(p)) < float(far.call(best)): best = p
	return {"id": str(best.id), "ready": true} if not best.is_empty() else {"id": str(any.id), "ready": false}

## One of the free three wild sites (view.wild.near3_sites, nearest first) of `type` — a vein of `main`, or the quarry —
## its id, "" when none.
static func near3_site(view: Dictionary, type: String, main := "") -> String:
	var sites = view.get("wild", {}).get("near3_sites", [])
	for x in sites if sites is Array else []:
		if x is Dictionary and str(x.get("type", "")) == type and (main == "" or str(x.get("main", "")) == main): return str(x.get("id", ""))
	return ""

## `dot`: the row's key for the Today icon's red dot (q(107)), "" for a row that never lights it.
static func _row(line: String, icon_id: String, go: String, dot := "") -> Dictionary:
	return {"line": line, "icon": icon_id, "go": go, "state": "default", "tail": "", "focus": false, "dot": dot}

## A row that ends with ` · <city>` (q(276)): `city` tells Today where to break when the line runs long, `line_short` (when
## given) the first line without the need's name, for when even that runs long — `Pond Catch · Pond Crucian 1/2` /
## `Rio de Janeiro`, `Big Market Order · 1/2` / `Mexico City`.
static func _city_row(row: Dictionary, city: String, short := "") -> Dictionary:
	row.line = str(row.line) + " · " + city
	row.city = city
	if short != "": row.line_short = short + " · " + city
	return row

## A taken request still short (李白 4ac4a4e7): `An Old Man's Catch · Rare fish 0/1`, what it takes as its card says it.
## A fish one shows on the map the pond its ! hangs on; one the player cannot land yet (q(104)) has no Show, a small line
## `Fishing Lv4 needed`, and the whole row opens that fish's gate card (`gate`: the Fish-dex silhouette's, P0Ui).
static func _request_row(view: Dictionary, r: Dictionary) -> Dictionary:
	# q(128) cross-city: before the check-in `Tea Trail · Shanghai`, Show on map to that outpost's pin (亚瑟's #279 loads
	# the city); Far Pond `Far Pond · 1/3 fish` — fish the home city's ponds don't have, no pin.
	var v = r.get("visit", null)
	if v is Dictionary and str(v.get("city", "")) != "":
		return _row("%s · %s" % [str(r.title), str(v.city)], "pin", "outpost:" + str(v.get("place", "")))
	if str(r.get("where", "")) == "not_home":
		return _row("%s · %d/%d fish" % [str(r.title), int(r.have), int(r.qty)], "fish", "")
	var items: Array = r.get("items", [])
	var kind := str(r.get("kind", ""))
	var icon_id := str(items[0]) if items.size() == 1 else str({"fish": "fish", "sow": "seed_radish", "crop": "seed_radish", "dish": "pot"}.get(kind, "board"))
	var sow := request_sow(view, r)
	if sow != "":
		var sowing := _row("%s · %s" % [str(r.title), sow], icon_id, "plots")   # Show (on map): the farm
		sowing.sow_crop = str(items[0])   # the generic Sow row leaves this crop to it while Today shows it (today_rows)
		return sowing
	# another city's request ends with its city (q(270) ⑥), a keeper's local one too (q(272) ⑧): Today measures it and
	# breaks before the city, the need's name dropped only when the first line still runs long (q(276), `line_short`)
	var city := str(r.get("city", ""))
	var row := _row("%s · %s %d/%d" % [str(r.title), str(r.need_name), int(r.have), int(r.qty)], icon_id, "")
	if city != "": _city_row(row, city, "%s · %d/%d" % [str(r.title), int(r.have), int(r.qty)])
	if kind != "fish": return row
	var gate := fish_level_gate(view, items, r.get("rarity", null))
	if not gate.is_empty():
		row.state = "short"
		row.tail = "Fishing Lv%d needed" % int(gate.level)
		row.gate = str(gate.id)
		return row
	for m in PinReason.markers(view):
		# a pond's pin: the written city's `pond_…` or a generated city's `gn-…~pondN` (another city's request, q(270) ⑥)
		var at := str(m.get("place", ""))
		if str(m.get("kind", "")) == "request" and str(m.get("why", {}).get("request", "")) == str(r.id) and (at.begins_with("pond_") or at.contains("~pond")):
			row.go = "pond:" + str(m.place)
			break
	return row

## A taken harvest request short of its crop in the ground (q(218), §14.3 after the guide): fewer plots sown, growing
## or ripe with it than it still needs (a Quick Radish grows a Radish) — `Sow 6 Radishes`, `Sow 2 more Radishes` with
## some already in; "" once enough are in (the row is its count again, `Radish 0/6`) and for any other request. Only
## while it can be sown: a free bed and seeds for it in the bag; else its count too (不知火舞 on 341).
static func request_sow(view: Dictionary, r: Dictionary) -> String:
	var items: Array = r.get("items", [])
	if str(r.get("kind", "")) != "harvest" or items.size() != 1: return ""
	var crop := str(items[0])
	var plots: Array = view.get("plots", [])
	if not plots.any(func(p): return str(p.get("state", "")) in ["tilled", "wild"]): return ""
	if not (view.get("bag", {}).get("slots", []) as Array).any(func(s): return str(s.get("id", "")).begins_with("seed_") \
			and int(s.get("qty", 0)) > 0 and harvest_of(view, str(crop_for_seed(view, str(s.id)).get("id", ""))) == crop):
		return ""
	var planted := plots.filter(func(p): return str(p.get("state", "")) in ["sown", "growing", "ready"] \
		and harvest_of(view, str(p.get("crop", ""))) == crop).size()
	var n := int(r.get("qty", 1)) - int(r.get("have", 0)) - planted
	if n <= 0: return ""
	return "Sow %d %s%s" % [n, "more " if planted > 0 else "", P0Guide.crop_count_name(view, crop, n)]

## The crops taken requests' rows say to sow now (request_sow).
static func request_sow_crops(view: Dictionary) -> Array:
	return PinReason.taken(view).filter(func(r): return request_sow(view, r) != "").map(func(r): return str(r.items[0]))

## "Sow your first plot", short of Energy when sowing a radish costs more than the player has (TodayRow Short).
static func _first_sow_row(view: Dictionary) -> Dictionary:
	var r := _row("Sow your first plot", "seed_radish", "plots")
	var e: Dictionary = view.get("energy", {})
	var cost := int(crop_for_seed(view, "seed_radish").get("energy", 2))
	if int(e.get("value", 0)) < cost:
		r.state = "short"
		r.tail = "needs %d Energy" % cost + ("" if e.get("next_in", null) == null else " · +1 in %s" % duration(float(e.next_in)))
	return r

## A resident's request entry in the content table by id: their line (`requests`) or their teaching requests
## (`intro_requests`, q(218): Nadia's A Fresh Radish / Four Radishes, kept outside the line); {} when neither has it.
static func resident_request(id: String, req_id: String) -> Dictionary:
	var def: Dictionary = content().get("residents", {}).get(id, {})
	for q in def.get("requests", []) + def.get("intro_requests", []):
		if str(q.get("id", "")) == req_id: return q
	return {}

## Who a resident request belongs to (its id in their `requests` or `intro_requests`); "" for none.
static func request_owner(req_id: String) -> String:
	for rid in content().get("residents", {}):
		if not resident_request(str(rid), req_id).is_empty(): return str(rid)
	return ""

## A teaching request (q(218)), not one of the resident's line.
static func is_intro_request(id: String, req_id: String) -> bool:
	return (content().get("residents", {}).get(id, {}).get("intro_requests", []) as Array).any(func(q): return str(q.get("id", "")) == req_id)

## What the resident says on the open bar once a request is handed in (q(218) ①: Nadia's soup line, `{pond}` the home
## set's beginner pond); "" for requests without one.
static func request_thanks(view: Dictionary, req_id: String) -> String:
	var line := str(resident_request(request_owner(req_id), req_id).get("thanks", ""))
	if line == "": return ""
	return line.replace("{pond}", P0Guide.home_pond_name(view))

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
	var state := str(r.get("request_state", "none"))
	var next_in = r.get("next_in", 0)
	if state == "wait" and (next_in == null or float(next_in) <= 0.0): state = "open"   # no wait left to say (no cooldown since 0.2.18)
	match state:
		"open":
			reason = track_full_reason(view, label)   # spec ③: tracking 25 already, `Request · Requests 25/25`
			if reason == "": cmd = {"type": "accept", "request": str(req.id)}
		"accepted":
			label = "Deliver"
			if req.get("ready", false): cmd = {"type": "deliver", "request": str(req.id)}
			else: reason = _request_gap(view, req)
		"wait":
			reason = "Next request in " + span(float(r.get("next_in", 0)))
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
		"meal": meal == "given" and not gift_meal(view, id).is_empty(), "meal_note": note,
		# §7.5.3 Taught: Recipe lesson shows only when one is ready now; the server picks the page.
		"lesson": str(r.get("lesson", {}).get("state", "none")) == "ready" if r.get("lesson", null) is Dictionary else false,
	}

## Stamp Run's check-in toast (不知火舞 / 李白 on #224): `Stamp Run · Checked in` over `Deliver at Mission Market Square`
## (where its board takes it, as request_of writes it, the pin that lights ✓). Two lines always, as the spec has them.
static func visit_toast(view: Dictionary, id: String) -> String:
	var r := PinReason.request_of(view, id)
	var title := str(r.get("title", "Stamp Run")) if not r.is_empty() else "Stamp Run"
	var deliver := str(r.get("deliver", "")) if not r.is_empty() else ""
	return "%s · Checked in" % title + ("\n" + deliver if deliver != "" else "")

## A resident's favourite as words (§7.16.3): a style stays as it is (`Dessert`); a rarity and up reads
## `Fine dishes and up` (Hana; Mira and Tomo `Rare dishes and up`).
static func likes_text(likes: String) -> String:
	return ("%s dishes and up" % likes.trim_suffix("+")) if likes.ends_with("+") else likes

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

## What an accepted request still needs, written on the button (LOCK-10: gaps on buttons). A fish the player cannot
## land yet says the level first, `Fishing Lv4 needed` (q(104)), not `Need 1 more Rare fish`.
static func _request_gap(view: Dictionary, req: Dictionary) -> String:
	var left := maxi(0, int(req.get("qty", 0)) - int(req.get("have", 0)))
	var item := str(req.get("item", "")) if req.get("item", null) != null else ""
	match str(req.get("kind", "")):
		"sow": return "Plant %d more plot%s" % [left, "" if left == 1 else "s"]
		# q(218) ②: Four Radishes counts what is harvested after accepting — `Harvest 3 more Radishes` / `Harvest 1 more Radish`
		"harvest":
			var crop := item_name(view, item) if item != "" else "crop"
			return "Harvest %d more %s" % [left, plural(crop) if left > 1 else crop]
		"dish":
			if item != "": return "Need %d more %s" % [left, item_name(view, item)]
			var style := str(req.get("style", "")) if req.get("style", null) != null else ""
			if style != "": return "Need %d more %s dish%s" % [left, style, "" if left == 1 else "es"]
			return "Need %d more dish%s" % [left, "" if left == 1 else "es"]
		"crop", "material":
			if item != "": return "Need %d more %s" % [left, plural(item_name(view, item)) if left > 1 else item_name(view, item)]
			return "Need %d more %s" % [left, "crops" if str(req.kind) == "crop" else "materials"]
		"fish":
			var short := fish_level_short(view, [item] if item != "" else [], req.get("rarity", null))
			if short > 0: return "Fishing Lv%d needed" % short
			if item != "": return "Need %d more %s" % [left, item_name(view, item)]
			if short > 0: return "Fishing Lv%d needed" % short
			var rarity := int(req.get("rarity", 0)) if req.get("rarity", null) != null else 0
			var names: Array = content().get("rarity_names", [])
			var what := (str(names[rarity - 1]) + " fish") if rarity > 0 and rarity <= names.size() else "fish"
			return "Need %d more %s" % [left, what]
	return "Need %d more" % left

# ---------------------------------------------------------------- outpost keepers (SGODOT-224, LOCK-15 / 16)
## Keeper greeting card copy (李白 SGODOT-228 b7d8b665 D, P0 version) from the server's facts in view.keepers[role]
## (SGODOT-228: state codes and numbers, no names). Names and places are data (后裔's p0_outposts.json): the caller
## passes them in ctx {keeper, place}; the tackle answer also takes ctx.nearest {name, site} (the closest pond).
## Returns {line, greet, counter, trade, question, answer} — line is "Pours the tea · Oak Tea House" when ctx.place is
## given; `greet` is the greeting card's line, `counter` the keeper bar's over the counter drawer (附录 B 掌柜问候 · P0's
## counter lines: the greeting card's question never sits on the counter, 不知火舞 #56).
const _KEEPER_COPY := {
	"tea": {"does": "Pours the tea", "question": "Any news in town?"},
	"post": {"does": "Runs the post", "question": "Who needs help today?"},
	"tackle": {"does": "Minds the tackle", "question": "Where are they biting?"},
	"market": {"does": "Keeps the stall", "question": "What's fresh today?"},
	"casino": {"does": "Deals the cards", "question": "How does it work?"},   # Lou at the Barbary Card Room (q(240))
	"church": {"does": "Welcomes visitors", "question": "Any stories?"},   # Gabriel at Grace Cathedral (q(299)): talk only
}
## Gabriel's stories (q(299), 李白): his answer to Any stories?, the next one each time it is asked, round again after the
## last; counted on this phone for this run only (P0Ui._keeper_told), from the first on the next start.
const CHURCH_STORIES := ["The windows catch the afternoon light. Find a pew and watch.",
	"Fog rolls in most mornings. It's quieter in here then.",
	"Walk the labyrinth slowly. There's no wrong way to finish.",
	"Long day on the farm? The pews don't mind a little dirt.",
	"Nob Hill is steep. You've earned the quiet in here."]
const _CUPS_OUT := "That's three cups today. Come back tomorrow."

## The city the player is in, by name (the Tea Host's `around San Francisco`): an arrived city's, else home's.
static func _here_name(view: Dictionary) -> String:
	var travel = load("res://modules/p0/p0_travel.gd")
	var cl := P0Clusters.get_cluster(travel.here(view))
	return str(cl.name) if not cl.is_empty() and travel.away(view) else travel.home_name(view)

## Gabriel's Pray (q(300), SGODOT-445; the user 11-08 via 奕星, 不知火舞 priest-buff ui-spec v1.2 §2): one full-width key
## over `Any stories?` for both buffs — each tap draws one of them, half and half (BUFF_ORDER), and takes it with the
## buff command the server already has: both may be on at once, a draw of one already on starts its 20 minutes again.
## The time left is the HUD's, not the card's. {} from a server without buffs (no view.buff_takes, before #865).
## From the daily limit (view.buff_takes.limit, 11-15): the count line `2 left today`; used up, the key greys (LOCK-10,
## reason beside it) and the line says `Limit reached · resets in 5h 12m`. In the demo (no limit) neither shows.
const PRAY := "Pray"
static func priest_pray(view: Dictionary) -> Dictionary:
	var takes = view.get("buff_takes", null)
	if not takes is Dictionary: return {}
	if takes.get("limit", null) == null: return {"reason": "", "line": ""}
	var left := int(takes.limit) - int(takes.get("used", 0))
	if left > 0: return {"reason": "", "line": "%d left today" % left}
	var full := "Limit reached · resets in %s" % span(float(takes.get("resets_in", 0)))
	return {"reason": full, "line": full}

## Which buff a prayer draws, from a roll in [0, 1): the first half Twin Catch, the second Swift Growth.
static func pray_draw(roll: float) -> String:
	return str(BUFF_ORDER[clampi(int(roll * BUFF_ORDER.size()), 0, BUFF_ORDER.size() - 1)])

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
			if k.get("online", null) != null: answer += " %d %s around %s right now." % [int(k.online), "person" if int(k.online) == 1 else "people", _here_name(view)]
		"post":
			var pip := resident_name(str(k.get("request_by", ""))) if k.get("request_by", null) != null else ""
			match str(k.get("greet", "")):
				"cups_out": greet = _CUPS_OUT
				"request": greet = "Coffee's fresh. %s's been asking for a hand." % pip
				_: greet = "Coffee's fresh. %d %s left today." % [int(k.get("cups_left", 0)), "cup" if int(k.get("cups_left", 0)) == 1 else "cups"]
			if pip != "": answer = "%s has a request for you." % pip
			elif int(k.get("board_open", 0)) > 0: answer = _board_count(int(k.board_open))
			else: answer = "All quiet." + ("" if k.get("refill_in", null) == null or float(k.refill_in) <= 0.0 else " The Market Board refills in %s." % span(float(k.refill_in)))
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
			var selling := market_sell_line(view)   # q(252) ④: what in the bag she takes, said over the counter
			if selling != "": counter = selling
			var titles: Array = k.get("board_templates", []).map(func(t): return str(content().get("requests", {}).get("templates", {}).get(str(t), {}).get("title", "")))
			titles = titles.filter(func(t): return t != "")
			if not titles.is_empty(): answer = "Fresh off the board: %s." % " and ".join(PackedStringArray(titles))
			else: answer = "Board's empty." + ("" if k.get("refill_in", null) == null or float(k.refill_in) <= 0.0 else " Next request in %s." % span(float(k.refill_in)))
		"casino":   # q(240): no number when coins are short (the table's key says how many); Play opens the table all the same
			# — said only while the table is open (不知火舞 351 66d46cf9: not on screen while it is not)
			var bj: Dictionary = view.get("blackjack", {}) if view.get("blackjack") is Dictionary else {}
			var least := int(bj.get("floor", 40)) + int(bj.get("min_bet", 5))
			var short := bool(bj.get("open", false)) and int(view.get("coins", 0)) < least
			greet = "Keep those coins for seeds. Come back with a few more." if short else "Pull up a chair. Care for a hand?"
			answer = "Get closer to 21 than me without going over. You bet with your own coins."
		"church":   # q(299): no counter, no requests — a welcome and his stories
			greet = "Welcome to Grace. Sit as long as you like."
			answer = CHURCH_STORIES[0]
	var place := str(ctx.get("place", ""))
	return {
		"line": ("%s · %s" % [str(copy.get("does", "")), place]) if place != "" else str(copy.get("does", "")),
		# one word on every keeper (q(154), Joey on 296): Trade at a counter, Play at the card room's table (q(240))
		"greet": greet, "counter": counter if counter != "" else greet, "trade": "Play" if role == "casino" else "Trade",
		"question": str(copy.get("question", "")), "answer": answer,   # no `Just passing by`: the card's ✕ closes it (q(154))
		"answers": CHURCH_STORIES if role == "church" else [answer],   # what the question key says, one a press
		"talk_only": role == "church",   # no Trade: a keeper with no counter (q(299))
	}

## Words that keep their capital inside a sentence (不知火舞 on q(252) ④): the proper adjectives that begin a fish's
## name today — `Arctic char`, `Atlantic salmon`; `rainbow trout`, `northern pike` read lower case.
const PROPER_WORDS := ["Arctic", "Atlantic"]

## An item as a keeper names it in speech (q(252) ④): crops in the lower-case plural (`pumpkins`, `lettuce`), fish
## as one lower-case catch (`rainbow trout`, `Arctic char`).
static func speech_name(view: Dictionary, id: String) -> String:
	var name := item_name(view, id)
	if id.begins_with("crop_"): return plural(name).to_lower()
	return " ".join(PackedStringArray(Array(name.split(" ")).map(func(w): return w if w in PROPER_WORDS else w.to_lower())))

## Mei's selling line (q(252) ④; 不知火舞 on q(252)): the first two things in bag order that the Market takes here (no
## Gifted, nothing locked), `I'll take your Arctic char and pumpkins. Same price as your stall.` at home,
## `Arctic char and pumpkins? I'll take them, though home pays better.` away; "" when she takes nothing in the bag or
## the server does not price by distance yet (an older server keeps her greeting).
static func market_sell_line(view: Dictionary) -> String:
	var d := P0ItemInfo.distance(view, "market")
	if d.is_empty(): return ""
	var ids: Array = []
	for st in view.get("bag", {}).get("slots", []):
		var id := str(st.get("id", ""))
		if id == "" or ids.has(id) or bool(st.get("gifted", false)) or bool(st.get("locked", false)): continue
		if P0ItemInfo.flags(view, id, &"counter_sell", {counter = "market"}).sold_here: ids.append(id)
		if ids.size() == 2: break
	if ids.is_empty(): return ""
	var things := and_list(ids.map(func(id): return speech_name(view, str(id))))
	if bool(d.get("home", true)): return "I'll take your %s. Same price as your stall." % things
	return "%s? I'll take them, though home pays better." % (things.left(1).to_upper() + things.substr(1))

## Small counts in keeper speech ("sows three plots"), digits from ten up; digits under 中文 (「一次能播 3 块田」, 0.2.23 —
## the English word stayed in the Chinese line).
static func _count_word(n: int) -> String:
	if TranslationServer.get_locale() == "zh_CN": return str(n)
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

# ---------------------------------------------------------------- rest bench (FARM-7, q(30) / q(269), SGODOT-224)
## The bench's state from view.rest {used, limit, resets_in, amount} and Energy (FARM-7-2 482:52): state "ready" /
## "used" / "full"; the badge (STATE-ICONS: Available, Used today); the sheet's lines and its one button. Used today,
## the sheet's last line counts down to the 04:00 home-day reset like the mine's `Resets in 9h 12m` (q(96)).
## Near-full Rest says the real gain (WP4-D10 ②: "Rest · +25 Energy"). q(269) (SGODOT-377, the user's ③): once a day
## with no 2 h away first — the away state is gone (不知火舞 on 377 3d9f426f), and an away_ready_in a server before it
## sends is not read: null there meant "never left", which no longer stops anything.
static func rest_state(view: Dictionary) -> Dictionary:
	var r: Dictionary = view.get("rest", {})
	var e: Dictionary = view.get("energy", {})
	var amount := int(r.get("amount", 60))
	var gain := mini(amount, maxi(0, int(e.get("max", 200)) - int(e.get("value", 0))))
	var used := int(r.get("used", 0)) >= int(r.get("limit", 1))
	var out := {
		"state": "ready", "badge": "available",
		"sheet_state": "Available", "effect": "Restores up to %d Energy" % amount,
		"fact": "Uses left", "fact_value": "%d today" % maxi(0, int(r.get("limit", 1)) - int(r.get("used", 0))),
		"button": ("Rest · +%d Energy" % gain) if gain < amount else "Rest", "reason": "", "can_rest": true,
		"close": "Not now", "note": "",
	}
	if used:
		out.merge({"state": "used", "badge": "used_today", "sheet_state": "Used today", "effect": "",
			"fact": "Uses", "fact_value": "%d/%d" % [int(r.get("used", 0)), int(r.get("limit", 1))], "button": "", "can_rest": false,
			"close": "Close", "note": "Available again in " + span(float(r.get("resets_in", 0)))}, true)
	elif gain <= 0:
		out.merge({"state": "full", "reason": "Energy full", "can_rest": false}, true)
	return out

## HOME-1 away from home: the toast for a tap on the grey `At home` button, and for an upgrade refused not_home.
const HOME_AWAY_TAP := "Upgrade at home · Going home is free"
## q(303) (SGODOT-450, 不知火舞 450 v1.2 ②): what stands on the Kitchen Wing's cells stops the upgrade into it — the key
## grey with the existing `Space taken`, a tap says this and offers `Decorate ›` (P0Ui), as does the server's
## homestead_blocked; a save already past Lv8 with its cells held (wing_blocked) says it each launch (P0Farm).
const HOME_BLOCKED := "Space taken"
const HOME_BLOCKED_TAP := "Space taken · clear it first"

## HOME-1 "What changes" rows and the level-up banner lines for the P1 kitchen and Homestead unlocks (§8.3.1, §8.7
## copy; SGODOT-282). Travel tiers, looks and room tiers are announced by their own lines, not here.
const P1_UNLOCKS := {
	"second_stove": {"icon": "kitchen", "text": "Second Stove", "note": "two dishes at once"},
	"notice_board": {"icon": "board", "text": "Notice Board", "note": "at the Home Stall"},   # §9: the stall's board (Figma HOME-1-LV5)
	"big_pot": {"icon": "big_pot", "text": "Big Pot · 2 servings on any stove", "note": ""},   # q(201): a stove switched to it
	"bag_upgrade_2": {"icon": "bag", "text": "Bag Upgrade II"},   # price and note come from the content tier
	"third_stove": {"icon": "kitchen", "text": "Third Stove", "note": "three dishes at once"},
	"bag_upgrade_3": {"icon": "bag", "text": "Bag Upgrade III"},
	"bag_upgrade_4": {"icon": "bag", "text": "Bag Upgrade IV"},
	"chefs_sign": {"icon": "kitchen", "text": "Chef's Sign", "note": "every dish's gold zone +5"},
	"title_homestead_master": {"icon": "star", "text": "Home Master", "note": "title"},
	"healing_potion": {"icon": "star", "text": "Healing Potion", "note": "at the Home Stall"},
	"potion_heal": {"icon": "star", "text": "Healing Potion", "note": "at the Home Stall"},
	"decor_set_1": {"icon": "wood", "text": "New decor", "note": "at the Home Stall"},
	"decor_set_2": {"icon": "wood", "text": "New decor", "note": "at the Home Stall"},
	"orchard_10": {"icon": "crop_apple", "text": "Orchard 10/10", "note": "+1 slot"},
	"sprinklers_12": {"icon": "facility_sprinkler", "text": "Sprinklers 12/12", "note": "+1 sprinkler"},
	"fourth_stove": {"icon": "kitchen", "text": "Fourth Stove", "note": "four dishes at once"},
	# Capacity labels follow the unlock ids supplied by the content table; later batches may add further tiers.
	"orchard_8": {"icon": "crop_apple", "text": "Orchard 8/8", "note": "+1 slot"},
	"sprinklers_10": {"icon": "facility_sprinkler", "text": "Sprinklers 10/10", "note": "+1 sprinkler"},
	"warming_cabinet_12": {"icon": "kitchen", "text": "Warming Cabinet 12", "note": "keeps 12 dishes"},
}
# Lv8's `stall_upgrade` has no line (不知火舞 on 282, 李元芳's c62a6ed9 ③): the stall is still the crate stand-in, with no
# Lv8 look to show, so HOME-1 and the banner promise nothing yet; it comes back with the stall's model.

## A Bag Upgrade's What changes note (不知火舞 on 282, 李元芳's c62a6ed9 ④): the tiers are fixed (content bag_upgrades: I to
## 30, II to 35 after I, III to 40 after II), so `Bag 30 → 35` from the tier before once it is bought, else
## `Bag 35 · after Upgrade I`; the first tier from the bag as it is (`Bag 25 → 30`).
static func bag_tier_note(view: Dictionary, id: String) -> String:
	var tier := _bag_tier(id)
	if tier.is_empty(): return ""
	var to := int(tier.get("capacity", 0))
	var now := int(view.get("bag", {}).get("capacity", 25))
	var before_id := str(tier.get("requires", ""))
	if before_id == "": return "Bag %d → %d" % [now, to]
	var before := _bag_tier(before_id)
	var owned := str(view.get("homestead", {}).get("unlocks", {}).get(before_id, "")) == "owned" or now >= int(before.get("capacity", 0))
	if owned: return "Bag %d → %d" % [int(before.get("capacity", now)), to]
	return "Bag %d · after %s" % [to, str(before.get("name", "")).trim_prefix("Bag ")]

## A Bag Upgrade's own slots: its capacity less the tier before it (Upgrade I: the bag's starting 25) — +5 each, whatever
## the bag holds now (不知火舞 on 283, q(194): the buy row, its › card and the full-bag row say the same).
static func bag_tier_slots(id: String) -> int:
	var tier := _bag_tier(id)
	if tier.is_empty(): return 0
	var before := _bag_tier(str(tier.get("requires", "")))
	return int(tier.get("capacity", 0)) - int(before.get("capacity", content().get("bag", {}).get("capacity", 25)))

static func _bag_tier(id: String) -> Dictionary:
	for t in content().get("bag_upgrades", []):
		if str(t.get("id", "")) == id: return t
	return {}

static func bag_upgrade_line(id: String) -> String:
	var tier := _bag_tier(id)
	if tier.is_empty(): return str(P1_UNLOCKS.get(id, {}).get("text", ""))
	return "%s · %d coins" % [str(tier.name), int(tier.price)]

static func homestead_max(view: Dictionary) -> int:
	return int(view.get("homestead", {}).get("max", content().get("homestead", {}).get("max_level", 1)))

## v4q(1): shared by HOME-1 and refusal toasts; Today keeps its own factual `needed` wording.
static func home_gate_gap(kind: String, need: int, have: int) -> String:
	if kind in ["stamps", "climates"]:
		var missing := maxi(0, need - have)
		return "Need %d more %s%s" % [missing, "stamp" if kind == "stamps" else "climate", "" if missing == 1 else "s"]
	return "Need %s Lv%d" % [kind.capitalize(), need]

## Homestead looks (§8.3.1, LOOK-PICK, SGODOT-282): content homestead.looks, one stage per look level, its id the
## level's unlock id — {id, level, name, a, b}, a timber and b stone (q(112)). HOME-1's icon per stage (Figma 2201:33545).
const LOOK_ICONS := {"fence": "mailbox", "porch": "door", "kitchen_extension": "kitchen", "master_farmhouse": "home"}
## What changes' look row (q(115) ①): `Porch · Timber or Stone` with this note (q(117): `pick when you upgrade` ran past
## the row at the frame's size).
const LOOK_NOTE := "pick one"
const MAX_LEVEL_LINE := "Highest level for now"   # 355 7d9aa825: neutral cap copy, independent of the Master title

static func look_stages() -> Array:
	return content().get("homestead", {}).get("looks", [])

static func look_stage(id: String) -> Dictionary:
	for l in look_stages(): if str(l.get("id", "")) == id: return l
	return {}

## The look picked on a stage, from the view (homestead.looks[].look): "a" / "b", or "" while the stage is not reached.
static func look_of(view: Dictionary, id: String) -> String:
	var h: Dictionary = view.get("homestead", {})
	for l in h.get("looks", []):
		if str(l.get("id", "")) == id: return str(l.look) if l.get("look", null) != null else ""
	var stage := look_stage(id)   # an older view without looks: a once reached (q(24))
	return "a" if not stage.is_empty() and int(h.get("level", 1)) >= int(stage.level) else ""

## HOME-1's Looks section (e2d76a7c, Figma 2201:33545): a row per stage in level order. Reached: the stage name and the
## look on it with › (`Porch` … `Stone Porch ›`), a tap opens LOOK-PICK — at home only, where the farmhouse is in view;
## away it reads without ›. Not reached: grey, `Homestead Lv8`, no ›. Empty until the first stage (Lv3).
## [{id, icon, name, value, reached, open}]
static func look_rows(view: Dictionary, at_home := true) -> Array:
	var out: Array = []
	for l in look_stages():
		var id := str(l.id)
		var look := look_of(view, id)
		var reached := look != ""
		out.append({"id": id, "icon": str(LOOK_ICONS.get(id, "home")), "name": str(l.name), "reached": reached,
			"open": reached and at_home,
			"value": (str(l.get(look, "")) + (" ›" if at_home else "")) if reached else "Home Lv%d" % int(l.level)})
	return out if out.any(func(r): return bool(r.reached)) else []

## HOME-1 (Figma 482:152, §8.6.1, LOCK-10) from view.homestead facts: title, the look line, NEED-TILEs in order
## materials → coins → skills → travel, what changes, and the first gap on the button (355 A view contract).
## {title, look, tiles: [{id, name, have, need, icon}], changes: [{icon, text, note}], label, reason, tap, footer, max}
static func home_panel(view: Dictionary, at_home := true) -> Dictionary:
	var h: Dictionary = view.get("homestead", {})
	var level := int(h.get("level", 1))
	var next = h.get("next", null)
	var out := {"title": "Home Lv%d" % level, "look": "", "tiles": [], "changes": [], "label": "Upgrade",
		"reason": "", "tap": "", "footer": "Upgrading is free of Energy", "max": next == null,
		"subtitle": "", "button": true, "looks": look_rows(view, at_home)}
	if next == null:
		if level >= homestead_max(view):
			out.subtitle = MAX_LEVEL_LINE
			out.button = false
		else:
			out.reason = "Highest level for now"
		return out
	out.title = "Home Lv%d → Lv%d" % [level, int(next.level)]
	var unlocks: Array = next.get("unlocks", [])
	for u in unlocks:   # look stages and their levels come from content, never inferred from the current cap
		var stage := look_stage(str(u))
		if not stage.is_empty(): out.look = "Lv%d look · %s" % [int(next.level), str(stage.name)]
	for m in next.get("materials", []):
		out.tiles.append({"id": str(m.id), "name": str(m.name), "have": int(m.have), "need": int(m.need), "icon": str(m.id)})
	out.tiles.append({"id": "coins", "name": "Coins", "have": int(next.coins.have), "need": int(next.coins.need), "icon": "coin"})
	for skill in next.get("skills", []):
		var id := str(skill.skill)
		out.tiles.append({"id": "skill_" + id, "name": id.capitalize(), "have": int(skill.have), "need": int(skill.need),
			"icon": str(GATE_SKILL_ICONS.get(id, "star"))})
	var travel = next.get("travel", null)
	if travel is Dictionary:
		for id in ["stamps", "climates"]:
			if not travel.get(id) is Dictionary: continue
			out.tiles.append({"id": id, "name": "Stamps" if id == "stamps" else "Climates",
				"have": int(travel[id].have), "need": int(travel[id].need), "icon": "stamp" if id == "stamps" else "globe"})
	var energy: Dictionary = view.get("energy", {})
	out.changes.append({"icon": "energy", "text": "Max Energy %d · Meals %d a day" % [int(next.energy), int(next.meals)],
		"note": "now %d" % int(energy.get("max", 0))})
	var plots_now := int(h.get("plots", {}).get("now", 0))
	if h.get("plots") is Dictionary and int(next.get("plots", plots_now)) > plots_now:
		out.changes.append({"icon": "field", "text": "Plots %d" % int(next.plots), "note": "now %d" % plots_now})
	var yard := yard_change(view)
	if not yard.is_empty(): out.changes.append(yard)
	var board_now := int(h.get("unlocks", {}).get("board_slots", 2))
	for u in unlocks:
		match str(u):
			"spice_rack": out.changes.append({"icon": "kitchen", "text": "Spice Rack", "note": "seasonings off your bag"})
			"warming_cabinet": out.changes.append({"icon": "kitchen", "text": "Warming Cabinet", "note": "keeps 6 dishes by the stove"})
			"bag_upgrade_1", "bag_upgrade_2", "bag_upgrade_3", "bag_upgrade_4":
				out.changes.append({"icon": "bag", "text": bag_upgrade_line(str(u)), "note": bag_tier_note(view, str(u))})
			"board_slot_3": out.changes.append({"icon": "board", "text": "Stall Board · 3rd slot", "note": "now %d" % board_now})
			_ when not look_stage(str(u)).is_empty():   # q(115) ①: `Porch · Timber or Stone` · pick one
				out.changes.append({"icon": str(LOOK_ICONS.get(str(u), "home")), "text": "%s · Timber or Stone" % str(look_stage(str(u)).name), "note": LOOK_NOTE})
			_:
				var line := P1_UNLOCKS.get(str(u), {}) as Dictionary
				if not line.is_empty(): out.changes.append(line.duplicate())
	# The first gap in v4q(1) priority goes on the button (LOCK-10). Away from home (HOME-1 from the Profile farm card,
	# §10.6.2) the button is grey with `At home`, as the Energy card's Cook / Rest tiles (q(6)); a tap says
	# `Upgrade at home · Going home is free` and sends nothing. Going home is the place chip / the map, not a button
	# here (k(1), q(83); 不知火舞 and 李白, 2026-10-09).
	if not at_home:
		out.reason = "At home"
		out.tap = HOME_AWAY_TAP
		return out
	var gaps: Array = []
	for key in ["skill_farming", "skill_fishing", "skill_cooking", "stamps", "climates"]:
		gaps.append_array(out.tiles.filter(func(t): return str(t.id) == key))
	gaps.append_array(out.tiles.filter(func(t): return str(t.id) != "coins" and not str(t.id).begins_with("skill_") and str(t.id) not in ["stamps", "climates"]))
	gaps.append_array(out.tiles.filter(func(t): return str(t.id) == "coins"))
	for t in gaps:
		if int(t.have) >= int(t.need): continue
		var short := int(t.need) - int(t.have)
		match str(t.id):
			"coins": out.reason = "Need %d more coins" % short
			"stamps", "climates": out.reason = home_gate_gap(str(t.id), int(t.need), int(t.have))
			_ when str(t.id).begins_with("skill_"): out.reason = home_gate_gap(str(t.id).trim_prefix("skill_"), int(t.need), int(t.have))
			_: out.reason = "Need %d more %s" % [short, str(t.name)]
		break
	if out.reason == "" and not P0Decor.next_blocked(view).is_empty():   # the last gap (q(303) ①)
		out.reason = HOME_BLOCKED
		out.tap = HOME_BLOCKED_TAP
		out.blocked = true
	return out

## The one-line source for a HOME-1 tile (NeedSource, guide only): coins, skill levels, or a material's places, the
## same line as the workbench (P0MaterialLogic.material_source, Li Bai q(65)).
## v4q(1) (frames A3a–c, 355 48dedfd0; SGODOT-394): a skill's line says how it levels (and Shows its Skills), the travel
## gates how they count.
const HOME_SKILL_HOW := {"farming": "Sow and harvest to level up", "fishing": "Catch fish to level up",
	"cooking": "Cook dishes to level up"}
static func home_source(view: Dictionary, id: String) -> Dictionary:
	if id.begins_with("skill_"):
		var key := id.trim_prefix("skill_")
		var next = view.get("homestead", {}).get("next", null)
		if not next is Dictionary: return {"text": "", "go": ""}
		for skill in next.get("skills", []):
			if str(skill.skill) == key:
				return {"text": "%s Lv%d · %s" % [key.capitalize(), int(skill.need), HOME_SKILL_HOW.get(key, "")], "go": "skills"}
		return {"text": "", "go": ""}
	match id:
		"coins": return {"text": "Coins · sell crops and fish at the Home Stall", "go": "stall"}
		# no Show on the travel gates (A3b / A3c: only a skill's line has one), so they fit as drawn
		"stamps": return {"text": "Stamps · First visit to a city · up to 2 a day", "go": ""}
		"climates": return {"text": "Climates · Visit a city or wild site in another climate", "go": ""}
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

## Yard v2 (v4q(12); 不知火舞's spec v1 一): the What changes row of the level that grows the yard — the next cap and the
## spaces the yard gains (view.decor next_cap, room, next_room: the server's, the yard's cells counted), note the cap now.
## {} when the next level does not grow it, or for a view without them (an older server, or a client not saying yard2).
const YARD_LINE := "Decor %d · Yard +%d spaces"

static func yard_change(view: Dictionary) -> Dictionary:
	var d = view.get("decor", null)
	if not d is Dictionary or d.get("next_room", null) == null or d.get("next_cap", null) == null: return {}
	var gained := int(d.next_room) - int(d.get("room", 0))
	if gained <= 0: return {}
	return {"icon": "wood", "text": YARD_LINE % [int(d.next_cap), gained], "note": "now %d" % int(d.get("cap", 0))}

## HOME-2 MomentBanner (Figma 482:154 / 1228:108620) from the server's homestead event: level disc, title,
## what changed (the event's actual Energy gain at any level) and one line of consequences.
static func home_moment(view: Dictionary, ev: Dictionary) -> Dictionary:
	var level := int(ev.get("level", 1))
	var max_e := int(view.get("energy", {}).get("max", 0))
	var lines: Array = []
	# yard v2 (v4q(12); 不知火舞's spec v1 二): the level that grows the yard says it first, the server's numbers
	var yard = ev.get("yard", null)
	if yard is Dictionary: lines.append(YARD_LINE % [int(yard.get("cap", 0)), int(yard.get("spaces", 0))])
	for u in ev.get("unlocks", []):
		match str(u):
			"spice_rack": lines.append("Spice Rack · seasonings off your bag")
			"warming_cabinet": lines.append("Warming Cabinet")
			"bag_upgrade_1", "bag_upgrade_2", "bag_upgrade_3", "bag_upgrade_4": lines.append(bag_upgrade_line(str(u)))
			_:
				var line := P1_UNLOCKS.get(str(u), {}) as Dictionary
				if not line.is_empty(): lines.append(str(line.text))
	var gain := maxi(0, int(ev.get("energy", 0)))
	var energy := " · +%d Energy" % gain if gain > 0 else ""
	return {"level": str(level), "title": "Home Lv%d" % level, "subtitle": "Max Energy %d" % max_e + energy,
		"detail": "\n".join(lines)}
