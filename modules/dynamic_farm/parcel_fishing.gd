extends RefCounted
## Aquatic Park fishing on the parcel save (C-232, 0.4.7): the client copy of server/src/parcels/fishing.ts, the same
## arithmetic in the same order, for the local stand-in store, the scene's own reel and the shared cases
## (tests/dynamic_farm/fixtures/fishing_cases.json, also run by server/test/parcels/fishing.test.ts).
## Numbers are the rules' `fishing` (SEN-C-223 §6, owner SEN-Q-342): seven fish 60 : 30 : 10, a cast 5 Energy and 3 back
## when a fish gets away, the Starter Rod on the first pier visit, Reed / Carbon rods, Worm / Spinner baits.
## The reel is P0's (FishingModel.step, P0FishingPanel.reel_tier): the server picks the cast's tier, seed and bite time;
## the client plays the reel on that seed and sends only how long after the bite it hooked and one bit per `reel.step_ms`
## (1 held, 0 let go). The server replays the bits on the seed and decides; a cast settles once.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const COMMANDS := ["visit_pier", "cast_line", "reel_line", "cancel_line"]
## A trace may last this much longer than the server counts since the bite (server REPLAY_SLACK_MS).
const REPLAY_SLACK_MS := 250
const MAX_INPUTS := 10000

## The rules' `fishing` with the server's bounds (fishing.ts parseFishingRules), integers made ints; null when out of them.
## `parsed` is the rest of the parsed rules (its economy for the fish's prices).
static func parse_rules(raw: Variant, parsed: Dictionary) -> Variant:
	if not raw is Dictionary: return null
	var w := ParcelFarm.whole_in
	for field in ["cast_energy", "bite_min_ms", "bite_spread_ms", "hook_window_ms", "settle_grace_ms"]:
		if not raw.has(field) or not ParcelFarm._number(raw[field]): return null
	if not w.call(raw.cast_energy, 0, 1000) or not w.call(raw.get("refund_fail"), 0, int(raw.cast_energy)) \
			or not w.call(raw.bite_min_ms, 0, 60000) or not w.call(raw.bite_spread_ms, 1, 60000) or not w.call(raw.hook_window_ms, 100, 60000) \
			or not w.call(raw.settle_grace_ms, 0, 600000) or not ParcelFarm._is_id(raw.get("starter_rod")):
		return null
	var weights = raw.get("weights")
	if not weights is Array or weights.is_empty() or weights.size() > 9: return null
	var any := false
	for x in weights:
		if not w.call(x, 0, 10000): return null
		any = any or int(x) > 0
	if not any: return null
	var fish = raw.get("fish")
	if not fish is Dictionary or fish.is_empty(): return null
	var out := {"cast_energy": int(raw.cast_energy), "refund_fail": int(raw.refund_fail), "bite_min_ms": int(raw.bite_min_ms),
		"bite_spread_ms": int(raw.bite_spread_ms), "hook_window_ms": int(raw.hook_window_ms), "settle_grace_ms": int(raw.settle_grace_ms),
		"starter_rod": raw.starter_rod, "weights": [], "fish": {}, "rods": [], "baits": {}, "goods": {}, "reel": {}}
	for x in weights: out.weights.append(int(x))
	for id in fish:
		if not ParcelFarm._is_id(id) or not w.call(fish[id], 1, weights.size()): return null
		if not parsed.get("economy", {}).get("sell_prices", {}).has(id): return null
		out.fish[id] = int(fish[id])
	for t in weights.size():
		if int(weights[t]) > 0 and not out.fish.values().has(t + 1): return null
	var rods = raw.get("rods")
	if not rods is Array or rods.is_empty(): return null
	var ids := {}
	for rod in rods:
		if not rod is Dictionary or not ParcelFarm._is_id(rod.get("id")) or ids.has(rod.id) or not w.call(rod.get("hook_bonus_ms"), 0, 60000) \
				or not _real(rod.get("band_bonus"), 0.0, 1.0) or not _real(rod.get("loss_mult"), 0.0, 10.0):
			return null
		ids[rod.id] = true
		out.rods.append({"id": rod.id, "hook_bonus_ms": int(rod.hook_bonus_ms), "band_bonus": float(rod.band_bonus), "loss_mult": float(rod.loss_mult)})
	if not ids.has(out.starter_rod): return null
	if not raw.get("baits") is Dictionary: return null
	for id in raw.baits:
		var b = raw.baits[id]
		if not ParcelFarm._is_id(id) or ids.has(id) or not b is Dictionary or not b.get("shift") is Array or b.shift.size() != weights.size() \
				or not _real(b.get("wait"), 0.05, 10.0):
			return null
		var shift := []
		for n in b.shift:
			if not w.call(n, -10000, 10000): return null
			shift.append(int(n))
		out.baits[id] = {"shift": shift, "wait": float(b.wait)}
	if not raw.get("goods") is Dictionary: return null
	for id in raw.goods:
		var g = raw.goods[id]
		if not ParcelFarm._is_id(id) or not g is Dictionary: return null
		var rule := {}
		for field in ["max_owned", "daily"]:
			if g.has(field):
				if not w.call(g[field], 1, 999): return null
				rule[field] = int(g[field])
		if g.has("min_level"):
			if not w.call(g.min_level, 1, 99): return null
			rule.min_level = int(g.min_level)
		out.goods[id] = rule
	var q = raw.get("reel")
	if not q is Dictionary or not w.call(q.get("step_ms"), 10, 1000) or not w.call(q.get("max_steps"), 1, 10000) \
			or not _real(q.get("bar_acceleration"), 0.0, 100.0) or not _real(q.get("bar_max_speed"), 0.0, 100.0) \
			or not _real(q.get("initial_progress"), 0.01, 0.99) or not _real(q.get("max_band"), 0.01, 1.0) or not _real(q.get("min_loss"), 0.0, 100.0) \
			or not q.get("tiers") is Dictionary:
		return null
	out.reel = {"step_ms": int(q.step_ms), "max_steps": int(q.max_steps), "bar_acceleration": float(q.bar_acceleration),
		"bar_max_speed": float(q.bar_max_speed), "initial_progress": float(q.initial_progress), "max_band": float(q.max_band),
		"min_loss": float(q.min_loss), "tiers": {}}
	for t in range(1, weights.size() + 1):
		var tier = q.tiers.get(str(t))
		if not tier is Dictionary or not _real(tier.get("bar_size"), 0.01, 1.0) or not _real(tier.get("fish_speed"), 0.0, 100.0) \
				or not w.call(tier.get("turn_steps"), 1, 10000) or not _real(tier.get("gain"), 0.0, 100.0) or not _real(tier.get("loss"), 0.0, 100.0):
			return null
		out.reel.tiers[str(t)] = {"bar_size": float(tier.bar_size), "fish_speed": float(tier.fish_speed), "turn_steps": int(tier.turn_steps),
			"gain": float(tier.gain), "loss": float(tier.loss)}
	return out

