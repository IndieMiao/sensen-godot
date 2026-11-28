extends SceneTree
## Aquatic Park fishing (C-232, 0.4.7): the client copy of the rules against the server on the shared cases
## (fixtures/fishing_cases.json, also run by server/test/parcels/fishing.test.ts): the Starter Rod on the first pier
## visit, casting (5 Energy; the server's tier, seed and bite), the reel replayed step for step (the same bar, fish and
## progress after every 40th step), landed / got away / refused traces, the line in before the bite, the tackle limits
## at Jasmine's and fish sales; the shipped numbers (SEN-C-223 §6, SEN-Q-342); the save's `fishing` read back.
##   godot --headless --path . --script res://tests/dynamic_farm/test_parcel_fishing.gd
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fishing = preload("res://modules/dynamic_farm/parcel_fishing.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const CASES := "res://tests/dynamic_farm/fixtures/fishing_cases.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	_rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	_check(shared is Dictionary and shared.cases.size() >= 40 and shared.reels.size() >= 150, "the shared fixture reads")
	if shared is Dictionary:
		_cases(shared)
		_reels(shared)
	_saves()
	_hidden_line()
	print("PARCEL_FISHING checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _rules() -> void:
	var f: Dictionary = ParcelFarm.rules().fishing
	_check(f.fish == {"fish_crucian": 1, "fish_carp": 1, "fish_mullet": 1, "fish_perch": 2, "fish_bass": 2, "fish_mackerel": 2, "fish_seabass": 3},
		"seven fish in three tiers")
	_check(f.weights == [60, 30, 10] and f.cast_energy == 5 and f.refund_fail == 3 and f.starter_rod == "rod_starter", "60/30/10, 5 Energy, 3 back")
	_check(f.rods.map(func(r): return r.id) == ["rod_starter", "rod_reed", "rod_carbon"] and is_equal_approx(float(f.rods[2].loss_mult), 0.9),
		"three rods, the Carbon Rod loses 10 % less")
	_check(f.goods.rod_carbon == {"max_owned": 1, "min_level": 4} and f.goods.bait_worm == {"daily": 30} and f.goods.bait_lure == {"daily": 10, "min_level": 4},
		"the tackle limits")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad: Dictionary = raw.duplicate(true)
	bad.fishing.fish["fish_unknown"] = 1
	_check(ParcelFarm.parse_rules(bad).is_empty(), "a fish without a price is refused, as the server refuses it")
	bad = raw.duplicate(true)
	bad.fishing.refund_fail = 6
	_check(ParcelFarm.parse_rules(bad).is_empty(), "more back than a cast costs is refused")
	bad = raw.duplicate(true)
	bad.erase("fishing")
	var none := ParcelFarm.parse_rules(bad)
	_check(not none.is_empty() and none.fishing.is_empty(), "rules without fishing still read")
	var r := ParcelFarm.apply(none, ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {}, "welcomed_at": 0}),
		[{"type": "visit_pier"}], 1000)
	_check(not r.ok and r.code == "NO_FISHING", "… and cannot fish")

func _cases(shared: Dictionary) -> void:
	var rules := ParcelFarm.rules()
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var frozen := JSON.stringify(farm, "", true)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now), str(shared.parcel_id))
		var got := {"ok": true, "bag": r.state.bag, "energy": r.state.energy, "coins": r.state.coins, "fishing": r.state.get("fishing")} \
			if r.ok else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])
		_check(JSON.stringify(farm, "", true) == frozen, "case '%s': the input save is untouched" % c.name)

## Every reel: the outcome and step count exactly, bar / fish / progress after every 40th step as the server computed them
## (to 1e-12: the fixture's decimals are read back by Godot's JSON).
func _reels(shared: Dictionary) -> void:
	var f: Dictionary = ParcelFarm.rules().fishing
	var same := 0
	for r: Dictionary in shared.reels:
		var tier := Fishing.reel_tier(f, int(r.rarity), Fishing.rod_of(f, str(r.rod)))
		var s := Fishing.initial(f, int(r.seed))
		var marks := []
		for bit in str(r.inputs):
			Fishing.step(f, s, bit == "1", tier)
			if int(s.step) % 40 == 0 or s.outcome != "playing": marks.append([int(s.step), float(s.bar), float(s.fish), float(s.progress)])
		var exact: bool = marks.size() == r.marks.size()
		for i in mini(marks.size(), r.marks.size()):
			var want: Array = r.marks[i]
			# Godot's JSON reads a decimal to within an ulp or so, not always the server's exact double: 1e-12 apart at most.
			exact = exact and marks[i][0] == int(want[0]) and absf(marks[i][1] - float(want[1])) < 1e-12 \
				and absf(marks[i][2] - float(want[2])) < 1e-12 and absf(marks[i][3] - float(want[3])) < 1e-12
		var replayed := Fishing.replay(f, int(r.seed), tier, str(r.inputs))
		if exact and not replayed.is_empty() and replayed.outcome == r.outcome: same += 1
		else: _check(false, "reel %d %s %s %s: %s, server %s" % [int(r.seed), r.rarity, r.rod, r.kind, JSON.stringify(marks.slice(-1)), JSON.stringify(r.marks.slice(-1))])
	_check(same == shared.reels.size(), "%d of %d reels replay step for step" % [same, shared.reels.size()])
	var rolled := 0
	for x: Dictionary in shared.rolls:
		if Fishing.roll_rarity(f, int(x.seed), null) == int(x.none) and Fishing.roll_rarity(f, int(x.seed), "bait_worm") == int(x.bait_worm) \
				and Fishing.roll_rarity(f, int(x.seed), "bait_lure") == int(x.bait_lure):
			rolled += 1
	_check(rolled == shared.rolls.size(), "%d of %d tier rolls as the server's" % [rolled, shared.rolls.size()])

