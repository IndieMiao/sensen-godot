extends SceneTree
## Aquatic Park fishing (C-232, 0.4.7): the client copy of the rules against the server on the shared cases
## (fixtures/fishing_cases.json, also run by server/test/parcels/fishing.test.ts): the Starter Rod on the first pier
## visit, casting (5 Energy; the server's tier, seed and bite), the reel replayed step for step (the same bar, fish and
## progress after every 40th step), landed / got away / refused traces, the line in before the bite, the tackle limits
## at Jasmine's and fish sales; the shipped numbers (SEN-C-223 §6, SEN-Q-342); the save's `fishing` read back.
##   godot --headless --path . --script res://tests/dynamic_farm/test_parcel_fishing.gd
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fishing = preload("res://modules/dynamic_farm/parcel_fishing.gd")
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