static func _real(v: Variant, low: float, high: float) -> bool:
	return (v is float or v is int) and is_finite(float(v)) and float(v) >= low and float(v) <= high

static func empty() -> Dictionary:
	return {"cast": null, "casts": 0, "caught": {}, "gifted_at": null, "bought": {"day": null, "counts": {}}, "last": null}

## The save's `fishing` as the server reads it (fishingOf): none (a save from before C-232) is never fished; malformed
## parts are left out. A copy.
static func fishing_of(raw: Variant) -> Dictionary:
	var out := empty()
	if not raw is Dictionary: return out
	var w := ParcelFarm.whole_in
	var c = raw.get("cast")
	if c is Dictionary and ParcelFarm._number(c.get("at")) and ParcelFarm._number(c.get("bite_at")) and w.call(c.get("hook_ms"), 0, 600000) \
			and w.call(c.get("rarity"), 1, 9) and w.call(c.get("seed"), 0, 0xFFFFFFFF) \
			and (c.get("bait") == null or ParcelFarm._is_id(c.get("bait"))) and ParcelFarm._is_id(c.get("rod")):
		out.cast = {"at": int(c.at), "bite_at": int(c.bite_at), "hook_ms": int(c.hook_ms), "rarity": int(c.rarity), "seed": int(c.seed),
			"bait": c.get("bait"), "rod": c.rod}
	if w.call(raw.get("casts"), 0, ParcelFarm.MAX_ID): out.casts = int(raw.casts)
	if raw.get("caught") is Dictionary:
		for id in raw.caught:
			if ParcelFarm._is_id(id) and w.call(raw.caught[id], 1, ParcelFarm.MAX_ID): out.caught[id] = int(raw.caught[id])
	if ParcelFarm._number(raw.get("gifted_at")): out.gifted_at = int(raw.gifted_at)
	var b = raw.get("bought")
	if b is Dictionary and ParcelFarm._is_day(b.get("day")) and b.get("counts") is Dictionary:
		out.bought.day = b.day
		for id in b.counts:
			if ParcelFarm._is_id(id) and w.call(b.counts[id], 1, 100000): out.bought.counts[id] = int(b.counts[id])
	var l = raw.get("last")
	if l is Dictionary and str(l.get("result", "")) in ["landed", "escaped", "cancelled"] and ParcelFarm._number(l.get("at")) \
			and (l.get("fish") == null or ParcelFarm._is_id(l.get("fish"))) and w.call(l.get("refund"), 0, 10000):
		out.last = {"result": l.result, "at": int(l.at), "fish": l.get("fish"), "refund": int(l.refund)}
	return out