## The save's fishing reads back as written; an older save has none and gains none from reading.
func _saves() -> void:
	var rules := ParcelFarm.rules()
	var old := ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"rod_starter": 1}, "welcomed_at": 0})
	_check(not old.has("fishing"), "an older save has no fishing")
	var r := ParcelFarm.apply(rules, old, [{"type": "cast_line", "bait": null}], 5000, "p-1")
	_check(r.ok and r.state.fishing.cast is Dictionary, "it casts")
	var reread := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(r.state)))
	_check(JSON.stringify(_ints(reread.fishing), "", true) == JSON.stringify(_ints(r.state.fishing), "", true), "the line in the water reads back")
	var junk := ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {}, "welcomed_at": 0,
		"fishing": {"cast": {"at": "x"}, "casts": -1, "caught": {"fish_carp": 0}}})
	_check(junk.fishing.cast == null and junk.fishing.casts == 0 and junk.fishing.caught.is_empty(), "malformed parts are left out")
	var view := ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"bait_worm": 3}, "welcomed_at": 0,
		"level": 4, "fishing": {"bought": {"day": ParcelFarm.day_key(rules, 5000), "counts": {"bait_worm": 28}}}})
	_check(Fishing.can_buy(rules, view, "bait_worm", 5000) == 2 and Fishing.can_buy(rules, view, "bait_lure", 5000) == 10
		and Fishing.can_buy(rules, view, "rod_reed", 5000) == 1 and Fishing.can_buy(rules, view, "seed_carrot", 5000) == -1,
		"what is left to buy today")

## C-241: before the bite the save the client is given holds the cast without its tier and seed (server castView); the
## client reads such a cast as a line in the water, not yet shown; from the bite on it is the cast as saved. The local
## stand-in answers the same way, and its line in before the bite still gives all 5 back.
func _hidden_line() -> void:
	var rules := ParcelFarm.rules()
	var farm := ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"rod_starter": 1, "bait_worm": 1},
		"welcomed_at": 0})
	var r := ParcelFarm.apply(rules, farm, [{"type": "cast_line", "bait": "bait_worm"}], 5000, "p-1")
	var saved: Dictionary = r.state.fishing
	var bite := int(saved.cast.bite_at)
	_check(Fishing.shown(saved.cast), "the saved cast has its tier and seed")
	for at in [5000, bite - 1]:
		var seen: Dictionary = Fishing.cast_view(saved, at)
		_check(not seen.cast.has("rarity") and not seen.cast.has("seed") and seen.cast.size() == 5 and int(seen.cast.bite_at) == bite,
			"at %d (bite %d) the client's cast has no tier and no seed (%s)" % [at, bite, JSON.stringify(seen.cast)])
		_check(Fishing.shown(saved.cast) and int(saved.casts) == int(seen.casts), "… the save itself keeps them")
		var read := Fishing.fishing_of(seen)
		_check(read.cast is Dictionary and not Fishing.shown(read.cast) and int(read.cast.bite_at) == bite and read.cast.bait == "bait_worm",
			"… and it reads as a line in the water, not yet shown")
		_check(not Fishing.shown(ParcelFarm.view(rules, r.state, at).fishing.cast), "… the client view hides it too (farmView)")
	_check(Fishing.cast_view(saved, bite) == saved and Fishing.shown(ParcelFarm.view(rules, r.state, bite).fishing.cast), "from the bite on it shows")
	var half: Dictionary = saved.duplicate(true)
	half.cast.erase("seed")
	_check(Fishing.fishing_of(half).cast == null, "a cast with a tier but no seed is malformed")
	# The stand-in answers a cast with the line hidden; a read at the bite shows it; a line in before the bite: all 5 back.
	var dir := "user://test_parcel_fishing_hidden"
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	var store := LocalStore.new("p-1", dir)
	var clock := [5000]
	store.now_ms = func() -> int: return clock[0]
	store._save(farm, 1)
	var cast: Dictionary = store.send(1, [{"type": "cast_line", "bait": "bait_worm"}])
	var line = Fishing.fishing_of(cast.get("farm", {}).get("fishing")).cast
	_check(cast.ok and line is Dictionary and not Fishing.shown(line), "the stand-in's cast answer hides the tier and the seed")
	clock[0] = int(line.bite_at) - 1
	_check(not Fishing.shown(Fishing.fishing_of(store.read().farm.fishing).cast), "a read before the bite still hides them")
	var energy := int(cast.farm.energy.value)
	var back: Dictionary = store.send(2, [{"type": "cancel_line"}])
	_check(back.ok and back.farm.fishing.last.result == "cancelled" and int(back.farm.fishing.last.refund) == 5
		and int(back.farm.energy.value) == energy + 5 and int(back.farm.bag.get("bait_worm", 0)) == 1, "a line in before the bite: 5 back, bait kept")
	var cast_at: int = clock[0]
	store.send(3, [{"type": "cast_line", "bait": null}])
	clock[0] = int(store.read().farm.fishing.cast.bite_at)
	var shown = Fishing.fishing_of(store.read().farm.fishing).cast
	_check(Fishing.shown(shown) and int(shown.seed) == Fishing.cast_seed("p-1", cast_at, 1), "a read at the bite shows the tier and the seed")
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))

func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 9.0e15: return int(v)
	if v is Array: return v.map(func(x): return _ints(x))
	if v is Dictionary:
		var out := {}
		var keys: Array = v.keys()
		keys.sort()
		for k in keys: out[k] = _ints(v[k])
		return out
	return v
