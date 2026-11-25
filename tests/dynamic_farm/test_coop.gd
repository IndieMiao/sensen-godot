extends SceneTree
## The coop (C-154): the client copy of the rules against the server on the shared cases
## (fixtures/coop_cases.json, also run by server/test/parcels/farm.test.ts), the yard's art file (fence runs with the
## entry open, walls, feeders, the placeholder while SEN-C-155's yard is not in), and ParcelLivestock: hens stay on
## the open floor and step away from the player, a laid egg is reported in reach once, a failed pickup waits until
## the player steps away, an unlaid one appears when due.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_coop.gd
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Livestock = preload("res://modules/dynamic_farm/farm_livestock.gd")
const LivestockScene = preload("res://scenes/dynamic_farm/parcel_livestock.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const T0 := 1795406400000
const BODY := 0.3
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
	_cases()
	_saves()
	_layout()
	_walls()
	await _animals()
	_items()
	print("COOP_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## The shipped coop and its livestock rule; malformed ones are refused as the server refuses them.
func _rules() -> void:
	var rules := ParcelFarm.rules()
	var coop: Dictionary = rules.buildings.coop
	_check(coop.width == 7 and coop.depth == 5 and coop.max == 1 and coop.blueprint == "blueprint_coop" and coop.materials == {},
		"coop: 7×5, one per parcel, the coop blueprint only")
	var l: Dictionary = coop.livestock
	_check(l.animals == ["hen_white", "hen_brown", "hen_white"] and l.feed == "crop_carrot" and l.product == "egg" and l.amount == 1 \
		and l.produce_seconds == 120 and l.max_ground == 6 and l.spots.size() >= 6, "coop: three hens, a carrot gives an egg in 120 s, 6 on the ground")
	_check(rules.energy.costs.feed == 1 and rules.economy.sell_prices.egg == 20, "feeding 1 Energy (P0); an egg sells for 20")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad := func(change: Callable) -> bool:
		var copy: Dictionary = raw.duplicate(true)
		change.call(copy.buildings.coop)
		return ParcelFarm.parse_rules(copy).is_empty()
	_check(not bad.call(func(_c): pass), "rules: the shipped coop parses")
	_check(bad.call(func(c): c.livestock.animals = []), "rules: no animals refused")
	_check(bad.call(func(c): c.livestock.produce_seconds = 0), "rules: no time refused")
	_check(bad.call(func(c): c.livestock.spots = c.livestock.spots.slice(0, 5)), "rules: fewer spots than eggs on the ground refused")
	_check(bad.call(func(c): c.livestock.spots.append([8, 1])), "rules: a spot outside the footprint refused")
	_check(bad.call(func(c): c.materials = {"wood": 0}), "rules: a material of 0 refused")

func _cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/coop_cases.json"))
	_check(shared is Dictionary and shared.cases.size() >= 15, "coop cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var frozen := JSON.stringify(farm, "", true)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now))
		var got := {"ok": true, "buildings": r.state.buildings, "drops": r.state.drops, "drop_seq": r.state.drop_seq, "bag": r.state.bag,
			"energy": r.state.energy} if r.ok else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "coop case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])
		_check(JSON.stringify(farm, "", true) == frozen, "coop case '%s': the input save is untouched" % c.name)

## Drops and animals survive the save's JSON; a save from before C-154 reads with none and keeps its blueprint.
func _saves() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/coop_cases.json"))
	var fed: Dictionary = {}
	for c: Dictionary in shared.cases:
		if str(c.name).begins_with("three hens"):
			fed = ParcelFarm.apply(rules, ParcelFarm.normalize(c.farm), c.commands, int(c.now)).state
	var reread := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(fed)))
	_check(not fed.is_empty() and JSON.stringify(reread, "", true) == JSON.stringify(fed, "", true), "saves: drops and hens read back as written")
	var old := {"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"blueprint_coop": 1}, "welcomed_at": T0,
		"coins": 12, "sales": 1, "gathered": {}, "blueprints_claimed": {"coop": T0}}
	var read := ParcelFarm.normalize(old)
	_check(read.drops == [] and read.drop_seq == 0 and read.bag == {"blueprint_coop": 1}, "saves: before C-154 no drops, the blueprint kept")
	var odd: Dictionary = JSON.parse_string(JSON.stringify(fed))
	odd.drops.append({"id": "x"})
	odd.drop_seq = 1
	var cleaned := ParcelFarm.normalize(odd)
	_check(cleaned.drops.size() == 3 and cleaned.drop_seq == 3, "saves: a malformed drop is left out; the id counter never goes below the drops")

## The art file: the fence's runs leave the entry open; walls are the runs and the parts; feeders inside.
func _layout() -> void:
	var base := Vector2i(7, 5)
	var runs := Livestock.fence_runs("coop", base)
	_check(runs.size() == 5, "layout: four sides, the front split by the entry (%d runs)" % runs.size())
	var front := runs.filter(func(r): return is_equal_approx(r.from.y, 5.0) and is_equal_approx(r.to.y, 5.0))
	_check(front.size() == 2 and is_equal_approx(front[0].to.x, 5.0) and is_equal_approx(front[1].from.x, 6.0), "layout: the entry is x 5–6 of the front")
	var profiles := Livestock.profiles("coop", base, 0.8)
	_check(profiles.size() == runs.size() + Livestock.parts("coop").size(), "layout: a wall per run and per part")
	var feeders := Livestock.feeders("coop")
	_check(feeders.size() == 2 and feeders.all(func(f: Vector2): return Rect2(Vector2.ZERO, Vector2(base)).has_point(f)), "layout: two feeders inside")
	for spot: Vector2 in ParcelFarm.rules().buildings.coop.livestock.spots:
		var free := true
		for r: Rect2 in Livestock.blocked_rects("coop", 0.05): free = free and not r.has_point(spot)
		_check(free and Livestock.floor_rect("coop", base, 0.05).has_point(spot), "layout: egg spot %s lies on the open floor" % spot)
	var model := Building.model("coop", base, 0.8)
	var scene := str(Livestock.building_art("coop").scene)
	_check(model != null and (ResourceLoader.exists(scene) or model.get_node_or_null("Placeholder") != null),
		"layout: the yard's scene, or a placeholder until it exists")
	model.free()
	_check(Building.kind("coop").name == "Coop" and Building.kind("coop").get("livestock", false), "layout: Build Coop from the art file's name")

## The walls in all four turns: the player (0.3 m) passes the entry, not the fence, and stands on the open floor.
func _walls() -> void:
	var data := Data.decode(Fixture.farm())
	var walk := Walk.new(data)
	var base := Vector2i(7, 5)
	for turns in 4:
		var at := Building.transform(walk, Vector2i(2, 2), base, turns)
		var proxies := Building.proxies(walk, "coop", Vector2i(2, 2), base, turns)
		var blocked := func(local: Vector2) -> bool:
			var p := at * Livestock.model_point(local, base, walk.cell_m)
			return proxies.any(func(x): return x.touches(p, BODY))
		_check(not blocked.call(Vector2(5.5, 5.0)) and not blocked.call(Vector2(5.5, 4.3)) and not blocked.call(Vector2(5.5, 5.6)),
			"walls turned %d: in and out through the entry" % turns)
		_check(blocked.call(Vector2(2.5, 5.0)) and blocked.call(Vector2(3.5, 0.0)) and blocked.call(Vector2(0.0, 2.5)) \
			and blocked.call(Vector2(7.0, 2.5)), "walls turned %d: the fence stops the player" % turns)
		_check(blocked.call(Vector2(4.0, 0.75)) and blocked.call(Vector2(2.5, 3.5)), "walls turned %d: the coop and a feeder stop the player" % turns)
		_check(not blocked.call(Vector2(4.5, 3.2)) and not blocked.call(Vector2(1.5, 4.0)), "walls turned %d: the floor is open" % turns)

func _animals() -> void:
	var rules := ParcelFarm.rules()
	var data := Data.decode(Fixture.farm())
	var walk := Walk.new(data)
	var host := LivestockScene.new()
	host.setup(walk)
	root.add_child(host)
	var farm := ParcelFarm.empty_state()
	farm.buildings = [{"id": 1, "type": "coop", "model": "chicken_yard", "x": 2, "y": 2, "width": 7, "depth": 5, "rotation": 1,
		"built_at": T0, "animals": ["hen_white", "hen_brown", "hen_white"]}]
	farm.drops = [{"id": 1, "item": "egg", "amount": 1, "building": 1, "animal": 0, "spot": 2, "ready_at": T0 - 1000},
		{"id": 2, "item": "egg", "amount": 1, "building": 1, "animal": 1, "spot": 5, "ready_at": T0 + 5000}]
	farm.drop_seq = 2
	host.sync(farm, rules, T0)
	var snap: Dictionary = host.snapshot()
	_check(snap.has(1) and snap[1].animals.size() == 3, "animals: three hens in the coop")
	_check(snap[1].drops == [1], "animals: the laid egg lies there, the one not laid yet does not")
	_check(host.covers(Vector2i(2, 2)) and host.covers(Vector2i(6, 8)) and not host.covers(Vector2i(7, 2)), "animals: the turned coop's cells are its floor")
	var egg: Vector3 = host.drop_position(1)
	var far := egg + Vector3(3, 0, 0)
	_check(host.update(0.016, far, T0).is_empty(), "pickup: nothing out of reach")
	_check(host.update(0.016, egg + Vector3(0.5, 0, 0), T0) == [1], "pickup: an egg 0.5 m away is in reach (0.8 m)")
	_check(host.update(0.016, egg + Vector3(0.5, 0, 0), T0, true).is_empty(), "pickup: none while paused (another command out)")
	host.fly(1, egg + Vector3(0.5, 0, 0))
	_check(host.update(0.016, egg, T0).is_empty(), "pickup: a flying egg is not reported again")
	host.settle([1], true)
	_check(host.update(0.016, egg, T0).is_empty(), "pickup: refused, it waits while the player stays")
	host.update(0.016, egg + Vector3(2, 0, 0), T0)
	_check(host.update(0.016, egg, T0) == [1], "pickup: after stepping away and back it is taken again")
	# The hens: ten seconds with the player in the middle; they keep to the open floor and step away from the player.
	var b: Dictionary = farm.buildings[0]
	var frame := Building.transform(walk, Building.at_of(b), Building.base_of(b), 1)
	var middle := frame * Livestock.model_point(Vector2(4.5, 3.0), Vector2i(7, 5), walk.cell_m)
	var inside := true
	for i in 600:
		host.update(1.0 / 60.0, middle, T0 + i * 16)
		for a: Dictionary in host.snapshot()[1].animals:
			var p: Vector2 = a.pos
			inside = inside and Livestock.floor_rect("coop", Vector2i(7, 5), 0.15).grow(0.01).has_point(p)
			for r: Rect2 in Livestock.blocked_rects("coop", 0.15): inside = inside and not r.grow(-0.01).has_point(p)
	_check(inside, "animals: always on the open floor, never in a part")
	var near := 0
	for a: Dictionary in host.snapshot()[1].animals:
		if (a.pos as Vector2).distance_to(Vector2(4.5, 3.0)) < 1.0: near += 1
	_check(near == 0, "animals: none stays within a metre of the player")
	# The second egg is laid at T0 + 5 s: it appears; the hen that laid it went to its spot first.
	host.update(0.016, far, T0 + 6000)
	_check(host.snapshot()[1].drops.has(2), "animals: the egg appears when it is due")
	# A new feeding: the hen goes to a feeder.
	farm.drops.append({"id": 3, "item": "egg", "amount": 1, "building": 1, "animal": 2, "spot": 7, "ready_at": T0 + 200000})
	host.sync(farm, rules, T0 + 7000)
	_check(host.snapshot()[1].animals[2].errand == "feed", "animals: a fed hen goes to the feeder")
	var feeder := frame * Livestock.model_point(Livestock.feeders("coop")[0], Vector2i(7, 5), walk.cell_m)
	_check(not host.feeder_near(feeder + Vector3(0.6, 0, 0), 1.1).is_empty() and host.feeder_near(feeder + Vector3(2, 0, 0), 1.1).is_empty(),
		"feeding: the key's feeder within 1.1 m")
	# Gone from the save (picked elsewhere): gone from the ground.
	farm.drops = []
	host.sync(farm, rules, T0 + 8000)
	_check(host.snapshot()[1].drops.is_empty(), "animals: a picked egg leaves the ground")
	host.queue_free()
	await process_frame

func _items() -> void:
	# Loaded here, not preloaded: it reads P0's content through autoloads that exist only once the tree runs.
	var ParcelItems = load("res://modules/dynamic_farm/parcel_items.gd")
	_check(ParcelItems.name_of("egg") == "Egg", "items: the Egg is named")
	var icon: Texture2D = ParcelItems.icon_of("egg")
	_check(icon != null and icon.get_width() == 96, "items: the Egg has its own icon")

## Whole floats to ints, all the way down (JSON reads numbers as floats).
func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v): return int(v)
	if v is Dictionary:
		var out := {}
		for k in v: out[k] = _ints(v[k])
		return out
	if v is Array: return v.map(_ints)
	return v