## The best rod in the bag (the rules' `rods` run worst to best), {} with none.
static func best_rod(f: Dictionary, bag: Dictionary) -> Dictionary:
	for i in range((f.rods as Array).size() - 1, -1, -1):
		if int(bag.get(f.rods[i].id, 0)) > 0: return f.rods[i]
	return {}

static func rod_of(f: Dictionary, id: String) -> Dictionary:
	for rod: Dictionary in f.rods:
		if rod.id == id: return rod
	return f.rods[0]

## A tier's reel on a rod (P0 reel_tier): the band widened up to `max_band`, the loss times the rod's, at least `min_loss`.
static func reel_tier(f: Dictionary, rarity: int, rod: Dictionary) -> Dictionary:
	var t: Dictionary = (f.reel.tiers[str(rarity)] as Dictionary).duplicate()
	t.bar_size = minf(float(f.reel.max_band), float(t.bar_size) + float(rod.band_bonus))
	t.loss = maxf(float(f.reel.min_loss), float(t.loss) * float(rod.loss_mult))
	return t

static func initial(f: Dictionary, seed_value: int) -> Dictionary:
	return {"step": 0, "bar": 0.5, "velocity": 0.0, "fish": 0.5, "target": 0.5, "rng": seed_value & 0xFFFFFFFF,
		"progress": float(f.reel.initial_progress), "outcome": "playing"}

## One reel step (server stepReel, the same operations in the same order).
static func step(f: Dictionary, s: Dictionary, held: bool, tier: Dictionary) -> void:
	if s.outcome != "playing": return
	var q: Dictionary = f.reel
	var dt := float(q.step_ms) / 1000.0
	if int(s.step) % int(tier.turn_steps) == 0:
		s.rng = (int(s.rng) * 1664525 + 1013904223) & 0xFFFFFFFF
		s.target = 0.1 + float(s.rng) / 4294967296.0 * 0.8
	s.fish = move_toward(float(s.fish), float(s.target), float(tier.fish_speed) * dt)
	s.velocity = clampf(float(s.velocity) + (1.0 if held else -1.0) * float(q.bar_acceleration) * dt, -float(q.bar_max_speed), float(q.bar_max_speed))
	var half := float(tier.bar_size) * 0.5
	s.bar = clampf(float(s.bar) + float(s.velocity) * dt, half, 1.0 - half)
	if float(s.bar) == half or float(s.bar) == 1.0 - half: s.velocity = 0.0
	var inside := absf(float(s.fish) - float(s.bar)) <= half
	s.progress = clampf(float(s.progress) + (float(tier.gain) if inside else -float(tier.loss)) * dt, 0.0, 1.0)
	s.step = int(s.step) + 1
	if float(s.progress) >= 1.0: s.outcome = "caught"
	elif float(s.progress) <= 0.0 or int(s.step) >= int(q.max_steps): s.outcome = "escaped"

## The trace replayed from the start; {} when it ends still playing or goes on past the result (server replayReel null).
static func replay(f: Dictionary, seed_value: int, tier: Dictionary, inputs: String) -> Dictionary:
	var s := initial(f, seed_value)
	for bit in inputs:
		if s.outcome != "playing": return {}
		step(f, s, bit == "1", tier)
	return {} if s.outcome == "playing" else s

static func cast_seed(parcel: String, now: int, casts: int) -> int:
	return ParcelFarm.hash32("%s:%d:%d" % [parcel, now, casts])

static func roll_rarity(f: Dictionary, seed_value: int, bait: Variant) -> int:
	var shift: Array = f.baits.get(bait, {}).get("shift", []) if bait is String else []
	var weights := []
	var total := 0
	for i in (f.weights as Array).size():
		var x := maxi(0, int(f.weights[i]) + (int(shift[i]) if i < shift.size() else 0)) if f.fish.values().has(i + 1) else 0
		weights.append(x)
		total += x
	var roll := ParcelFarm.hash32("%d:r" % seed_value) % total
	for i in weights.size():
		if roll < int(weights[i]): return i + 1
		roll -= int(weights[i])
	for i in weights.size():
		if int(weights[i]) > 0: return i + 1
	return 1

static func pick_fish(f: Dictionary, seed_value: int, rarity: int) -> String:
	var pool := []
	for id in f.fish:
		if int(f.fish[id]) == rarity: pool.append(id)
	return pool[ParcelFarm.hash32("%d:f" % seed_value) % pool.size()]

static func deadline(f: Dictionary, c: Dictionary) -> int:
	return int(c.bite_at) + int(c.hook_ms) + int(f.reel.max_steps) * int(f.reel.step_ms) + int(f.settle_grace_ms)

## A command's shape (server parseFishingCommand): "" when well formed.
static func schema(command: Dictionary) -> bool:
	match str(command.get("type", "")):
		"visit_pier", "cancel_line": return true
		"cast_line":
			var bait = command.get("bait")
			return bait == null or (bait is String and bait.length() <= 64)
		"reel_line":
			var inputs = command.get("inputs")
			return ParcelFarm.whole_in(command.get("hook_ms"), 0, 600000) and inputs is String and inputs.length() >= 1 \
				and inputs.length() <= MAX_INPUTS and RegEx.create_from_string("^[01]+$").search(inputs) != null
	return false

## Refunds Energy (3 when a fish gets away, 5 before the bite) up to the pool; a full pool holds its timer at now.
static func _refund(rule_set: Dictionary, next: Dictionary, now: int, n: int) -> int:
	var e := ParcelFarm.settle_energy(rule_set, next, now)
	var top := ParcelFarm.max_energy(rule_set, next)
	var back := maxi(0, mini(n, top - int(e.value)))
	e.value = int(e.value) + back
	if int(e.value) >= top: e.at = now
	return back

static func _settle(rule_set: Dictionary, next: Dictionary, fs: Dictionary, now: int, result: String, fish: Variant) -> void:
	var f: Dictionary = rule_set.fishing
	var c: Dictionary = fs.cast
	fs.cast = null
	var back := 0
	if result == "landed" and fish is String:
		next.bag[fish] = int(next.bag.get(fish, 0)) + 1
		fs.caught[fish] = int(fs.caught.get(fish, 0)) + 1
	else:
		back = _refund(rule_set, next, now, int(f.cast_energy) if result == "cancelled" else int(f.refund_fail))
	if result != "cancelled" and c.bait is String and int(next.bag.get(c.bait, 0)) > 0: ParcelFarm._take(next.bag, c.bait)
	fs.last = {"result": result, "at": now, "fish": fish if result == "landed" else null, "refund": back}

## One fishing command on `next` (ParcelFarm.apply, Energy settled to now): {code, detail}, code "" when done.
static func command(rule_set: Dictionary, next: Dictionary, cmd: Dictionary, now: int, parcel_id: String) -> Dictionary:
	var f: Dictionary = rule_set.get("fishing", {})
	if f.is_empty(): return {"code": "NO_FISHING", "detail": {}}
	var fs := fishing_of(next.get("fishing"))
	var active = fs.cast
	match str(cmd.type):
		"visit_pier":
			if fs.gifted_at != null: return {"code": "PIER_GIFTED", "detail": {}}
			fs.gifted_at = now
			next.bag[f.starter_rod] = int(next.bag.get(f.starter_rod, 0)) + 1
		"cast_line":
			var bait = cmd.get("bait")
			if active != null and now <= deadline(f, active): return {"code": "ALREADY_CASTING", "detail": {"bite_at": int(active.bite_at)}}
			var rod := best_rod(f, next.bag)
			if rod.is_empty(): return {"code": "NO_ROD", "detail": {"item": f.starter_rod}}
			if bait != null and (not f.baits.has(bait) or int(next.bag.get(bait, 0)) <= 0): return {"code": "NO_BAIT", "detail": {"item": bait}}
			if active != null: _settle(rule_set, next, fs, now, "escaped", null)
			if bait != null and int(next.bag.get(bait, 0)) <= 0: return {"code": "NO_BAIT", "detail": {"item": bait}}
			var e: Dictionary = next.energy
			if int(e.value) < int(f.cast_energy):
				return {"code": "NO_ENERGY", "detail": {"need": int(f.cast_energy), "have": int(e.value),
					"next_in": ParcelFarm.next_tick_in(rule_set, next, now)}}
			if int(e.value) >= ParcelFarm.max_energy(rule_set, next): e.at = now
			e.value = int(e.value) - int(f.cast_energy)
			var seed_value := cast_seed(parcel_id, now, int(fs.casts))
			fs.casts = int(fs.casts) + 1
			var wait := float(f.baits[bait].wait) if bait != null else 1.0
			var bite := roundi(float(int(f.bite_min_ms) + ParcelFarm.hash32("%d:b" % seed_value) % int(f.bite_spread_ms)) * wait)
			fs.cast = {"at": now, "bite_at": now + bite, "hook_ms": int(f.hook_window_ms) + int(rod.hook_bonus_ms),
				"rarity": roll_rarity(f, seed_value, bait), "seed": seed_value, "bait": bait, "rod": rod.id}
		"reel_line":
			if active == null: return {"code": "NO_CAST", "detail": {}}
			if now < int(active.bite_at): return {"code": "TOO_EARLY", "detail": {"bite_at": int(active.bite_at)}}
			var inputs: String = cmd.inputs
			if now > deadline(f, active) or int(cmd.hook_ms) > int(active.hook_ms):
				_settle(rule_set, next, fs, now, "escaped", null)
			elif int(active.bite_at) + int(cmd.hook_ms) + inputs.length() * int(f.reel.step_ms) > now + REPLAY_SLACK_MS:
				return {"code": "REEL_INPUT", "detail": {"reason": "too_fast"}}
			else:
				var sim := replay(f, int(active.seed), reel_tier(f, int(active.rarity), rod_of(f, str(active.rod))), inputs)
				if sim.is_empty(): return {"code": "REEL_INPUT", "detail": {"reason": "unfinished"}}
				var caught: bool = sim.outcome == "caught"
				_settle(rule_set, next, fs, now, "landed" if caught else "escaped",
					pick_fish(f, int(active.seed), int(active.rarity)) if caught else null)
		"cancel_line":
			if active == null: return {"code": "NO_CAST", "detail": {}}
			_settle(rule_set, next, fs, now, "cancelled" if now < int(active.bite_at) else "escaped", null)
	next.fishing = fs
	return {"code": "", "detail": {}}

## The tackle limits at Jasmine's (server goodsRefusal), checked before the coins: {code, detail}, code "" when the item
## has none or keeps to them; today's count is written when it does.
static func goods_refusal(rule_set: Dictionary, next: Dictionary, item: String, n: int, now: int) -> Dictionary:
	var g: Dictionary = rule_set.get("fishing", {}).get("goods", {}).get(item, {})
	if g.is_empty(): return {"code": "", "detail": {}}
	var level := ParcelFarm.farm_level(next)
	if g.has("min_level") and level < int(g.min_level): return {"code": "CONDITION_NOT_MET", "detail": {"level": level, "min_level": int(g.min_level)}}
	if g.has("max_owned") and int(next.bag.get(item, 0)) + n > int(g.max_owned):
		return {"code": "ALREADY_OWNED", "detail": {"item": item, "max": int(g.max_owned)}}
	if g.has("daily"):
		var fs := fishing_of(next.get("fishing"))
		var day := ParcelFarm.day_key(rule_set, now)
		if fs.bought.day != day: fs.bought = {"day": day, "counts": {}}
		var had := int(fs.bought.counts.get(item, 0))
		if had + n > int(g.daily): return {"code": "DAILY_LIMIT", "detail": {"item": item, "limit": int(g.daily), "bought": had}}
		fs.bought.counts[item] = had + n
		next.fishing = fs
	return {"code": "", "detail": {}}

## How many of `item` can be bought now: the daily cap left, the one rod; -1 without a limit. Jasmine's keys read it.
static func can_buy(rule_set: Dictionary, state: Dictionary, item: String, now: int) -> int:
	var g: Dictionary = rule_set.get("fishing", {}).get("goods", {}).get(item, {})
	if g.is_empty(): return -1
	if g.has("min_level") and ParcelFarm.farm_level(state) < int(g.min_level): return 0
	var left := -1
	if g.has("max_owned"): left = maxi(0, int(g.max_owned) - int(state.get("bag", {}).get(item, 0)))
	if g.has("daily"):
		var fs := fishing_of(state.get("fishing"))
		var had := int(fs.bought.counts.get(item, 0)) if fs.bought.day == ParcelFarm.day_key(rule_set, now) else 0
		var day_left := maxi(0, int(g.daily) - had)
		left = day_left if left < 0 else mini(left, day_left)
	return left
